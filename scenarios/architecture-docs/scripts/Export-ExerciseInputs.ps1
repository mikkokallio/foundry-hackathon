#requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FoundationOutputs,
    [Parameter(Mandatory)][string]$WorkloadOutputs,
    [Parameter(Mandatory)][string]$Inputs,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,30}$')][string]$Team,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$source = Join-Path $PSScriptRoot '..\exercises'

function Read-Object([string]$Path) {
    $value = Get-Content -LiteralPath $Path -Raw |
        ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    if ($value -isnot [System.Collections.IDictionary]) { throw "Expected a JSON object: $Path" }
    return $value
}

function Read-Output([System.Collections.IDictionary]$Values, [string]$Name) {
    if (-not $Values.Contains($Name) -or
        $Values[$Name] -isnot [System.Collections.IDictionary] -or
        $Values[$Name].value -isnot [System.Collections.IDictionary]) {
        throw "Missing applied Terraform output '$Name'; use terraform output -json, not a plan/state file."
    }
    if ($Values[$Name].sensitive -eq $true) { throw "Refusing to export sensitive output '$Name'." }
    return $Values[$Name].value
}

$settings = Read-Object $Inputs
$foundation = Read-Output (Read-Object $FoundationOutputs) 'foundation'
$workload = Read-Object $WorkloadOutputs
$gateway = Read-Output $workload 'gateway'
$identity = Read-Output $workload 'gateway_identity'
$models = Read-Output $workload 'model_deployments'
$nativeModels = Read-Output $workload 'native_gateway_models'
$extensions = Read-Output $workload 'extension_authoring'
$gatewayExercises = Read-Output $workload 'gateway_exercises'
foreach ($key in @('subscription_id', 'tenant_id')) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($settings[$key], [ref]$parsed) -or
        $parsed -eq [guid]::Empty -or $foundation[$key] -ne $settings[$key]) {
        throw "Explicit input and applied foundation $key must match."
    }
}
if ($foundation.contract_version -ne 1 -or
    -not $foundation.projects.Contains($Team) -or -not $identity.roles.Contains($Team)) {
    throw 'Select an actual team present in both applied foundation and workload identity outputs.'
}
if ($nativeModels.projects -isnot [System.Collections.IDictionary] -or
    -not $nativeModels.projects.Contains($Team)) {
    throw 'Missing applied native gateway models for the selected team.'
}
$teamNativeModels = $nativeModels.projects[$Team]
$organization = $settings.workload_inputs.organization_name
if ($organization -isnot [string] -or [string]::IsNullOrWhiteSpace($organization) -or
    $organization -match '[\r\n]|\{\{|\}\}') {
    throw 'Supply the chosen organization name as a single line without template markers.'
}
$workloadName = $settings.workload_name
if ($workloadName -notmatch '^[a-z][a-z0-9-]{2,28}[a-z0-9]$') { throw 'Invalid workload name.' }
$scenario = Read-Object (Join-Path $source '..\scenario.json')
$referenceDate = $scenario.terraform_inputs.reference_date
if ($settings.workload_inputs.Contains('reference_date')) {
    $referenceDate = $settings.workload_inputs.reference_date
}
$parsedDate = [datetime]::MinValue
if ($referenceDate -isnot [string] -or -not [datetime]::TryParseExact(
    $referenceDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::None, [ref]$parsedDate
)) { throw 'Use an explicit YYYY-MM-DD scenario reference date.' }

