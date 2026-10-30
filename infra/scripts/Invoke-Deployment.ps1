#requires -Version 7.5
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,39}$')]
    [string]$Scenario,
    [Parameter(Mandatory)]
    [ValidateSet('Inspect', 'Validate', 'Plan', 'BuildImages', 'InitializeKnowledge', 'Preflight')]
    [string]$Action,
    [ValidateSet('Foundation', 'Access', 'Workload')]
    [string]$Component = 'Foundation',
    [string]$Inputs
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$inspection = @{ Scenario = $Scenario }
$settings = $null
if ($Inputs) {
    $settings = Get-Content -LiteralPath $Inputs -Raw |
        ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
    if ($settings -isnot [System.Collections.IDictionary]) {
        throw 'Deployment inputs must be a JSON object.'
    }
    if ($settings.ContainsKey('profile')) { $inspection.Profile = $settings.profile }
    if ($settings.ContainsKey('enable_search')) {
        if ($settings.enable_search -isnot [bool]) {
            throw 'enable_search must be a JSON boolean.'
        }
        $inspection.EnableSearch = $settings.enable_search
    }
    if ($settings.ContainsKey('model_overrides')) {
        if ($settings.model_overrides -isnot [System.Collections.IDictionary]) {
            throw 'model_overrides must be a JSON object.'
        }
        $inspection.ModelOverrides = $settings.model_overrides
    }
    if ($settings.ContainsKey('workload_inputs')) {
        if ($settings.workload_inputs -isnot [System.Collections.IDictionary]) {
            throw 'workload_inputs must be a JSON object.'
        }
        $inspection.WorkloadInputs = $settings.workload_inputs
    }
}
$review = & (Join-Path $PSScriptRoot 'Inspect-Deployment.ps1') @inspection -AsJson |
    ConvertFrom-Json -AsHashtable -Depth 30
$roots = @{
    Foundation = Join-Path $root 'infra\foundation'
    Access = Join-Path $root 'infra\access'
    Workload = $review.workload.terraform_root
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments) {
    & terraform "-chdir=$Directory" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Terraform failed in $Directory (exit $LASTEXITCODE)." }
}

if ($Action -eq 'Inspect') {
    & (Join-Path $PSScriptRoot 'Inspect-Deployment.ps1') @inspection
    return
}
if ($Action -eq 'Validate') {
    foreach ($directory in @($roots.Foundation, $roots.Access, $roots.Workload)) {
        Invoke-Terraform $directory @('init', '-backend=false', '-input=false', '-no-color')
        Invoke-Terraform $directory @('validate', '-no-color')
    }
    return
}

