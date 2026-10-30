#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$entry = Join-Path $root 'infra\scripts\Invoke-Deployment.ps1'
$suffix = "tst$([guid]::NewGuid().ToString('N').Substring(0, 5))"
$outputDirectory = Join-Path $root "out\00000000-0000-0000-0000-000000000001\$suffix"
$inputPath = Join-Path ([IO.Path]::GetTempPath()) "deployment-plan-$([guid]::NewGuid()).json"
$previousExitCode = $global:LASTEXITCODE
$previousDataDirectory = $env:TF_DATA_DIR
if (Test-Path -LiteralPath $outputDirectory) { throw 'Test output directory must be new.' }

# Test-scoped command doubles: no Azure call or real Terraform plan is permitted.
$testFixture = @{}
$testFixture.account = @{
    id = '00000000-0000-0000-0000-000000000001'
    tenantId = '00000000-0000-0000-0000-000000000002'
}
$groupId = "/subscriptions/$($testFixture.account.id)/resourceGroups/test-only-foundation"
$testFixture.foundation = @{
    contract_version = 1
    subscription_id = $testFixture.account.id
    tenant_id = $testFixture.account.tenantId
    resource_group_id = $groupId
}
$testFixture.access = @{
    contract_version = 1
    subscription_id = $testFixture.account.id
    tenant_id = $testFixture.account.tenantId
    resource_group_id = $groupId
    teams = @{ alpha = @('participant@unit.invalid') }
    members = @{
        '00000000-0000-0000-0000-000000000003' = @{ team = 'alpha' }
    }
}
$settings = @{
    subscription_id = $testFixture.account.id
    tenant_id = $testFixture.account.tenantId
    suffix = $suffix
    workload_name = 'architecture-docs'
    profile = 'full'
    location = 'swedencentral'
    search_location = 'francecentral'
    publisher_email = 'operator@unit.invalid'
    expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o')
    expected_participant_count = 1
    teams = @{ alpha = @('PARTICIPANT@UNIT.INVALID') }
    tags = @{}
    protection = @{ monthly_cap_eur = 130; reserve_eur = 30; max_hourly_eur = 2 }
    model_overrides = @{
        'chat-small' = @{
            name = 'gpt-4.1-mini'; version = '2025-04-14'
            sku = 'GlobalStandard'; capacity = 75
        }
    }
    workload_inputs = @{
        organization_name = 'Northwind R&D "Test"'
        runtime_images = @{
            backend = "testonly.azurecr.io/backend@sha256:$('1' * 64)"
            toolkit = "testonly.azurecr.io/toolkit@sha256:$('2' * 64)"
        }
        librarians = @('librarian@unit.invalid')
    }
}
$testFixture.planCount = 0
$testFixture.azureCount = 0
$testFixture.lastVariables = $null
$testFixture.lastDirectory = $null
$testFixture.lastDataDirectory = $null
$testFixture.backendFiles = @{}

function az {
    $global:LASTEXITCODE = 0
    $testFixture.azureCount++
    if (($args -join ' ') -ne "account show --subscription $($testFixture.account.id) -o json") {
        throw "Unexpected test Azure invocation: $args"
    }
    $testFixture.account | ConvertTo-Json -Compress
}

