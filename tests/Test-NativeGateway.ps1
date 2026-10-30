#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\native-gateway.tf') -Raw
$gateway = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\gateway.tf') -Raw
$variables = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\variables.tf') -Raw
$limitVariable = [regex]::Match($variables, '(?ms)^variable "gateway_tokens_per_minute" \{.*?^\}').Value
$limitExpression = [regex]::Match($gateway, '(?m)^\s*token_limit\s*=\s*(.+)$').Groups[1].Value.Trim()
if (-not $limitVariable -or -not $limitExpression) { throw 'The normal model gateway must expose its real Terraform throttle input.' }
$toolkit = [regex]::Match($gateway, '(?ms)^resource "azapi_resource" "toolkit_mcp" \{.*?^\}').Value
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
'@ + "`n$limitVariable`n$locals" | Set-Content (Join-Path $scratch 'main.tf')
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
        @{ route = 'models-tight'; selected = 50000; expected = 256 }
    )) {
        $expression = $limitExpression.Replace('each.key', "`"$($case.route)`"")
        $value = $expression | terraform "-chdir=$scratch" console "-var=gateway_tokens_per_minute=$($case.selected)" -no-color
        if ($LASTEXITCODE -ne 0 -or "$value".Trim() -cne "$($case.expected)") {
            throw 'Actual model gateway throttle expression ignored the selected limit or changed the restrictive exercise route.'
        }
    }
    foreach ($invalid in @('0', '-1', '1.5')) {
        $validation = (terraform "-chdir=$scratch" plan -input=false "-var=gateway_tokens_per_minute=$invalid" -no-color 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $validation -notmatch 'Use a positive whole-number token/minute limit') {
            throw "Invalid gateway limit $invalid was not rejected by its Terraform validation."
        }
    }
    Write-Output 'Actual Terraform native gateway connection and configurable normal/fixed tight-route throttle checks passed; no Azure call.'
} finally {
    $env:TF_DATA_DIR = $previousData
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse
}
