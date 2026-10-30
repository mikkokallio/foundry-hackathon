#requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][hashtable]$Images,
    [Parameter(Mandatory)][string]$ResultFile
)

$ErrorActionPreference = 'Stop'
$registries = @()
foreach ($name in @('backend', 'toolkit')) {
    if ($Images[$name] -notmatch '^([a-z0-9]+\.azurecr\.io)/[a-z0-9/_-]+@sha256:[0-9a-f]{64}$') {
        throw "Supply the actual immutable registry digest for '$name'."
    }
    $registries += $Matches[1]
}
$registries = @($registries | Sort-Object -Unique)
if ($registries.Count -ne 1) { throw 'This container rehearsal requires one explicit registry.' }
$registry = $registries[0]
$dockerEndpoint = docker context inspect --format '{{.Endpoints.docker.Host}}'
if ($LASTEXITCODE -ne 0 -or $dockerEndpoint -notlike 'npipe:*') {
    throw 'The Windows container rehearsal must use a local Docker named-pipe endpoint.'
}
$dockerConfiguration = Join-Path ([IO.Path]::GetTempPath()) "container-test-login-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $dockerConfiguration -ErrorAction Stop | Out-Null
$dockerArguments = @('--config', $dockerConfiguration, '--host', $dockerEndpoint)
$containers = @()
$checks = @{}
$previousExitCode = $global:LASTEXITCODE

function Invoke-Docker([string[]]$Arguments) {
    $output = & docker @dockerArguments @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Local Docker command failed (exit $LASTEXITCODE): $($Arguments[0])" }
    return $output
}

try {
    $login = az acr login --subscription "$SubscriptionId" --name $registry.Split('.')[0] --expose-token -o json |
        ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $login.accessToken -or $login.loginServer -ine $registry) {
        throw 'Entra registry authentication failed.'
    }
    $login.accessToken | & docker @dockerArguments login $registry `
        --username '00000000-0000-0000-0000-000000000000' --password-stdin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Isolated Docker registry login failed.' }
    $login = $null

    foreach ($name in @('backend', 'toolkit')) {
        Invoke-Docker @('pull', '--platform', 'linux/amd64', $Images[$name]) | Out-Null
        $platform = Invoke-Docker @('image', 'inspect', $Images[$name], '--format', '{{.Os}}/{{.Architecture}} {{.Config.User}}')
        if ($platform -cne 'linux/amd64 10001') { throw "Wrong platform or runtime user for '$name': $platform" }
        $port = if ($name -eq 'backend') { '8000' } else { '8080' }

        # Test-only local storage; authentication stays Entra and no Azure/Foundry response is fabricated.
        $id = Invoke-Docker @('run', '--detach', '--platform', 'linux/amd64',
            '--publish', "127.0.0.1::${port}",
            '--env', 'STORAGE_MODE=local', '--env', 'LOCAL_STORE_DIR=/tmp/archdocs-container-test',
            '--env', 'AUTH_MODE=entra', '--env', 'ORGANIZATION_NAME=Container rehearsal',
            '--env', 'AZURE_TENANT_ID=00000000-0000-0000-0000-000000000001',
            '--env', 'BACKEND_AUDIENCE=00000000-0000-0000-0000-000000000002',
            '--env', 'GATEWAY_PRINCIPAL_ID=00000000-0000-0000-0000-000000000003',
            $Images[$name])
        if ($id -notmatch '^[0-9a-f]{64}$') { throw 'Docker returned no unique container ID.' }
        $containers += $id
        $binding = Invoke-Docker @('port', $id, "${port}/tcp")
        if ($binding -notmatch '^127\.0\.0\.1:(\d+)$') { throw 'The test listener must remain local-only.' }
        $url = "http://127.0.0.1:$($Matches[1])"
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(90)
        $healthy = $false
        $startupError = 'No response'
        do {
            $state = Invoke-Docker @('inspect', $id, '--format', '{{json .State}}') | ConvertFrom-Json
            if (-not $state.Running) {
                Invoke-Docker @('logs', $id) | Write-Host
                throw "Container '$name' exited before readiness (exit $($state.ExitCode))."
            }
            try {
                $response = Invoke-WebRequest -Uri "$url/health" -SkipHttpErrorCheck -TimeoutSec 3
                $healthy = $response.StatusCode -eq 200
                $startupError = "HTTP $($response.StatusCode)"
            } catch [System.Net.Http.HttpRequestException] {
                $startupError = $_.Exception.Message
            }
            if ($healthy) { break }
            Start-Sleep -Seconds 1
        } while ([DateTimeOffset]::UtcNow -lt $deadline)
        if (-not $healthy) {
            Invoke-Docker @('logs', $id) | Write-Host
            throw "Container '$name' did not become ready: $startupError"
        }
        $protectedPath = if ($name -eq 'backend') { '/systems' } else { '/mcp' }
        $anonymous = Invoke-WebRequest -Uri "$url$protectedPath" -SkipHttpErrorCheck -TimeoutSec 5
        if ($anonymous.StatusCode -ne 401) {
            throw "Container '$name' accepted or mishandled anonymous traffic: HTTP $($anonymous.StatusCode)"
        }
        $checks[$name] = @{ image = $Images[$name]; platform_and_user = $platform; health = 200; anonymous = 401 }
        Write-Output "$name : actual linux/amd64 image starts as user 10001, health 200, anonymous access 401."
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultFile) -Force | Out-Null
    @{
        checked_at = [DateTimeOffset]::UtcNow.ToString('o')
        scope = 'local-container-startup-and-anonymous-access-only'
        checks = $checks
        blob_connectivity_tested = $false
        entra_valid_token_flow_tested = $false
        foundry_acceptance = $false
    } | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $ResultFile -Encoding utf8NoBOM
} finally {
    foreach ($id in $containers) {
        & docker @dockerArguments rm --force $id | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "Cleanup failed for this test container: $id" }
    }
    Remove-Item -LiteralPath $dockerConfiguration -Recurse -ErrorAction Stop
    $global:LASTEXITCODE = $previousExitCode
}