function terraform {
    $global:LASTEXITCODE = 0
    if ($args[1] -eq 'output' -and $args[2] -eq '-json') {
        switch ($args[3]) {
            foundation { $testFixture.foundation | ConvertTo-Json -Depth 20 -Compress }
            deployment_access { $testFixture.access | ConvertTo-Json -Depth 20 -Compress }
            default { throw "Unexpected test output: $args" }
        }
    } elseif ($args[1] -eq 'plan') {
        $variableArgument = @($args | Where-Object { $_.StartsWith('-var-file=') })
        $planArgument = @($args | Where-Object { $_.StartsWith('-out=') })
        if ($variableArgument.Count -ne 1 -or $planArgument.Count -ne 1) {
            throw 'Test expected exactly one saved variable file and plan.'
        }
        $testFixture.lastVariables = Get-Content -LiteralPath $variableArgument[0].Substring(10) -Raw |
            ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
        $testFixture.lastDirectory = $args[0].Substring(7)
        $testFixture.lastDataDirectory = $env:TF_DATA_DIR
        Set-Content -LiteralPath $planArgument[0].Substring(5) -Value 'TEST ONLY - NOT A TERRAFORM PLAN'
        $testFixture.planCount++
    } elseif ($args[1] -eq 'init') {
        $backendArgument = @($args | Where-Object { $_.StartsWith('-backend-config=path=') })
        if ($backendArgument.Count -ne 1 -or -not $env:TF_DATA_DIR.StartsWith($outputDirectory)) {
            throw 'Test requires an isolated explicit local backend and provider data directory.'
        }
        $testFixture.backendFiles[$args[0]] = $backendArgument[0].Substring(21)
    } elseif ($args[1] -ne 'validate') {
        throw "Unexpected test Terraform invocation: $args"
    }
}

