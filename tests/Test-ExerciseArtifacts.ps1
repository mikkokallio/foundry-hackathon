#requires -Version 7.5
[CmdletBinding()]
param([string]$ReferenceDataset)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $root 'scenarios\architecture-docs\exercises'
$export = Join-Path $root 'scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1'
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Body, [string]$Pattern) {
    try { & $Body | Out-Null } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw
    }
    throw "Expected explicit failure matching '$Pattern'."
}
function Read-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 40
}
function Write-Json([object]$Value, [string]$Path) {
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}
function Read-Rows([string]$Path) {
    @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } |
        ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 30 })
}

$manifest = Read-Json (Join-Path $source 'modules.json')
Assert ($manifest.modules.Count -eq 14) 'All five core and nine bonus modules must be covered.'
foreach ($id in @('M1', 'M2', 'M3', 'M4', 'M5', 'B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7', 'B8', 'B9')) {
    $module = @($manifest.modules | Where-Object id -CEQ $id)
    Assert ($module.Count -eq 1) "Missing or duplicate module $id."
    foreach ($artifact in $module[0].artifacts) {
        $path = Join-Path $source $artifact.Replace('/', '\')
        Assert (Test-Path -LiteralPath $path) "Missing actual artifact: $id/$artifact."
    }
}
$cases = Read-Rows (Join-Path $source 'evaluation\eval_set.jsonl')
$plan = Read-Json (Join-Path $source 'evaluation\plan.json')
Assert ($cases.Count -eq 25) 'Do not remove inherited cases.'
Assert (@($cases.id | Sort-Object -Unique).Count -eq 25) 'Duplicate evaluation case IDs.'
Assert (-not (Compare-Object @($cases.id) @($plan.regression_case_ids))) 'Regression must contain every inherited case.'
$smoke = @('qa', 'gap', 'draft', 'guardrail') | ForEach-Object {
    @($cases | Where-Object category -CEQ $_)[0].id
}
Assert (-not (Compare-Object @($smoke) @($plan.smoke_case_ids))) 'Preserve inherited first-per-category smoke selection.'
$api = Read-Json (Join-Path $source '..\openapi.json')
$toolNames = @($api.paths.Values | ForEach-Object {
    $_.Values | ForEach-Object { if ($_.operationId) { $_.operationId } }
})
$interfaces = @(Get-Content -LiteralPath (Join-Path $source '..\data\inventory\interfaces.json') -Raw |
    ConvertFrom-Json -AsHashtable)
foreach ($case in $cases) {
    foreach ($field in @('id', 'category', 'query', 'expected_tools', 'forbidden_tools', 'expected_facts', 'forbidden_facts', 'ground_truth')) {
        Assert ($case.Contains($field)) "Missing $field in $($case.id)."
    }
    foreach ($tool in @($case.expected_tools) + @($case.forbidden_tools)) {
        Assert ($tool -cin $toolNames) "Unknown tool $tool in $($case.id)."
    }
    foreach ($id in $case.expected_interfaces) {
        $interface = @($interfaces | Where-Object interface_id -CEQ $id)
        Assert ($interface.Count -eq 1 -and $interface[0].status -ceq 'active') "Non-active/unknown expected interface $id."
    }
}
$gate = Get-Content -LiteralPath (Join-Path $source 'evaluation\gate.yaml') -Raw
Assert ($gate -match '(?m)^on_missing: fail\r?$') 'Missing metrics must fail.'
Assert ($gate -match '(?s)task_adherence:\s+min_mean: 3\.0\s+template_compliance:\s+min_mean: 0\.5') 'Frozen quality thresholds changed.'
Assert (-not ((Get-Content -LiteralPath (Join-Path $source 'evaluation\eval_set.jsonl') -Raw) -match '(?i)contoso')) 'Do not force old branding/contact domains.'
$prices = Read-Json (Join-Path $source 'pricing.json')
Assert ($prices.rates.Count -eq 7 -and $prices.complete_estimate -eq $false) 'Prices are partial retail inputs, not a complete bill.'
Assert ($prices.arm_region -ceq 'francecentral' -and $prices.currency -ceq 'EUR') 'Default exercise retail inputs must match the preferred France/EUR deployment.'
foreach ($rate in $prices.rates) {
    Assert ([math]::Abs($rate.price_eur * 1000000 / $rate.unit_tokens - $rate.eur_per_million_tokens) -lt 0.00000001) 'Incorrect 1K/1M token price conversion.'
}
if ($ReferenceDataset) {
    $reference = Read-Rows $ReferenceDataset
    Assert ($reference.Count -eq 25) 'Unexpected inherited dataset.'
    foreach ($case in $cases) {
        $original = @($reference | Where-Object id -CEQ $case.id)
        Assert ($original.Count -eq 1) "Inherited case missing: $($case.id)."
        $original = $original[0]
        if ($case.id -cin @('qa-10', 'gr-04')) {
            $original.ground_truth = $original.ground_truth.Replace('@contoso-industrial.example', '@teams.example.invalid')
        }
        Assert (($case | ConvertTo-Json -Compress -Depth 30) -ceq
            ($original | ConvertTo-Json -Compress -Depth 30)) "Unapproved case/assertion change: $($case.id)."
    }
}

# Command fixtures below exist only in this test and are never runtime acceptance.
$scratch = Join-Path $root "out\exercise-artifact-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $subscription = '11111111-1111-1111-1111-111111111111'
    $tenant = '22222222-2222-2222-2222-222222222222'
    $client = '33333333-3333-3333-3333-333333333333'
    $settings = @{
        subscription_id = $subscription; tenant_id = $tenant; workload_name = 'architecture-docs'
        publisher_email = 'never-export@participants.example.invalid'
        teams = @{ alpha = @('never-export@participants.example.invalid') }
        workload_inputs = @{ organization_name = 'Example & Co [QA]' }
    }
    $foundation = @{ foundation = @{ value = @{
        contract_version = 1; subscription_id = $subscription; tenant_id = $tenant
        foundry_endpoint = 'https://aif-test.services.ai.azure.com'
        gateway_url = 'https://apim-test.azure-api.net'
        projects = @{ alpha = @{ endpoint = 'https://aif-test.services.ai.azure.com/api/projects/alpha' } }
    } } }
    $workload = @{
        gateway = @{ value = @{
            docs_url = 'https://apim-test.azure-api.net/architecture-docs/docs-api'
            docs_mcp = 'https://apim-test.azure-api.net/architecture-docs/docs-mcp/mcp'
            toolkit_mcp = 'https://apim-test.azure-api.net/architecture-docs/toolkit/mcp'
        } }
        gateway_identity = @{ value = @{ client_id = $client; scope = "api://$client/Lab.Access"; roles = @{ alpha = 'test-role' } } }
        model_deployments = @{ value = @{
            'chat-small' = 'architecture-docs-chat-small'; 'chat-medium' = 'architecture-docs-chat-medium'
            judge = 'architecture-docs-judge'; embedding = 'architecture-docs-embedding'
        } }
        native_gateway_models = @{ value = @{ projects = @{ alpha = @{ agent_model_ids = @{
            'chat-small' = 'architecture-docs-alpha-models/chat-small'
            'chat-medium' = 'architecture-docs-alpha-models/chat-medium'
            judge = 'architecture-docs-alpha-models/judge'
        } } } } }
        extension_authoring = @{ value = @{ resource_group_id = "/subscriptions/$subscription/resourceGroups/test-extensions" } }
        gateway_exercises = @{ value = @{ semantic_cache_enabled = $false; live_accepted = $false } }
    }
    $inputFile = Join-Path $scratch 'inputs.json'
    $foundationFile = Join-Path $scratch 'foundation.json'
    $workloadFile = Join-Path $scratch 'workload.json'
    Write-Json $settings $inputFile
    Write-Json $foundation $foundationFile
    Write-Json $workload $workloadFile
    $arguments = @{ FoundationOutputs = $foundationFile; WorkloadOutputs = $workloadFile; Inputs = $inputFile; Team = 'alpha' }
    $destination = Join-Path $scratch 'pack'
    & $export @arguments -OutputDirectory $destination -WarningAction SilentlyContinue | Out-Null
    $pack = Read-Json (Join-Path $destination 'workshop.json')
    $receipt = Read-Json (Join-Path $destination 'assembly-receipt.json')
    Assert ($pack.runtime_accepted -eq $false -and $receipt.runtime_accepted -eq $false) 'An input pack must never claim live acceptance.'
    Assert ($pack.model_variants.Count -eq 4) 'Need exactly two models by two prompt variants.'
    foreach ($variant in $pack.model_variants) {
        Assert ($variant.agent_model_id -ceq "architecture-docs-alpha-models/$($variant.model_alias)") 'Agent variants must use their project-scoped native gateway connection, not direct deployments.'
    }
    Assert ($pack.reference_date -ceq '2026-11-01') 'Use the scenario reference date, not the current day.'
    Assert ((Read-Rows (Join-Path $destination 'evaluation\quick.jsonl')).Count -eq 4) 'Quick set must cover four categories.'
    Assert ((Read-Rows (Join-Path $destination 'evaluation\quick.portal.jsonl')).Count -eq 4) 'Portal input must preserve four smoke rows.'
    Assert ((Read-Rows (Join-Path $destination 'evaluation\smoke.jsonl')).Count -eq 4) 'Explicit smoke name must retain all four smoke rows.'
    $comparison = Read-Rows (Join-Path $destination 'evaluation\comparison-12.jsonl')
    Assert ($comparison.Count -eq 12) 'Educational comparison must contain twelve cases.'
    Assert (@($comparison | Where-Object category -CEQ 'qa').Count -eq 5) 'Comparison needs five QA cases.'
    Assert (@($comparison | Where-Object category -CEQ 'gap').Count -eq 3) 'Comparison needs three gap cases.'
    Assert (@($comparison | Where-Object category -CEQ 'draft').Count -eq 1) 'Comparison needs one drafting case.'
    Assert (@($comparison | Where-Object category -CEQ 'guardrail').Count -eq 3) 'Comparison needs three guardrail cases.'
    Assert (@($comparison | Where-Object id -CIn $plan.write_back_case_ids).Count -eq 0) 'Comparison cannot save proposals or mutate the corpus.'
    Assert ((Read-Rows (Join-Path $destination 'evaluation\comparison-12.portal.jsonl')).Count -eq 12) 'Portal comparison must retain all twelve case IDs.'
    Assert ((Read-Rows (Join-Path $destination 'evaluation\write-back.jsonl')).Count -eq 3) 'All three inherited write cases are needed.'
    $importApi = Read-Json (Join-Path $destination 'openapi.json')
    foreach ($path in $api.paths.Keys) {
        foreach ($method in $api.paths[$path].Keys) {
            $operation = $api.paths[$path][$method]
            if ($operation -is [System.Collections.IDictionary] -and $operation.Contains('operationId')) {
                Assert ($importApi.paths[$path][$method].summary -ceq $operation.operationId) 'Portal import summaries must preserve exact MCP contract names.'
                $importApi.paths[$path][$method].summary = $operation.summary
            }
        }
    }
    Assert (($importApi | ConvertTo-Json -Compress -Depth 50) -ceq
        ($api | ConvertTo-Json -Compress -Depth 50)) 'Participant OpenAPI may change only operation summaries, not the API contract.'
    foreach ($entry in $receipt.sha256.GetEnumerator()) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $destination $entry.Key) -Algorithm SHA256).Hash -ieq $entry.Value) 'Pack receipt hash mismatch.'
    }
    foreach ($file in Get-ChildItem -LiteralPath $destination -Recurse -File) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        Assert ($text -notmatch 'never-export@') 'Private roster/publisher email leaked into the pack.'
        if ($file.Extension -eq '.md') { Assert ($text -notmatch '\{\{[^}]+\}\}') 'Unresolved rendered prompt marker.' }
    }
    $mcp = Read-Json (Join-Path $destination 'mcp.json')
    Assert ($mcp.inputs[0].password -eq $true) 'Token prompt must be secret.'
    Assert ($mcp.servers['architecture-docs'].headers.Authorization -ceq 'Bearer ${input:gateway-token}') 'Do not embed a token.'
    Assert-Throws { & $export @arguments -OutputDirectory $destination } 'already exists'
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $root 'not-an-allowed-export') } 'ignored out'
    $arguments.Team = 'missing'
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'missing-team') } 'actual team'
    $arguments.Team = 'alpha'
    $nativeOutput = $workload.native_gateway_models
    $workload.Remove('native_gateway_models')
    Write-Json $workload $workloadFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'missing-native-models') } "Missing applied Terraform output 'native_gateway_models'"
    $workload.native_gateway_models = $nativeOutput
    $workload.native_gateway_models.value.projects.alpha.agent_model_ids['chat-small'] = 'architecture-docs-chat-small'
    Write-Json $workload $workloadFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'direct-model-fallback') } 'native gateway model'
    $workload.native_gateway_models.value.projects.alpha.agent_model_ids['chat-small'] = 'architecture-docs-alpha-models/chat-small'
    $workload.gateway.value.docs_url = 'https://different.invalid/docs'
    Write-Json $workload $workloadFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'mixed-workload') } 'does not match'
    $workload.gateway.value.docs_url = 'https://apim-test.azure-api.net/architecture-docs/docs-api'
    Write-Json $workload $workloadFile
    $settings.tenant_id = '44444444-4444-4444-4444-444444444444'
    Write-Json $settings $inputFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'mixed-tenant') } 'must match'
    $settings.tenant_id = $tenant
    $settings.workload_inputs.reference_date = '2027-01-01'
    Write-Json $settings $inputFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'changed-corpus-date') } 'frozen evaluation'
    $settings.workload_inputs.Remove('reference_date')
    Write-Json $settings $inputFile
    $workload.gateway_identity.sensitive = $true
    Write-Json $workload $workloadFile
    Assert-Throws { & $export @arguments -OutputDirectory (Join-Path $scratch 'sensitive-output') } 'sensitive output'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
Write-Output 'All 14 module inputs, 25 retained evaluation cases, frozen thresholds, four-way export, token/roster safety and explicit failure cases passed locally. No Azure operations or Foundry acceptance occurred.'
