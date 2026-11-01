#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\native-gateway.tf') -Raw
$gateway = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\gateway.tf') -Raw
$variables = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\variables.tf') -Raw
$runtime = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\runtime.tf') -Raw
$inspection = Join-Path $root 'infra\scripts\Inspect-Deployment.ps1'
$defaults = & $inspection -Scenario architecture-docs -AsJson | ConvertFrom-Json -AsHashtable
if ($defaults.workload.inputs.gateway_requests_per_minute -ne 30 -or
    $defaults.workload.inputs.gateway_tool_requests_per_minute -ne 60 -or
    $defaults.workload.inputs.mcp_protocol_diagnostics_enabled -cne $false) {
    throw 'Scenario inspection must preserve all three native gateway defaults.'
}
$selected = & $inspection -Scenario architecture-docs -AsJson -WorkloadInputs @{
    gateway_requests_per_minute = 60
    gateway_tool_requests_per_minute = 300
    mcp_protocol_diagnostics_enabled = $true
} | ConvertFrom-Json -AsHashtable
if ($selected.workload.inputs.gateway_requests_per_minute -ne 60 -or
    $selected.workload.inputs.gateway_tool_requests_per_minute -ne 300 -or
    $selected.workload.inputs.mcp_protocol_diagnostics_enabled -cne $true) {
    throw 'Scenario inspection must forward explicit native gateway selections unchanged.'
}
$diagnosticVariable = [regex]::Match($variables, '(?ms)^variable "mcp_protocol_diagnostics_enabled" \{.*?^\}').Value
$diagnosticEnvExpression = [regex]::Match($runtime, '(?ms)(each\.key == "toolkit" && var\.mcp_protocol_diagnostics_enabled \? \[.*?\] : \[\])').Value
if (-not $diagnosticVariable -or -not $diagnosticEnvExpression -or
    [regex]::Matches($gateway, 'diagnostics\s*=\s*var\.mcp_protocol_diagnostics_enabled \? file').Count -ne 2) {
    throw 'Only the two MCP policies and toolkit runtime must share the opt-in diagnostic input.'
}
$limitVariable = [regex]::Match($variables, '(?ms)^variable "gateway_tokens_per_minute" \{.*?^\}').Value
$toolLimitVariable = [regex]::Match($variables, '(?ms)^variable "gateway_tool_requests_per_minute" \{.*?^\}').Value
$requestLimitVariable = [regex]::Match($variables, '(?ms)^variable "gateway_requests_per_minute" \{.*?^\}').Value
$requestLimitExpression = [regex]::Match($gateway, '(?m)^\s*request_limit\s*=\s*(each\.key.+)$').Groups[1].Value.Trim()
$limitExpression = [regex]::Match($gateway, '(?m)^\s*token_limit\s*=\s*(.+)$').Groups[1].Value.Trim()
if (-not $limitVariable -or -not $limitExpression) { throw 'The normal model gateway must expose its real Terraform throttle input.' }
if (-not $toolLimitVariable -or
    [regex]::Matches($gateway, 'request_limit\s*=\s*var\.gateway_tool_requests_per_minute').Count -ne 3) {
    throw 'All three normal documentation/tool policies must share the real Terraform request-limit input.'
}
if (-not $requestLimitVariable -or -not $requestLimitExpression) {
    throw 'The normal model request limit must expose its real Terraform input independently of the tight route.'
}
$toolkit = [regex]::Match($gateway, '(?ms)^resource "azapi_resource" "toolkit_mcp" \{.*?^\}').Value
$mcp = [regex]::Match($gateway, '(?ms)^resource "azapi_resource" "docs_mcp" \{.*?^\}').Value
$rest = [regex]::Match($gateway, '(?ms)^resource "azurerm_api_management_api" "docs" \{.*?^\}').Value
$removedTools = [regex]::Match($gateway, '(?ms)^removed \{\s+from = azapi_resource\.docs_tool\s+lifecycle \{\s+destroy = false\s+\}\s+\}').Value
$connections = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\connections.tf') -Raw
$telemetry = Get-Content (Join-Path $root 'infra\foundation\telemetry.tf') -Raw
foreach ($case in @(
    @{ source = $connections; resource = 'tool_connection'; owner = 'var.foundation.foundry_id' },
    @{ source = $source; resource = 'native_gateway_connection'; owner = 'var.foundation.foundry_id' },
    @{ source = $telemetry; resource = 'project_telemetry'; owner = 'module.foundry.resource_id' }
)) {
    $block = [regex]::Match($case.source, '(?ms)^resource "azapi_resource" "' + $case.resource + '" \{.*?^\}').Value
    $retry = [regex]::Match($block, '(?ms)^\s*retry = \{.*?^\s*\}').Value
    $pattern = [regex]::Match($retry, 'error_message_regex\s*=\s*\["([^"]+)"\]').Groups[1].Value
    if ($block -notmatch ('locks\s*=\s*\[' + [regex]::Escape($case.owner) + '\]') -or
        $pattern -cne '(?is)TransientError.*Etag conflict' -or
        $retry -notmatch 'interval_seconds\s*=\s*5\b' -or
        $retry -notmatch 'max_interval_seconds\s*=\s*30\b') {
        throw "$($case.resource): Foundry connection CRUD must serialize and retry only the observed transient Etag conflict."
    }
    foreach ($errorCase in @(
        @{ message = "ERROR CODE: TransientError`nEtag conflict on owned connection"; matches = $true },
        @{ message = "transienterror`netag conflict on owned connection"; matches = $true },
        @{ message = '409 Conflict: connection is in use'; matches = $false },
        @{ message = '403 Forbidden: AuthorizationFailed'; matches = $false },
        @{ message = 'TransientError: unrelated service failure'; matches = $false }
    )) {
        if ([regex]::IsMatch($errorCase.message, $pattern) -ne $errorCase.matches) {
            throw 'Foundry connection retries must not mask unrelated conflicts, permission failures or service errors.'
        }
    }
}
if ($mcp -notmatch 'schema_validation_enabled\s*=\s*false' -or
    $mcp -notmatch 'depends_on\s*=\s*\[azurerm_api_management_api_policy\.docs\]' -or
    $gateway -match 'resource "azapi_resource" "docs_tool"' -or
    -not $removedTools -or $connections -match 'azapi_resource\.docs_tool' -or
    $connections -notmatch 'azurerm_api_management_api_policy\.docs_mcp') {
    throw 'Native tools must be owned inline by the secured parent; old child state must not delete them or block connections.'
}
if ($rest -notmatch 'display_name\s*=\s*local\.docs_spec\.info\.title' -or
    $rest -notmatch 'description\s*=\s*local\.docs_spec\.info\.description') {
    throw 'Imported REST metadata must match its OpenAPI definition to avoid repeat-plan changes.'
}
if ($toolkit -notmatch 'backendId\s*=\s*azapi_resource\.toolkit_backend\.name' -or
    $toolkit -match '\bserviceUrl\s*=' -or
    $toolkit -notmatch 'path\s*=\s*"\$\{local\.gateway_paths\.toolkit\}/mcp"' -or
    $gateway -notmatch 'url\s*=\s*"\$\{module\.runtime_app\["toolkit"\]\.fqdn_url\}/mcp"') {
    throw 'The external toolkit requires an explicit MCP backend, not an empty APIM-hosted MCP server.'
}
$locals = ($source -split 'resource "azapi_resource" "native_gateway_connection"')[0].
    Replace('azapi_resource.model[alias].name', '"${var.workload_name}-${alias}"').
    Replace('azuread_application_identifier_uri.gateway.identifier_uri', '"api://test-only"')