$projectEndpoint = $foundation.projects[$Team].endpoint
$expectedProject = "$($foundation.foundry_endpoint.TrimEnd('/'))/api/projects/$Team"
if ($projectEndpoint -cne $expectedProject) { throw 'Project endpoint does not match the selected foundation/team.' }
$gatewayBase = $foundation.gateway_url.TrimEnd('/')
foreach ($pair in @{
    docs_url = "$gatewayBase/$workloadName/docs-api"
    docs_mcp = "$gatewayBase/$workloadName/docs-mcp/mcp"
    toolkit_mcp = "$gatewayBase/$workloadName/toolkit/mcp"
}.GetEnumerator()) {
    if ($gateway[$pair.Key] -cne $pair.Value) { throw "Applied gateway '$($pair.Key)' does not match this workload." }
    $uri = [uri]$pair.Value
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Workshop gateway endpoints must be HTTPS without embedded credentials/query/fragment.'
    }
}
foreach ($alias in @('chat-small', 'chat-medium', 'judge', 'embedding')) {
    if ($models[$alias] -cne "$workloadName-$alias") { throw "Applied deployment '$alias' does not match this workload." }
}
foreach ($alias in @('chat-small', 'chat-medium', 'judge')) {
    if ($teamNativeModels.agent_model_ids[$alias] -cne "$workloadName-$Team-models/$alias") {
        throw "Applied native gateway model '$alias' does not match this workload."
    }
}
$clientId = [guid]::Empty
if (-not [guid]::TryParse($identity.client_id, [ref]$clientId) -or $clientId -eq [guid]::Empty -or
    $identity.scope -cne "api://$($identity.client_id)/Lab.Access") {
    throw 'Applied workload identity/scope is missing or inconsistent.'
}
if ($extensions.resource_group_id -notlike "/subscriptions/$($settings.subscription_id)/resourceGroups/*") {
    throw 'Extension resource group is outside the selected subscription.'
}

$files = @{}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $source 'prompts') -Filter '*.md') {
    $text = (Get-Content -LiteralPath $file.FullName -Raw).
        Replace('{{ORGANIZATION_NAME}}', $organization).
        Replace('{{REFERENCE_DATE}}', $referenceDate)
    if ($text -match '\{\{[^}]+\}\}') { throw "Unresolved prompt marker in $($file.Name)." }
    $files["prompts\$($file.Name)"] = $text
}
$plan = Read-Object (Join-Path $source 'evaluation\plan.json')
if ($referenceDate -cne $plan.reference_date) {
    throw 'Review the frozen evaluation corpus/ground truths before exporting a different reference date.'
}
$dataset = Join-Path $source 'evaluation\eval_set.jsonl'
$cases = @(Get-Content -LiteralPath $dataset | Where-Object { $_.Trim() } |
    ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 20 })
