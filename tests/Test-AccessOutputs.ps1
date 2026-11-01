#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content -LiteralPath (Join-Path $root 'infra\modules\participant-access\authoring.tf') -Raw
$match = [regex]::Match($source, '(?s)output "authoring_permissions" \{\s*value = (.*)\r?\n\}\s*$')
if (-not $match.Success) { throw 'Missing actual authoring-permissions output expression.' }
$expression = $match.Groups[1].Value.Replace('azurerm_role_definition.author', 'var.definitions')
$scratch = Join-Path $root "out\access-output-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
$previousExitCode = $global:LASTEXITCODE
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    "variable `"definitions`" { type = any }`nlocals {`nactual = $expression`n}`n" |
        Set-Content -LiteralPath (Join-Path $scratch 'main.tf') -Encoding utf8NoBOM
    $results = @()
    foreach ($shape in @('created','refreshed')) {
        $definitions = @{}
        foreach ($service in @('gateway','catalog','search')) {
            $definitions[$service] = @{
                role_definition_id = "test-$service"
                assignable_scopes = @('/subscriptions/test/resourceGroups/rg-test')
                permissions = @(@{
                    actions = @("test/$service/*")
                    not_actions = @("test/$service/delete")
                    data_actions = if ($shape -eq 'created') { $null } else { ,@() }
                    not_data_actions = if ($shape -eq 'created') { $null } else { ,@() }
                })
            }
        }
        $inputs = Join-Path $scratch "$shape.tfvars.json"
        @{ definitions = $definitions } | ConvertTo-Json -Depth 15 |
            Set-Content -LiteralPath $inputs -Encoding utf8NoBOM
        $raw = 'jsonencode(local.actual)' | terraform "-chdir=$scratch" console "-var-file=$inputs" -no-color
        if ($LASTEXITCODE -ne 0) { throw "Production output expression failed for $shape provider shape." }
        $json = $raw | ConvertFrom-Json
        $result = $json | ConvertFrom-Json -AsHashtable
        foreach ($service in $definitions.Keys) {
            $permission = $result[$service].permissions[0]
            if ($null -eq $permission.data_actions -or $permission.data_actions.Count -ne 0 -or
                $null -eq $permission.not_data_actions -or $permission.not_data_actions.Count -ne 0 -or
                $permission.actions[0] -cne "test/$service/*" -or
                $permission.not_actions[0] -cne "test/$service/delete" -or
                $result[$service].role_id -cne "test-$service" -or
                $result[$service].assignable_scopes[0] -cne '/subscriptions/test/resourceGroups/rg-test' -or
                $result[$service].cross_team_authoring -ne $true) {
                throw "Output canonicalization changed actual authoring permissions: $shape/$service."
            }
        }
        $results += $json
    }
    if ($results[0] -cne $results[1]) { throw 'Create/refresh outputs still differ.' }
    Write-Output 'Actual Access output is stable across provider null/empty-list refresh shapes; permission/scope fields preserved.'
}
finally {
    $env:TF_DATA_DIR = $previousData
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
