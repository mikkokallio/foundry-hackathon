#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content (Join-Path $root 'scenarios\architecture-docs\infra\variables.tf') -Raw
$start = $source.IndexOf('variable "runtime_images"')
$end = $source.IndexOf('variable "reference_date"')
$scratch = Join-Path $root "out\runtime-image-inputs-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $source.Substring($start, $end - $start) + "`noutput `"images`" { value = var.runtime_images }" |
        Set-Content (Join-Path $scratch 'main.tf')
    $valid = 'testonly.azurecr.io/test/image@sha256:' + ('1' * 64)
    foreach ($case in @(
        @{ image = $valid; accepted = $true },
        @{ image = 'testonly.azurecr.io/test/image@sha256:' + ('0' * 64); accepted = $false },
        @{ image = 'testonly.azurecr.io/test/image:latest'; accepted = $false },
        @{ image = 'testonly.azurecr.io/test/image@sha256:123'; accepted = $false }
    )) {
        @{ runtime_images = @{ backend = $case.image; toolkit = $valid } } |
            ConvertTo-Json | Set-Content (Join-Path $scratch 'case.tfvars.json')
        $text = terraform "-chdir=$scratch" plan -input=false -no-color '-var-file=case.tfvars.json' 2>&1 |
            Out-String
        $accepted = $LASTEXITCODE -eq 0
        if ($accepted -ne $case.accepted -or
            (-not $accepted -and $text -notmatch 'Both images must be real Azure Container Registry')) {
            throw "Unexpected runtime image validation result for $($case.image): $text"
        }
    }
    Write-Output 'Actual runtime-image validation accepts immutable digests and rejects zero hashes, tags and truncated hashes; no Azure call.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
