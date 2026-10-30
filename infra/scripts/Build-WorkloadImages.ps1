#requires -Version 7.5
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,39}$')]
    [string]$Scenario,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{2,28}[a-z0-9]$')]
    [string]$WorkloadName,
    [Parameter(Mandatory)]
    [hashtable]$Foundation,
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [string[]]$Artifacts = @()
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scenarioDirectory = Join-Path $root "scenarios\$Scenario"
$manifest = Get-Content -LiteralPath (Join-Path $scenarioDirectory 'scenario.json') -Raw |
    ConvertFrom-Json -AsHashtable -DateKind String -Depth 30
if ($manifest.id -cne $Scenario -or
    $manifest.container_artifacts -isnot [System.Collections.IDictionary] -or
    $manifest.container_artifacts.Count -eq 0 -or @($manifest.container_sources).Count -eq 0) {
    throw 'The selected scenario must declare its container artifacts and explicit production sources.'
}
$selectedArtifacts = if ($Artifacts.Count -eq 0) { @($manifest.container_artifacts.Keys) } else { @($Artifacts | Sort-Object -Unique) }
foreach ($artifact in $selectedArtifacts) {
    if (-not $manifest.container_artifacts.ContainsKey($artifact)) { throw "Unknown container artifact '$artifact'." }
}
foreach ($key in @('subscription_id', 'tenant_id', 'registry_id', 'registry_server')) {
    if ([string]::IsNullOrWhiteSpace($Foundation[$key])) { throw "Missing applied foundation field '$key'." }
}
if ($Foundation.registry_id -notlike "/subscriptions/$($Foundation.subscription_id)/resourceGroups/*/providers/Microsoft.ContainerRegistry/registries/*") {
    throw 'The registry must belong to the explicitly selected subscription.'
}

function Invoke-AzureJson([string[]]$Arguments) {
    $raw = & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed during image build (exit $LASTEXITCODE)." }
    return ($raw | ConvertFrom-Json -AsHashtable -DateKind String -Depth 40)
}

$account = Invoke-AzureJson @('account', 'show', '--subscription', $Foundation.subscription_id, '-o', 'json')
if ($account.id -ne $Foundation.subscription_id -or $account.tenantId -ne $Foundation.tenant_id) {
    throw 'Authenticated image-build target does not match the applied foundation.'
}
$registryParts = $Foundation.registry_id.Split('/')
$registry = Invoke-AzureJson @('acr', 'show', '--subscription', $Foundation.subscription_id,
    '--name', $registryParts[-1], '--resource-group', $registryParts[4], '-o', 'json')
if ($registry.id -ine $Foundation.registry_id -or $registry.loginServer -ine $Foundation.registry_server -or
    $registry.provisioningState -ne 'Succeeded') {
    throw 'The applied registry is missing, unready, or does not match the foundation contract.'
}

