#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$foundation = Join-Path $root 'infra\foundation'
$source = Get-Content (Join-Path $foundation 'main.tf') -Raw
$search = [regex]::Match($source, '(?ms)^module "search" \{.*?^\}').Value
$directory = Join-Path $root "out\search-configuration-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $directory | Out-Null
try {
    Copy-Item (Join-Path $foundation 'variables.tf') (Join-Path $directory 'variables.tf')
    $fields = @('sku', 'replica_count', 'partition_count', 'semantic_search_sku')
    $expressions = foreach ($field in $fields) {
        $expression = [regex]::Match($search, "(?m)^\s*$field\s*=\s*(.+)$").Groups[1].Value.Trim()
        if (-not $expression) { throw "Missing Search capacity expression '$field'." }
        "$field = $expression"
    }
    "locals { selected_search = {`n$($expressions -join "`n")`n} }" |
        Set-Content (Join-Path $directory 'main.tf')
    $inputs = @{
        subscription_id = '00000000-0000-0000-0000-000000000001'
        tenant_id = '00000000-0000-0000-0000-000000000002'
        suffix = 'testonly'; publisher_email = 'operator@unit.invalid'; team_names = @('alpha')
        profile = 'lite'
    }
    $choice = @{
        sku = 'standard'; replica_count = 3; partition_count = 1
        semantic_search_sku = 'standard'; knowledge_retrieval = 'standard'
    }
    foreach ($case in @(
        @{ profile = 'lite'; configuration = @{} },
        @{ profile = 'full'; configuration = @{} },
        @{ profile = 'lite'; configuration = $choice }
    )) {
        $inputs.profile = $case.profile
        $inputs.search_configuration = $case.configuration
        $inputPath = Join-Path $directory 'inputs.tfvars.json'
        $inputs | ConvertTo-Json -Depth 10 | Set-Content $inputPath
        $raw = 'jsonencode(local.selected_search)' |
            terraform "-chdir=$directory" console -no-color "-var-file=$inputPath"
        if ($LASTEXITCODE -ne 0) { throw 'Actual Search input expressions failed.' }
        $actual = $raw | ConvertFrom-Json | ConvertFrom-Json -AsHashtable
        $review = & (Join-Path $root 'infra\scripts\Inspect-Deployment.ps1') -Scenario architecture-docs `
            -Profile $case.profile -SearchConfiguration $case.configuration -AsJson |
            ConvertFrom-Json -AsHashtable -Depth 30
        foreach ($field in $fields) {
            if ($actual[$field] -cne $review.foundation.search_configuration[$field]) {
                throw "Native and composition Search selection disagree on '$field'."
            }
        }
    }
    foreach ($invalid in @(
        @{ sku = 's1' }, @{ replica_count = 0 }, @{ replica_count = 13 },
        @{ replica_count = 1.5 }, @{ partition_count = 5 },
        @{ semantic_search_sku = 'paid' }, @{ knowledge_retrieval = 'paid' }
    )) {
        $inputs.search_configuration = $invalid
        $inputs | ConvertTo-Json -Depth 10 | Set-Content $inputPath
        $text = (terraform "-chdir=$directory" plan -input=false -no-color "-var-file=$inputPath" 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0 -or $text -notmatch 'Invalid value for variable') {
            throw 'Invalid native Search configuration was not rejected by actual variable validation.'
        }
    }
    Write-Output 'Actual native Search capacity/billing inputs match inspection; invalid selections rejected. No Azure call.'
} finally {
    Remove-Item -LiteralPath $directory -Recurse
}
