#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$checker = Join-Path $root 'infra\scripts\Test-DeploymentPreflight.ps1'
$outputDirectory = Join-Path $root "out\preflight-tests-$([guid]::NewGuid().ToString('N'))"
$previousExitCode = $global:LASTEXITCODE
$previousCulture = [Globalization.CultureInfo]::CurrentCulture
[Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fi-FI')

# Test-scoped responses. Any command other than a declared read fails the test.
$preflightTest = @{ mode = 'success'; calls = @(); timeouts = 0; stoppedJobs = 0; costAttempts = 0 }
$member = '00000000-0000-0000-0000-000000000003'
$settings = @{
    subscription_id = '00000000-0000-0000-0000-000000000001'
    tenant_id = '00000000-0000-0000-0000-000000000002'
    location = 'swedencentral'
    search_location = 'francecentral'
    teams = @{ alpha = @($member) }
    expected_participant_count = 1
    protection = @{ monthly_cap_eur = 130; reserve_eur = 30; max_hourly_eur = 1 }
}
$review = & (Join-Path $root 'infra\scripts\Inspect-Deployment.ps1') -Scenario architecture-docs `
    -WorkloadInputs @{ librarians = @($member) } -AsJson | ConvertFrom-Json -AsHashtable -Depth 30
$review.workload.models.judge = $review.workload.models['chat-small'].Clone()
$review.workload.models.judge.capacity = 100

function Assert-Preflight([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Start-Job {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList)
    @{
        State = 'Completed'
        Result = @(& $ScriptBlock @ArgumentList)
        Arguments = $ArgumentList[0]
    }
}
function Wait-Job {
    param([object]$Job, [int]$Timeout)
    Assert-Preflight ($Timeout -eq 35) 'Every native CLI read must have an explicit short deadline.'
    if ($preflightTest.mode -eq 'graph-timeout-once' -and $preflightTest.timeouts -eq 0 -and
        ($Job.Arguments -join ' ') -match '/transitiveMemberOf/') {
        $preflightTest.timeouts++
        return
    }
    $Job
}
function Receive-Job { param([object]$Job, [string]$ErrorAction) $Job.Result }
function Stop-Job { param([object]$Job) $Job.State = 'Stopped'; $preflightTest.stoppedJobs++ }
function Remove-Job { param([object]$Job, [switch]$Force) }
function Start-Sleep { param([int]$Seconds) Assert-Preflight ($Seconds -eq 5) 'Retry backoff must remain bounded.' }
function az {
    $global:LASTEXITCODE = 0
    $preflightTest.calls += ,@($args)
    Assert-Preflight ('--subscription' -in $args -and $settings.subscription_id -in $args) 'Pin every operation to the selected subscription.'
    $operation = "$($args[0]) $($args[1])"
    switch ($operation) {
        'account show' { @{ id = $settings.subscription_id; tenantId = $settings.tenant_id } | ConvertTo-Json }
        'provider list' {
            @('Microsoft.CognitiveServices', 'Microsoft.Search', 'Microsoft.Storage', 'Microsoft.KeyVault',
                'Microsoft.OperationalInsights', 'Microsoft.Insights', 'Microsoft.ContainerRegistry',
                'Microsoft.App', 'Microsoft.ApiManagement', 'Microsoft.ApiCenter', 'Microsoft.Automation', 'Microsoft.Cache') |
                ForEach-Object { @{
                    namespace = $_
                    registrationState = if ($_ -eq 'Microsoft.Cache' -and $preflightTest.mode -eq 'cache-unregistered') { 'NotRegistered' } else { 'Registered' }
                } } | ConvertTo-Json
        }
        'provider show' {
            Assert-Preflight ('Microsoft.Cache' -in $args) 'Only read the explicitly selected cache provider.'
            @{ resourceTypes = @(@{
                resourceType = 'redisEnterprise'
                locations = if ($preflightTest.mode -eq 'cache-region-unavailable') { @('West Europe') } else { @('Sweden Central') }
            }) } | ConvertTo-Json -Depth 10
        }
        'cognitiveservices account' {
            Assert-Preflight ($args[2] -eq 'list-skus') 'Do not create/change a Cognitive Services account in preflight.'
            @(@{ name = 'S0' }) | ConvertTo-Json -AsArray
        }
        'cognitiveservices model' {
            Assert-Preflight ($args[2] -eq 'list') 'Do not deploy/alter a model in preflight.'
            $catalog = foreach ($model in $review.workload.models.Values) {
                foreach ($kind in @('AIServices', 'OpenAI')) {
                    @{
                        kind = $kind
                        skuName = 'S0'
                        model = @{
                            format = 'OpenAI'; name = $model.name; version = $model.version
                            lifecycleStatus = if ($preflightTest.mode -eq 'legacy-model') { 'Legacy' } elseif ($preflightTest.mode -eq 'unknown-lifecycle') { $null } else { 'GenerallyAvailable' }
                            deprecation = @{ inference = if ($preflightTest.mode -eq 'retired-model') { '2020-01-01T00:00:00Z' } else { '2099-09-21T00:00:00Z' } }
                            skus = @(
                                @{ name = $model.sku; usageName = "metric-$($model.name)"; capacity = @{ maximum = 1000 } },
                                @{ name = $model.sku; usageName = "metric-$($model.name)-finetune"; capacity = @{ maximum = 10000 } }
                            )
                        }
                    }
                }
            }
            $catalog | ConvertTo-Json -Depth 20
        }
        'rest --method' {
            $url = $args[[Array]::IndexOf($args, '--url') + 1]
            if ($url -eq "https://management.azure.com/subscriptions/$($settings.subscription_id)/providers/Microsoft.CostManagement/query?api-version=2023-11-01") {
                Assert-Preflight ($args[2] -ceq 'post') 'Cost Management query is a POST read, never a deployment operation.'
                Assert-Preflight ('ClientType=modular-workshop-preflight' -in $args) 'Use an explicit Cost Management client type.'
                $preflightTest.costAttempts++
                if ($preflightTest.mode -eq 'cost-throttled' -or
                    ($preflightTest.mode -eq 'cost-throttled-once' -and $preflightTest.costAttempts -eq 1)) {
                    $global:LASTEXITCODE = 1
                    Write-Output 'ERROR: 429 Too Many Requests'
                    return
                }
                $path = $args[[Array]::IndexOf($args, '--body') + 1]
                $body = Get-Content -LiteralPath $path.Substring(1) -Raw | ConvertFrom-Json
                Assert-Preflight ($body.type -ceq 'ActualCost' -and $body.timeframe -ceq 'MonthToDate' -and
                    -not $body.dataset.filter) 'Collect fresh costs for the whole subscription, not a workload-filtered subtotal.'
                @{
                    properties = @{
                        columns = @(@{ name = 'PreTaxCost' }, @{ name = 'UsageDate' }, @{ name = 'Currency' })
                        rows = ,@(10, 20261029, 'EUR')
                    }
                } | ConvertTo-Json -Depth 10
                return
            }
            Assert-Preflight ($args[2] -eq 'get') 'All other preflight requests must be GETs, never configuration writes.'
            if ($url -match '/locations\?') {
                @(@{ name = 'swedencentral' }, @{ name = 'francecentral' }) | ConvertTo-Json
            } elseif ($url -match '/usages\?') {
                $usages = foreach ($name in @($review.workload.models.Values.name | Sort-Object -Unique)) {
                    @{
                        name = @{ value = "metric-$name" }
                        currentValue = if ($preflightTest.mode -eq 'quota-short' -and $name -eq $review.workload.models['chat-small'].name) { 851 } else { 0 }
                        limit = 1000
                        unit = 'Count'
                    }
                }
                @{ value = @($usages) } | ConvertTo-Json -Depth 10
            } elseif ($url -match '/permissions\?') {
                @{ value = @(@{ actions = @('*'); notActions = @() }) } | ConvertTo-Json -Depth 10
            } elseif ($url -match '/transitiveMemberOf/') {
                if ($preflightTest.mode -eq 'graph-roles-unavailable') {
                    $global:LASTEXITCODE = 1
                    Write-Output 'ERROR: ConnectTimeout'
                    return
                }
                @{ value = @(@{ roleTemplateId = '158c047a-c907-4556-b7ef-446551a6b5f7' }) } | ConvertTo-Json -Depth 10
            } elseif ($url -match '/users/') {
                @{
                    id = $member; accountEnabled = $true
                    userType = if ($preflightTest.mode -eq 'guest-pending') { 'Guest' } else { 'Member' }
                    externalUserState = if ($preflightTest.mode -eq 'guest-pending') { 'PendingAcceptance' } else { $null }
                } | ConvertTo-Json
            } elseif ($url -match '/me\?') {
                @{ id = $member; userPrincipalName = 'operator@unit.invalid' } | ConvertTo-Json
            } else { throw "Unexpected test URL: $url" }
        }
        default { throw "Forbidden/unexpected test operation: $args" }
    }
}
try {
    foreach ($key in @('location', 'search_location')) {
        $allowedRegion = $settings[$key]
        try {
            $settings[$key] = 'northeurope'
            $rejected = $false
            try {
                & $checker -Settings $settings -Review $review -OutputDirectory $outputDirectory | Out-Null
            } catch {
                if ($_.Exception.Message -notmatch 'Unauthorized region') { throw }
                $rejected = $true
            }
            Assert-Preflight $rejected "Reject the banned region for $key."
            Assert-Preflight ($preflightTest.calls.Count -eq 0) 'Reject unauthorized regions before any Azure request.'
        } finally {
            [Globalization.CultureInfo]::CurrentCulture = $previousCulture
            $settings[$key] = $allowedRegion
        }
    }
    & $checker -Settings $settings -Review $review -OutputDirectory $outputDirectory | Out-Null
    $file = @(Get-ChildItem -LiteralPath $outputDirectory -Recurse -Filter 'preflight.json')
    $report = Get-Content -LiteralPath $file[0].FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 75
    Assert-Preflight ($report.technical_checks_passed -and -not $report.deployment_ready) 'Passing diagnostics must not imply deployment approval or release acceptance.'
    $quota = @($report.checks | Where-Object name -EQ "quota/metric-$($review.workload.models['chat-small'].name)")
    Assert-Preflight ($quota.Count -eq 1 -and $quota[0].details.requested_allocation_units -eq 300) 'Aggregate aliases sharing one base-model quota; ignore fine-tuning variants and other account kinds.'
    Assert-Preflight (@($preflightTest.calls | Where-Object { $_[0] -eq 'provider' -and $_[1] -eq 'show' }).Count -eq 0) 'Disabled cache must not require cache deployment or registration.'
    foreach ($mode in @('cost-throttled-once', 'graph-timeout-once')) {
        $preflightTest.mode = $mode
        $preflightTest.costAttempts = 0
        & $checker -Settings $settings -Review $review -OutputDirectory (Join-Path $outputDirectory $mode) `
            -WarningAction SilentlyContinue | Out-Null
    }
    Assert-Preflight ($preflightTest.timeouts -eq 1 -and $preflightTest.stoppedJobs -eq 1) 'The timed-out job must be stopped before one fresh retry.'
    $preflightTest.mode = 'success'

    $review.workload.inputs.semantic_cache_enabled = $true
    $cacheDirectory = Join-Path $outputDirectory 'cache-enabled'
    & $checker -Settings $settings -Review $review -OutputDirectory $cacheDirectory | Out-Null
    $cacheFile = @(Get-ChildItem -LiteralPath $cacheDirectory -Recurse -Filter 'preflight.json')[0]
    $cacheReport = Get-Content -LiteralPath $cacheFile.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 75
    Assert-Preflight (@($cacheReport.checks | Where-Object { $_.name -eq 'redis/advertised-region' -and $_.passed }).Count -eq 1) 'Selected Redis needs an actual provider-region check.'

    foreach ($mode in @('quota-short', 'guest-pending', 'cache-unregistered', 'cache-region-unavailable', 'cost-throttled', 'graph-roles-unavailable', 'legacy-model', 'unknown-lifecycle', 'retired-model')) {
        $preflightTest.mode = $mode
        $preflightTest.calls = @()
        $directory = Join-Path $outputDirectory $mode
        $rejected = $false
        try {
            & $checker -Settings $settings -Review $review -OutputDirectory $directory -WarningAction SilentlyContinue | Out-Null
        } catch {
            if ($_.Exception.Message -notmatch 'prerequisites failed') { throw }
            $rejected = $true
        }
        Assert-Preflight $rejected "Reject '$mode' explicitly."
        $file = @(Get-ChildItem -LiteralPath $directory -Recurse -Filter 'preflight.json')
        $report = Get-Content -LiteralPath $file[0].FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 75
        Assert-Preflight (-not $report.technical_checks_passed -and -not $report.deployment_ready) 'Persist failed checks without a success-shaped fallback.'
        if ($mode -eq 'graph-roles-unavailable') {
            Assert-Preflight (@($preflightTest.calls | Where-Object { ($_ -join ' ') -match '/users/' }).Count -eq 0) 'Do not repeat failing Graph transport calls for every roster entry.'
        }
    }
    Write-Output 'Preflight tests passed using test-scoped responses; no Azure changes or real deployment acceptance occurred.'
} finally {
    if (Test-Path -LiteralPath $outputDirectory) { Remove-Item -LiteralPath $outputDirectory -Recurse }
    $global:LASTEXITCODE = $previousExitCode
}
