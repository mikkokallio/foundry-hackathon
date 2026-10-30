#requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,39}$')]
    [string]$Scenario,
    [ValidateSet('lite', 'full')]
    [string]$Profile = 'lite',
    [hashtable]$ModelOverrides = @{},
    [hashtable]$WorkloadInputs = @{},
    [bool]$EnableSearch = $true,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scenarioDirectory = Join-Path $root "scenarios\$Scenario"
$manifestPath = Join-Path $scenarioDirectory 'scenario.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Scenario '$Scenario' has no manifest at $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw |
    ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
if ($manifest.schema_version -ne 1 -or $manifest.id -ne $Scenario) {
    throw 'Scenario schema version or directory identity does not match.'
}
if ($manifest.terraform_root -ne 'infra') {
    throw 'A scenario must use its own infra directory; external Terraform paths are not permitted.'
}
$workloadRoot = Join-Path $scenarioDirectory 'infra'
if (-not (Test-Path -LiteralPath (Join-Path $workloadRoot 'versions.tf') -PathType Leaf)) {
    throw 'The selected scenario has no Terraform root.'
}
$capabilities = @(
    'foundry', 'observability', 'gateway', 'catalog', 'storage',
    'key_vault', 'container_registry', 'container_environment', 'search'
)
$requirements = @($manifest.required_foundation_capabilities)
if ($requirements.Count -eq 0) {
    throw 'The scenario must explicitly declare its foundation requirements.'
}
$unknown = @($requirements | Where-Object { $_ -notin $capabilities })
if ($unknown.Count -gt 0) {
    throw "Unknown foundation requirements: $($unknown -join ', ')"
}
if ('search' -in $requirements -and -not $EnableSearch) {
    throw "Scenario '$Scenario' requires AI Search; it cannot be disabled."
}
if (-not ($manifest.models -is [System.Collections.IDictionary])) {
    throw 'The workload must declare its model requirements, possibly empty; the foundation supplies no defaults.'
}
foreach ($alias in $ModelOverrides.Keys) {
    if (-not $manifest.models.ContainsKey($alias)) {
        throw "Unknown model alias override '$alias'."
    }
    $manifest.models[$alias] = $ModelOverrides[$alias]
}
foreach ($alias in $manifest.models.Keys) {
    $model = $manifest.models[$alias]
    if ($alias -notmatch '^[a-z][a-z0-9-]{1,39}$' -or
        -not $model.name -or -not $model.version -or -not $model.sku -or
        -not ($model.capacity -is [long] -or $model.capacity -is [int]) -or
        $model.capacity -le 0) {
        throw "Invalid model declaration for '$alias'."
    }
}
$selectedInputs = @{}
if ($manifest.ContainsKey('terraform_inputs')) {
    if ($manifest.terraform_inputs -isnot [System.Collections.IDictionary]) {
        throw 'Scenario terraform_inputs must be a JSON object.'
    }
    foreach ($key in $manifest.terraform_inputs.Keys) {
        if ($key -in @('foundation', 'models', 'workload_name', 'participant_members') -or
            $key -notmatch '^[a-z][a-z0-9_]*$') {
            throw "Reserved or invalid workload input '$key'."
        }
        $selectedInputs[$key] = $manifest.terraform_inputs[$key]
    }
}
foreach ($key in $WorkloadInputs.Keys) {
    if (-not $selectedInputs.ContainsKey($key)) { throw "Unknown workload input '$key'." }
    $selectedInputs[$key] = $WorkloadInputs[$key]
}
foreach ($key in $selectedInputs.Keys) {
    if ($manifest.terraform_inputs[$key] -is [bool] -and $selectedInputs[$key] -isnot [bool]) {
        throw "Workload input '$key' must be a JSON boolean."
    }
}
if ($manifest.ContainsKey('requires_participant_access') -and
    $manifest.requires_participant_access -isnot [bool]) {
    throw 'requires_participant_access must be a boolean.'
}
$review = [ordered]@{
    operation = 'local-inspection-only'
    deployment_ready = $false
    azure_requests_made = $false
    scenario = $Scenario
    profile = $Profile
    foundation = @{
        terraform_root = Join-Path $root 'infra\foundation'
        capabilities = @($capabilities | Where-Object { $_ -ne 'search' -or $EnableSearch })
        model_deployments = @()
        gateway_sku = if ($Profile -eq 'lite') { 'BasicV2_1' } else { 'StandardV2_1' }
        search_sku = 'basic'
    }
    workload = @{
        terraform_root = $workloadRoot
        required_capabilities = $requirements
        models = $manifest.models
        inputs = $selectedInputs
        requires_participant_access = $manifest.requires_participant_access -eq $true
        core_modules = $manifest.core_modules
        bonus_modules = $manifest.bonus_modules
    }
    warnings = @(
        'Module 0 is not deployment-ready. Identity, protection, runtime and live acceptance are not complete.',
        'Model region availability, quota, Search features and prices require fresh verification before apply.',
        'Shared-service workshop authoring is approved; it permits cross-team lab configuration changes.',
        'Foundation and workload plans require separate explicit review. This command never applies anything.',
        'Existing lab resources still consume the same subscription budget.'
    )
}
if ($AsJson) {
    $review | ConvertTo-Json -Depth 30
} else {
    Write-Output 'LOCAL INSPECTION ONLY - NOT DEPLOYMENT ACCEPTANCE'
    Write-Output "Scenario: $Scenario; profile: $Profile"
    Write-Output "Foundation: $($review.foundation.terraform_root)"
    Write-Output "Workload: $workloadRoot"
    Write-Output 'Foundation model deployments: none'
    foreach ($alias in ($manifest.models.Keys | Sort-Object)) {
        $model = $manifest.models[$alias]
        Write-Output "Workload model $alias : $($model.name) / $($model.version), $($model.sku), capacity $($model.capacity)"
    }
    Write-Output "Workload inputs: $($selectedInputs | ConvertTo-Json -Depth 30 -Compress)"
    foreach ($warning in $review.warnings) { Write-Warning $warning }
}