if ($source -notmatch 'type\s*=\s*"Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01"' -or
    $source -notmatch 'body\s*=\s*local.native_gateway_connection_body' -or
    $source -notmatch 'name\s*=\s*"\$\{var.workload_name\}-\$\{each.key\}-models"' -or
    $source -notmatch 'parent_id\s*=\s*var.foundation.projects\[each.key\].id' -or
    $source -match 'Microsoft.Resources/deployments@') {
    throw 'Manage the tested project connection body through real connection CRUD, not deployment history.'
}
$scratch = Join-Path $root "out\native-gateway-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
$previousExitCode = $global:LASTEXITCODE
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    $diagnosticExpression = '[for key in ["backend", "toolkit"] : ' + $diagnosticEnvExpression.Replace('each.key', 'key') + ']'
    @'
variable "workload_name" { default = "test-workload" }
variable "foundation" { default = { gateway_url = "https://test.azure-api.net" } }
variable "models" {
  default = {
    chat-small = { name = "gpt-5.4-nano", version = "test-small" }
    chat-medium = { name = "gpt-5.4-mini", version = "test-medium" }
    judge = { name = "gpt-5.4", version = "test-judge" }
  }
}
'@ + "`n$limitVariable`n$toolLimitVariable`n$requestLimitVariable`n$diagnosticVariable`n$locals`nlocals { diagnostic_env = $diagnosticExpression }" |
        Set-Content (Join-Path $scratch 'main.tf')
    foreach ($enabled in @($false, $true)) {
        $arguments = @("-chdir=$scratch", 'console', '-no-color')
        if ($enabled) { $arguments += '-var=mcp_protocol_diagnostics_enabled=true' }
        $diagnosticRaw = 'jsonencode(local.diagnostic_env)' | terraform @arguments
        if ($LASTEXITCODE -ne 0) { throw 'Actual diagnostic runtime gate evaluation failed.' }
        $diagnosticEnv = $diagnosticRaw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($diagnosticEnv[0].Count -ne 0 -or $diagnosticEnv[1].Count -ne [int]$enabled -or
            ($enabled -and ($diagnosticEnv[1][0].name -cne 'MCP_PROTOCOL_DIAGNOSTICS' -or
                            $diagnosticEnv[1][0].value -cne 'true'))) {
            throw 'Diagnostics must default off and, when enabled, affect only the toolkit runtime.'
        }
    }
    $raw = 'jsonencode(local.native_gateway_connection_body)' | terraform "-chdir=$scratch" console -no-color
    if ($LASTEXITCODE -ne 0) { throw 'Actual native connection body evaluation failed.' }
    $body = $raw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable
    $p = $body.properties
    if ($body.Count -ne 1 -or $p.Count -ne 6 -or $p.metadata.Count -ne 3 -or
        $p.isSharedToAll -ne $false -or
        $p.authType -cne 'ProjectManagedIdentity' -or $p.category -cne 'ApiManagement' -or
        $p.audience -cne 'api://test-only' -or $p.ContainsKey('credentials') -or
        $p.target -cne 'https://test.azure-api.net/test-workload/models' -or
        $p.metadata.deploymentInPath -cne 'false' -or $p.metadata.inferenceAPIVersion -cne '2024-10-21') {
        throw 'Incorrect native gateway identity/routing body.'
    }
    $models = $p.metadata.models | ConvertFrom-Json -AsHashtable
    if (($models.name -join ',') -cne 'chat-medium,chat-small,judge' -or
        $models[0].properties.model.name -cne 'gpt-5.4-mini' -or
        $models[1].properties.model.name -cne 'gpt-5.4-nano' -or
        $models[2].properties.model.name -cne 'gpt-5.4' -or
        ($models.properties.model.version -join ',') -cne 'test-medium,test-small,test-judge' -or
        @($models | Where-Object { $_.properties.model.format -cne 'OpenAI' }).Count -ne 0) {
        throw 'Static aliases must retain actual configured provider-model metadata.'
    }
    foreach ($case in @(
        @{ route = 'models'; selected = 50000; expected = 50000 },
        @{ route = 'models'; selected = 25000; expected = 25000 },
        @{ route = 'models'; selected = 100000; expected = 100000 },
        @{ route = 'models-tight'; selected = 50000; expected = 256 },
        @{ route = 'models-tight'; selected = 100000; expected = 256 }
    )) {
        $expression = $limitExpression.Replace('each.key', "`"$($case.route)`"")
        $value = $expression | terraform "-chdir=$scratch" console "-var=gateway_tokens_per_minute=$($case.selected)" -no-color
        if ($LASTEXITCODE -ne 0 -or "$value".Trim() -cne "$($case.expected)") {
            throw 'Actual model gateway throttle expression ignored the selected limit or changed the restrictive exercise route.'
        }
    }
    foreach ($case in @(
        @{ route = 'models'; selected = 30; expected = 30 },
        @{ route = 'models'; selected = 60; expected = 60 },
        @{ route = 'models-tight'; selected = 60; expected = 2 }
    )) {
        $expression = $requestLimitExpression.Replace('each.key', "`"$($case.route)`"")
        $value = $expression | terraform "-chdir=$scratch" console "-var=gateway_requests_per_minute=$($case.selected)" -no-color
        if ($LASTEXITCODE -ne 0 -or "$value".Trim() -cne "$($case.expected)") {
            throw 'The model request-limit expression ignored the selected limit or changed the tight route.'
        }
    }
    foreach ($selected in @(60, 300, 600)) {
        $value = 'var.gateway_tool_requests_per_minute' |
            terraform "-chdir=$scratch" console "-var=gateway_tool_requests_per_minute=$selected" -no-color
        if ($LASTEXITCODE -ne 0 -or "$value".Trim() -cne "$selected") {
            throw 'The actual normal tool request-limit input did not preserve the selected value.'
        }
    }
    foreach ($invalid in @('0', '-1', '1.5')) {
        $validation = (terraform "-chdir=$scratch" plan -input=false "-var=gateway_tokens_per_minute=$invalid" -no-color 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $validation -notmatch 'Use a positive whole-number token/minute limit') {
            throw "Invalid gateway limit $invalid was not rejected by its Terraform validation."
        }
        $validation = (terraform "-chdir=$scratch" plan -input=false "-var=gateway_tool_requests_per_minute=$invalid" -no-color 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $validation -notmatch 'Use a positive whole-number request/minute limit') {
            throw "Invalid tool gateway limit $invalid was not rejected by its Terraform validation."
        }
        $validation = (terraform "-chdir=$scratch" plan -input=false "-var=gateway_requests_per_minute=$invalid" -no-color 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $validation -notmatch 'Use a positive whole-number request/minute limit for the normal model\s+gateway') {
            throw "Invalid model request limit $invalid was not rejected by its Terraform validation."
        }
    }
    $mcpDirectory = Join-Path $scratch 'mcp'
    New-Item -ItemType Directory -Path $mcpDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'scenarios\architecture-docs\openapi.json') `
        -Destination (Join-Path $scratch 'openapi.json')
    $mcpLocals = ($gateway -split '  gateway_auth =')[0] + "}`n"
    $mcpBody = [regex]::Match($mcp, '(?ms)^  body = (\{.*?^  \})').Groups[1].Value.
        Replace('azurerm_api_management_api.docs.id', 'var.docs_api_id')
    if (-not $mcpBody) { throw 'The actual inline native MCP body was not found.' }
    @'
