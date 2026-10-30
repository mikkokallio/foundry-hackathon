#requires -Version 7.5
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][hashtable]$Knowledge,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
foreach ($key in @('subscription_id', 'tenant_id')) {
    $id = [guid]::Empty
    if (-not [guid]::TryParse($Knowledge[$key], [ref]$id) -or $id -eq [guid]::Empty) {
        throw "Knowledge contract requires an explicit $key GUID."
    }
}
$endpoint = [uri]$Knowledge.search_endpoint
if ($Knowledge.contract_version -ne 2 -or $Knowledge.api_version -cne '2026-04-01' -or
    $Knowledge.knowledge_base_api_version -cne '2026-05-01-preview' -or
    $Knowledge.mcp_api_version -cne '2026-05-01-preview' -or
    $Knowledge.workload_name -cnotmatch '^[a-z][a-z0-9-]{2,28}[a-z0-9]$' -or
    $endpoint.Scheme -cne 'https' -or $endpoint.Port -ne 443 -or
    $endpoint.Host -notmatch '^[a-z0-9][a-z0-9-]+\.search\.windows\.net$' -or
    $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment -or $endpoint.AbsolutePath -ne '/') {
    throw 'Unsupported knowledge contract or noncanonical Azure Search endpoint.'
}
foreach ($name in @($Knowledge.index_name, $Knowledge.knowledge_source_name,
    $Knowledge.knowledge_base_name) + @($Knowledge.indexer_names)) {
    if ($name -cnotmatch '^[a-z0-9][a-z0-9-]{1,126}[a-z0-9]$' -or
        -not $name.StartsWith("$($Knowledge.workload_name)-", [StringComparison]::Ordinal)) {
        throw 'Knowledge resource names must belong to the selected workload namespace.'
    }
}
if (@($Knowledge.indexer_names).Count -ne 2 -or
    @($Knowledge.indexer_names | Sort-Object -Unique).Count -ne 2 -or
    $Knowledge.project_ids -isnot [System.Collections.IDictionary] -or
    $Knowledge.project_ids.Count -eq 0) {
    throw 'Supply both applied source indexers and the actual Foundry project IDs.'
}
foreach ($project in $Knowledge.project_ids.Values) {
    if ($project -notmatch "^/subscriptions/$([regex]::Escape($Knowledge.subscription_id))/resourceGroups/[^/]+/providers/Microsoft.CognitiveServices/accounts/[^/]+/projects/[^/]+$") {
        throw 'A knowledge connection project is outside the selected subscription or has an invalid resource ID.'
    }
}

$searchUrl = $endpoint.AbsoluteUri.TrimEnd('/')
$version = $Knowledge.api_version
$baseVersion = $Knowledge.knowledge_base_api_version
$mcpUrl = "$searchUrl/knowledgebases/$($Knowledge.knowledge_base_name)/mcp?api-version=$($Knowledge.mcp_api_version)"
$source = @{
    name = $Knowledge.knowledge_source_name
    kind = 'searchIndex'
    description = 'Published synthetic architecture documents, documentation standard and glossary.'
    searchIndexParameters = @{
        searchIndexName = $Knowledge.index_name
        semanticConfigurationName = 'architecture'
        searchFields = @(@{ name = 'content' }, @{ name = 'title' })
        sourceDataFields = @(@{ name = 'chunk_id' }, @{ name = 'content' },
            @{ name = 'title' }, @{ name = 'source_url' })
    }
}
$base = @{
    name = $Knowledge.knowledge_base_name
    description = 'Extractive grounding; the Foundry agent supplies reasoning and answers.'
    knowledgeSources = @(@{ name = $Knowledge.knowledge_source_name })
    models = @()
    retrievalReasoningEffort = @{ kind = 'minimal' }
    outputMode = 'extractiveData'
}
$connection = @{
    properties = @{
        category = 'RemoteTool'
        authType = 'ProjectManagedIdentity'
        target = $mcpUrl
        audience = 'https://search.azure.com'
        isSharedToAll = $false
    }
}
$plan = @{
    operation = 'initialize-workload-knowledge'
    subscription_id = $Knowledge.subscription_id
    tenant_id = $Knowledge.tenant_id
    search_endpoint = $searchUrl
    knowledge_source = $source
    knowledge_base = $base
    connection = $connection
    projects = $Knowledge.project_ids
    reset_and_run_indexers = @($Knowledge.indexer_names)
    release_accepted = $false
    foundry_evaluation_required = $true
}
if (-not $PSCmdlet.ShouldProcess($searchUrl,
    'Reset/reingest both sources (embedding calls), configure knowledge base and Foundry project connections')) {
    $plan
    return
}