function Assert-Plan([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-TestPlan([string]$Component) {
    $settings | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM
    & $entry -Scenario 'architecture-docs' -Action Plan -Component $Component `
        -Inputs $inputPath -WarningAction SilentlyContinue | Out-Null
}

function Assert-Rejected([string]$Pattern, [string]$Component = 'Workload') {
    $before = $testFixture.planCount
    $rejected = $false
    try {
        Invoke-TestPlan $Component
    } catch {
        if ($_.Exception.Message -notlike $Pattern) { throw }
        $rejected = $true
    }
    Assert-Plan ($rejected -and $before -eq $testFixture.planCount) 'Invalid composition must never reach Terraform planning.'
}

try {
    $reviewedProtection = $settings.protection.Clone()
    foreach ($invalid in @($null, 0, -1, '2', $true)) {
        $settings.protection.max_hourly_eur = $invalid
        Assert-Rejected 'Supply a reviewed positive JSON number for protection.max_hourly_eur.' 'Foundation'
    }
    $settings.protection.Remove('max_hourly_eur')
    Assert-Rejected 'Supply a reviewed positive JSON number for protection.max_hourly_eur.' 'Foundation'
    $settings.protection.max_hourly_eur = $reviewedProtection.max_hourly_eur
    $settings.protection.reserve_eur = $settings.protection.monthly_cap_eur
    Assert-Rejected 'The reviewed protection reserve must be below the monthly cap.' 'Foundation'
    $settings.protection = $null
    Assert-Rejected 'Supply reviewed protection limits before foundation planning.' 'Foundation'
    Assert-Plan ($testFixture.azureCount -eq 0) 'Unreviewed protection limits must fail before contacting Azure.'
    $settings.protection = $reviewedProtection

    $originalRoster = $settings.teams.alpha
    $settings.teams.alpha = @()
    Invoke-TestPlan 'Foundation'
    Assert-Plan ($testFixture.lastDirectory -eq (Join-Path $root 'infra\foundation')) 'Foundation selection chose the wrong root.'
    Assert-Plan ($testFixture.lastVariables.profile -eq 'full' -and $testFixture.lastVariables.enable_search) 'Foundation must use the selected profile and required Search capability.'
    Assert-Plan (-not $testFixture.lastVariables.ContainsKey('models') -and
        -not $testFixture.lastVariables.ContainsKey('runtime_images')) 'Workload model/image settings leaked into foundation inputs.'
    $foundationDataDirectory = $testFixture.lastDataDirectory

    $settings.teams.alpha = $originalRoster
    Invoke-TestPlan 'Access'
    Assert-Plan ($testFixture.lastDirectory -eq (Join-Path $root 'infra\access')) 'Access selection chose the wrong root.'
    Assert-Plan ($testFixture.lastVariables.teams.alpha[0] -ceq 'PARTICIPANT@UNIT.INVALID') 'Deployment-time roster was not passed to access.'
    Assert-Plan ($foundationDataDirectory -ne $testFixture.lastDataDirectory) 'Access and foundation must not share provider backend metadata.'

    Invoke-TestPlan 'Workload'
    Assert-Plan ($testFixture.lastDirectory -eq (Join-Path $root 'scenarios\architecture-docs\infra')) 'Workload must use the selected scenario root.'
    Assert-Plan ($testFixture.lastVariables.models['chat-small'].capacity -eq 75) 'Workload plan lost the reviewed model override.'
    Assert-Plan ($testFixture.lastVariables.runtime_images.backend -ceq $settings.workload_inputs.runtime_images.backend) 'Planning must preserve the exact immutable artifact.'
    Assert-Plan ($testFixture.lastVariables.reference_date -eq '2026-11-01') 'Scenario defaults were not composed.'
    Assert-Plan ($testFixture.lastVariables.organization_name -ceq $settings.workload_inputs.organization_name) 'The workload must preserve the deployer-chosen organization name exactly.'
    Assert-Plan ($testFixture.lastVariables.participant_members.ContainsKey('00000000-0000-0000-0000-000000000003')) 'Resolved access membership was not passed to workload.'
    Assert-Plan ($testFixture.lastDataDirectory.EndsWith('workloads\architecture-docs')) 'Workload state must be isolated by workload name.'
    Assert-Plan (@($testFixture.backendFiles.Values | Sort-Object -Unique).Count -eq 3) 'All three components must use independent state files.'
    Assert-Plan ($env:TF_DATA_DIR -ceq $previousDataDirectory) 'Composition must restore the caller provider-data environment.'

    $ownershipFile = Join-Path $outputDirectory 'state\workloads\architecture-docs.owner.json'
    $owner = Get-Content -LiteralPath $ownershipFile -Raw | ConvertFrom-Json -AsHashtable
    $owner.scenario = 'another-scenario'
    $owner | ConvertTo-Json | Set-Content -LiteralPath $ownershipFile
    Assert-Rejected 'This workload name is already reserved by another scenario or target*'
    $owner.scenario = 'architecture-docs'
    $owner | ConvertTo-Json | Set-Content -LiteralPath $ownershipFile

    $testFixture.access.tenant_id = '00000000-0000-0000-0000-000000000009'
    Assert-Rejected 'Applied access does not match the selected foundation.'
    $testFixture.access.tenant_id = $testFixture.account.tenantId
    $testFixture.access.teams = @{ beta = @('participant@unit.invalid') }
    Assert-Rejected 'Applied access roster is stale*'
    $testFixture.access.teams = @{ alpha = @('different@unit.invalid') }
    Assert-Rejected 'Applied access roster is stale*'
    $testFixture.access.teams = @{ alpha = @('participant@unit.invalid') }

    $before = $testFixture.azureCount
    $organization = $settings.workload_inputs.organization_name
    $settings.workload_inputs.organization_name = $null
    Assert-Rejected "Supply the selected scenario's required workload input 'organization_name'."
    Assert-Plan ($before -eq $testFixture.azureCount) 'A missing organization choice must fail before Azure.'
    $settings.workload_inputs.organization_name = $organization
    $settings.workload_inputs.runtime_images = $null
    Assert-Rejected "Supply the selected scenario's required workload input 'runtime_images'."
    Assert-Plan ($before -eq $testFixture.azureCount) 'Missing required workload inputs must fail before Azure.'
    $settings.workload_inputs.undeclared_input = 'test-only'
    Assert-Rejected "Unknown workload input 'undeclared_input'."
    Assert-Plan ($before -eq $testFixture.azureCount) 'Unknown workload inputs must fail before Azure.'

    Write-Output 'Composition planning tests passed using test-scoped command doubles. No Azure operations or real Terraform plans executed.'
} finally {
    if (Test-Path -LiteralPath $inputPath) { Remove-Item -LiteralPath $inputPath }
    if (Test-Path -LiteralPath $outputDirectory) {
        Remove-Item -LiteralPath $outputDirectory -Recurse
    }
    $global:LASTEXITCODE = $previousExitCode
}
