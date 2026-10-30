#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $root 'infra\scripts\Remove-Knowledge.ps1'
$directory = Join-Path $root "out\knowledge-cleanup-tests-$([guid]::NewGuid().ToString('N'))"
$previousExitCode = $global:LASTEXITCODE
$contract = @{
    contract_version = 1
    subscription_id = '00000000-0000-0000-0000-000000000001'
    tenant_id = '00000000-0000-0000-0000-000000000002'
    workload_name = 'docs-test'
    search_endpoint = 'https://test-cleanup.search.windows.net'
    api_version = '2026-04-01'
    index_name = 'docs-test-knowledge'
    knowledge_source_name = 'docs-test-published'
    knowledge_base_name = 'docs-test-architecture'
    project_ids = @{ alpha = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test/projects/alpha' }
}
# Test-scoped transport; normal entry points never use these responses.
$fixture = @{ mode = 'success'; removed = @{}; deletes = @(); authentication = 0 }
function Assert-Cleanup([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Start-Job {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList)
    @{ State = 'Completed'; Result = @(& $ScriptBlock @ArgumentList) }
}
function Wait-Job { param($Job, [int]$Timeout) $Job }
function Receive-Job { param($Job, $ErrorAction) $Job.Result }
function Stop-Job { param($Job) $Job.State = 'Stopped' }
function Remove-Job { param($Job, [switch]$Force) }
function az {
    Assert-Cleanup (($args[0..1] -join ' ') -eq 'account get-access-token') 'Cleanup may authenticate but cannot mutate through Azure CLI.'
    Assert-Cleanup ('--subscription' -in $args -and '--tenant' -notin $args) 'Azure CLI rejects simultaneous subscription and tenant selectors; verify the returned tenant instead.'
    $fixture.authentication++
    $global:LASTEXITCODE = 0
    @{ accessToken = 'unmistakably-test-scoped-token'; tenant = $contract.tenant_id; subscription = $contract.subscription_id } | ConvertTo-Json
}
function Invoke-WebRequest {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [switch]$SkipHttpErrorCheck, [int]$TimeoutSec)
    Assert-Cleanup ($TimeoutSec -gt 0 -and $TimeoutSec -le 30) 'Every HTTP call must remain bounded.'
    if ($fixture.mode -eq 'forbidden') { return @{ StatusCode = 403; Content = '{"error":"denied"}' } }
    if ($Method -eq 'DELETE') {
        $fixture.deletes += $Uri
        $fixture.removed[$Uri] = $true
        return @{ StatusCode = 204; Content = '' }
    }
    Assert-Cleanup ($Method -eq 'GET') 'Only GET and DELETE are permitted.'
    if ($fixture.removed.ContainsKey($Uri)) { return @{ StatusCode = 404; Content = '' } }
    $body = if ($Uri -match '/connections/') {
        @{ properties = @{
            category = 'RemoteTool'; isSharedToAll = $false
            target = if ($fixture.mode -eq 'wrong-target') { 'https://other.invalid' } else {
                "$($contract.search_endpoint)/knowledgebases/$($contract.knowledge_base_name)/mcp?api-version=2026-04-01"
            }
        } }
    } elseif ($Uri -match '/knowledgebases/') {
        @{ knowledgeSources = @(@{ name = $contract.knowledge_source_name }) }
    } elseif ($Uri -match '/knowledgesources/') {
        @{ kind = 'searchIndex'; searchIndexParameters = @{ searchIndexName = $contract.index_name } }
    } else { throw "Unexpected test request: $Uri" }
    @{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 10) }
}
try {
    & $script -Knowledge $contract -OutputDirectory $directory -WhatIf | Out-Null
    Assert-Cleanup ($fixture.authentication -eq 0) 'WhatIf must make no authentication or HTTP calls.'
    & $script -Knowledge $contract -OutputDirectory $directory -Confirm:$false | Out-Null
    Assert-Cleanup ($fixture.deletes.Count -eq 3) 'Remove exactly the private connection, base and source.'
    Assert-Cleanup ($fixture.deletes[0] -match '/connections/' -and
        $fixture.deletes[1] -match '/knowledgebases/' -and
        $fixture.deletes[2] -match '/knowledgesources/') 'Delete references before their dependencies, never the Terraform-owned index.'
    & $script -Knowledge $contract -OutputDirectory $directory -Confirm:$false | Out-Null
    Assert-Cleanup ($fixture.deletes.Count -eq 3) 'A second cleanup must verify already-absent resources without more deletes.'
    foreach ($mode in @('wrong-target', 'forbidden')) {
        $fixture.mode = $mode
        $fixture.removed.Clear()
        $failed = $false
        try { & $script -Knowledge $contract -OutputDirectory $directory -Confirm:$false | Out-Null } catch {
            if ($_.Exception.Message -notmatch 'unexpected/shared|HTTP 403') { throw }
            $failed = $true
        }
        Assert-Cleanup $failed "Reject $mode without a success-shaped fallback."
        Assert-Cleanup ($fixture.deletes.Count -eq 3) 'Do not delete an unexpected connection or suppress authorization failure.'
    }
    $source = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\knowledge.tf') -Raw
    Assert-Cleanup ($source -match 'input\s*=\s*local.knowledge_contract' -and
        $source -match 'when\s*=\s*destroy' -and $source -match 'jsonencode\(self.input\)') 'Native Terraform must persist the actual contract and invoke cleanup before index destruction.'
    Write-Output 'Knowledge cleanup tests passed: dry run, exact ordered scope, verified absence/idempotence, wrong-target refusal and explicit403. Test-scoped transport only.'
} finally {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse }
    $global:LASTEXITCODE = $previousExitCode
}
