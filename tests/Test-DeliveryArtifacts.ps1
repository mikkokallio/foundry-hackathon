#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$delivery = Join-Path $root 'scenarios\architecture-docs\delivery'
$workflow = Get-Content -LiteralPath (Join-Path $delivery 'foundry-gate.workflow.yml') -Raw
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Body, [string]$Pattern) {
    try { & $Body | Out-Null } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw
    }
    throw "Expected explicit failure matching '$Pattern'."
}

$scripts = @([regex]::Matches($workflow, '(?m)^        run: \|\r?\n((?:^          .*(?:\r?\n|\z)|^\r?\n)+)') |
    ForEach-Object {
        $text = ($_.Groups[1].Value -split '\r?\n' | ForEach-Object {
            if ($_.StartsWith('          ')) { $_.Substring(10) } else { $_ }
        }) -join "`n"
        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert ($parseErrors.Count -eq 0) "Invalid workflow PowerShell: $($parseErrors.Message -join '; ')"
        $text
    })
Assert ($scripts.Count -eq 4) 'Validate every inline workflow PowerShell step.'
Assert ($workflow -notmatch 'continue-on-error|pull_request_target|terraform\s+.*\bapply\b|client-secret') 'CI may not bypass failures, apply infrastructure or use client secrets.'
Assert ($workflow.IndexOf('Evaluate fresh deployed candidate') -lt $workflow.IndexOf('Plan against existing protected')) 'The live gate must precede the plan.'
Assert ($scripts[2] -match 'run_foundry_gate\.py' -and
    $scripts[2] -match 'if \(\$LASTEXITCODE -ne 0\).*throw' -and
    $scripts[3] -match 'Remote state is absent or unreadable') 'Real runner failures and missing remote state must block planning.'
Assert ($workflow -match 'if: always\(\)' -and $workflow -match 'include-hidden-files: true' -and
    $workflow -match 'if-no-files-found: error') 'Keep failure/provenance evidence; never upload an empty success report.'
Assert (([regex]::Matches($workflow, '(?m)^      - (?:uses:|name:)')).Count -eq 9) 'Review unexpected workflow steps.'
$main = Get-Content -LiteralPath (Join-Path $delivery 'main.tf') -Raw
Assert (([regex]::Matches($main, 'prevent_destroy\s*=\s*true')).Count -eq 3) 'Retain the state group, account and container through Terraform teardown.'
$requirements = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\scripts\requirements-gate.txt')
Assert ($requirements.Count -eq 5 -and @($requirements | Where-Object { $_ -notmatch '^[a-zA-Z0-9-]+==[0-9]+(?:\.[0-9]+)+$' }).Count -eq 0) 'Pin the actual gate dependencies, not an unreviewed latest SDK.'

# Execute only configuration validation, with explicit test-scoped bindings.
$names = @(
    'ARM_CLIENT_ID', 'ARM_TENANT_ID', 'ARM_SUBSCRIPTION_ID', 'WORKSHOP_DIRECTORY',
    'STATE_RESOURCE_GROUP', 'STATE_ACCOUNT', 'STATE_KEY', 'FOUNDATION_INPUTS_JSON',
    'PROJECT_ENDPOINT', 'APP_INSIGHTS_RESOURCE_ID', 'WORKSPACE_RESOURCE_ID',
    'JUDGE_DEPLOYMENT', 'AGENT_NAME', 'AGENT_VERSION', 'GITHUB_WORKSPACE', 'GITHUB_ENV'
)
$previous = @{}
$scratch = Join-Path $root "out\delivery-artifact-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, 'unmistakably-test-scoped-binding')
    }
    $env:AGENT_VERSION = '2'
    $env:WORKSHOP_DIRECTORY = '.'
    $env:GITHUB_WORKSPACE = $root
    $env:GITHUB_ENV = Join-Path $scratch 'github-env.txt'
    $validate = [scriptblock]::Create($scripts[0])
    & $validate
    Assert ((Get-Content -LiteralPath $env:GITHUB_ENV -Raw).Trim() -ceq "WORKSHOP_ROOT=$root") 'Bind the actual checkout path, not another workspace.'
    $env:ARM_CLIENT_ID = ''
    Assert-Throws $validate 'Missing protected environment binding: ARM_CLIENT_ID'
    $env:ARM_CLIENT_ID = 'unmistakably-test-scoped-binding'
    $env:AGENT_VERSION = 'latest'
    Assert-Throws $validate 'immutable numeric agent version'
    $env:AGENT_VERSION = '2'
    $env:WORKSHOP_DIRECTORY = '..'
    Assert-Throws $validate 'inside this checkout'
    Write-Output 'Delivery workflow scripts parse; explicit configuration, immutable version and checkout boundaries pass. No Azure/Foundry calls were made.'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
    Remove-Item -LiteralPath $scratch -Recurse
}
