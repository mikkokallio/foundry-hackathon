#requires -Version 7.5
<#
.SYNOPSIS
Creates native Terraform input files using the shared deployment example and private people file.
.DESCRIPTION
Only reads the selected Azure CLI account (cached account show); never logs in, switches
accounts, resolves users, initializes a backend or deploys. Identity syntax checks cannot
prove that a user is a real human; supply reviewed tenant users, resolved by the access stage.
FoundationOnly needs just a monitored publisher_email. Full mode additionally needs explicit
librarians and a nonempty roster for a nonempty subset of the declared teams. Remove unused
team keys from the private people file. Librarians may also be participants. The deploying operator
is never added. Keep the people file and generated inputs private.
Existing foundation inputs are reused unchanged; access/workload files are never overwritten.
Applied foundation, participant_members and built runtime_images must be supplied separately.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$PeopleFile,
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [string]$Suffix,
    [switch]$FoundationOnly
)

$ErrorActionPreference = 'Stop'

function Test-TargetGuid($Value) {
    $parsed = [guid]::Empty
    return ($Value -is [string] -and
        $Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and
        [guid]::TryParse($Value, [ref]$parsed) -and $parsed -ne [guid]::Empty)
}

function Test-ActualEmail($Value) {
    if ($Value -isnot [string] -or $Value -cne $Value.Trim() -or
        $Value -notmatch '^[^@\s<>]+@([a-z0-9-]+\.)+[a-z]{2,}$' -or
        $Value -match '(?i)REPLACE|placeholder|[<>]') { return $false }
    $domain = $Value.Split('@')[1]
    return ($domain -notmatch '(?i)(^|\.)(example|invalid|test|localhost)$|(^|\.)(example|contoso)\.(com|net|org)$' -and
        $domain -notmatch '(?i)^(your[-.]|tenant\.)')
}

function Assert-IdentityList($Values, [string]$Label, [System.Collections.Generic.HashSet[string]]$Seen) {
    if ($Values -isnot [array] -or $Values.Count -eq 0) {
        throw "$Label must be a nonempty JSON array of explicitly selected real tenant users."
    }
    foreach ($value in $Values) {
        if (-not (Test-TargetGuid $value) -and -not (Test-ActualEmail $value)) {
            throw "$Label contains an empty, placeholder or malformed identity."
        }
        if (-not $Seen.Add($value)) { throw "$Label contains a repeated identity." }
    }
}

function ConvertTo-CanonicalJson($Value) {
    function Sort-Value($Item) {
        if ($Item -is [System.Collections.IDictionary]) {
            $sorted = [ordered]@{}
            foreach ($key in ($Item.Keys | Sort-Object -CaseSensitive)) {
                $sorted[$key] = Sort-Value $Item[$key]
            }
            return $sorted
        }
        if ($Item -is [array]) { return ,@($Item | ForEach-Object { Sort-Value $_ }) }
        return $Item
    }
    ConvertTo-Json -InputObject (Sort-Value $Value) -Depth 50 -Compress
}

if (-not (Test-TargetGuid $SubscriptionId)) { throw 'SubscriptionId must be an explicit nonempty subscription GUID.' }
if ($PSBoundParameters.ContainsKey('Suffix') -and $Suffix -cnotmatch '^[a-z0-9]{4,10}$') {
    throw 'Suffix must contain 4-10 lowercase letters/digits.'
}
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\deployment.example.json') -Raw |
    ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
