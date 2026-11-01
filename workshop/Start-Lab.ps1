#requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Configuration,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,30}$')][string]$Team,
    [Parameter(Mandatory)][string]$Prefix,
    [switch]$PrepareOnly,
    [switch]$SkipSignIn
)

$ErrorActionPreference = 'Stop'
if (-not $PrepareOnly -and $MyInvocation.InvocationName -ne '.') {
    throw 'Dot-source this starter so lab remains available: . .\workshop\Start-Lab.ps1 -Configuration PATH -Team TEAM -Prefix TEAM-p2'
}
if ($Prefix -cnotmatch "^$([regex]::Escape($Team))-p[1-4](?:-[a-z0-9]+)*$") {
    throw 'Use your actual team-p1 through team-p4 prefix, optionally followed by a rehearsal suffix.'
}
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$configurationPath = (Resolve-Path -LiteralPath $Configuration).Path
$output = Join-Path $root "out\participant\$Prefix-$([guid]::NewGuid().ToString('N'))"
& (Join-Path $root 'scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1') `
    -Configuration $configurationPath -Team $Team -OutputDirectory $output
$packPath = Join-Path $output 'workshop.json'
$context = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
Write-Host "Team: $Team; prefix: $Prefix"
Write-Host "Project: $($context.project_endpoint)"
Write-Host "Local inputs: $packPath"
if ($PrepareOnly) {
    Write-Output $packPath
    return
}
if ((Get-Command lab -ErrorAction SilentlyContinue) -and -not $global:FoundryLabSession) {
    throw 'A different lab command already exists. Use a fresh PowerShell session instead of replacing it.'
}
if ($global:FoundryLabSession -and $global:FoundryLabSession.Prefix -cne $Prefix) {
    throw 'Another participant prefix is already active. Use a fresh PowerShell session.'
}
Get-Command az -ErrorAction Stop | Out-Null
$venv = Join-Path $root '.venv'
if (-not (Test-Path -LiteralPath $venv)) {
    & python -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Python environment creation failed. Python 3.11+ is required.' }
}
$interpreter = if ($IsWindows) { Join-Path $venv 'Scripts\python.exe' } else { Join-Path $venv 'bin\python' }
if (-not (Test-Path -LiteralPath $interpreter -PathType Leaf)) {
    throw 'Existing .venv has no interpreter for this operating system. Keep it intact and use a fresh checkout.'
}
& $interpreter -c 'import azure.ai.projects, azure.identity, azure.monitor.query, openai, yaml'
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Required Python modules are missing; installing the declared workshop dependencies.'
    & $interpreter -m pip install --only-binary=:all: -r (Join-Path $root 'scenarios\architecture-docs\scripts\requirements-gate.txt')
    if ($LASTEXITCODE -ne 0) {
        throw 'Prebuilt workshop dependency installation failed. Keep the error; use Cloud Shell rather than installing a compiler or changing package pins.'
    }
}
$env:AZURE_CONFIG_DIR = Join-Path $HOME ".foundry-hackathon-$Prefix"
if (-not $SkipSignIn) {
    $accountTenant = & az account show --subscription $context.subscription_id --query tenantId --output tsv
    $requiresSignIn = $LASTEXITCODE -ne 0 -or $accountTenant -ine $context.tenant_id
    if (-not $requiresSignIn) {
        & az account get-access-token --subscription $context.subscription_id `
            --scope $context.gateway_scope --query expiresOn --output tsv
        $requiresSignIn = $LASTEXITCODE -ne 0
    }
    if ($requiresSignIn) {
        Write-Host 'This isolated workshop profile needs scoped sign-in. Use your own assigned workshop account.'
        & az login --tenant $context.tenant_id --scope $context.gateway_scope --use-device-code
        if ($LASTEXITCODE -ne 0) { throw 'Workshop sign-in failed.' }
    }
    & az account set --subscription $context.subscription_id
    if ($LASTEXITCODE -ne 0) { throw 'Workshop subscription selection failed.' }
    $accountTenant = & az account show --subscription $context.subscription_id --query tenantId --output tsv
    if ($LASTEXITCODE -ne 0 -or $accountTenant -ine $context.tenant_id) {
        throw 'Workshop account tenant does not match the deployment configuration.'
    }
} else {
    Write-Warning 'Sign-in was skipped. Later commands still require the correct workshop identity and scope.'
}
$global:FoundryLabSession = @{
    Python = $interpreter; Pack = $packPath; Prefix = $Prefix; Root = $root
}
function global:lab {
    Push-Location $global:FoundryLabSession.Root
    try {
        & $global:FoundryLabSession.Python -m workshop --pack $global:FoundryLabSession.Pack `
            --prefix $global:FoundryLabSession.Prefix @args
        if ($LASTEXITCODE -ne 0) { throw 'Workshop command failed; inspect the explicit error above.' }
    } finally {
        Pop-Location
    }
}
Write-Host 'lab is now available in this shell. First run: lab check'
Write-Host 'Then continue M3 with: lab practice status'
Write-Warning 'Input assembly is not live acceptance. lab check does not prove authoring permissions.'
