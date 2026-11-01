#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$foundation = Join-Path $root 'infra\foundation'
$source = Get-Content (Join-Path $foundation 'main.tf') -Raw
$data = [regex]::Match($source, '(?ms)^data "azapi_resource" "search_configuration" \{.*?^\}').Value
$billing = [regex]::Match($source, '(?ms)^resource "azapi_update_resource" "search_agentic_billing" \{.*?^\}').Value
if (-not $data -or -not $billing -or $data -notmatch 'depends_on\s*=\s*\[module\.search\]') {
    throw 'Billing requires an actual service-read barrier after AVM changes.'
}
$output = Get-Content (Join-Path $foundation 'outputs.tf') -Raw
if ($output -notmatch '(?s)depends_on\s*=\s*\[.*?azapi_update_resource\.search_agentic_billing') {
    throw 'Foundation consumers must wait for selected Search billing.'
}
$directory = Join-Path $root "out\search-billing-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'search-billing\main.tf') $directory
    Copy-Item (Join-Path $PSScriptRoot 'search-billing\tests') $directory -Recurse
    Copy-Item (Join-Path $foundation 'variables.tf') $directory
    Copy-Item (Join-Path $foundation '.terraform.lock.hcl') $directory
    ($data + "`n" + $billing).Replace('module.search[0].resource_id', 'local.search_id').
        Replace('depends_on = [module.search]', 'depends_on = [terraform_data.search]') |
        Set-Content (Join-Path $directory 'billing.tf')
    $env:TF_DATA_DIR = Join-Path $directory 'terraform-data'
    & terraform "-chdir=$directory" init -backend=false -input=false -no-color `
        "-plugin-dir=$(Join-Path $foundation '.terraform\providers')" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Search billing test initialization failed.' }
    $events = @(& terraform "-chdir=$directory" test -json -verbose)
    if ($LASTEXITCODE -ne 0) { throw "Actual billing source failed native mock tests:`n$($events -join "`n")" }
    $plans = @($events | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } |
        Where-Object { $_.type -eq 'test_plan' })
    $repeat = @($plans | Where-Object { $_.'@testrun' -eq 'repeat_selected_billing' })
    if ($repeat.Count -ne 1 -or @($repeat[0].test_plan.resource_changes |
        Where-Object { ($_.change.actions -join ',') -ne 'no-op' }).Count -ne 0) {
        throw 'Selected billing must have a clean native mock repeat plan.'
    }
    $changed = @($plans | Where-Object { $_.'@testrun' -eq 'changing_service_defers_billing_read' })
    $billingChange = @($changed[0].test_plan.resource_changes |
        Where-Object { $_.address -eq 'azapi_update_resource.search_agentic_billing[0]' })
    $deferredRead = @($changed[0].test_plan.resource_changes |
        Where-Object { $_.address -eq 'data.azapi_resource.search_configuration[0]' })
    if ($changed.Count -ne 1 -or $billingChange.Count -ne 1 -or $deferredRead.Count -ne 1 -or
        ($billingChange[0].change.actions -join ',') -cnotin @('update', 'delete,create') -or
        ($deferredRead[0].change.actions -join ',') -cne 'read') {
        throw "An AVM service change must defer readback and reapply billing in the same plan, not leave a second-plan repair: $($billingChange | ConvertTo-Json -Depth 15 -Compress)"
    }
    Write-Output 'Actual Search billing source passed six native mock cases, clean repeat plan and same-plan billing reapplication; no Azure call.'
} finally {
    $env:TF_DATA_DIR = $previousData
    for ($attempt = 0; (Test-Path -LiteralPath $directory) -and $attempt -lt 21; $attempt++) {
        try {
            Remove-Item -LiteralPath $directory -Recurse -Force
        } catch [IO.IOException], [UnauthorizedAccessException] {
            if ($attempt -eq 20) { throw }
            Write-Verbose 'Waiting for Windows to release the test provider executable.'
            Start-Sleep -Milliseconds 500
        }
    }
}