$people = Get-Content -LiteralPath $PeopleFile -Raw | ConvertFrom-Json -AsHashtable -Depth 30
if ($people -isnot [System.Collections.IDictionary] -or
    @($people.Keys | Where-Object { $_ -cnotin @('publisher_email', 'librarians', 'teams') }).Count -gt 0) {
    throw 'PeopleFile must be a JSON object containing only publisher_email, librarians and teams.'
}
if (-not (Test-ActualEmail $people.publisher_email)) {
    throw 'Supply an actual monitored publisher_email, not an example or placeholder.'
}
$teamNames = @($settings.teams.Keys | Sort-Object)
$access = $null
if (-not $FoundationOnly) {
    if ($people.teams -isnot [System.Collections.IDictionary] -or
        $people.teams.Count -eq 0 -or
        @($people.teams.Keys | Where-Object { $_ -cnotin $teamNames }).Count -gt 0) {
        throw "PeopleFile teams must be a nonempty subset of: $($teamNames -join ', ')."
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($team in $people.teams.Keys) { Assert-IdentityList $people.teams[$team] "Team '$team'" $seen }
    $access = [ordered]@{ teams = $people.teams; expected_participant_count = $seen.Count }
    $publishers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    Assert-IdentityList $people.librarians 'Librarians' $publishers
}

$directory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$foundationPath = Join-Path $directory 'native-foundation.tfvars.json'
$accessPath = Join-Path $directory 'native-access.tfvars.json'
$workloadPath = Join-Path $directory 'native-workload.tfvars.json'
foreach ($path in @($accessPath, $workloadPath)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing existing access/workload file: $path" }
}
$existing = $null
if (Test-Path -LiteralPath $foundationPath) {
    $existing = Get-Content -LiteralPath $foundationPath -Raw |
        ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
    if ($existing -isnot [System.Collections.IDictionary] -or
        $existing.suffix -cnotmatch '^[a-z0-9]{4,10}$' -or
        ($PSBoundParameters.ContainsKey('Suffix') -and $Suffix -cne $existing.suffix)) {
        throw 'Existing foundation inputs have an invalid or different suffix.'
    }
    $Suffix = $existing.suffix
}
if (-not $Suffix) { $Suffix = [guid]::NewGuid().ToString('N').Substring(0, 8) }

$review = & (Join-Path $PSScriptRoot 'Inspect-Deployment.ps1') -Scenario $settings.workload_name `
    -Profile $settings.profile -ModelOverrides $settings.model_overrides `
    -WorkloadInputs $settings.workload_inputs -SearchConfiguration $settings.search_configuration `
    -EnableSearch $settings.enable_search -AsJson | ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
$accountText = & az account show --subscription $SubscriptionId -o json
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not read the explicitly selected subscription; authenticate separately.' }
$account = $accountText | ConvertFrom-Json -AsHashtable -Depth 10
if ($account -isnot [System.Collections.IDictionary] -or
    -not (Test-TargetGuid $account.id) -or $account.id -ine $SubscriptionId -or
    -not (Test-TargetGuid $account.tenantId)) {
    throw 'Azure CLI returned a different subscription or malformed subscription/tenant GUID.'
}
$foundation = [ordered]@{
    subscription_id = $SubscriptionId.ToLowerInvariant()
    tenant_id = $account.tenantId.ToLowerInvariant()
    suffix = $Suffix
    location = $settings.location
    search_location = $settings.search_location
    profile = $settings.profile
    publisher_email = $people.publisher_email
    team_names = $teamNames
    enable_search = 'search' -in $review.foundation.capabilities
    search_configuration = $review.foundation.search_configuration
    tags = $settings.tags
}
if ($null -ne $existing -and
    (ConvertTo-CanonicalJson $existing) -cne (ConvertTo-CanonicalJson $foundation)) {
    throw 'Existing foundation input/target differs (subscription, tenant, suffix, contact or shared defaults); nothing was written.'
}
$files = [ordered]@{}
if ($null -eq $existing) { $files[$foundationPath] = $foundation }
if (-not $FoundationOnly) {
    $workload = [ordered]@{ workload_name = $settings.workload_name; models = $review.workload.models }
    foreach ($key in $review.workload.inputs.Keys) {
        if ($key -notin @('runtime_images', 'librarians')) { $workload[$key] = $review.workload.inputs[$key] }
    }
    $workload.librarians = $people.librarians
    $files[$accessPath] = $access
    $files[$workloadPath] = $workload
}

# CreateNew also prevents overwriting a file created after the validation above.
$created = [System.Collections.Generic.List[string]]::new()
try {
    if ($files.Count -gt 0) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
    foreach ($path in $files.Keys) {
        $text = ($files[$path] | ConvertTo-Json -Depth 50) + [Environment]::NewLine
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        $created.Add($path)
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
} catch {
    foreach ($path in $created) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
    throw
}
Write-Output "Native inputs ready in $directory (suffix $Suffix). No Terraform or Azure deployment operations performed."