$bundle = Join-Path ([IO.Path]::GetTempPath()) "workload-build-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $bundle -ErrorAction Stop -WhatIf:$false | Out-Null
try {
    $files = @{}
    foreach ($pattern in $manifest.container_sources) {
        if ($pattern -isnot [string] -or [IO.Path]::IsPathRooted($pattern) -or
            $pattern -match '(^|[\\/])\.\.([\\/]|$)|:') {
            throw 'Container sources must be explicit scenario-relative file patterns.'
        }
        $matches = @(Get-ChildItem -Path (Join-Path $scenarioDirectory $pattern) -File -Force -ErrorAction Stop)
        if ($matches.Count -eq 0) { throw "Container source pattern matched no files: $pattern" }
        foreach ($file in $matches) {
            if (-not $file.FullName.StartsWith(
                    "$scenarioDirectory$([IO.Path]::DirectorySeparatorChar)",
                    $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })
                ) -or
                ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Container sources must be ordinary files within the selected scenario.'
            }
            $relative = [IO.Path]::GetRelativePath($scenarioDirectory, $file.FullName)
            if ($relative -match '(^|[\\/])(tests|fixtures|answers|\.foundry|\.venv|out)([\\/]|$)') {
                throw "Test/evaluation/operator artifacts must not enter production images: $relative"
            }
            $target = Join-Path $bundle $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force -WhatIf:$false | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop -WhatIf:$false
            $files[$relative.Replace('\', '/')] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    foreach ($artifact in $manifest.container_artifacts.Keys) {
        if ($artifact -notmatch '^[a-z][a-z0-9-]{0,30}$' -or
            -not $files.ContainsKey($manifest.container_artifacts[$artifact].Replace('\', '/'))) {
            throw "Artifact '$artifact' must reference a Dockerfile included in the frozen source bundle."
        }
    }
    $sourceManifest = [ordered]@{}
    foreach ($path in ($files.Keys | Sort-Object -CaseSensitive)) { $sourceManifest[$path] = $files[$path] }
    $sourceJson = $sourceManifest | ConvertTo-Json -Depth 10 -Compress
    $sourceHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($sourceJson))
    ).ToLowerInvariant()
    if (-not $PSCmdlet.ShouldProcess(
        $registry.id,
        "Queue billable linux/amd64 builds for '$WorkloadName', source SHA256 $sourceHash; push immutable artifacts"
    )) { return }

    $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
    $receiptDirectory = Join-Path $OutputDirectory $stamp
    New-Item -ItemType Directory -Path $receiptDirectory -ErrorAction Stop | Out-Null
    $sourceJson | Set-Content -LiteralPath (Join-Path $receiptDirectory 'source-manifest.json') -Encoding utf8NoBOM
    $images = @{}
    foreach ($artifact in ($selectedArtifacts | Sort-Object)) {
        $repository = "$WorkloadName/$artifact"
        $tag = "src-$($sourceHash.Substring(0, 16))-$stamp"
        @{
            source_sha256 = $sourceHash
            repository = $repository
            tag = $tag
            registry_id = $registry.id
            dockerfile = $manifest.container_artifacts[$artifact]
        } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $receiptDirectory "$artifact.intent.json") -Encoding utf8NoBOM
        $run = Invoke-AzureJson @('acr', 'build', '--subscription', $Foundation.subscription_id,
            '--registry', $registry.name, '--image', "${repository}:$tag",
            '--platform', 'linux/amd64', '--file', (Join-Path $bundle $manifest.container_artifacts[$artifact]),
            '--no-logs', '-o', 'json', $bundle)
        if ([string]::IsNullOrWhiteSpace($run.runId)) { throw "No build run ID returned for '$artifact'." }
        Write-Host "Queued $repository : run $($run.runId); source $sourceHash"
        $deadline = [DateTimeOffset]::UtcNow.AddMinutes(20)
        do {
            $finished = Invoke-AzureJson @('acr', 'task', 'show-run', '--subscription', $Foundation.subscription_id,
                '--registry', $registry.name, '--run-id', $run.runId, '-o', 'json')
            if ($finished.status -eq 'Succeeded') { break }
            if ($finished.status -notin @('Queued', 'Started', 'Running')) {
                throw "Image build '$($run.runId)' ended with '$($finished.status)'. Inspect its ACR logs; no workload plan was produced."
            }
            if ([DateTimeOffset]::UtcNow -ge $deadline) {
                throw "Image build '$($run.runId)' exceeded 20 minutes. It may still be running in ACR; inspect/cancel that specific run before retrying."
            }
            Start-Sleep -Seconds 10
        } while ($true)
        $image = @($finished.outputImages | Where-Object {
            $_.repository -ceq $repository -and $_.tag -ceq $tag -and $_.registry -ieq $registry.loginServer
        })
        if ($image.Count -ne 1 -or $image[0].digest -notmatch '^sha256:[0-9a-f]{64}$' -or
            $image[0].digest -eq "sha256:$('0' * 64)" -or
            $finished.platform.os -ine 'linux' -or $finished.platform.architecture -ine 'amd64') {
            throw "Build '$($run.runId)' lacks one verified linux/amd64 registry output and immutable digest."
        }
        $images[$artifact] = "$($registry.loginServer)/$repository@$($image[0].digest)"
        @{
            schema_version = 1
            scenario = $Scenario
            workload_name = $WorkloadName
            subscription_id = $Foundation.subscription_id
            tenant_id = $Foundation.tenant_id
            registry_id = $registry.id
            source_sha256 = $sourceHash
            run = $finished
            image = $images[$artifact]
            release_accepted = $false
        } | ConvertTo-Json -Depth 40 |
            Set-Content -LiteralPath (Join-Path $receiptDirectory "$artifact.receipt.json") -Encoding utf8NoBOM
        Write-Host "Built $artifact : $($images[$artifact])"
    }
    $complete = $images.Count -eq $manifest.container_artifacts.Count
    $imageFile = Join-Path $receiptDirectory $(if ($complete) { 'runtime-images.json' } else { 'built-images.json' })
    $images | ConvertTo-Json | Set-Content -LiteralPath $imageFile -Encoding utf8NoBOM
    Write-Output "Built immutable image values (complete set: $complete): $imageFile"
    Write-Warning 'Artifacts only: no Terraform apply, runtime acceptance or Foundry evaluation has occurred.'
} finally {
    Remove-Item -LiteralPath $bundle -Recurse -ErrorAction Stop -WhatIf:$false
}
