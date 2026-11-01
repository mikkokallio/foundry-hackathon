#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
foreach ($relative in @('infra\foundation', 'infra\access', 'scenarios\architecture-docs\infra')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $relative) -Filter '*.tf') {
        $source = Get-Content -LiteralPath $file.FullName -Raw
        if ($source -match 'azurerm_automation_|avm-res-automation|protection_(principal|cutoff|account|group)|Microsoft\.Resources/subscriptions/resourceGroups/delete|var\.expires_at|expires-on|spending authorization has expired') {
            throw "Automatic lab deletion or its retired spending-expiry gate must not be part of the deployment: $($file.FullName)"
        }
    }
}
foreach ($relative in @('infra\foundation\protection.tf', 'infra\scripts\Protect-Spending.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) {
        throw "Retired deletion implementation must not be distributed: $relative"
    }
}
$example = Get-Content -LiteralPath (Join-Path $root 'infra\deployment.example.json') -Raw |
    ConvertFrom-Json -AsHashtable
foreach ($key in @('protection', 'expires_at')) {
    if ($example.ContainsKey($key)) { throw "Deployment example must not request '$key'." }
}
Write-Output 'Deployment lifecycle checks passed: no automatic lab-deletion resources, grants or inputs are shipped.'
