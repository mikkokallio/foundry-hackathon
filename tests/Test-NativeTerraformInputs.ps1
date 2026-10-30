#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scratch = Join-Path $root "out\native-input-tests-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
$previousProfile = $env:TF_VAR_profile
$previousCache = $env:TF_VAR_semantic_cache_enabled
$previousInput = $env:TF_INPUT
$previousLocation = $env:TF_VAR_location
$previousSearchLocation = $env:TF_VAR_search_location
$previousExitCode = $global:LASTEXITCODE
foreach ($component in @('infra\foundation', 'infra\access', 'scenarios\architecture-docs\infra')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $component) -Filter '*.tf') {
        $source = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($variable in [regex]::Matches($source, '(?ms)^variable\s+"([^"]+)"\s*\{(.*?)(?=^variable\s|^resource\s|^module\s|^output\s|\z)')) {
            if ($variable.Groups[2].Value -notmatch '\bdescription\s*=\s*"[^"]+') {
                throw "Terraform input '$($variable.Groups[1].Value)' in $($file.Name) must explain its purpose and accepted value."
            }
        }
    }
}
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $root 'infra\foundation\variables.tf') `
        -Destination (Join-Path $scratch 'variables.tf')
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    $env:TF_VAR_profile = $null
    $env:TF_VAR_location = $null
    $env:TF_VAR_search_location = $null
    $env:TF_INPUT = 'true'
    & terraform "-chdir=$scratch" init -backend=false -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Provider-free native input test initialization failed.' }
    $text = ('' | & terraform "-chdir=$scratch" plan -input=true -no-color 2>&1 |
        ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -eq 0) { throw 'Empty native input must not yield an accepted plan.' }
    if ($text -notmatch '(?s)var\.profile\s+Choose lite.*?Enter a value:') {
        throw 'Terraform itself did not prompt for the profile; do not hide a default or shell prompt.'
    }
    foreach ($name in @('subscription_id', 'tenant_id', 'suffix', 'team_names')) {
        if ($text -notmatch "var\.$name\b") { throw "Terraform itself did not request $name." }
    }
    $inputs = @{
        subscription_id = '00000000-0000-0000-0000-000000000001'
        tenant_id = '00000000-0000-0000-0000-000000000002'
        suffix = 'lab123'
        profile = 'lite'
        publisher_email = 'operator@example.invalid'
        team_names = @('alpha')
        expires_at = '2099-01-01T00:00:00Z'
    }
    $inputPath = Join-Path $scratch 'inputs.tfvars.json'
    $inputs | ConvertTo-Json | Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM
    $defaults = ('[var.location, var.search_location]' |
        & terraform "-chdir=$scratch" console "-var-file=$inputPath" -no-color 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or ([regex]::Matches($defaults, '"francecentral"')).Count -ne 2) {
        throw 'Both native region inputs must default to France Central.'
    }
    foreach ($name in @('location', 'search_location')) {
        foreach ($region in @('francecentral', 'swedencentral', 'westeurope', 'northeurope', 'eastus')) {
            $regionText = (& terraform "-chdir=$scratch" plan -input=false -no-color `
                "-var-file=$inputPath" "-var=$name=$region" 2>&1) -join "`n"
            $allowed = $region -in @('francecentral', 'swedencentral', 'westeurope')
            if (($LASTEXITCODE -eq 0) -ne $allowed -or
                (-not $allowed -and $regionText -notmatch 'not authorized')) {
                throw "Native Terraform did not enforce the region allowlist for $name=$region."
            }
        }
    }
    $workload = Join-Path $scratch 'workload-inputs'
    New-Item -ItemType Directory -Path $workload | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\variables.tf') `
        -Destination (Join-Path $workload 'variables.tf')
    $env:TF_DATA_DIR = Join-Path $workload 'terraform-data'
    $env:TF_VAR_semantic_cache_enabled = $null
    & terraform "-chdir=$workload" init -backend=false -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Provider-free workload input test initialization failed.' }
    $workloadText = ('' | & terraform "-chdir=$workload" plan -input=true -no-color 2>&1 |
        ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -eq 0 -or $workloadText -notmatch '(?s)var\.semantic_cache_enabled\s+Explicit boolean choice:.*?Enter a value:') {
        throw 'Native Terraform must request an explicit B4 prerequisite decision, not silently omit Redis.'
    }
    Write-Output 'Native Terraform prompted for profile and required foundation inputs from the actual variables file. No wrapper, Read-Host, provider or Azure call was used.'
} finally {
    $env:TF_DATA_DIR = $previousData
    $env:TF_VAR_profile = $previousProfile
    $env:TF_VAR_semantic_cache_enabled = $previousCache
    $env:TF_INPUT = $previousInput
    $env:TF_VAR_location = $previousLocation
    $env:TF_VAR_search_location = $previousSearchLocation
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse
}