if (-not $Inputs) { throw "$Action requires an explicit deployment input file." }
foreach ($key in @('subscription_id', 'tenant_id')) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($settings[$key], [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw "Replace $key with the explicitly approved target GUID."
    }
}
if ($Action -eq 'Preflight') {
    & (Join-Path $PSScriptRoot 'Test-DeploymentPreflight.ps1') -Settings $settings -Review $review `
        -OutputDirectory (Join-Path $root "out\$($settings.subscription_id)\preflight")
    return
}
if ($Action -eq 'Plan' -and $Component -eq 'Foundation') {
    if ($settings.protection -isnot [System.Collections.IDictionary]) {
        throw 'Supply reviewed protection limits before foundation planning.'
    }
    foreach ($key in @('monthly_cap_eur', 'reserve_eur', 'max_hourly_eur')) {
        $value = $settings.protection[$key]
        if (($value -isnot [long] -and $value -isnot [int] -and
             $value -isnot [double] -and $value -isnot [decimal]) -or
            -not [double]::IsFinite([double]$value) -or $value -le 0) {
            throw "Supply a reviewed positive JSON number for protection.$key."
        }
    }
    if ($settings.protection.reserve_eur -ge $settings.protection.monthly_cap_eur) {
        throw 'The reviewed protection reserve must be below the monthly cap.'
    }
}
if ($settings.suffix -notmatch '^[a-z0-9]{4,10}$' -or
    $settings.workload_name -notmatch '^[a-z][a-z0-9-]{2,28}[a-z0-9]$') {
    throw 'Invalid deployment suffix or workload name.'
}
if ($settings.profile -notin @('lite', 'full')) { throw 'Choose lite or full explicitly.' }
if ([DateTimeOffset]$settings.expires_at -le [DateTimeOffset]::UtcNow) {
    throw 'Spending authorization is expired.'
}
if (-not ($settings.teams -is [System.Collections.IDictionary]) -or $settings.teams.Count -eq 0) {
    throw 'Supply the deployment-time team roster.'
}
$members = @()
$requiresRoster = $Action -eq 'Plan' -and $Component -in @('Access', 'Workload')
foreach ($team in $settings.teams.Keys) {
    if ($team -notmatch '^[a-z][a-z0-9-]{0,30}$' -or $team -eq 'facilitator' -or
        ($requiresRoster -and @($settings.teams[$team]).Count -eq 0)) {
        throw "Invalid or empty team '$team'."
    }
    if (-not $requiresRoster) { continue }
    foreach ($member in $settings.teams[$team]) {
        if (-not ($member -is [string]) -or $member -match '\.example$|REPLACE_' -or
            [string]::IsNullOrWhiteSpace($member)) {
            throw 'Replace all example roster entries with real work-account UPNs or tenant object IDs.'
        }
        $members += $member.Trim().ToLowerInvariant()
    }
}
if ($requiresRoster -and ($members.Count -ne $settings.expected_participant_count -or
    @($members | Sort-Object -Unique).Count -ne $members.Count)) {
    throw 'Supply the complete expected roster, without duplicate membership.'
}
if ($Component -eq 'Workload' -and $Action -eq 'Plan') {
    foreach ($key in $review.workload.inputs.Keys) {
        if ($null -eq $review.workload.inputs[$key]) {
            throw "Supply the selected scenario's required workload input '$key'."
        }
    }
}
$account = az account show --subscription $settings.subscription_id -o json |
    ConvertFrom-Json -AsHashtable
if ($LASTEXITCODE -ne 0 -or $account.id -ne $settings.subscription_id -or
    $account.tenantId -ne $settings.tenant_id) {
    throw 'Authenticated target subscription/tenant could not be verified.'
}

$subscriptionKey = ([guid]$settings.subscription_id).ToString('D')
$deploymentDirectory = Join-Path $root "out\$subscriptionKey\$($settings.suffix)"
$stateDirectory = Join-Path $deploymentDirectory 'state'
$contexts = @{}
foreach ($key in @('Foundation', 'Access', 'Workload')) {
    $stateKey = if ($key -eq 'Workload') { "workloads\$($settings.workload_name)" } else { $key.ToLowerInvariant() }
    $contexts[$key] = @{
        Directory = $roots[$key]
        StateFile = Join-Path $stateDirectory "$stateKey.tfstate"
        DataDirectory = Join-Path $deploymentDirectory "terraform-data\$stateKey"
    }
}

function Invoke-ComponentTerraform([string]$Key, [string[]]$Arguments) {
    $previousDataDirectory = $env:TF_DATA_DIR
    try {
        $env:TF_DATA_DIR = $contexts[$Key].DataDirectory
        Invoke-Terraform $contexts[$Key].Directory $Arguments
    } finally {
        $env:TF_DATA_DIR = $previousDataDirectory
    }
}

function Initialize-Component([string]$Key) {
    $context = $contexts[$Key]
    New-Item -ItemType Directory -Path (Split-Path -Parent $context.StateFile) -Force | Out-Null
    if ($Key -eq 'Workload') {
        $ownershipFile = Join-Path $stateDirectory "workloads\$($settings.workload_name).owner.json"
        if (Test-Path -LiteralPath $ownershipFile) {
            $owner = Get-Content -LiteralPath $ownershipFile -Raw | ConvertFrom-Json -AsHashtable
            if ($owner.scenario -cne $Scenario -or
                $owner.subscription_id -ne $settings.subscription_id -or
                $owner.tenant_id -ne $settings.tenant_id) {
                throw 'This workload name is already reserved by another scenario or target; choose a different workload name.'
            }
        } else {
            @{
                scenario = $Scenario
                subscription_id = $settings.subscription_id
                tenant_id = $settings.tenant_id
                workload_name = $settings.workload_name
            } | ConvertTo-Json | Set-Content -LiteralPath $ownershipFile -Encoding utf8NoBOM
        }
    }
    Invoke-ComponentTerraform $Key @(
        'init', '-input=false', '-no-color', "-backend-config=path=$($context.StateFile)"
    )
}

$variables = @{}
if ($Action -eq 'InitializeKnowledge') {
    Initialize-Component 'Workload'
    $raw = Invoke-ComponentTerraform 'Workload' @('output', '-json', 'knowledge')
    $knowledge = $raw | ConvertFrom-Json -AsHashtable -Depth 30
    if ($knowledge.subscription_id -ne $settings.subscription_id -or
        $knowledge.tenant_id -ne $settings.tenant_id -or
        $knowledge.workload_name -cne $settings.workload_name) {
        throw 'Applied workload knowledge contract does not match the explicitly selected target.'
    }
    & (Join-Path $PSScriptRoot 'Initialize-Knowledge.ps1') -Knowledge $knowledge `
        -OutputDirectory (Join-Path $deploymentDirectory "knowledge\$($settings.workload_name)") `
        -WhatIf:$WhatIfPreference
    return
}
if ($Action -eq 'BuildImages') {
    Initialize-Component 'Foundation'
    $raw = Invoke-ComponentTerraform 'Foundation' @('output', '-json', 'foundation')
    $foundation = $raw | ConvertFrom-Json -AsHashtable -Depth 30
    if ($foundation.subscription_id -ne $settings.subscription_id -or
        $foundation.tenant_id -ne $settings.tenant_id -or $foundation.contract_version -ne 1) {
        throw 'Applied foundation does not match the explicitly selected target.'
    }
    $artifactDirectory = Join-Path $deploymentDirectory "artifacts\$($settings.workload_name)"
    & (Join-Path $PSScriptRoot 'Build-WorkloadImages.ps1') -Scenario $Scenario `
        -WorkloadName $settings.workload_name -Foundation $foundation -OutputDirectory $artifactDirectory `
        -WhatIf:$WhatIfPreference
    return
}
if ($Component -eq 'Foundation') {
    foreach ($key in @('subscription_id', 'tenant_id', 'location', 'search_location',
        'suffix', 'profile', 'publisher_email', 'expires_at', 'tags', 'protection')) {
        if (-not $settings.ContainsKey($key)) { throw "Missing foundation input '$key'." }
        $variables[$key] = $settings[$key]
    }
    $variables.team_names = @($settings.teams.Keys)
    $variables.enable_search = 'search' -in $review.foundation.capabilities
} else {
    Initialize-Component 'Foundation'
    $raw = Invoke-ComponentTerraform 'Foundation' @('output', '-json', 'foundation')
    $foundation = $raw | ConvertFrom-Json -AsHashtable -Depth 30
    if ($foundation.subscription_id -ne $settings.subscription_id -or
        $foundation.tenant_id -ne $settings.tenant_id) {
        throw 'Applied foundation does not match the explicitly selected target.'
    }
    $variables.foundation = $foundation
    if ($Component -eq 'Access') {
        $variables.teams = $settings.teams
        $variables.expected_participant_count = $settings.expected_participant_count
    } else {
        $variables.workload_name = $settings.workload_name
        $variables.models = $review.workload.models
        foreach ($key in $review.workload.inputs.Keys) {
            $variables[$key] = $review.workload.inputs[$key]
        }
        if ($review.workload.requires_participant_access) {
            Initialize-Component 'Access'
            $rawAccess = Invoke-ComponentTerraform 'Access' @('output', '-json', 'deployment_access')
            $access = $rawAccess | ConvertFrom-Json -AsHashtable -Depth 30
            if ($access.contract_version -ne 1 -or
                $access.subscription_id -ne $foundation.subscription_id -or
                $access.tenant_id -ne $foundation.tenant_id -or
                $access.resource_group_id -ne $foundation.resource_group_id) {
                throw 'Applied access does not match the selected foundation.'
            }
            if ($access.teams.Count -ne $settings.teams.Count) {
                throw 'Applied access roster is stale; review and apply the new access plan first.'
            }
            foreach ($team in $settings.teams.Keys) {
                if (-not $access.teams.ContainsKey($team)) {
                    throw 'Applied access roster is stale; review and apply the new access plan first.'
                }
                $expected = @($settings.teams[$team] | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object)
                $actual = @($access.teams[$team] | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object)
                if ((ConvertTo-Json -InputObject $expected -Compress) -cne
                    (ConvertTo-Json -InputObject $actual -Compress)) {
                    throw 'Applied access roster is stale; review and apply the new access plan first.'
                }
            }
            $variables.participant_members = $access.members
        }
    }
}

$directory = Join-Path $deploymentDirectory 'plans'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
$variableFile = Join-Path $directory "$Component-$stamp.tfvars.json"
$planFile = Join-Path $directory "$Component-$stamp.tfplan"
$variables | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $variableFile -Encoding utf8NoBOM
Initialize-Component $Component
Invoke-ComponentTerraform $Component @('validate', '-no-color')
Invoke-ComponentTerraform $Component @('plan', '-input=false', '-no-color', "-var-file=$variableFile", "-out=$planFile")
Write-Output "Saved $Component plan: $planFile"
Write-Output "SHA256: $((Get-FileHash -LiteralPath $planFile -Algorithm SHA256).Hash)"
Write-Output "State: $($contexts[$Component].StateFile)"
Write-Output "TF_DATA_DIR: $($contexts[$Component].DataDirectory)"
Write-Warning 'PLAN ONLY. Module 0 is not accepted. Do not apply until protection, prerequisites and every planned resource/permission have been reviewed together.'
