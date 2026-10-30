#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$initializer = Join-Path $root 'infra\scripts\Initialize-Knowledge.ps1'
$outputDirectory = Join-Path $root "out\knowledge-tests-$([guid]::NewGuid().ToString('N'))"
$previousExitCode = $global:LASTEXITCODE

# Test-scoped responses only. This test cannot invoke Azure or Foundry.
$knowledgeTest = @{ mode = 'success'; calls = @(); runs = @{}; statusPolls = @{}; configured = @{}; failures = @(); delays = @(); kills = 0; waits = @() }
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
        beta = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.CognitiveServices/accounts/test-only/projects/beta'
    }
}

function Assert-Knowledge([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-TestArgument([object[]]$Arguments, [string]$Name) {
    $index = [Array]::IndexOf($Arguments, $Name)
    if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) { throw "Missing test argument '$Name'." }
    return $Arguments[$index + 1]
}
function Start-Process {
    param($FilePath, $ArgumentList, $RedirectStandardOutput, $RedirectStandardError, [switch]$NoNewWindow, [switch]$PassThru)
    Assert-Knowledge ($ArgumentList -contains '-NonInteractive') 'CLI child must not request interactive input.'
    Assert-Knowledge $NoNewWindow 'CLI requests must run without opening extra console windows during Terraform apply.'
    $argumentPath = Join-Path (Split-Path $RedirectStandardOutput) 'cli-arguments.json'
    $arguments = @(Get-Content -LiteralPath $argumentPath -Raw | ConvertFrom-Json)
    $failure = $null
    if ($knowledgeTest.failures.Count -gt 0) {
        $failure = $knowledgeTest.failures[0]
        $knowledgeTest.failures = @($knowledgeTest.failures | Select-Object -Skip 1)
    } elseif ($knowledgeTest.mode -cin @('indexer-busy', 'indexer-busy-forever') -and
        ($arguments -contains 'post') -and (($arguments -join ' ') -match '/indexers/([^/]+)/reset\?')) {
        $key = "busy-$($Matches[1])"
        if ($knowledgeTest.mode -eq 'indexer-busy-forever' -or -not $knowledgeTest.statusPolls.ContainsKey($key)) {
            $knowledgeTest.statusPolls[$key] = 1
            $failure = "ERROR: Conflict: Cannot reset indexer '$($Matches[1])' while it is currently running. Please wait for the current run to complete and try again."
        }
    } elseif ($knowledgeTest.mode -eq 'persistent-403') {
        $failure = 'ERROR: Forbidden (403)'
    }
    if ($null -ne $failure) {
        $output = ''
        $exitCode = 1
    } else {
        $output = az @arguments
        $exitCode = $global:LASTEXITCODE
    }
    Set-Content -LiteralPath $RedirectStandardOutput -Value ($output -join "`n")
    "$failure" | Set-Content -LiteralPath $RedirectStandardError
    $process = [pscustomobject]@{ ExitCode = $exitCode; TestHang = ($knowledgeTest.mode -eq 'hang') }
    $process | Add-Member ScriptMethod WaitForExit {
        param($Milliseconds)
        $knowledgeTest.waits += $Milliseconds
        return -not $this.TestHang
    }
    $process | Add-Member ScriptMethod Kill { param($Tree); $knowledgeTest.kills++; Assert-Knowledge $Tree 'Kill only the owned CLI process tree.' }
    $process | Add-Member ScriptMethod Dispose {}
    return $process
}
function Start-Sleep {
    param([int]$Milliseconds)
    $knowledgeTest.delays += $Milliseconds
    if ($knowledgeTest.mode -cin @('persistent-403', 'hang', 'stale', 'empty-stats', 'reset-forever', 'indexer-busy-forever')) {
        Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds
    }
}
function az {
    $global:LASTEXITCODE = 0
    $knowledgeTest.calls += ,@($args)
    Assert-Knowledge ((Get-TestArgument $args '--subscription') -eq $contract.subscription_id) 'All knowledge operations must pin the selected subscription.'
    if ($args[0] -eq 'account') {
        @{ id = $contract.subscription_id; tenantId = $contract.tenant_id } | ConvertTo-Json
        return
    }
    Assert-Knowledge ($args[0] -eq 'rest') 'Unexpected test command.'
    $url = Get-TestArgument $args '--url'
    $method = Get-TestArgument $args '--method'
    if ($url.StartsWith('https://test-only.search.windows.net/')) {
        Assert-Knowledge ((Get-TestArgument $args '--resource') -ceq 'https://search.azure.com') 'Search must use Entra authentication for the Search audience.'
        $expectedVersion = if ($url -match '/knowledgebases/') { '2026-05-01-preview' } elseif ($url -match '/knowledgesources/') { '2026-04-01' } else { '2024-07-01' }
        Assert-Knowledge ($url.EndsWith("?api-version=$expectedVersion")) 'Pin index, knowledge-source and knowledge-base APIs independently.'
    }
    if ($url -match '/indexers/([^/]+)/(status|reset|run)\?') {
        $name, $operation = $Matches[1], $Matches[2]
        if ($operation -eq 'run') { $knowledgeTest.runs[$name] = [int]$knowledgeTest.runs[$name] + 1; return }
        if ($operation -eq 'reset') { return }
        $fresh = $knowledgeTest.runs.ContainsKey($name) -and $knowledgeTest.mode -ne 'stale'
        if ($fresh -and $knowledgeTest.mode -cin @('reset-then-success', 'reset-forever')) {
            $knowledgeTest.statusPolls[$name] = [int]$knowledgeTest.statusPolls[$name] + 1
            if ($knowledgeTest.mode -eq 'reset-forever' -or $knowledgeTest.statusPolls[$name] -eq 1) {
                @{
                    status = 'running'
                    lastResult = @{
                        status = 'reset'
                        startTime = ([DateTimeOffset]'2020-01-01T00:00:00Z').AddDays(1).AddSeconds(-1).ToString('o')
                        itemsProcessed = 0
                        itemsFailed = 0
                        errors = @()
                    }
                } | ConvertTo-Json -Depth 10
                return
            }
        }
        @{
            status = 'running'
            lastResult = @{
                status = 'success'
                startTime = if ($fresh) { ([DateTimeOffset]'2020-01-01T00:00:00Z').AddDays($knowledgeTest.runs[$name]).ToString('o') } else { '2020-01-01T00:00:00Z' }
                itemsProcessed = if ($knowledgeTest.mode -eq 'empty') { 0 } else { 3 }
                itemsFailed = if ($knowledgeTest.mode -eq 'failed-items' -or
                    ($knowledgeTest.mode -eq 'indexer-transient' -and $fresh -and $knowledgeTest.runs[$name] -eq 1)) { 1 } else { 0 }
                errors = @(if ($knowledgeTest.mode -eq 'indexer-transient' -and $fresh -and $knowledgeTest.runs[$name] -eq 1) {
                    @{ message = 'Embedding request failed: Forbidden (403)' }
                })
            }
        } | ConvertTo-Json -Depth 10
        return
    }
    if ($url -match '/indexes/[^/]+/stats\?') {
        $knowledgeTest.statsCalls++
        @{ documentCount = if ($knowledgeTest.mode -eq 'empty-stats' -or
            ($knowledgeTest.mode -eq 'stats-lag' -and $knowledgeTest.statsCalls -eq 1)) { 0 } else { 6 } } |
            ConvertTo-Json
        return
    }
    if ($method -eq 'get' -and $url -match '/(knowledgesources|knowledgebases|connections)/') {
        Assert-Knowledge ($knowledgeTest.configured.ContainsKey($url)) 'Read back only actual test writes.'
        $actual = $knowledgeTest.configured[$url] | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
        if ($url -match '/knowledgebases/') {
            switch ($knowledgeTest.mode) {
                'missing-reasoning' { $actual.Remove('retrievalReasoningEffort') }
                'wrong-reasoning' { $actual.retrievalReasoningEffort.kind = 'low' }
                'missing-output' { $actual.Remove('outputMode') }
                'wrong-output' { $actual.outputMode = 'answerSynthesis' }
                'missing-models' { $actual.Remove('models') }
                'null-models' { $actual.models = $null }
                'extra-model' { $actual.models = @(@{ kind = 'azureOpenAI' }) }
                'wrong-base-source' { $actual.knowledgeSources = @(@{ name = 'other-source' }) }
                'extra-base-source' { $actual.knowledgeSources += @{ name = 'other-source' } }
            }
        } elseif ($url -match '/knowledgesources/') {
            switch ($knowledgeTest.mode) {
                'wrong-source-index' { $actual.searchIndexParameters.searchIndexName = 'other-index' }
                'wrong-semantic' { $actual.searchIndexParameters.semanticConfigurationName = 'other' }
                'missing-source-fields' { $actual.searchIndexParameters.Remove('sourceDataFields') }
                'wrong-search-fields' { $actual.searchIndexParameters.searchFields = @(@{ name = 'title' }) }
            }
        }
        $actual | ConvertTo-Json -Depth 30
        return
    }
    Assert-Knowledge ($method -eq 'put') 'Only declared configuration writes are allowed.'
    $bodyArgument = Get-TestArgument $args '--body'
    Assert-Knowledge ($bodyArgument.StartsWith('@')) 'Payloads must use a reviewed JSON file, not CLI-interpreted inline JSON.'
    $body = Get-Content -LiteralPath $bodyArgument.Substring(1) -Raw | ConvertFrom-Json -AsHashtable
    if ($url -match '/knowledgesources/') {
        Assert-Knowledge ($body.kind -ceq 'searchIndex') 'Use a real Search index knowledge source.'
        Assert-Knowledge ($body.searchIndexParameters.searchIndexName -ceq $contract.index_name) 'Knowledge must use the workload-owned index.'
        Assert-Knowledge ($body.searchIndexParameters.semanticConfigurationName -ceq 'architecture') 'GA knowledge sources require the declared semantic configuration.'
        Assert-Knowledge ($body.searchIndexParameters.sourceDataFields[0].name -ceq 'chunk_id') 'Source data fields must be named field-reference objects.'
    } elseif ($url -match '/knowledgebases/') {
        Assert-Knowledge (@($body.knowledgeSources).Count -eq 1 -and $body.knowledgeSources[0].name -ceq $contract.knowledge_source_name) 'Extractive knowledge must use only the declared source.'
        Assert-Knowledge ($body.models -is [array] -and $body.models.Count -eq 0) 'Explicitly disable knowledge-base models; do not add another LLM.'
        Assert-Knowledge ($body.retrievalReasoningEffort.kind -ceq 'minimal' -and $body.outputMode -ceq 'extractiveData') 'Use the preview minimal/extractive defaults required by a model-free knowledge base.'
    } elseif ($url -match '/connections/') {
        Assert-Knowledge ($url -cmatch '/projects/(alpha|beta)/connections/architecture-docs-\1-knowledge\?') 'Every selected project needs its own private, project-specific connection.'
        Assert-Knowledge ($body.properties.isSharedToAll -eq $false) 'Knowledge connections must remain project-private.'
        Assert-Knowledge ($body.properties.target.EndsWith('/mcp?api-version=2026-05-01-preview')) 'Use the supported independently pinned knowledge-base MCP endpoint.'
        Assert-Knowledge ($body.properties.authType -ceq 'ProjectManagedIdentity') 'Knowledge connections must not use admin keys.'
        if ($knowledgeTest.mode -eq 'wrong-connection') { $body.properties.authType = 'ApiKey' }
    } else {
        throw "Unexpected test URL: $url"
    }
    $knowledgeTest.configured[$url] = $body
    if ($knowledgeTest.mode -ne 'empty-put') { $body | ConvertTo-Json -Depth 30 }
}
function Invoke-TestInitialization([string]$Directory, [int]$TimeoutSeconds = 1) {
    $knowledgeTest.runs = @{}
    $knowledgeTest.statusPolls = @{}
    & $initializer -Knowledge $contract -OutputDirectory $Directory -Confirm:$false -TimeoutSeconds $TimeoutSeconds | Out-Null
}

try {
    & $initializer -Knowledge $contract -OutputDirectory $outputDirectory -WhatIf | Out-Null
    Assert-Knowledge (@($knowledgeTest.calls | Where-Object { $_[0] -eq 'rest' }).Count -eq 0) 'WhatIf must not reset, run or configure anything.'
    Assert-Knowledge (-not (Test-Path -LiteralPath $outputDirectory)) 'WhatIf must not write an accepted initialization.'

    Invoke-TestInitialization $outputDirectory
    $receiptFile = @(Get-ChildItem -LiteralPath $outputDirectory -Recurse -Filter 'initialization.json')
    Assert-Knowledge ($receiptFile.Count -eq 1) 'Persist exactly one completed ingestion/configuration receipt.'
    $receipt = Get-Content -LiteralPath $receiptFile[0].FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 50
    Assert-Knowledge (-not $receipt.release_accepted -and $receipt.foundry_evaluation_required) 'Ingestion must never masquerade as Foundry acceptance.'
    Assert-Knowledge ($receipt.indexers.Count -eq 2 -and $receipt.index_stats.documentCount -gt 0) 'Both fresh source runs and positive index statistics are required.'
    Assert-Knowledge ($receipt.connections.Count -eq $contract.project_ids.Count) 'Every selected project needs its real knowledge connection.'
    Assert-Knowledge ($receipt.knowledge_base.retrievalReasoningEffort.kind -ceq 'minimal' -and
        $receipt.knowledge_base.outputMode -ceq 'extractiveData' -and
        $receipt.knowledge_base.models -is [array] -and $receipt.knowledge_base.models.Count -eq 0) 'Persist actual model-free minimal/extractive readback, not merely the intended payload.'
    foreach ($mode in @('missing-reasoning', 'wrong-reasoning', 'missing-output', 'wrong-output',
        'missing-models', 'null-models', 'extra-model', 'wrong-base-source', 'extra-base-source',
        'wrong-source-index', 'wrong-semantic', 'missing-source-fields', 'wrong-search-fields')) {
        $knowledgeTest.mode = $mode
        $directory = Join-Path $outputDirectory $mode
        $rejected = $false
        try { Invoke-TestInitialization $directory 30 } catch {
            if ($_.Exception.Message -notmatch 'intended knowledge (base|source)') { throw }
            $rejected = $true
        }
        Assert-Knowledge $rejected "Reject unexpected actual readback '$mode'."
        Assert-Knowledge (@(Get-ChildItem -LiteralPath $directory -Recurse -Filter 'initialization.json').Count -eq 0) 'Unexpected defaults or source/model drift cannot produce completion evidence.'
    }
    $knowledgeTest.mode = 'empty-put'
    Invoke-TestInitialization (Join-Path $outputDirectory 'empty-put')
    Assert-Knowledge (@($knowledgeTest.calls | Where-Object {
        $_ -contains 'get' -and ($_ -join ' ') -match '/knowledgesources/'
    }).Count -ge 2) 'A successful empty update must still have fresh readback verification.'

    $knowledgeTest.mode = 'reset-then-success'
    $knowledgeTest.delays = @()
    Invoke-TestInitialization (Join-Path $outputDirectory 'reset-then-success') 30
    Assert-Knowledge (@($knowledgeTest.statusPolls.Values | Where-Object { $_ -ne 2 }).Count -eq 0) 'Poll past each fresh reset marker and require the subsequent positive successful run.'
    Assert-Knowledge (@($knowledgeTest.runs.Values | Where-Object { $_ -ne 1 }).Count -eq 0) 'A reset marker must not trigger another reset/run.'
    Assert-Knowledge (($knowledgeTest.delays -join ',') -ceq '5000,5000') 'Wait between reset markers and actual completed runs, without a busy loop.'

    $knowledgeTest.mode = 'indexer-busy'
    $knowledgeTest.delays = @()
    Invoke-TestInitialization (Join-Path $outputDirectory 'indexer-busy') 30
    Assert-Knowledge (($knowledgeTest.delays -join ',') -ceq '2000,2000') 'Retry each busy indexer reset within the existing deadline.'
    Assert-Knowledge (@($knowledgeTest.runs.Values | Where-Object { $_ -ne 1 }).Count -eq 0) 'Busy reset recovery must still require exactly one fresh run per indexer.'

    foreach ($mode in @('empty', 'failed-items', 'stale', 'wrong-connection', 'empty-stats', 'reset-forever')) {
        $knowledgeTest.mode = $mode
        $directory = Join-Path $outputDirectory $mode
        $rejected = $false
        try {
            Invoke-TestInitialization $directory
        } catch {
            if ($_.Exception.Message -notmatch 'positive-item verification|Timed out waiting|deadline exceeded|intended knowledge connection') { throw }
            $rejected = $true
        }
        Assert-Knowledge $rejected "Reject '$mode' explicitly."
        Assert-Knowledge (@(Get-ChildItem -LiteralPath $directory -Recurse -Filter 'initialization.json').Count -eq 0) 'Failed/incomplete work must not have a completion receipt.'
    }
    $knowledgeTest.mode = 'stats-lag'
    $knowledgeTest.statsCalls = 0
    Invoke-TestInitialization (Join-Path $outputDirectory 'stats-lag') 30
    Assert-Knowledge ($knowledgeTest.statsCalls -eq 2) 'Require a fresh positive statistics response after asynchronous propagation.'
    $knowledgeTest.mode = 'success'
    $knowledgeTest.failures = @('ERROR: Forbidden (403)', 'ERROR: TooManyRequests (429)',
        'ERROR: ServiceUnavailable (503)', 'ERROR: ConnectionError: connection reset')
    $knowledgeTest.delays = @()
    Invoke-TestInitialization (Join-Path $outputDirectory 'retry-success') 30
    Assert-Knowledge (($knowledgeTest.delays -join ',') -ceq '2000,4000,8000,15000') 'Classified failures require bounded exponential backoff.'
    Assert-Knowledge ($knowledgeTest.failures.Count -eq 0) 'All transient failure classes must recover without fallback.'
    $knowledgeTest.mode = 'indexer-transient'
    Invoke-TestInitialization (Join-Path $outputDirectory 'indexer-retry-success') 30
    Assert-Knowledge (@($knowledgeTest.runs.Values | Where-Object { $_ -ne 2 }).Count -eq 0) 'Both indexers must recover through fresh real reruns after transient embedding/RBAC failures.'
    foreach ($mode in @('bad-request', 'cancelled', 'unrelated-conflict', 'indexer-busy-forever', 'persistent-403', 'hang')) {
        $knowledgeTest.mode = $mode
        $knowledgeTest.failures = if ($mode -eq 'bad-request') { @('ERROR: Bad Request (400)') } elseif ($mode -eq 'cancelled') { @('^C') } elseif ($mode -eq 'unrelated-conflict') { @('ERROR: Conflict (409): a different resource already exists') } else { @() }
        $knowledgeTest.delays = @()
        $directory = Join-Path $outputDirectory $mode
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $rejected = $false
        try { Invoke-TestInitialization $directory } catch {
            if ($_.Exception.Message -notmatch 'nonretryable|deadline exceeded') { throw }
            $rejected = $true
        }
        Assert-Knowledge $rejected "Reject '$mode' without a completion receipt."
        Assert-Knowledge ($timer.Elapsed.TotalSeconds -lt 3) 'Persistent failures and hung calls must respect the one-second test deadline.'
        Assert-Knowledge (@(Get-ChildItem -LiteralPath $directory -Recurse -Filter 'initialization.json').Count -eq 0) 'No failed retry sequence may produce acceptance evidence.'
        if ($mode -cin @('bad-request', 'cancelled', 'unrelated-conflict')) {
            Assert-Knowledge ($knowledgeTest.delays.Count -eq 0) 'Do not retry nontransient 400 errors or explicit cancellation.'
        }
    }
    Assert-Knowledge ($knowledgeTest.kills -gt 0) 'Hung CLI calls must terminate their owned process tree.'
    Assert-Knowledge (@($knowledgeTest.waits | Where-Object { $_ -gt 60000 -or $_ -le 0 }).Count -eq 0) 'Every CLI call must have a positive, capped wait.'
    $knowledgeTest.mode = 'success'
    $before = $knowledgeTest.calls.Count
    foreach ($key in @('contract_version', 'api_version', 'knowledge_base_api_version', 'mcp_api_version')) {
        $original = $contract[$key]
        $contract[$key] = if ($key -eq 'contract_version') { 1 } else { 'unsupported' }
        $rejected = $false
        try { Invoke-TestInitialization (Join-Path $outputDirectory "invalid-$key") } catch {
            if ($_.Exception.Message -notmatch 'Unsupported knowledge contract') { throw }
            $rejected = $true
        } finally { $contract[$key] = $original }
        Assert-Knowledge ($rejected -and $knowledgeTest.calls.Count -eq $before) 'Reject stale or unpinned creation contracts before authentication or mutation.'
    }
    $before = $knowledgeTest.calls.Count
    $contract.search_endpoint = 'https://untrusted.example.invalid/'
    $rejected = $false
    try {
        Invoke-TestInitialization (Join-Path $outputDirectory 'unsafe-target')
    } catch {
        if ($_.Exception.Message -notmatch 'noncanonical Azure Search endpoint') { throw }
        $rejected = $true
    }
    Assert-Knowledge ($rejected -and $knowledgeTest.calls.Count -eq $before) 'Reject unsafe targets before any Azure operation.'
    Write-Output 'Knowledge contracts passed using test-scoped responses only; no Azure/Foundry acceptance occurred.'
} finally {
    if (Test-Path -LiteralPath $outputDirectory) { Remove-Item -LiteralPath $outputDirectory -Recurse }
    $global:LASTEXITCODE = $previousExitCode
}
