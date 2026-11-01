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
$fixture = @{ mode = 'success'; removed = @{}; deletes = @(); authentication = 0; requests = @(); timeouts = 0 }
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
    $fixture.requests += @{ method = $Method; uri = $Uri }
    if ($Method -eq 'GET') {
        if ($fixture.mode -eq 'get-cancelled') {
            throw [Threading.Tasks.TaskCanceledException]::new('Test caller cancelled the request.')
        }
        if ($fixture.mode -eq 'get-timeout-expired') { Start-Sleep -Milliseconds 1100 }
        if ($fixture.mode -in @('get-timeout-always', 'get-timeout-expired') -or
            ($fixture.mode -eq 'get-timeout-once' -and $fixture.timeouts -eq 0) -or
            ($fixture.mode -eq 'verification-timeout-once' -and $fixture.removed.Count -gt 0 -and $fixture.timeouts -eq 0)) {
            $fixture.timeouts++
            throw [Threading.Tasks.TaskCanceledException]::new('Test HTTP request timed out.',
                [TimeoutException]::new('Test HttpClient timeout.'))
        }
    }
    if ($fixture.mode -eq 'forbidden') { return @{ StatusCode = 403; Content = '{"error":"denied"}' } }
    if ($Method -eq 'DELETE') {
        $fixture.deletes += $Uri
        $fixture.removed[$Uri] = $true
        if ($fixture.mode -eq 'delete-timeout') {
            throw [Threading.Tasks.TaskCanceledException]::new('Test DELETE outcome uncertain.',
                [TimeoutException]::new('Test HttpClient timeout.'))
        }
        return @{ StatusCode = 204; Content = '' }
    }
    Assert-Cleanup ($Method -eq 'GET') 'Only GET and DELETE are permitted.'
    if ($fixture.removed.ContainsKey($Uri)) { return @{ StatusCode = 404; Content = '' } }
    $body = if ($Uri -match '/connections/') {
        @{ properties = @{
            category = 'RemoteTool'; isSharedToAll = ($fixture.mode -eq 'shared')
            target = if ($fixture.mode -eq 'wrong-target') { 'https://other.invalid' } else {
                $mcpVersion = if ($contract.contract_version -eq 1) { '2026-04-01' } else { '2026-05-01-preview' }
                "$($contract.search_endpoint)/knowledgebases/$($contract.knowledge_base_name)/mcp?api-version=$mcpVersion"
            }
        } }
    } elseif ($Uri -match '/knowledgebases/') {
        $baseVersion = if ($contract.contract_version -eq 1) { '2026-04-01' } else { '2026-05-01-preview' }
        Assert-Cleanup ($Uri.EndsWith("?api-version=$baseVersion")) 'Cleanup must use the exact persisted knowledge-base management API.'
        @{ knowledgeSources = @(@{ name = $contract.knowledge_source_name }) }
    } elseif ($Uri -match '/knowledgesources/') {
        Assert-Cleanup ($Uri.EndsWith('?api-version=2026-04-01')) 'Cleanup must preserve the knowledge-source management API.'
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
    foreach ($mode in @('wrong-target', 'shared', 'forbidden')) {
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
    $fixture.mode = 'success'
    $fixture.removed.Clear()
    $fixture.deletes = @()
    $contract.contract_version = 2
    $contract.knowledge_base_api_version = '2026-05-01-preview'
    $contract.mcp_api_version = '2026-05-01-preview'
    & $script -Knowledge $contract -OutputDirectory $directory -Confirm:$false | Out-Null
    Assert-Cleanup ($fixture.deletes.Count -eq 3 -and
        $fixture.deletes[1].EndsWith('?api-version=2026-05-01-preview') -and
        $fixture.deletes[2].EndsWith('?api-version=2026-04-01')) 'Current cleanup must delete only its exact private connection, preview base and GA source.'
    $beforeAuthentication = $fixture.authentication
    foreach ($invalid in @(
        @{ contract_version = 3; knowledge_base_api_version = '2026-05-01-preview'; mcp_api_version = '2026-05-01-preview' },
        @{ contract_version = 2; knowledge_base_api_version = '2026-04-01'; mcp_api_version = '2026-05-01-preview' },
        @{ contract_version = 2; knowledge_base_api_version = '2026-05-01-preview'; mcp_api_version = '2026-04-01' },
        @{ contract_version = 1; knowledge_base_api_version = '2026-05-01-preview'; mcp_api_version = '2026-05-01-preview' }
    )) {
        $bad = $contract.Clone()
        foreach ($key in $invalid.Keys) { $bad[$key] = $invalid[$key] }
        $failed = $false
        try { & $script -Knowledge $bad -OutputDirectory $directory -Confirm:$false | Out-Null } catch {
            if ($_.Exception.Message -notmatch 'Invalid knowledge cleanup contract') { throw }
            $failed = $true
        }
        Assert-Cleanup $failed 'Reject unsupported/mixed cleanup versions instead of guessing the live connection target.'
    }
    Assert-Cleanup ($fixture.authentication -eq $beforeAuthentication) 'Reject unsupported cleanup contracts before authentication or mutation.'
    foreach ($mode in @('get-timeout-once', 'verification-timeout-once')) {
        $fixture.mode = $mode
        $fixture.removed.Clear()
        $fixture.deletes = @()
        $fixture.requests = @()
        $fixture.timeouts = 0
        $retryDirectory = Join-Path $directory $mode
        & $script -Knowledge $contract -OutputDirectory $retryDirectory -Confirm:$false | Out-Null
        Assert-Cleanup ($fixture.timeouts -eq 1 -and $fixture.deletes.Count -eq 3) 'Retry only the failed read, never duplicate a DELETE.'
        $receipt = Get-Content (Get-ChildItem $retryDirectory -Recurse -Filter cleanup.json).FullName -Raw |
            ConvertFrom-Json -AsHashtable
        $timeouts = @($receipt.events | Where-Object failure -eq 'http-request-timeout')
        Assert-Cleanup ($receipt.completed -eq $true -and $timeouts.Count -eq 1 -and
            $timeouts[0].retry -eq $true -and $timeouts[0].method -ceq 'GET') 'Retain timeout/retry evidence and verify actual absence.'
    }
    foreach ($mode in @('get-timeout-always', 'get-cancelled', 'delete-timeout')) {
        $fixture.mode = $mode
        $fixture.removed.Clear()
        $fixture.deletes = @()
        $fixture.requests = @()
        $fixture.timeouts = 0
        $failedDirectory = Join-Path $directory $mode
        $failed = $false
        try { & $script -Knowledge $contract -OutputDirectory $failedDirectory -Confirm:$false | Out-Null }
        catch [Threading.Tasks.TaskCanceledException] { $failed = $true }
        Assert-Cleanup $failed 'Exhausted timeout, caller cancellation and uncertain DELETE must surface errors.'
        $receipt = Get-Content (Get-ChildItem $failedDirectory -Recurse -Filter cleanup.json).FullName -Raw |
            ConvertFrom-Json -AsHashtable
        Assert-Cleanup ($receipt.completed -eq $false) 'Never write a completion-shaped receipt after failure.'
        if ($mode -eq 'get-timeout-always') {
            Assert-Cleanup ($fixture.requests.Count -eq 3 -and $fixture.deletes.Count -eq 0) 'Read retries are capped at three attempts before mutation.'
        } elseif ($mode -eq 'get-cancelled') {
            Assert-Cleanup ($fixture.requests.Count -eq 1 -and $fixture.deletes.Count -eq 0) 'Do not retry caller cancellation.'
        } else {
            Assert-Cleanup ($fixture.deletes.Count -eq 1 -and $fixture.requests.Count -eq 2) 'Never retry an uncertain DELETE.'
            $fixture.mode = 'success'
            & $script -Knowledge $contract -OutputDirectory (Join-Path $directory 'delete-reconciliation') -Confirm:$false | Out-Null
            Assert-Cleanup ($fixture.deletes.Count -eq 3) 'GET reconciliation must avoid deleting the already-absent uncertain resource again.'
        }
    }
    $fixture.mode = 'get-timeout-expired'
    $fixture.removed.Clear()
    $fixture.deletes = @()
    $fixture.requests = @()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $failed = $false
    try { & $script -Knowledge $contract -OutputDirectory (Join-Path $directory 'expired') -TimeoutSeconds 1 -Confirm:$false | Out-Null }
    catch [Threading.Tasks.TaskCanceledException] { $failed = $true }
    Assert-Cleanup ($failed -and $fixture.requests.Count -eq 1 -and $fixture.deletes.Count -eq 0 -and
        $timer.Elapsed.TotalSeconds -lt 3) 'Read retries cannot extend the existing overall cleanup deadline.'
    $source = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\knowledge.tf') -Raw
    Assert-Cleanup ($source -match 'input\s*=\s*local.knowledge_contract' -and
        $source -match 'when\s*=\s*destroy' -and $source -match 'jsonencode\(self.input\)') 'Native Terraform must persist the actual contract and invoke cleanup before index destruction.'
    Assert-Cleanup ($source -match 'filesha256\("\$\{path.module\}/../../../infra/scripts/Remove-Knowledge.ps1"\)') 'Cleanup script changes must participate in the scoped knowledge replacement trigger.'
    Write-Output 'Knowledge cleanup tests passed: scoped idempotence, bounded read-timeout recovery/deadline, cancellation and uncertain DELETE refusal. Test-scoped transport only.'
} finally {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse }
    $global:LASTEXITCODE = $previousExitCode
}
