#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scenario = Join-Path $root 'scenarios\architecture-docs\infra'
$identity = Get-Content -LiteralPath (Join-Path $scenario 'identity.tf') -Raw
$connections = Get-Content -LiteralPath (Join-Path $scenario 'connections.tf') -Raw
$models = Get-Content -LiteralPath (Join-Path $scenario 'native-gateway.tf') -Raw
$variables = Get-Content -LiteralPath (Join-Path $scenario 'variables.tf') -Raw
$identityLocals = ($identity -split 'resource "terraform_data" "identity_boundary"')[0]
$toolLocals = ($connections -split 'resource "azapi_resource" "tool_connection"')[0]
$memberVariable = [regex]::Match($variables, '(?ms)^variable "participant_members" \{.*?^\}').Value
$memberBoundary = [regex]::Match($identity, '(?ms)condition = (alltrue\(\[\s*for member in values\(var\.participant_members\).*?^\s*\]\))').Groups[1].Value
if (-not $memberVariable -or -not $memberBoundary -or
    $models -notmatch 'for_each\s*=\s*local\.team_roles' -or
    $identity -notmatch '(?s)resource "azuread_app_role_assignment" "project" \{\s*for_each\s*=\s*local\.team_roles' -or
    $identity -notmatch '(?s)resource "azuread_app_role_assignment" "participant" \{\s*for_each\s*=\s*var\.participant_members') {
    throw 'Project integration and real-human assignments must retain their distinct production boundaries.'
}
$scratch = Join-Path $root "out\team-integration-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
$previousExitCode = $global:LASTEXITCODE
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    @'
variable "workload_name" { default = "test-workload" }
variable "foundation" {
  default = {
    resource_group_id = "/subscriptions/test/resourceGroups/rg-test"
    gateway_url = "https://example.azure-api.net"
    projects = {
      alpha = { principal_id = "alpha" }
      beta = { principal_id = "beta" }
      gamma = { principal_id = "gamma" }
      delta = { principal_id = "delta" }
      epsilon = { principal_id = "epsilon" }
      facilitator = { principal_id = "facilitator" }
    }
  }
}
locals {
  gateway_paths = { mcp = "test/docs-mcp", toolkit = "test/toolkit" }
  legacy_alpha_role = uuidv5("url", "/subscriptions/test/resourceGroups/rg-test/workloads/test-workload/roles/team/alpha")
}
'@ + "`n$memberVariable`n$identityLocals`n$toolLocals`n" |
        Set-Content -LiteralPath (Join-Path $scratch 'main.tf') -Encoding utf8NoBOM
    foreach ($case in @(
        @{ name = 'one-human-team'; teams = @('alpha'); valid = $true },
        @{ name = 'five-human-teams'; teams = @('alpha', 'beta', 'gamma', 'delta', 'epsilon'); valid = $true },
        @{ name = 'undeclared-human-team'; teams = @('unknown'); valid = $false }
    )) {
        $members = @{}
        for ($i = 0; $i -lt $case.teams.Count; $i++) {
            $members[('00000000-0000-0000-0000-{0:d12}' -f ($i + 1))] = @{ team = $case.teams[$i] }
        }
        $inputs = Join-Path $scratch "$($case.name).tfvars.json"
        @{ participant_members = $members } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $inputs -Encoding utf8NoBOM
        $expression = "jsonencode({ roles = local.team_roles, tools = local.project_tools, legacy = local.legacy_alpha_role, roster_valid = $memberBoundary })" -replace '\r?\n', ' '
        $raw = $expression | terraform "-chdir=$scratch" console "-var-file=$inputs" -no-color
        if ($LASTEXITCODE -ne 0) { throw "Production team expressions failed for $($case.name)." }
        $result = $raw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable
        if (($result.roles.Keys | Sort-Object) -join ',' -cne 'alpha,beta,delta,epsilon,gamma' -or
            $result.roles.alpha -cne $result.legacy -or $result.tools.Count -ne 10 -or
            $result.roster_valid -ne $case.valid -or
            @($result.tools.Values | Where-Object { $_.team -eq 'facilitator' }).Count -ne 0) {
            throw "Declared teams, role stability, tool wiring or roster validation changed incorrectly: $($case.name)."
        }
    }
    foreach ($invalid in @(
        @{ name = 'empty'; members = @{} },
        @{ name = 'facilitator'; members = @{ '00000000-0000-0000-0000-000000000001' = @{ team = 'facilitator' } } }
    )) {
        $inputs = Join-Path $scratch "$($invalid.name).tfvars.json"
        @{ participant_members = $invalid.members } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $inputs -Encoding utf8NoBOM
        $output = (terraform "-chdir=$scratch" plan -input=false "-var-file=$inputs" -no-color 2>&1 |
            ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $output -notmatch 'Supply the nonempty, resolved participant roster') {
            throw "Production human-roster validation was bypassed: $($invalid.name)."
        }
    }
    Write-Output 'Declared-team wiring passed: five projects, ten tool connections, stable roles, facilitator excluded, human roster remains strict.'
}
finally {
    $env:TF_DATA_DIR = $previousData
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
