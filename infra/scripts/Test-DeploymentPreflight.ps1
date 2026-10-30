#requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$Settings,
    [Parameter(Mandatory)][hashtable]$Review,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
foreach ($key in @('subscription_id', 'tenant_id')) {
    $id = [guid]::Empty
    if (-not [guid]::TryParse($Settings[$key], [ref]$id) -or $id -eq [guid]::Empty) {
        throw "Preflight requires an explicit $key GUID."
    }
}
foreach ($key in @('location', 'search_location')) {
    if ($Settings[$key] -cnotin @('francecentral', 'swedencentral', 'westeurope')) {
        throw "Unauthorized region '$key': use francecentral (preferred), swedencentral or westeurope."
    }
}
if ($Review.scenario -cne 'architecture-docs') {
    throw 'This preflight currently implements architecture-docs prerequisites only; other scenarios need an explicit checker.'
}
$checks = [Collections.Generic.List[object]]::new()
$evidence = @{}
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
@{ operation = 'read-only-preflight-started'; deployment_ready = $false } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDirectory 'intent.json') -Encoding utf8NoBOM

function Add-Check([string]$Name, [bool]$Passed, [object]$Details) {
    $checks.Add(@{ name = $Name; passed = $Passed; details = $Details })
}
function Read-Azure([string]$Name, [string[]]$Arguments) {
    if ($Arguments[0] -eq 'rest') {
        $costRead = $Name -ceq 'whole-subscription-costs' -and $Arguments[2] -ceq 'post' -and
            $Arguments[4] -ceq "https://management.azure.com/subscriptions/$($Settings.subscription_id)/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
        if ($Arguments[1] -ne '--method' -or ($Arguments[2] -ne 'get' -and -not $costRead)) {
            throw 'Preflight permits only GET requests and the exact nonmutating Cost Management query.'
        }
    }
    if ($Arguments[0] -notin @('rest', 'account', 'provider', 'cognitiveservices')) {
        throw 'Unexpected operation in read-only preflight.'
    }
    $raw = @()
    $exitCode = $null
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $cliArguments = @($Arguments) + @('--subscription', $Settings.subscription_id, '--only-show-errors', '-o', 'json')
        $job = Start-Job -ScriptBlock {
            param([string[]]$CliArguments)
            $lines = @(& az @CliArguments 2>&1 | ForEach-Object { "$_" })
            [pscustomobject]@{ exit_code = $LASTEXITCODE; lines = $lines }
        } -ArgumentList (,$cliArguments)
        try {
            if (Wait-Job -Job $job -Timeout 35) {
                $result = @(Receive-Job -Job $job -ErrorAction Stop)
                if ($result.Count -ne 1 -or $null -eq $result[0].exit_code) {
                    throw "Read-only preflight '$Name' returned no valid CLI result."
                }
                $raw = @($result[0].lines)
                $exitCode = $result[0].exit_code
            } else {
                Stop-Job -Job $job
                $raw = @("Azure CLI read '$Name' timed out after 35 seconds.")
                $exitCode = 124
            }
        } finally {
            if ($job.State -eq 'Running') { Stop-Job -Job $job }
            Remove-Job -Job $job -Force
        }
        if ($exitCode -eq 0) { break }
        $failure = $raw -join "`n"
        $transient = $exitCode -eq 124 -or $failure -match '429|Too Many Requests|503|ConnectTimeout|ConnectionError|ConnectionReset|RemoteDisconnected|SSLError|temporarily unavailable'
        if (-not $transient -or $attempt -eq 1) { break }
        $evidence["$Name-retry"] = @{ failed_attempt = 1; failure = $failure; retry_delay_seconds = 5 }
        Write-Warning "Read-only preflight '$Name' hit a transient failure; retrying once after 5 seconds."
        Start-Sleep -Seconds 5
    }
    if ($exitCode -ne 0) {
        $failure = ($raw -join "`n")
        Add-Check $Name $false $failure
        Write-Warning "Read-only preflight '$Name' failed: $($raw | Select-Object -First 1). Full error is in the receipt."
        return @{ succeeded = $false; transient = $transient }
    }
    $data = $raw | ConvertFrom-Json -AsHashtable -Depth 60 -NoEnumerate -DateKind String
    if ($null -eq $data) { throw "Read-only preflight '$Name' returned no JSON." }
    $evidence[$Name] = $data
    return @{ succeeded = $true; data = $data }
}

$account = Read-Azure 'account' @('account', 'show')
if (-not $account.succeeded -or $account.data.id -ne $Settings.subscription_id -or
    $account.data.tenantId -ne $Settings.tenant_id) {
    throw "Authenticated subscription/tenant does not match; no further checks are permitted. Evidence: $runDirectory"
}
Add-Check 'target' $true @{ subscription_id = $account.data.id; tenant_id = $account.data.tenantId }

