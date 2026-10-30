#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content (Join-Path $root 'infra\foundation\main.tf') -Raw
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
variable "expires_at" { default = "2026-11-03T16:42:33Z" }
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
    Write-Output 'Foundation association logic passed bootstrap, server ordering, additions and removals; no Azure call.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
