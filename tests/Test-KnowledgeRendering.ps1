#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$knowledge = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\knowledge.tf') -Raw
if ($knowledge -notmatch '(?s)organization_markdown = (?<expression>.*?)\r?\n  knowledge_sources') {
    throw 'Cannot locate the actual Terraform organization-rendering expression.'
}
$expression = $Matches.expression
$scratch = Join-Path $root "out\knowledge-render-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    "variable `"organization_name`" { type = string }`nlocals { organization_markdown = $expression }" |
        Set-Content -LiteralPath (Join-Path $scratch 'main.tf') -Encoding utf8NoBOM
    & terraform "-chdir=$scratch" init -backend=false -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Provider-free rendering test initialization failed.' }
    foreach ($case in @(
        @{ input = 'Northwind'; expected = 'Northwind' },
        @{ input = 'R&D <QA> [A]*_|'; expected = 'R&amp;D &lt;QA&gt; \[A\]\*\_\|' },
        @{ input = 'A\B `C`'; expected = 'A\\B \`C\`' },
        @{ input = 'Company "Example"'; expected = 'Company "Example"' }
    )) {
        $raw = 'jsonencode(local.organization_markdown)' |
            & terraform "-chdir=$scratch" console "-var=organization_name=$($case.input)"
        if ($LASTEXITCODE -ne 0) { throw 'Terraform rendering evaluation failed.' }
        $actual = $raw | ConvertFrom-Json | ConvertFrom-Json
        if ($actual -cne $case.expected) { throw "Terraform Markdown escaping mismatch for '$($case.input)'." }
    }
    Write-Output 'Actual Terraform organization rendering passed HTML/Markdown metacharacter cases without providers or Azure calls.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