$costQueryPath = Join-Path $runDirectory 'cost-query.json'
@{
    type = 'ActualCost'; timeframe = 'MonthToDate'
    dataset = @{ granularity = 'Daily'; aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } } }
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $costQueryPath -Encoding utf8NoBOM
$costs = Read-Azure 'whole-subscription-costs' @('rest', '--method', 'post', '--url',
    "https://management.azure.com/subscriptions/$($Settings.subscription_id)/providers/Microsoft.CostManagement/query?api-version=2023-11-01",
    '--headers', 'Content-Type=application/json', 'ClientType=modular-workshop-preflight', '--body', "@$costQueryPath")
if ($costs.succeeded) {
    $columns = @($costs.data.properties.columns.name)
    $amountIndex = [array]::IndexOf($columns, 'PreTaxCost')
    $currencyIndex = [array]::IndexOf($columns, 'Currency')
    $valid = $amountIndex -ge 0 -and $currencyIndex -ge 0 -and
        $null -ne $costs.data.properties.rows -and -not $costs.data.properties.nextLink
    $total = [decimal]0
    if ($valid) {
        foreach ($row in $costs.data.properties.rows) {
            $amount = [decimal]0
            if ($row.Count -ne $columns.Count -or $row[$currencyIndex] -cne 'EUR' -or
                $null -eq $row[$amountIndex] -or -not [decimal]::TryParse(
                    [string]$row[$amountIndex], [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$amount)) {
                $valid = $false
                break
            }
            $total += $amount
        }
    }
    Add-Check 'costs/fresh-eur-snapshot' $valid @{
        actual_month_to_date_eur = if ($valid) { $total } else { $null }
        scope = 'whole subscription, including all earlier resources'
        note = 'Billing is delayed. This snapshot is not the price of the new deployment or a hard spending cap.'
    }
    if ($valid -and $Settings.protection.monthly_cap_eur -gt 0) {
        Add-Check 'costs/below-cap' ($total -lt $Settings.protection.monthly_cap_eur) @{
            actual_eur = $total; cap_eur = $Settings.protection.monthly_cap_eur
        }
    }
}
$cacheEnabled = $Review.workload.inputs.semantic_cache_enabled -eq $true
$providers = Read-Azure 'providers' @('provider', 'list',
    '--query', '[].{namespace:namespace,registrationState:registrationState}')
if ($providers.succeeded) {
    $requiredProviders = @('Microsoft.CognitiveServices', 'Microsoft.Search', 'Microsoft.Storage',
        'Microsoft.KeyVault', 'Microsoft.OperationalInsights', 'Microsoft.Insights',
        'Microsoft.ContainerRegistry', 'Microsoft.App', 'Microsoft.ApiManagement', 'Microsoft.ApiCenter',
        'Microsoft.Automation')
    if ($cacheEnabled) { $requiredProviders += 'Microsoft.Cache' }
    foreach ($namespace in $requiredProviders) {
        $match = @($providers.data | Where-Object namespace -EQ $namespace)
        Add-Check "provider/$namespace" ($match.Count -eq 1 -and $match[0].registrationState -eq 'Registered') $match
    }
}
if ($cacheEnabled) {
    $redis = Read-Azure 'redis-provider-metadata' @('provider', 'show', '--namespace', 'Microsoft.Cache')
    if ($redis.succeeded) {
        $types = @($redis.data.resourceTypes | Where-Object resourceType -EQ 'redisEnterprise')
        $regions = @($types | ForEach-Object { $_.locations } | ForEach-Object {
            ($_ -replace '[ -]', '').ToLowerInvariant()
        })
        Add-Check 'redis/advertised-region' ($Settings.location -in $regions) @{
            location = $Settings.location; sku = 'Balanced_B0'
            note = 'Provider-advertised service region only. Specific SKU allocation and live cache access still require deployment verification.'
        }
    }
}
$locations = Read-Azure 'locations' @('rest', '--method', 'get', '--url',
    "https://management.azure.com/subscriptions/$($Settings.subscription_id)/locations?api-version=2022-12-01",
    '--query', 'value[].{name:name,displayName:displayName}')
if ($locations.succeeded) {
    foreach ($key in @('location', 'search_location')) {
        Add-Check "region/$key" (@($locations.data | Where-Object name -EQ $Settings[$key]).Count -eq 1) $Settings[$key]
    }
}
$contentSafety = Read-Azure 'content-safety-skus' @('cognitiveservices', 'account', 'list-skus',
    '--kind', 'ContentSafety', '--location', $Settings.location)
if ($contentSafety.succeeded) {
    Add-Check 'content-safety/S0' (@($contentSafety.data | Where-Object { $_.name -eq 'S0' -or $_.sku.name -eq 'S0' }).Count -gt 0) $contentSafety.data
}

$models = Read-Azure 'model-catalog' @('cognitiveservices', 'model', 'list', '--location', $Settings.location)
$quota = Read-Azure 'regional-quota' @('rest', '--method', 'get', '--url',
    "https://management.azure.com/subscriptions/$($Settings.subscription_id)/providers/Microsoft.CognitiveServices/locations/$($Settings.location)/usages?api-version=2023-05-01")
$requested = @{}
if ($models.succeeded) {
    foreach ($alias in $Review.workload.models.Keys) {
        $model = $Review.workload.models[$alias]
        $matching = @($models.data | Where-Object {
            $_.kind -ceq 'AIServices' -and $_.skuName -ceq 'S0' -and
            $_.model.format -ceq 'OpenAI' -and $_.model.name -ceq $model.name -and $_.model.version -ceq $model.version
        })
        $sku = @($matching | ForEach-Object { $_.model.skus } | Where-Object {
            $_.name -ceq $model.sku -and $_.usageName -and
            -not $_.usageName.EndsWith('-finetune', [StringComparison]::Ordinal)
        })
        $usageNames = @($sku.usageName | Where-Object { $_ } | Sort-Object -Unique)
        $available = $matching.Count -gt 0 -and $sku.Count -gt 0 -and $usageNames.Count -eq 1
        Add-Check "model/$alias" $available @{ requested = $model; matching_skus = $sku }
        $lifecycleValid = $matching.Count -gt 0
        foreach ($candidate in $matching) {
            $retirement = [DateTimeOffset]::MinValue
            $lifecycleValid = $lifecycleValid -and
                $candidate.model.lifecycleStatus -ceq 'GenerallyAvailable' -and
                [DateTimeOffset]::TryParse($candidate.model.deprecation.inference, [ref]$retirement) -and
                $retirement -gt [DateTimeOffset]::UtcNow
        }
        Add-Check "model-lifecycle/$alias" $lifecycleValid @{
            status = @($matching | ForEach-Object { $_.model.lifecycleStatus })
            retirement = @($matching | ForEach-Object { $_.model.deprecation.inference })
            rule = 'GenerallyAvailable with a future inference retirement date; Legacy/unknown/deprecated/preview/retired rejected.'
        }
        if ($available) {
            $usageName = $usageNames[0]
            if (-not $requested.ContainsKey($usageName)) { $requested[$usageName] = 0 }
            $requested[$usageName] += $model.capacity
            foreach ($candidate in $sku) {
                $capacity = $candidate.capacity
                $valid = $model.capacity -gt 0 -and $model.capacity -eq [math]::Floor($model.capacity)
                if ($null -ne $capacity.minimum) { $valid = $valid -and $model.capacity -ge $capacity.minimum }
                if ($null -ne $capacity.maximum) { $valid = $valid -and $model.capacity -le $capacity.maximum }
                if ($null -ne $capacity.step) {
                    if ($capacity.step -le 0) { throw "Invalid Azure capacity step for '$alias'." }
                    $valid = $valid -and ($model.capacity % $capacity.step -eq 0)
                }
                Add-Check "capacity/$alias" $valid @{ requested_allocation_units = $model.capacity; metadata = $capacity }
            }
        }
    }
}
if ($quota.succeeded) {
    foreach ($usageName in $requested.Keys) {
        $usage = @($quota.data.value | Where-Object { $_.name.value -ceq $usageName })
        $valid = $usage.Count -eq 1 -and $null -ne $usage[0].limit -and $null -ne $usage[0].currentValue
        if ($valid) { $valid = $usage[0].limit - $usage[0].currentValue -ge $requested[$usageName] }
        Add-Check "quota/$usageName" $valid @{
            requested_allocation_units = $requested[$usageName]
            existing_subscription_region_usage = $usage
            note = 'These are deployment allocation units, not observed token processing or a claim that one unit equals one TPM.'
        }
    }
}

$permissions = Read-Azure 'operator-azure-permissions' @('rest', '--method', 'get', '--url',
    "https://management.azure.com/subscriptions/$($Settings.subscription_id)/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
if ($permissions.succeeded) {
    $requiredActions = @('Microsoft.Resources/subscriptions/resourceGroups/write',
        'Microsoft.Authorization/roleAssignments/write', 'Microsoft.Authorization/roleDefinitions/write',
        'Microsoft.CognitiveServices/accounts/write', 'Microsoft.App/managedEnvironments/write')
    if ($cacheEnabled) { $requiredActions += 'Microsoft.Cache/redisEnterprise/write' }
    foreach ($action in $requiredActions) {
        $allowed = @($permissions.data.value | Where-Object {
            $permission = $_
            @($permission.actions | Where-Object { $action -like $_ }).Count -gt 0 -and
            @($permission.notActions | Where-Object { $action -like $_ }).Count -eq 0
        }).Count -gt 0
        Add-Check "operator/$action" $allowed 'Effective subscription permission read; deny assignments, conditions and Azure Policy still require plan review.'
    }
}
$graph = Read-Azure 'graph-operator' @('rest', '--method', 'get', '--resource', 'https://graph.microsoft.com',
    '--url', 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName')
if ($graph.succeeded) {
    $roles = Read-Azure 'graph-directory-roles' @('rest', '--method', 'get', '--resource', 'https://graph.microsoft.com',
        '--url', 'https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=roleTemplateId,displayName')
    if ($roles.succeeded) {
        $adminTemplates = @('62e90394-69f5-4237-9190-012177145e10', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3',
            '158c047a-c907-4556-b7ef-446551a6b5f7')
        Add-Check 'operator/entra-application-admin' (
            -not $roles.data['@odata.nextLink'] -and
            @($roles.data.value | Where-Object { $_.roleTemplateId -in $adminTemplates }).Count -gt 0
        ) 'Requires an active supported directory application-administration role; equivalent custom-role authorization needs separate explicit verification.'
    }
}

$references = @()
if ($Settings.teams -is [System.Collections.IDictionary]) {
    $references = @($Settings.teams.Values | ForEach-Object { $_ } | ForEach-Object { "$_".Trim().ToLowerInvariant() })
}
Add-Check 'roster/complete' ($references.Count -gt 0 -and
    $references.Count -eq $Settings.expected_participant_count -and
    @($references | Sort-Object -Unique).Count -eq $references.Count) @{ supplied = $references.Count; expected = $Settings.expected_participant_count }
$librarians = @($Review.workload.inputs.librarians | Where-Object { $_ })
Add-Check 'librarians/selected' ($librarians.Count -gt 0) $librarians
$users = @{}
$canResolveUsers = $graph.succeeded -and $roles.succeeded
foreach ($reference in @(@($references) + @($librarians) | Sort-Object -Unique)) {
    if ($reference -match 'REPLACE_|\.example$' -or [string]::IsNullOrWhiteSpace($reference)) {
        Add-Check "user/$reference" $false 'Replace the placeholder with a real tenant UPN/object ID.'
        continue
    }
    if (-not $canResolveUsers) {
        Add-Check "user/$reference" $false 'Not queried because Graph connectivity prerequisites failed; no cached identity is substituted.'
        continue
    }
    $escaped = [uri]::EscapeDataString($reference)
    $user = Read-Azure "user/$reference" @('rest', '--method', 'get', '--resource', 'https://graph.microsoft.com',
        '--url', "https://graph.microsoft.com/v1.0/users/${escaped}?`$select=id,userPrincipalName,accountEnabled,userType,externalUserState")
    if ($user.succeeded) {
        $users[$reference] = $user.data.id
        Add-Check "user-enabled/$reference" ($user.data.id -and $user.data.accountEnabled -eq $true -and
            ($user.data.userType -ne 'Guest' -or $user.data.externalUserState -eq 'Accepted')) $user.data
    } elseif ($user.transient) {
        $canResolveUsers = $false
    }
}
$resolvedMembers = @($references | Where-Object { $users.ContainsKey($_) } | ForEach-Object { $users[$_] })
Add-Check 'roster/distinct-identities' ($resolvedMembers.Count -eq $references.Count -and
    @($resolvedMembers | Sort-Object -Unique).Count -eq $references.Count -and $references.Count -gt 0) $resolvedMembers

$failed = @($checks | Where-Object { -not $_.passed })
$report = @{
    operation = 'read-only-deployment-preflight'
    collected_at = [DateTimeOffset]::UtcNow.ToString('o')
    subscription_id = $Settings.subscription_id
    tenant_id = $Settings.tenant_id
    scenario = $Review.scenario
    location = $Settings.location
    search_location = $Settings.search_location
    technical_checks_passed = $failed.Count -eq 0
    deployment_ready = $false
    checks = $checks.ToArray()
    evidence = $evidence
    still_required = @('Exact Terraform/SKU/name and Azure Policy plan review',
        'New-deployment price/exposure review alongside the fresh whole-subscription cost snapshot',
        'Independent deployed cost/expiry protection and timer verification',
        'Joint approval before any apply',
        'Live runtime/Search checks and genuine Foundry evaluations/provenance')
}
$reportPath = Join-Path $runDirectory 'preflight.json'
$report | ConvertTo-Json -Depth 70 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
Write-Output "Read-only preflight: $($failed.Count) failed check(s). Deployment is NOT approved. Evidence: $reportPath"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Warning "Failed: $($_.name)" }
    throw "Read-only deployment prerequisites failed ($($failed.Count)); no resources or permissions were changed."
}
