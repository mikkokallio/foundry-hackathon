#requires -Version 7.5
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][hashtable]$Knowledge,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
foreach ($key in @('subscription_id', 'tenant_id')) {
    $id = [guid]::Empty
    if (-not [guid]::TryParse($Knowledge[$key], [ref]$id) -or $id -eq [guid]::Empty) {
        throw "Knowledge cleanup requires an explicit $key GUID."
    }
}
$endpoint = [uri]$Knowledge.search_endpoint
$legacyContract = $Knowledge.contract_version -eq 1 -and
    -not $Knowledge.ContainsKey('knowledge_base_api_version') -and -not $Knowledge.ContainsKey('mcp_api_version')
$currentContract = $Knowledge.contract_version -eq 2 -and
    $Knowledge.knowledge_base_api_version -ceq '2026-05-01-preview' -and
    $Knowledge.mcp_api_version -ceq '2026-05-01-preview'
if ((-not $legacyContract -and -not $currentContract) -or $Knowledge.api_version -cne '2026-04-01' -or
    $Knowledge.workload_name -cnotmatch '^[a-z][a-z0-9-]{2,28}[a-z0-9]$' -or
    $endpoint.Scheme -cne 'https' -or $endpoint.Port -ne 443 -or
    $endpoint.Host -cnotmatch '^[a-z0-9][a-z0-9-]+\.search\.windows\.net$' -or
    $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment -or $endpoint.AbsolutePath -ne '/') {
    throw 'Invalid knowledge cleanup contract or noncanonical Azure Search endpoint.'
}
foreach ($name in @($Knowledge.index_name, $Knowledge.knowledge_source_name, $Knowledge.knowledge_base_name)) {
    if ($name -cnotmatch '^[a-z0-9][a-z0-9-]{1,126}[a-z0-9]$' -or
        -not $name.StartsWith("$($Knowledge.workload_name)-", [StringComparison]::Ordinal)) {
        throw 'Cleanup names must belong to the selected workload namespace.'
    }
}
if ($Knowledge.project_ids -isnot [Collections.IDictionary] -or $Knowledge.project_ids.Count -eq 0) {
    throw 'Actual Foundry project IDs are required for knowledge connection cleanup.'
}
foreach ($entry in $Knowledge.project_ids.GetEnumerator()) {
    if ($entry.Key -cnotmatch '^[a-z][a-z0-9-]{0,30}$' -or
        $entry.Value -cnotmatch "^/subscriptions/$([regex]::Escape($Knowledge.subscription_id))/resourceGroups/[^/]+/providers/Microsoft.CognitiveServices/accounts/[^/]+/projects/$([regex]::Escape($entry.Key))$") {
        throw 'Knowledge connection project is outside the selected subscription or has a mismatched project key.'
    }
}
$search = $endpoint.AbsoluteUri.TrimEnd('/')
$version = $Knowledge.api_version
$baseVersion = if ($legacyContract) { $version } else { $Knowledge.knowledge_base_api_version }
$mcpVersion = if ($legacyContract) { $version } else { $Knowledge.mcp_api_version }
$mcp = "$search/knowledgebases/$($Knowledge.knowledge_base_name)/mcp?api-version=$mcpVersion"
if (-not $PSCmdlet.ShouldProcess($search, 'Delete only this workload knowledge connections, base and source before its index')) {
    return
}
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
$directory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$events = [Collections.Generic.List[object]]::new()
$receipt = @{ operation = 'remove-workload-knowledge'; completed = $false; events = $events }
function Get-RemainingSeconds {
    $left = [Math]::Ceiling(($deadline - [DateTimeOffset]::UtcNow).TotalSeconds)
    if ($left -le 0) { throw 'Knowledge cleanup deadline expired; deletion is not verified.' }
    return [int][Math]::Min(30, $left)
}
function Get-CleanupToken([string]$Audience) {
    $arguments = @('account', 'get-access-token', '--subscription', $Knowledge.subscription_id,
        '--resource', $Audience, '--only-show-errors', '-o', 'json')
    $job = Start-Job -ScriptBlock {
        param([string[]]$Arguments)
        $lines = @(& az @Arguments 2>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ code = $LASTEXITCODE; lines = $lines }
    } -ArgumentList (,$arguments)
    try {
        if (-not (Wait-Job -Job $job -Timeout (Get-RemainingSeconds))) {
            Stop-Job -Job $job
            throw 'Azure CLI authentication timed out during knowledge cleanup.'
        }
        $result = @(Receive-Job -Job $job -ErrorAction Stop)
        if ($result.Count -ne 1 -or $result[0].code -ne 0) { throw 'Knowledge cleanup authentication failed.' }
        $token = ($result[0].lines -join "`n") | ConvertFrom-Json -AsHashtable -DateKind String
        if (-not $token.accessToken -or $token.tenant -cne $Knowledge.tenant_id -or
            $token.subscription -cne $Knowledge.subscription_id) {
            throw 'Knowledge cleanup token does not match the selected subscription and tenant.'
        }
        return $token.accessToken
    } finally {
        if ($job.State -eq 'Running') { Stop-Job -Job $job }
        Remove-Job -Job $job -Force
    }
}
function Invoke-CleanupRequest([string]$Method, [string]$Url) {
    $token = if ($Url.StartsWith("$search/", [StringComparison]::Ordinal)) {
        $searchToken
    } elseif ($Url.StartsWith('https://management.azure.com/', [StringComparison]::Ordinal)) {
        $armToken
    } else { throw 'Unexpected endpoint in knowledge cleanup.' }
    $response = Invoke-WebRequest -Method $Method -Uri $Url -Headers @{ Authorization = "Bearer $token" } `
        -SkipHttpErrorCheck -TimeoutSec (Get-RemainingSeconds)
    $status = [int]$response.StatusCode
    $events.Add(@{ method = $Method; url = $Url; status = $status })
    if ($status -eq 404) { return @{ status = $status } }
    if (($Method -eq 'GET' -and $status -ne 200) -or
        ($Method -eq 'DELETE' -and $status -notin @(200, 202, 204))) {
        throw "Knowledge cleanup $Method failed: HTTP $status at $Url."
    }
    $body = $null
    if ($Method -eq 'GET') {
        $body = $response.Content | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
        if ($null -eq $body) { throw "Knowledge cleanup GET returned no JSON at $Url." }
    }
    return @{ status = $status; body = $body }
}
function Remove-CleanupResource([string]$Url) {
    $null = Invoke-CleanupRequest 'DELETE' $Url
    while ((Invoke-CleanupRequest 'GET' $Url).status -ne 404) {
        Start-Sleep -Seconds ([Math]::Min(2, (Get-RemainingSeconds)))
    }
    Write-Output "Verified absent: $Url"
}
try {
    $searchToken = Get-CleanupToken 'https://search.azure.com'
    $armToken = Get-CleanupToken 'https://management.azure.com/'
    foreach ($entry in $Knowledge.project_ids.GetEnumerator()) {
        $name = "$($Knowledge.workload_name)-$($entry.Key)-knowledge"
        $url = "https://management.azure.com$($entry.Value)/connections/${name}?api-version=2025-06-01"
        $current = Invoke-CleanupRequest 'GET' $url
        if ($current.status -eq 404) { Write-Output "Already absent: $url"; continue }
        if ($current.body.properties.target -cne $mcp -or
            $current.body.properties.isSharedToAll -ne $false -or
            $current.body.properties.category -cne 'RemoteTool') {
            throw "Refusing to delete an unexpected/shared knowledge connection: $url."
        }
        Remove-CleanupResource $url
    }
    $base = "$search/knowledgebases/$($Knowledge.knowledge_base_name)?api-version=$baseVersion"
    $current = Invoke-CleanupRequest 'GET' $base
    if ($current.status -ne 404) {
        if (@($current.body.knowledgeSources).Count -ne 1 -or
            $current.body.knowledgeSources[0].name -cne $Knowledge.knowledge_source_name) {
            throw 'Refusing to delete a knowledge base with unexpected sources.'
        }
        Remove-CleanupResource $base
    } else { Write-Output "Already absent: $base" }
    $source = "$search/knowledgesources/$($Knowledge.knowledge_source_name)?api-version=$version"
    $current = Invoke-CleanupRequest 'GET' $source
    if ($current.status -ne 404) {
        if ($current.body.kind -cne 'searchIndex' -or
            $current.body.searchIndexParameters.searchIndexName -cne $Knowledge.index_name) {
            throw 'Refusing to delete a knowledge source referencing another index.'
        }
        Remove-CleanupResource $source
    } else { Write-Output "Already absent: $source" }
    $receipt.completed = $true
} finally {
    $receipt | ConvertTo-Json -Depth 15 |
        Set-Content -LiteralPath (Join-Path $directory 'cleanup.json') -Encoding utf8NoBOM
}
