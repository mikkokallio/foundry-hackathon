#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$module = Join-Path $root 'infra\modules\participant-access'
$main = Get-Content -LiteralPath (Join-Path $module 'main.tf') -Raw
$authoring = Get-Content -LiteralPath (Join-Path $module 'authoring.tf') -Raw
$role = [regex]::Match($authoring, '(?ms)^resource "azurerm_role_definition" "project_connection_writer" \{.*?^\}').Value
$permissions = [regex]::Match($role, '(?ms)^  permissions \{\s*actions = (\[[^\r\n]+\])\s*\}').Groups[1].Value
if (-not $role -or -not $permissions -or
    [regex]::Matches($role, '\bpermissions\s*\{').Count -ne 1 -or
    $role -match '\b(not_actions|data_actions|not_data_actions)\s*=' -or
    $role -notmatch 'depends_on\s*=\s*\[terraform_data\.roster\]') {
    throw 'The targeted role must add only the exact connection-write action and retain the roster boundary.'
}
$inputs = $main.Substring($main.IndexOf('variable "subscription_id"'),
    $main.IndexOf('data "azuread_user"') - $main.IndexOf('variable "subscription_id"'))
$requests = [regex]::Match($main, '(?ms)^locals \{\s*role_requests = .*?^\}').Value.
    Replace('azurerm_role_definition.project_connection_writer.role_definition_id', 'local.connection_role_id').
    Replace('azurerm_role_definition.author', 'var.author_roles')
if (-not $requests -or
    $main -notmatch 'for_each\s*=\s*local\.role_requests' -or
    $main -notmatch 'principal_id\s*=\s*data\.azuread_user\.member\[each\.value\.member\]\.object_id' -or
    $main -notmatch 'principal_type\s*=\s*"User"') {
    throw 'Every role request must still assign the resolved human identity, not a UPN or team service principal.'
}
$expressions = @{}
foreach ($field in @('role_definition_id', 'assignable_scopes', 'scope')) {
    $expressions[$field] = [regex]::Match($role, "(?m)^  $field\s*=\s*(.+)$").Groups[1].Value.Trim()
    if (-not $expressions[$field]) { throw "Missing actual role expression: $field." }
}
$scratch = Join-Path $root "out\participant-connection-write-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
$previousExitCode = $global:LASTEXITCODE
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    $fixture = @"
$inputs
variable "author_roles" {
  default = {
    gateway = { role_definition_id = "gateway-role" }
    catalog = { role_definition_id = "catalog-role" }
    search = { role_definition_id = "search-role" }
  }
}
locals {
  connection_role_id = $($expressions.role_definition_id)
  actual_role = {
    id = $($expressions.role_definition_id)
    assignable_scopes = $($expressions.assignable_scopes)
    scope = $($expressions.scope)
    actions = $permissions
  }
}
$requests
"@
    $fixture | Set-Content -LiteralPath (Join-Path $scratch 'main.tf') -Encoding utf8NoBOM
    $subscription = '/subscriptions/00000000-0000-0000-0000-000000000001'
    $group = "$subscription/resourceGroups/test-only"
    $projects = @{
        alpha = "$group/providers/Microsoft.CognitiveServices/accounts/test/projects/alpha"
        beta = "$group/providers/Microsoft.CognitiveServices/accounts/test/projects/beta"
    }
    $settings = @{
        subscription_id = '00000000-0000-0000-0000-000000000001'
        resource_group_id = $group
        teams = @{ alpha = @('ALPHA@UNIT.INVALID', '00000000-0000-0000-0000-000000000002'); beta = @('beta@unit.invalid') }
        expected_participant_count = 3
        project_ids = $projects
        gateway_id = "$group/gateway"; catalog_id = "$group/catalog"
        workspace_id = "$group/workspace"; applicationinsights_id = "$group/insights"
        search_id = "$group/search"
    }
    $members = @{
        'alpha@unit.invalid' = 'alpha'
        '00000000-0000-0000-0000-000000000002' = 'alpha'
        'beta@unit.invalid' = 'beta'
    }
    $roleId = $null
    foreach ($searchEnabled in @($true, $false)) {
        $settings.search_id = if ($searchEnabled) { "$group/search" } else { $null }
        $path = Join-Path $scratch 'inputs.tfvars.json'
        $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $raw = 'jsonencode({ role = local.actual_role, requests = local.role_requests })' |
            terraform "-chdir=$scratch" console "-var-file=$path" -no-color
        if ($LASTEXITCODE -ne 0) { throw 'Actual role/request expressions failed provider-free evaluation.' }
        $actual = $raw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable
        if ($actual.role.actions.Count -ne 1 -or
            $actual.role.actions[0] -cne 'Microsoft.CognitiveServices/accounts/projects/connections/write' -or
            $actual.role.assignable_scopes.Count -ne 1 -or
            $actual.role.assignable_scopes[0] -cne $group -or
            $actual.role.scope -cne $subscription -or
            ($null -ne $roleId -and $actual.role.id -cne $roleId)) {
            throw 'Role permissions, assignability or deterministic identity changed unexpectedly.'
        }
        $roleId = $actual.role.id
        if ($roleId -notmatch '^[0-9a-f-]{36}$') { throw 'The role must retain a deterministic GUID identity.' }
        $expected = @{}
        foreach ($member in $members.Keys) {
            $existing = @{
                reader = @{ scope = $group; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
                foundry = @{ scope = $projects[$members[$member]]; role = '53ca6127-db72-4b80-b1b0-d745d6d5456d' }
                'gateway-author' = @{ scope = "$group/gateway"; role = 'gateway-role' }
                'catalog-author' = @{ scope = "$group/catalog"; role = 'catalog-role' }
                'trace-reader' = @{ scope = "$group/workspace"; role = '73c42c96-874c-492b-b04d-ab87d138a893' }
                'telemetry-publisher' = @{ scope = "$group/insights"; role = '3913510d-42f4-4e42-8a64-420c390055eb' }
                'project-connection-writer' = @{ scope = $projects[$members[$member]]; role = $roleId }
            }
            if ($searchEnabled) {
                $existing['search-author'] = @{ scope = "$group/search"; role = 'search-role' }
                $existing['search-data-author'] = @{ scope = "$group/search"; role = '8ebe5a00-799e-43f5-93ac-243d3dce84a7' }
            }
            foreach ($key in $existing.Keys) {
                $requestKey = "$member/$key"
                $expected[$requestKey] = $true
                $request = $actual.requests[$requestKey]
                if ($null -eq $request -or $request.member -cne $member -or
                    $request.scope -cne $existing[$key].scope -or $request.role -cne $existing[$key].role) {
                    throw "Wrong/missing human, own-team scope or existing role: $requestKey."
                }
            }
        }
        if ($actual.requests.Count -ne $expected.Count) { throw 'Unexpected additional participant grants.' }
    }
    Write-Output 'Connection-write role passed: exact write-only action, deterministic role, three resolved-human requests across two own-team projects, all existing roles preserved with Search on/off. No Azure call.'
}
finally {
    $env:TF_DATA_DIR = $previousData
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
