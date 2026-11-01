#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content (Join-Path $root 'infra\foundation\main.tf') -Raw
$logs = [regex]::Match($source, '(?ms)^module "logs" \{.*?^\}').Value
$insights = [regex]::Match($source, '(?ms)^module "insights" \{.*?^\}').Value
$locals = $source.Substring(0, $source.IndexOf('data "azurerm_client_config"')).
    Replace('data.azapi_resource_list.foundry_accounts.output.value', 'var.existing_accounts')
$scratch = Join-Path $root "out\foundation-lifecycle-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    @'
variable "suffix" { default = "testonly" }
variable "team_names" { default = ["alpha", "beta"] }
variable "tags" { default = {} }
variable "profile" { default = "lite" }
variable "existing_accounts" {
  type = list(object({
    name = string
    properties = object({ associatedProjects = list(string) })
  }))
  default = []
}
'@ + "`n$locals" | Set-Content (Join-Path $scratch 'main.tf')
    $cases = @(
        @{ projects = $null; expected = 'alpha,beta,facilitator' },
        @{ projects = @('alpha', 'facilitator', 'beta'); expected = 'alpha,facilitator,beta' },
        @{ projects = @('facilitator', 'alpha'); expected = 'facilitator,alpha,beta' },
        @{ projects = @('removed', 'beta', 'facilitator', 'alpha'); expected = 'beta,facilitator,alpha' }
    )
    foreach ($case in $cases) {
        $accounts = @()
        if ($null -ne $case.projects) {
            $accounts = @(@{ name = 'aif-ai-lab-testonly'; properties = @{ associatedProjects = $case.projects } })
        }
        @{ existing_accounts = $accounts } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $scratch 'case.tfvars.json')
        $raw = 'jsonencode(local.project_associations)' |
            terraform "-chdir=$scratch" console -no-color '-var-file=case.tfvars.json'
        if ($LASTEXITCODE -ne 0) { throw 'Actual Foundation association evaluation failed.' }
        $actual = @($raw | ConvertFrom-Json | ConvertFrom-Json) -join ','
        if ($actual -cne $case.expected) {
            throw "Association order/membership mismatch: expected $($case.expected), got $actual."
        }
    }
    foreach ($case in @(
        @{ source = $logs; field = 'log_analytics_workspace_daily_quota_gb'; expected = '-1' },
        @{ source = $insights; field = 'daily_data_cap_in_gb'; expected = '0' },
        @{ source = $logs; field = 'log_analytics_workspace_retention_in_days'; expected = '30' }
    )) {
        $expression = [regex]::Match($case.source, "(?m)^\s*$($case.field)\s*=\s*(.+)$").Groups[1].Value.Trim()
        if (-not $expression) { throw "Missing explicit telemetry setting '$($case.field)'." }
        $actual = $expression | terraform "-chdir=$scratch" console -no-color
        if ($LASTEXITCODE -ne 0 -or "$actual".Trim() -cne $case.expected) {
            throw "Telemetry setting '$($case.field)' must preserve the approved ingestion/retention behavior."
        }
    }
    Write-Output 'Foundation association lifecycle and actual unlimited-ingestion/unchanged-retention expressions passed; no Azure call.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
