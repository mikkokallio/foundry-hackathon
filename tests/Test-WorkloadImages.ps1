#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$builder = Join-Path $root 'infra\scripts\Build-WorkloadImages.ps1'
$outputDirectory = Join-Path $root "out\image-tests-$([guid]::NewGuid().ToString('N'))"
$previousExitCode = $global:LASTEXITCODE

# These command doubles exist only in this test. No Azure build or image is created.
$imageTest = @{
    calls = @()
    builds = @{}
    status = 'Succeeded'
    digest = "sha256:$('1' * 64)"
    architecture = 'amd64'
    wrongRegistry = $false
}
$foundation = @{
    subscription_id = '00000000-0000-0000-0000-000000000001'
    tenant_id = '00000000-0000-0000-0000-000000000002'
    registry_id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.ContainerRegistry/registries/testonly'
    registry_server = 'testonly.azurecr.io'
}

function Assert-Image([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-TestArgument([object[]]$Arguments, [string]$Name) {
    $index = [Array]::IndexOf($Arguments, $Name)
    if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) { throw "Missing test CLI argument $Name" }
    return $Arguments[$index + 1]
}

function az {
    $global:LASTEXITCODE = 0
    $imageTest.calls += ,@($args)
    Assert-Image ((Get-TestArgument $args '--subscription') -ceq $foundation.subscription_id) 'Every image operation must pin the subscription.'
    $operation = "$($args[0]) $($args[1])"
    switch ($operation) {
        'account show' {
            @{ id = $foundation.subscription_id; tenantId = $foundation.tenant_id } | ConvertTo-Json
        }
        'acr show' {
            Assert-Image ((Get-TestArgument $args '--name') -ceq 'testonly') 'Registry lookup must use the supported name argument.'
            Assert-Image ((Get-TestArgument $args '--resource-group') -ceq 'test-only') 'Registry lookup must pin the resource group.'
            @{
                id = $foundation.registry_id
                name = 'testonly'
                loginServer = if ($imageTest.wrongRegistry) { 'wrong.azurecr.io' } else { $foundation.registry_server }
                provisioningState = 'Succeeded'
            } | ConvertTo-Json
        }
        'acr build' {
            $context = $args[-1]
            Assert-Image ((Get-TestArgument $args '--platform') -ceq 'linux/amd64') 'Builds must target ACA Linux AMD64, not the developer architecture.'
            Assert-Image ('--no-logs' -in $args -and '--no-wait' -notin $args) 'Build execution must return machine-readable run metadata, not discard it with --no-wait.'
            $dockerfile = Get-TestArgument $args '--file'
            Assert-Image ($dockerfile.StartsWith("$context$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::Ordinal)) 'The CLI Dockerfile path must resolve inside the frozen bundle, not against the caller working directory.'
            Assert-Image (Test-Path -LiteralPath $dockerfile) 'The frozen context must contain its Dockerfile.'
            $files = @(Get-ChildItem -LiteralPath $context -Recurse -File)
            Assert-Image ($files.Count -gt 20) 'The production source bundle is incomplete.'
            Assert-Image (@($files | Where-Object FullName -Match '[\\/](tests|fixtures|answers|\.foundry|\.venv|out)[\\/]').Count -eq 0) 'Test/evaluation artifacts entered the upload bundle.'
            $image = Get-TestArgument $args '--image'
            $repository, $tag = $image -split ':', 2
            Assert-Image ($repository -like 'architecture-docs/*') 'Repositories must be workload-namespaced.'
            $runId = "test-only-run-$($imageTest.builds.Count)"
            $imageTest.builds[$runId] = @{
                runId = $runId
                status = $imageTest.status
                platform = @{ os = 'Linux'; architecture = $imageTest.architecture }
                outputImages = @(@{
                    registry = $foundation.registry_server
                    repository = $repository
                    tag = $tag
                    digest = $imageTest.digest
                })
            }
            @{ runId = $runId } | ConvertTo-Json
        }
        'acr task' {
            Assert-Image ($args[2] -eq 'show-run') 'Unexpected test task operation.'
            $imageTest.builds[(Get-TestArgument $args '--run-id')] | ConvertTo-Json -Depth 10
        }
        default { throw "Unexpected test Azure operation: $args" }
    }
}

function Invoke-TestBuild([string]$Directory) {
    & $builder -Scenario 'architecture-docs' -WorkloadName 'architecture-docs' `
        -Foundation $foundation -OutputDirectory $Directory -Confirm:$false -WarningAction SilentlyContinue | Out-Null
}

try {
    & $builder -Scenario 'architecture-docs' -WorkloadName 'architecture-docs' `
        -Foundation $foundation -OutputDirectory $outputDirectory -WhatIf | Out-Null
    Assert-Image ($imageTest.builds.Count -eq 0) 'WhatIf must never queue billable builds.'
    Assert-Image (-not (Test-Path -LiteralPath $outputDirectory)) 'WhatIf must not create success-shaped image receipts.'

    Invoke-TestBuild $outputDirectory
    $receipts = @(Get-ChildItem -LiteralPath $outputDirectory -Recurse -Filter '*.receipt.json')
    Assert-Image ($receipts.Count -eq 2) 'Both exact build receipts must be persisted.'
    $receiptValues = @($receipts | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    })
    Assert-Image ($receiptValues[0].source_sha256 -ceq $receiptValues[1].source_sha256) 'Both apps must use one frozen source bundle.'
    foreach ($receipt in $receiptValues) {
        Assert-Image ($receipt.image -match '@sha256:[0-9a-f]{64}$') 'An image receipt must contain an immutable digest, never just a tag.'
        Assert-Image (-not $receipt.release_accepted) 'A build must not claim Foundry/runtime acceptance.'
    }
    $sourceManifest = Get-ChildItem -LiteralPath $outputDirectory -Recurse -Filter 'source-manifest.json'
    $sources = Get-Content -LiteralPath $sourceManifest.FullName -Raw | ConvertFrom-Json -AsHashtable
    Assert-Image ($sources.ContainsKey('backend/src/docs_api/main.py') -and
        $sources.ContainsKey('toolkit-mcp/server.py')) 'The source receipt must identify both actual application entry points.'

    $before = $imageTest.builds.Count
    $partialDirectory = Join-Path $outputDirectory 'partial'
    & $builder -Scenario 'architecture-docs' -WorkloadName 'architecture-docs' `
        -Foundation $foundation -OutputDirectory $partialDirectory -Artifacts toolkit -Confirm:$false | Out-Null
    Assert-Image ($imageTest.builds.Count -eq $before + 1) 'A subset request must build only the requested artifact.'
    Assert-Image (@(Get-ChildItem -LiteralPath $partialDirectory -Recurse -Filter 'runtime-images.json').Count -eq 0) 'A partial build must never claim a complete deployment image map.'
    $partialFile = @(Get-ChildItem -LiteralPath $partialDirectory -Recurse -Filter 'built-images.json')
    $partial = Get-Content -LiteralPath $partialFile[0].FullName -Raw | ConvertFrom-Json -AsHashtable
    Assert-Image ($partial.Count -eq 1 -and $partial.ContainsKey('toolkit')) 'Partial outputs must contain exactly the actual selected build.'
    $before = $imageTest.calls.Count
    $rejected = $false
    try {
        & $builder -Scenario 'architecture-docs' -WorkloadName 'architecture-docs' `
            -Foundation $foundation -OutputDirectory $partialDirectory -Artifacts unknown -Confirm:$false | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Unknown container artifact') { throw }
        $rejected = $true
    }
    Assert-Image ($rejected -and $imageTest.calls.Count -eq $before) 'Reject unknown artifacts before any Azure operation or paid work.'

    foreach ($failure in @('status', 'digest', 'architecture', 'registry')) {
        $directory = Join-Path $outputDirectory $failure
        $imageTest.status = if ($failure -eq 'status') { 'Failed' } else { 'Succeeded' }
        $imageTest.digest = if ($failure -eq 'digest') { 'mutable-tag-is-not-a-digest' } else { "sha256:$('1' * 64)" }
        $imageTest.architecture = if ($failure -eq 'architecture') { 'arm64' } else { 'amd64' }
        $imageTest.wrongRegistry = $failure -eq 'registry'
        $rejected = $false
        try {
            Invoke-TestBuild $directory
        } catch {
            if ($_.Exception.Message -notmatch 'ended with|lacks one verified|registry is missing') { throw }
            $rejected = $true
        }
        Assert-Image $rejected "Invalid $failure must fail explicitly."
        if (Test-Path -LiteralPath $directory) {
            Assert-Image (@(Get-ChildItem -LiteralPath $directory -Recurse -Filter 'runtime-images.json').Count -eq 0) 'A failed build must never write a completed runtime image map.'
        }
    }
    Write-Output 'Image-build contract passed using test-scoped Azure command doubles. No real image build or runtime acceptance occurred.'
} finally {
    if (Test-Path -LiteralPath $outputDirectory) { Remove-Item -LiteralPath $outputDirectory -Recurse }
    $global:LASTEXITCODE = $previousExitCode
}
