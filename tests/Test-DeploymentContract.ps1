#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$inspect = Join-Path $root 'infra\scripts\Inspect-Deployment.ps1'

function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($profile in @('lite', 'full')) {
    $result = & $inspect -Scenario 'architecture-docs' -Profile $profile -AsJson |
        ConvertFrom-Json -AsHashtable -Depth 30
    Assert-Contract ($result.operation -eq 'local-inspection-only') 'Inspection must not pretend to deploy.'
    Assert-Contract (-not $result.deployment_ready -and -not $result.azure_requests_made) 'Local inspection is not Azure acceptance.'
    Assert-Contract ($result.foundation.model_deployments.Count -eq 0) 'Foundation must not impose model deployments.'
    Assert-Contract ($result.workload.models.ContainsKey('embedding')) 'B1 needs a workload-owned embedding deployment.'
    Assert-Contract ('search' -in $result.workload.required_capabilities) 'Architecture-docs must require Search.'
    Assert-Contract ($result.workload.bonus_modules.Count -eq 9) 'Do not silently remove bonus modules.'
    Assert-Contract $result.workload.requires_participant_access 'This workload must use the applied access roster.'
    Assert-Contract ($null -eq $result.workload.inputs.runtime_images) 'No placeholder or implicit runtime images are permitted.'
    Assert-Contract ($null -eq $result.workload.inputs.organization_name) 'Organization branding must be chosen by the deployer, not imposed by the scenario.'
    Assert-Contract ($null -eq $result.workload.inputs.librarians) 'The deployment operator is not automatically a human publisher.'
    Assert-Contract ($result.workload.inputs.semantic_cache_enabled -is [bool] -and
        -not $result.workload.inputs.semantic_cache_enabled) 'Redis requires explicit selection and cost review; disabled is a real boolean.'
    Assert-Contract ($result.workload.terraform_root.StartsWith((Join-Path $root 'scenarios\architecture-docs\'), [StringComparison]::OrdinalIgnoreCase)) 'Workload root must stay in the selected scenario.'
}

$override = @{
    'chat-small' = @{
        name = 'gpt-4.1-mini'; version = '2025-04-14'
        sku = 'GlobalStandard'; capacity = 75
    }
}
$overridden = & $inspect -Scenario 'architecture-docs' -ModelOverrides $override -AsJson |
    ConvertFrom-Json -AsHashtable -Depth 30
Assert-Contract ($overridden.workload.models['chat-small'].capacity -eq 75) 'Inspection must show the exact selected model capacity.'
Assert-Contract ($overridden.foundation.model_deployments.Count -eq 0) 'Model overrides must not affect foundation ownership.'
$selected = & $inspect -Scenario 'architecture-docs' -WorkloadInputs @{ reference_date = '2026-10-29' } -AsJson |
    ConvertFrom-Json -AsHashtable -Depth 30
Assert-Contract ($selected.workload.inputs.reference_date -eq '2026-10-29') 'Explicit workload inputs must override scenario defaults.'
$cached = & $inspect -Scenario 'architecture-docs' -WorkloadInputs @{ semantic_cache_enabled = $true } -AsJson |
    ConvertFrom-Json -AsHashtable -Depth 30
Assert-Contract ($cached.workload.inputs.semantic_cache_enabled) 'The optional workload cache must be selectable without becoming a foundation model/capability default.'
foreach ($invalid in @('true', 1, $null)) {
    $rejected = $false
    try {
        & $inspect -Scenario 'architecture-docs' -WorkloadInputs @{ semantic_cache_enabled = $invalid } -AsJson | Out-Null
    } catch {
        if ($_.Exception.Message -cne "Workload input 'semantic_cache_enabled' must be a JSON boolean.") { throw }
        $rejected = $true
    }
    Assert-Contract $rejected 'Do not coerce strings, numbers or null into billable workload switches.'
}
foreach ($invalid in @(
    @{ unknown = $override['chat-small'] },
    @{ 'chat-small' = @{ name = 'x'; version = '1'; sku = 'GlobalStandard'; capacity = 0 } },
    @{ 'chat-small' = @{ name = 'x'; version = '1'; sku = 'GlobalStandard'; capacity = '75' } }
)) {
    $rejected = $false
    try {
        & $inspect -Scenario 'architecture-docs' -ModelOverrides $invalid -AsJson | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Unknown model alias override|Invalid model declaration') { throw }
        $rejected = $true
    }
    Assert-Contract $rejected 'Unknown aliases and invalid model capacities must fail locally.'
}

$inputPath = Join-Path ([IO.Path]::GetTempPath()) "deployment-contract-$([guid]::NewGuid()).json"
try {
    @{ profile = 'full'; model_overrides = $override } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM
    $text = & (Join-Path $root 'infra\scripts\Invoke-Deployment.ps1') -Scenario 'architecture-docs' `
        -Action Inspect -Inputs $inputPath -WarningAction SilentlyContinue
    Assert-Contract (($text -join "`n") -match 'profile: full') 'Entry-point inspection must use the operator profile.'
    Assert-Contract (($text -join "`n") -match 'capacity 75') 'Entry-point inspection and planning must use the same model selection.'
} finally {
    Remove-Item -LiteralPath $inputPath -ErrorAction Stop
}

$foundationSource = Get-ChildItem -LiteralPath (Join-Path $root 'infra\foundation') -Filter '*.tf' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$source = $foundationSource -join "`n"
Assert-Contract ($source -notmatch 'architecture-docs|docs-steward|chat-small|chat-medium|text-embedding|gpt-') 'Foundation contains scenario or model literals.'
Assert-Contract ($source -notmatch 'Microsoft\.CognitiveServices/accounts/deployments@') 'Model resources belong to the workload root.'

$unknownRejected = $false
try {
    & $inspect -Scenario 'missing-scenario' -AsJson | Out-Null
} catch {
    if ($_.Exception.Message -notlike "Scenario 'missing-scenario' has no manifest*") { throw }
    $unknownRejected = $true
}
Assert-Contract $unknownRejected 'Unknown scenarios must fail, not fall back to another workload.'

$searchRejected = $false
try {
    & $inspect -Scenario 'architecture-docs' -EnableSearch:$false -AsJson | Out-Null
} catch {
    if ($_.Exception.Message -notlike "Scenario 'architecture-docs' requires AI Search*") { throw }
    $searchRejected = $true
}
Assert-Contract $searchRejected 'A required Search service cannot be disabled through composition.'

$exampleRejected = $false
try {
    & (Join-Path $root 'infra\scripts\Invoke-Deployment.ps1') -Scenario 'architecture-docs' `
        -Action Plan -Inputs (Join-Path $root 'infra\deployment.example.json') | Out-Null
} catch {
    if ($_.Exception.Message -notlike 'Replace subscription_id with the explicitly approved target GUID.*') { throw }
    $exampleRejected = $true
}
Assert-Contract $exampleRejected 'Example targets must fail before Azure or Terraform planning.'

foreach ($script in (Get-ChildItem -LiteralPath (Join-Path $root 'infra\scripts') -Filter '*.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    Assert-Contract ($parseErrors.Count -eq 0) "PowerShell parser errors in $($script.Name): $parseErrors"
}

Write-Output 'Deployment composition contract passed for lite and full. No Azure operations executed.'