variable "organization_name" { default = "Example" }
variable "workload_name" { default = "test-workload" }
variable "docs_api_id" {
  default = "/subscriptions/test/resourceGroups/test/providers/Microsoft.ApiManagement/service/test/apis/test-workload-docs-api;rev=1"
}
'@ + "`n$mcpLocals`nlocals { tested_mcp_body = $mcpBody }`n" |
        Set-Content -LiteralPath (Join-Path $mcpDirectory 'main.tf')
    $env:TF_DATA_DIR = Join-Path $mcpDirectory 'terraform-data'
    $mcpRaw = 'jsonencode(local.tested_mcp_body)' | terraform "-chdir=$mcpDirectory" console -no-color
    if ($LASTEXITCODE -ne 0) { throw 'Actual inline native MCP body evaluation failed.' }
    $mcpProperties = ($mcpRaw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable).properties
    $tools = $mcpProperties.mcpTools
    $expectedNames = @(
        'findDocumentationGaps', 'getDocument', 'getDocumentationStandard', 'getProposal',
        'getSystem', 'listDataProducts', 'listDocuments', 'listInterfaces', 'listProposals',
        'listSystems', 'submitProposal', 'validateDocument'
    )
    if ($mcpProperties.Count -ne 6 -or $mcpProperties.type -cne 'mcp' -or
        $mcpProperties.subscriptionRequired -ne $false -or
        ($mcpProperties.protocols -join ',') -cne 'https' -or
        $mcpProperties.path -cne 'test-workload/docs-mcp' -or
        $tools.Count -ne 12 -or ($tools.name -join ',') -cne ($expectedNames -join ',')) {
        throw 'The inline native definition must preserve the exact twelve canonical tools, HTTPS path and Entra-based access.'
    }
    $spec = Get-Content -LiteralPath (Join-Path $scratch 'openapi.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach ($tool in $tools) {
        $operation = @(
            foreach ($path in $spec.paths.Values) {
                foreach ($method in @('get', 'post')) {
                    if ($path.ContainsKey($method) -and $path[$method].operationId -ceq $tool.name) {
                        $path[$method]
                    }
                }
            }
        )
        if ($operation.Count -ne 1 -or $tool.Count -ne 3 -or
            $tool.operationId -cne "/subscriptions/test/resourceGroups/test/providers/Microsoft.ApiManagement/service/test/apis/test-workload-docs-api/operations/$($tool.name)" -or
            $tool.description -cne $operation[0].description.Substring(0, [Math]::Min(1000, $operation[0].description.Length))) {
            throw "Inline tool '$($tool.name)' must retain its actual REST operation ID and description."
        }
    }
    Write-Output 'Actual Terraform native connection, throttle expressions and twelve-tool inline MCP contract checks passed; no Azure call.'
} finally {
    $env:TF_DATA_DIR = $previousData
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse
}