if ($cases.Count -ne 25 -or @($cases.id | Sort-Object -Unique).Count -ne 25) {
    throw 'The inherited 25-case dataset is incomplete or contains duplicate IDs.'
}
foreach ($name in @('smoke_case_ids', 'comparison_case_ids', 'regression_case_ids', 'write_back_case_ids')) {
    foreach ($id in $plan[$name]) {
        if ($id -cnotin $cases.id) { throw "Unknown $name entry '$id'." }
    }
}
$files['evaluation\quick.jsonl'] = ($cases | Where-Object id -CIn $plan.smoke_case_ids |
    ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join "`n"
$files['evaluation\quick.portal.jsonl'] = ($cases | Where-Object id -CIn $plan.smoke_case_ids |
    ForEach-Object {
        @{ case_id = $_.id; query = $_.query; ground_truth = $_.ground_truth } |
            ConvertTo-Json -Compress -Depth 20
    }) -join "`n"
$files['evaluation\smoke.jsonl'] = $files['evaluation\quick.jsonl']
$files['evaluation\smoke.portal.jsonl'] = $files['evaluation\quick.portal.jsonl']
$files['evaluation\comparison-12.jsonl'] = ($plan.comparison_case_ids | ForEach-Object {
    $id = $_
    $cases | Where-Object id -CEQ $id | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }
}) -join "`n"
$files['evaluation\comparison-12.portal.jsonl'] = ($plan.comparison_case_ids | ForEach-Object {
    $id = $_
    $cases | Where-Object id -CEQ $id | ForEach-Object {
        @{ case_id = $_.id; query = $_.query; ground_truth = $_.ground_truth } |
            ConvertTo-Json -Compress -Depth 20
    }
}) -join "`n"
$files['evaluation\write-back.jsonl'] = ($cases | Where-Object id -CIn $plan.write_back_case_ids |
    ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join "`n"
$files['evaluation\eval_set.jsonl'] = Get-Content -LiteralPath $dataset -Raw
$files['evaluation\gate.yaml'] = Get-Content -LiteralPath (Join-Path $source 'evaluation\gate.yaml') -Raw
$files['evaluation\plan.json'] = Get-Content -LiteralPath (Join-Path $source 'evaluation\plan.json') -Raw
$files['openapi.json'] = Get-Content -LiteralPath (Join-Path $source '..\openapi.json') -Raw
$files['pricing.json'] = Get-Content -LiteralPath (Join-Path $source 'pricing.json') -Raw
$matrix = foreach ($alias in $plan.model_aliases) {
    foreach ($instruction in $plan.instruction_files) {
        @{ model_alias = $alias; deployment = $models[$alias]; agent_model_id = $teamNativeModels.agent_model_ids[$alias]; instructions = "prompts\$instruction" }
    }
}
$files['workshop.json'] = @{
    schema_version = 1; runtime_accepted = $false
    agent_binding_status = 'Select actual agent names/immutable versions after creation; none invented.'
    subscription_id = $settings.subscription_id; tenant_id = $settings.tenant_id
    workload_name = $workloadName
    team = $Team; organization_name = $organization; reference_date = $referenceDate
    project_endpoint = $projectEndpoint; docs_url = $gateway.docs_url
    docs_mcp = $gateway.docs_mcp; toolkit_mcp = $gateway.toolkit_mcp
    gateway_models = $gateway.models
    workspace_resource_id = $foundation.workspace_id
    application_insights_resource_id = $foundation.applicationinsights_id
    foundry_resource_id = $foundation.foundry_id
    catalog_resource_id = $foundation.catalog_id
    gateway_resource_id = $foundation.gateway_id
    dataset_names = @{
        smoke = 'evaluation\smoke.jsonl'
        comparison = 'evaluation\comparison-12.jsonl'
        regression = 'evaluation\eval_set.jsonl'
        legacy_quick = 'Four-case smoke compatibility name; NOT the twelve-case teaching comparison.'
    }
    gateway_scope = $identity.scope; model_variants = @($matrix)
    pricing_status = 'Dated reference only; verify actual models/SKUs/region/current prices, including overrides.'
    extension_authoring = $extensions; gateway_exercises = $gatewayExercises
    evaluation_dataset_sha256 = (Get-FileHash -LiteralPath $dataset -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 30
$files['mcp.json'] = @{
    inputs = @(@{
        id = 'gateway-token'; type = 'promptString'; password = $true
        description = "Short-lived Entra token for $($identity.scope); do not store it in this file."
    })
    servers = @{
        'architecture-docs' = @{
            type = 'http'; url = $gateway.docs_mcp
            headers = @{ Authorization = 'Bearer ${input:gateway-token}' }
        }
        'drafting-toolkit' = @{
            type = 'http'; url = $gateway.toolkit_mcp
            headers = @{ Authorization = 'Bearer ${input:gateway-token}' }
        }
    }
} | ConvertTo-Json -Depth 20

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "out\exercise-inputs\$Team-$([guid]::NewGuid().ToString('N'))"
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
$allowed = [IO.Path]::GetFullPath((Join-Path $root 'out')) + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Export only into a new directory under ignored out; never publish private operational inputs.'
}
if (Test-Path -LiteralPath $output) { throw 'Output directory already exists; choose a new one instead of overwriting.' }
foreach ($entry in $files.GetEnumerator()) {
    $target = Join-Path $output $entry.Key
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Set-Content -LiteralPath $target -Value $entry.Value -Encoding utf8NoBOM
}
$hashes = @{}
foreach ($file in Get-ChildItem -LiteralPath $output -Recurse -File) {
    $hashes[[IO.Path]::GetRelativePath($output, $file.FullName)] =
        (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
@{
    generated_at = [DateTimeOffset]::UtcNow.ToString('o')
    input_pack_written = $true; runtime_accepted = $false
    dataset_cases = $cases.Count; smoke_cases = 4; write_back_cases = 3; model_variants = @($matrix).Count
    sha256 = $hashes
    note = 'Local inputs only. No Azure calls, registered evaluation, fabricated response or live acceptance.'
} | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath (Join-Path $output 'assembly-receipt.json') -Encoding utf8NoBOM
Write-Output "Exercise inputs: $output"
Write-Warning 'INPUTS ONLY. No services/agents/evaluations were invoked or accepted. MCP writes still require human approval.'
