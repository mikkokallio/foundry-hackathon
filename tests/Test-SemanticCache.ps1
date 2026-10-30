#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$directory = Join-Path $root "out\semantic-cache-tests-$([guid]::NewGuid().ToString('N'))"
$workload = Join-Path $root 'scenarios\architecture-docs\infra'
$previousData = $env:TF_DATA_DIR
try {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $env:TF_DATA_DIR = Join-Path $directory 'terraform-data'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'semantic-cache\main.tf') -Destination $directory
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'semantic-cache\group') -Destination $directory -Recurse
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'semantic-cache\tests') -Destination $directory -Recurse
    Copy-Item -LiteralPath (Join-Path $workload 'semantic-cache.tf') -Destination $directory
    Copy-Item -LiteralPath (Join-Path $workload '.terraform.lock.hcl') -Destination $directory
    & terraform "-chdir=$directory" init -backend=false -input=false -no-color `
        "-plugin-dir=$(Join-Path $workload '.terraform\providers')"
    if ($LASTEXITCODE -ne 0) { throw 'Semantic-cache test initialization failed.' }
    & terraform "-chdir=$directory" test -no-color
    if ($LASTEXITCODE -ne 0) { throw 'Actual semantic-cache Terraform contract failed.' }
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
Write-Output 'Actual semantic-cache source passed native Terraform tests with test-scoped Azure provider doubles; no live cache or Foundry acceptance occurred.'
