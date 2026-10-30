#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scratch = Join-Path $root "out\model-lifecycle-tests-$([guid]::NewGuid().ToString('N'))"
$previousData = $env:TF_DATA_DIR
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    Copy-Item -LiteralPath (Join-Path $root 'tests\model-lifecycle\main.tf') -Destination $scratch
    Copy-Item -LiteralPath (Join-Path $root 'tests\model-lifecycle\tests') -Destination $scratch -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\models.tf') -Destination $scratch
    Copy-Item -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\.terraform.lock.hcl') -Destination $scratch
    $plugins = Join-Path $root 'scenarios\architecture-docs\infra\.terraform\providers'
    & terraform "-chdir=$scratch" init -backend=false -input=false -no-color "-plugin-dir=$plugins"
    if ($LASTEXITCODE -ne 0) { throw 'Native model-lifecycle test initialization failed.' }
    & terraform "-chdir=$scratch" test -no-color
    if ($LASTEXITCODE -ne 0) { throw 'Actual native model-lifecycle guard tests failed.' }
} finally {
    $env:TF_DATA_DIR = $previousData
    for ($attempt = 0; ; $attempt++) {
        try {
            Remove-Item -LiteralPath $scratch -Recurse -ErrorAction Stop
            break
        } catch [IO.IOException], [UnauthorizedAccessException] {
            if ($attempt -ge 20) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}
Write-Output 'Actual production model Terraform passed five native plan tests using test-only provider doubles. No Azure operations or deployed-agent acceptance occurred.'
