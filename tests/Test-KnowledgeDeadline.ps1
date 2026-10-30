#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scratch = Join-Path $root "out\knowledge-deadline-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
$previousPath = $env:PATH
$childId = $null
try {
    # This PATH-local az executable only sleeps. It cannot contact Azure.
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    "@`"$pwsh`" -NoProfile -NonInteractive -File `"%~dp0test-az.ps1`"" |
        Set-Content -LiteralPath (Join-Path $scratch 'az.cmd') -Encoding ascii
    @'
$PID | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'child.pid')
Start-Sleep -Seconds 60
throw 'The test-only hung CLI must have been terminated.'
'@ | Set-Content -LiteralPath (Join-Path $scratch 'test-az.ps1')
    $env:PATH = "$scratch;$previousPath"
    $contract = @{
        contract_version = 2
        subscription_id = '00000000-0000-0000-0000-000000000001'
        tenant_id = '00000000-0000-0000-0000-000000000002'
        workload_name = 'architecture-docs'
        search_endpoint = 'https://test-only.search.windows.net/'
        index_name = 'architecture-docs-knowledge'
        knowledge_source_name = 'architecture-docs-published-architecture'
        knowledge_base_name = 'architecture-docs-architecture'
        api_version = '2026-04-01'
        knowledge_base_api_version = '2026-05-01-preview'
        mcp_api_version = '2026-05-01-preview'
        indexer_names = @('architecture-docs-published', 'architecture-docs-standards')
        project_ids = @{
            alpha = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.CognitiveServices/accounts/test-only/projects/alpha'
        }
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $rejected = $false
    try {
        & (Join-Path $root 'infra\scripts\Initialize-Knowledge.ps1') -Knowledge $contract `
            -OutputDirectory (Join-Path $scratch 'evidence') -Confirm:$false -TimeoutSeconds 5 | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'deadline exceeded') { throw }
        $rejected = $true
    }
    if (-not $rejected -or $timer.Elapsed.TotalSeconds -ge 9) {
        throw 'A real hung CLI process escaped the shared deadline.'
    }
    $childId = [int](Get-Content -LiteralPath (Join-Path $scratch 'child.pid'))
    for ($i = 0; $i -lt 10 -and (Get-Process -Id $childId -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Milliseconds 100
    }
    if (Get-Process -Id $childId -ErrorAction SilentlyContinue) {
        throw 'The owned CLI descendant survived deadline cancellation.'
    }
    if (Get-ChildItem -LiteralPath $scratch -Recurse -Filter 'initialization.json') {
        throw 'Timed-out initialization wrote a completion receipt.'
    }
    Write-Output 'Real test-only hung CLI and descendant were terminated within the shared deadline; no Azure calls or completion receipt.'
} finally {
    $env:PATH = $previousPath
    if ($childId -and (Get-Process -Id $childId -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $childId
    }
    Remove-Item -LiteralPath $scratch -Recurse
}