$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory -Force -WhatIf:$false | Out-Null
$plan | ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath (Join-Path $runDirectory 'intent.json') -Encoding utf8NoBOM -WhatIf:$false
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)

function Test-KnowledgeTransientError([string]$Text) {
    $Text -match '(?i)\b(403|429|5\d\d)\b|Forbidden|AuthorizationPermissionMismatch|AuthorizationFailed|TooManyRequests|ServiceUnavailable|InternalServerError|BadGateway|GatewayTimeout|ConnectionError|ConnectionResetError|ConnectTimeout|ReadTimeout|NameResolutionError|NewConnectionError|RemoteDisconnected|ProxyError|timed out|connection (reset|aborted|refused)|remote end closed|name resolution|temporar(il)?y unavailable'
}

function Wait-KnowledgeRetry([int]$Seconds) {
    $remaining = ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds
    if ($remaining -le 0) { throw 'Knowledge initialization deadline exceeded; initialization is NOT accepted.' }
    Start-Sleep -Milliseconds ([int][Math]::Min($Seconds * 1000, [Math]::Ceiling($remaining)))
}

function Invoke-KnowledgeCli([string[]]$Arguments) {
    $argumentPath = Join-Path $runDirectory 'cli-arguments.json'
    $stdoutPath = Join-Path $runDirectory 'cli-stdout.json'
    $stderrPath = Join-Path $runDirectory 'cli-stderr.txt'
    ConvertTo-Json -InputObject $Arguments -Compress |
        Set-Content -LiteralPath $argumentPath -Encoding utf8NoBOM
    $escapedPath = $argumentPath.Replace("'", "''")
    $command = "`$arguments = Get-Content -LiteralPath '$escapedPath' -Raw | ConvertFrom-Json; & az @arguments; exit `$LASTEXITCODE"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $delay = 2
    try {
        while ($true) {
            $remaining = ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds
            if ($remaining -le 0) { throw 'Knowledge initialization deadline exceeded; initialization is NOT accepted.' }
            $executable = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
            $process = Start-Process -FilePath (Join-Path $PSHOME $executable) `
                -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
                -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
            try {
                # Individual hung calls cannot consume the entire ingestion budget.
                $remaining = ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds
                $waitMilliseconds = [int][Math]::Max(1, [Math]::Min(60000, [Math]::Floor($remaining)))
                if (-not $process.WaitForExit($waitMilliseconds)) {
                    $process.Kill($true)
                    $failure = 'Azure CLI transport timed out.'
                } else {
                    if ([DateTimeOffset]::UtcNow -ge $deadline) {
                        throw 'Knowledge initialization deadline exceeded; initialization is NOT accepted.'
                    }
                    if ($process.ExitCode -eq 0) {
                        return Get-Content -LiteralPath $stdoutPath -Raw
                    }
                    $failure = Get-Content -LiteralPath $stderrPath -Raw
                }
            } finally {
                $process.Dispose()
            }
            $indexerBusy = ($Arguments -contains 'post') -and
                (($Arguments -join ' ') -match '/indexers/[^/]+/(reset|run)\?') -and
                ($failure -match '(?i)Cannot (reset|run) indexer .+ (while it is currently running|because it is already running)')
            if (-not $indexerBusy -and -not (Test-KnowledgeTransientError $failure)) {
                $failure | Set-Content -LiteralPath (Join-Path $runDirectory 'cli-failure.txt') -Encoding utf8NoBOM
                throw "Azure CLI failed with a nonretryable error; initialization is NOT accepted. See $runDirectory."
            }
            Write-Warning "Transient Azure CLI failure; retrying within the initialization deadline (delay ${delay}s)."
            Wait-KnowledgeRetry $delay
            $delay = [Math]::Min(15, $delay * 2)
        }
    } finally {
        Remove-Item -LiteralPath $argumentPath, $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }
}

function Invoke-KnowledgeRequest([string]$Method, [string]$Url, [hashtable]$Body) {
    $arguments = @('rest', '--method', $Method, '--url', $Url,
        '--subscription', $Knowledge.subscription_id, '--only-show-errors', '-o', 'json')
    if ($Url.StartsWith("$searchUrl/", [StringComparison]::Ordinal)) {
        $arguments += @('--resource', 'https://search.azure.com')
    } elseif (-not $Url.StartsWith('https://management.azure.com/', [StringComparison]::Ordinal)) {
        throw 'Knowledge requests may target only the reviewed Search and ARM endpoints.'
    }
    if ($null -ne $Body) {
        $bodyPath = Join-Path $runDirectory 'request.json'
        $Body | ConvertTo-Json -Depth 30 |
            Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM -WhatIf:$false
        $arguments += @('--headers', 'Content-Type=application/json', '--body', "@$bodyPath")
    }
    $raw = Invoke-KnowledgeCli $arguments
    if ([string]::IsNullOrWhiteSpace(($raw -join "`n"))) {
        if ($Method -notin @('post', 'put')) { throw "Knowledge $Method returned no JSON: $Url" }
        return
    }
    $raw | ConvertFrom-Json -AsHashtable -Depth 50
}

function Wait-Indexer([string]$Name, [Nullable[DateTimeOffset]]$After, [bool]$RequireFresh) {
    do {
        $status = Invoke-KnowledgeRequest 'get' "$searchUrl/indexers/$Name/status?api-version=2024-07-01"
        $result = $status.lastResult
        if ($status.status -eq 'error') { throw "Indexer '$Name' has a service error; initialization is NOT accepted." }
        if ($null -ne $result -and $result.status -ne 'inProgress' -and
            (-not $RequireFresh -or $result.status -ne 'reset')) {
            if (-not $RequireFresh) { return $result }
            if ($result.startTime -and ($null -eq $After -or [DateTimeOffset]$result.startTime -gt $After)) {
                if ($result.status -ne 'success' -or $null -eq $result.itemsProcessed -or
                    $result.itemsProcessed -le 0 -or $null -eq $result.itemsFailed -or
                    $result.itemsFailed -ne 0 -or @($result.errors).Count -ne 0) {
                    $result | ConvertTo-Json -Depth 30 |
                        Set-Content -LiteralPath (Join-Path $runDirectory "$Name.failed.json") -Encoding utf8NoBOM
                    if (Test-KnowledgeTransientError (@($result.errorMessage, $result.errors) | ConvertTo-Json -Depth 30)) {
                        Wait-KnowledgeRetry 5
                        $After = [DateTimeOffset]$result.startTime
                        $null = Invoke-KnowledgeRequest 'post' "$searchUrl/indexers/$Name/reset?api-version=2024-07-01"
                        $null = Invoke-KnowledgeRequest 'post' "$searchUrl/indexers/$Name/run?api-version=2024-07-01"
                        continue
                    }
                    throw "Indexer '$Name' failed fresh positive-item verification; initialization is NOT accepted."
                }
                return $result
            }
        } elseif ($null -eq $result -and -not $RequireFresh) {
            return $null
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) { throw "Timed out waiting for '$Name'; initialization is NOT accepted." }
        Wait-KnowledgeRetry 5
    } while ($true)
}

$account = Invoke-KnowledgeCli @('account', 'show', '--subscription', $Knowledge.subscription_id, '-o', 'json') |
    ConvertFrom-Json -AsHashtable
if ($account.id -ne $Knowledge.subscription_id -or $account.tenantId -ne $Knowledge.tenant_id) {
    throw 'Authenticated subscription/tenant does not match the applied knowledge contract.'
}

$indexerEvidence = @{}
foreach ($name in $Knowledge.indexer_names) {
    $before = Wait-Indexer $name $null $false
    $after = if ($null -ne $before -and $before.startTime) { [DateTimeOffset]$before.startTime } else { $null }
    $null = Invoke-KnowledgeRequest 'post' "$searchUrl/indexers/$name/reset?api-version=2024-07-01"
    $null = Invoke-KnowledgeRequest 'post' "$searchUrl/indexers/$name/run?api-version=2024-07-01"
    $indexerEvidence[$name] = Wait-Indexer $name $after $true
    $indexerEvidence[$name] | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath (Join-Path $runDirectory "$name.status.json") -Encoding utf8NoBOM
}
do {
    $stats = Invoke-KnowledgeRequest 'get' "$searchUrl/indexes/$($Knowledge.index_name)/stats?api-version=2024-07-01"
    if ($null -eq $stats.documentCount) { throw 'Search returned no document count; initialization is NOT accepted.' }
    if ($stats.documentCount -gt 0) { break }
    Write-Warning 'Fresh indexer runs succeeded; waiting for Search document-count propagation.'
    Wait-KnowledgeRetry 5
} while ($true)
$sourceUrl = "$searchUrl/knowledgesources/$($source.name)?api-version=$version"
$null = Invoke-KnowledgeRequest 'put' $sourceUrl $source
$actualSource = Invoke-KnowledgeRequest 'get' $sourceUrl
if ($actualSource.name -cne $source.name -or $actualSource.kind -cne 'searchIndex' -or
    $actualSource.searchIndexParameters.searchIndexName -cne $Knowledge.index_name -or
    $actualSource.searchIndexParameters.semanticConfigurationName -cne 'architecture' -or
    (@($actualSource.searchIndexParameters.searchFields.name | Sort-Object) -join ',') -cne 'content,title' -or
    (@($actualSource.searchIndexParameters.sourceDataFields.name | Sort-Object) -join ',') -cne 'chunk_id,content,source_url,title') {
    throw 'Search did not return the intended knowledge source.'
}
$baseUrl = "$searchUrl/knowledgebases/$($base.name)?api-version=$baseVersion"
$null = Invoke-KnowledgeRequest 'put' $baseUrl $base
$actualBase = Invoke-KnowledgeRequest 'get' $baseUrl
if ($actualBase.name -cne $base.name -or @($actualBase.knowledgeSources).Count -ne 1 -or
    $actualBase.knowledgeSources[0].name -cne $source.name -or
    $actualBase.retrievalReasoningEffort.kind -cne 'minimal' -or
    $actualBase.outputMode -cne 'extractiveData' -or
    $actualBase.models -isnot [array] -or $actualBase.models.Count -ne 0) {
    throw 'Search did not return the intended knowledge base.'
}
$connectionEvidence = @{}
foreach ($projectName in $Knowledge.project_ids.Keys) {
    $projectId = $Knowledge.project_ids[$projectName]
    $url = "https://management.azure.com$projectId/connections/$($Knowledge.workload_name)-$projectName-knowledge?api-version=2025-04-01-preview"
    $null = Invoke-KnowledgeRequest 'put' $url $connection
    $actual = Invoke-KnowledgeRequest 'get' $url
    foreach ($key in @('category', 'authType', 'target', 'audience', 'isSharedToAll')) {
        if ($actual.properties[$key] -cne $connection.properties[$key]) {
            throw "Project '$projectName' did not return the intended knowledge connection '$key'."
        }
    }
    $connectionEvidence[$projectName] = $actual
}
@{
    operation = 'workload-knowledge-initialized'
    completed_at = [DateTimeOffset]::UtcNow.ToString('o')
    contract = $Knowledge
    indexers = $indexerEvidence
    index_stats = $stats
    knowledge_source = $actualSource
    knowledge_base = $actualBase
    connections = $connectionEvidence
    mcp_endpoint = $mcpUrl
    release_accepted = $false
    foundry_evaluation_required = $true
} | ConvertTo-Json -Depth 50 |
    Set-Content -LiteralPath (Join-Path $runDirectory 'initialization.json') -Encoding utf8NoBOM
Write-Output "Knowledge ingestion/configuration verified. Foundry invocation, evaluation and trace acceptance are still required. Evidence: $runDirectory"
