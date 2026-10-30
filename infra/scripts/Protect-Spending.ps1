param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$config = Get-AutomationVariable -Name 'SpendingProtection' | ConvertFrom-Json
$subscription = [guid]$config.subscription_id
$principal = [guid]$config.principal_id
$expires = [DateTimeOffset]$config.expires_at
$scope = "/subscriptions/$subscription"
$root = 'https://management.azure.com'
if ($subscription -eq [guid]::Empty -or $principal -eq [guid]::Empty -or
    $config.deployment -cnotmatch '^[a-z0-9]{4,10}$' -or
    $config.cutoff_role_id -notmatch "^$scope/providers/Microsoft.Authorization/roleDefinitions/[0-9a-f-]{36}$" -or
    $config.protection_group -cne "$scope/resourceGroups/rg-ai-lab-$($config.deployment)-protection" -or
    $config.limits.monthly_cap_eur -le 0 -or $config.limits.reserve_eur -le 0 -or
    $config.limits.reserve_eur -ge $config.limits.monthly_cap_eur -or $config.limits.max_hourly_eur -le 0) {
    throw 'Invalid spending-protection configuration.'
}
if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) {
    throw 'Spending protection requires its Azure Automation managed identity; no local credential fallback exists.'
}
$token = Invoke-RestMethod -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01" -Headers @{
    'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
    Metadata = 'true'
} -TimeoutSec 30
if ([string]::IsNullOrWhiteSpace($token.access_token)) { throw 'Automation did not return a managed-identity token.' }
Add-Type -AssemblyName System.Net.Http
$client = [Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(60)
$client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token.access_token)
$client.DefaultRequestHeaders.Add('ClientType', 'modular-workshop-spending-protection')

function Invoke-ProtectionRequest([string]$Method, [string]$Uri, [object]$Body) {
    $target = [uri]$Uri
    if ($target.Scheme -cne 'https' -or $target.Host -cne 'management.azure.com' -or
        $target.UserInfo -or -not $target.IsDefaultPort -or
        -not $target.AbsolutePath.StartsWith("$scope/", [StringComparison]::OrdinalIgnoreCase)) {
        throw [Security.SecurityException] 'Protection request outside the explicitly configured subscription.'
    }
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        if ($null -ne $Body) {
            $request.Content = [Net.Http.StringContent]::new(
                ($Body | ConvertTo-Json -Depth 20 -Compress), [Text.Encoding]::UTF8, 'application/json')
        }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $retry = @{}
            foreach ($header in $response.Headers) { $retry[$header.Key] = @($header.Value) }
            return @{
                status = [int]$response.StatusCode
                text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                headers = $retry
            }
        } finally { $response.Dispose() }
    } finally { $request.Dispose() }
}
function Read-ProtectionJson([object]$Response) {
    if ($Response.status -lt 200 -or $Response.status -ge 300 -or
        [string]::IsNullOrWhiteSpace($Response.text)) {
        throw [FormatException] "Protection API returned HTTP $($Response.status), without a successful JSON body."
    }
    return ($Response.text | ConvertFrom-Json)
}
function Get-ProtectionCollection([string]$Uri) {
    $path = ([uri]$Uri).AbsolutePath
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($Uri) {
        if (([uri]$Uri).AbsolutePath -ine $path -or -not $seen.Add($Uri) -or $seen.Count -gt 100) {
            throw [Security.SecurityException] 'Invalid protection pagination boundary or cycle.'
        }
        $page = Read-ProtectionJson (Invoke-ProtectionRequest 'GET' $Uri)
        if ($null -eq $page.value) { throw [FormatException] 'Incomplete protection collection.' }
        $page.value
        $Uri = [string]$page.nextLink
    }
}
function Get-FreshSubscriptionCosts {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(180)
    $body = @{
        type = 'ActualCost'; timeframe = 'MonthToDate'
        dataset = @{ granularity = 'Daily'; aggregation = @{ totalCost = @{ name = 'PreTaxCost'; function = 'Sum' } } }
    }
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        if ([DateTimeOffset]::UtcNow -ge $deadline -or [DateTimeOffset]::UtcNow -ge $expires) {
            throw [TimeoutException] 'Cost visibility or authorization window exhausted.'
        }
        $response = Invoke-ProtectionRequest 'POST' "$root$scope/providers/Microsoft.CostManagement/query?api-version=2023-11-01" $body
        if ($response.status -notin @(429, 503)) { break }
        if ($attempt -eq 3) { throw [TimeoutException] 'Cost visibility remained throttled or unavailable.' }
        $delay = 15 * [Math]::Pow(2, $attempt)
        foreach ($name in $response.headers.Keys) {
            if ($name -notmatch '^(Retry-After|x-ms-ratelimit-microsoft\.costmanagement-.+-retry-after)$') { continue }
            foreach ($value in $response.headers[$name]) {
                $seconds = 0
                if (-not [int]::TryParse($value, [ref]$seconds) -or $seconds -lt 0) {
                    $at = [DateTimeOffset]::MinValue
                    if ($name -ne 'Retry-After' -or -not [DateTimeOffset]::TryParse($value, [ref]$at)) {
                        throw [FormatException] 'Invalid Cost Management retry metadata.'
                    }
                    $seconds = [int][Math]::Ceiling(($at - [DateTimeOffset]::UtcNow).TotalSeconds)
                }
                $delay = [Math]::Max($delay, $seconds)
            }
        }
        if ([DateTimeOffset]::UtcNow.AddSeconds($delay) -ge $deadline -or
            [DateTimeOffset]::UtcNow.AddSeconds($delay) -ge $expires) {
            throw [TimeoutException] 'Cost retry exceeds the visibility or authorization window.'
        }
        Write-Warning "Cost visibility HTTP $($response.status); retrying in $delay seconds. No cached costs are used."
        Start-Sleep -Seconds $delay
    }
    $cost = Read-ProtectionJson $response
    if ($cost.properties.nextLink) { throw [FormatException] 'Cost response is paginated; a partial cost total is not accepted.' }
    $columns = @($cost.properties.columns | ForEach-Object { $_.name })
    $amountIndex = [array]::IndexOf($columns, 'PreTaxCost')
    $currencyIndex = [array]::IndexOf($columns, 'Currency')
    $dateIndex = [array]::IndexOf($columns, 'UsageDate')
    if ($amountIndex -lt 0 -or $currencyIndex -lt 0 -or $dateIndex -lt 0 -or $null -eq $cost.properties.rows) {
        throw [FormatException] 'Incomplete cost response; no zero-cost fallback is permitted.'
    }
    $total = [decimal]0
    $daily = @{}
    foreach ($row in $cost.properties.rows) {
        if ($row.Count -ne $columns.Count -or $row[$currencyIndex] -cne 'EUR') {
            throw [FormatException] 'Invalid cost row or non-EUR billing currency.'
        }
        $amount = [decimal]0
        if ($null -eq $row[$amountIndex] -or -not [decimal]::TryParse(
            [string]$row[$amountIndex], [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$amount)) {
            throw [FormatException] 'Invalid cost amount.'
        }
        $day = [string]$row[$dateIndex]
        if ($day -notmatch '^\d{8}$') { throw [FormatException] 'Invalid usage date.' }
        $total += $amount
        if (-not $daily.ContainsKey($day)) { $daily[$day] = [decimal]0 }
        $daily[$day] += $amount
    }
    $maxDay = [decimal]0
    foreach ($amount in $daily.Values) { $maxDay = [Math]::Max($maxDay, $amount) }
    $buffered = $total + [Math]::Max([decimal]$config.limits.reserve_eur, 3 * $maxDay) +
        24 * [decimal]$config.limits.max_hourly_eur
    return @{ actual_eur = $total; buffered_eur = $buffered; queried_at = [DateTimeOffset]::UtcNow.ToString('o') }
}
function Remove-ProtectedFoundryProjects([string]$AccountId) {
    foreach ($deployment in @(Get-ProtectionCollection "$root$AccountId/deployments?api-version=2025-06-01")) {
        if ($deployment.id -notmatch "^$([regex]::Escape($AccountId))/deployments/[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$") {
            throw [Security.SecurityException] 'Deployment outside the protected account.'
        }
        $deleted = Invoke-ProtectionRequest 'DELETE' "$root$($deployment.id)?api-version=2025-06-01"
        if ($deleted.status -notin @(200, 202, 204, 404)) { throw "Model cutoff failed: HTTP $($deleted.status)." }
    }
    foreach ($project in @(Get-ProtectionCollection "$root$AccountId/projects?api-version=2025-06-01")) {
        if ($project.id -notmatch "^$([regex]::Escape($AccountId))/projects/[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$") {
            throw [Security.SecurityException] 'Project outside the protected account.'
        }
        $uri = "$root$($project.id)?api-version=2025-06-01"
        $deleted = Invoke-ProtectionRequest 'DELETE' $uri
        if ($deleted.status -notin @(200, 202, 204, 404)) { throw "Project cutoff failed: HTTP $($deleted.status)." }
        $deadline = [DateTimeOffset]::UtcNow.AddMinutes(3)
        do {
            $remaining = Invoke-ProtectionRequest 'GET' $uri
            if ($remaining.status -eq 404) { break }
            if ($remaining.status -ne 200 -or [DateTimeOffset]::UtcNow -ge $deadline) {
                throw 'Project deletion was not verified.'
            }
            Start-Sleep -Seconds 5
        } while ($true)
    }
    $updated = Invoke-ProtectionRequest 'PATCH' "$root$AccountId`?api-version=2025-06-01" @{
        properties = @{ associatedProjects = @() }
    }
    if ($updated.status -notin @(200, 202)) { throw "Foundry association cleanup failed: HTTP $($updated.status)." }
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(3)
    do {
        $account = Read-ProtectionJson (Invoke-ProtectionRequest 'GET' "$root$AccountId`?api-version=2025-06-01")
        if ($null -ne $account.properties -and
            @($account.properties.associatedProjects).Count -eq 0 -and
            $account.properties.provisioningState -eq 'Succeeded') {
            break
        }
        if ($account.properties.provisioningState -in @('Failed', 'Canceled') -or
            [DateTimeOffset]::UtcNow -ge $deadline) {
            throw 'Foundry association cleanup was not verified.'
        }
        Start-Sleep -Seconds 5
    } while ($true)
}

try {
    $costs = $null
    $cutoff = [DateTimeOffset]::UtcNow -ge $expires
    $reason = 'Spending authorization expired.'
    if (-not $cutoff) {
        try {
            $costs = Get-FreshSubscriptionCosts
            $cutoff = $costs.buffered_eur -ge $config.limits.monthly_cap_eur
            $reason = "Fresh whole-subscription costs plus lag/exposure buffer; cap EUR $($config.limits.monthly_cap_eur)."
        } catch [Net.Http.HttpRequestException], [Threading.Tasks.TaskCanceledException], [FormatException], [ArgumentException], [TimeoutException] {
            $cutoff = $true
            $reason = "Cost visibility failed; protection fails closed: $($_.Exception.Message)"
            Write-Warning $reason
        }
    }
    $bindings = @(Get-ProtectionCollection "$root$scope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=principalId%20eq%20'$principal'")
    $groups = @($bindings | Where-Object {
        $_.properties.principalId -eq $principal -and $_.properties.roleDefinitionId -ieq $config.cutoff_role_id
    } | ForEach-Object { $_.properties.scope } | Sort-Object -Unique)
    $activeGroups = [Collections.Generic.List[string]]::new()
    foreach ($groupId in $groups) {
        if ($groupId -notmatch "^$scope/resourceGroups/[a-zA-Z0-9._()-]{1,90}$" -or
            $groupId -ieq $config.protection_group) {
            throw [Security.SecurityException] 'Cutoff binding outside an eligible resource-group boundary.'
        }
        $groupResponse = Invoke-ProtectionRequest 'GET' "$root$groupId`?api-version=2022-09-01"
        if ($groupResponse.status -eq 404) { continue }
        $group = Read-ProtectionJson $groupResponse
        if ($group.tags.deployment -cne $config.deployment -or $group.tags.workload -cne 'ai-lab' -or
            $group.tags.purpose -eq 'spending-protection') {
            throw [Security.SecurityException] 'Enrolled group tags do not match this disposable deployment.'
        }
        $activeGroups.Add($groupId)
    }
    if ([DateTimeOffset]::UtcNow -ge $expires) {
        $cutoff = $true
        $reason = 'Spending authorization expired.'
    }
    Write-Output ('SPENDING_PROTECTION ' + (@{
        checked_at = [DateTimeOffset]::UtcNow.ToString('o')
        cutoff = $cutoff; reason = $reason; costs = $costs
        dry_run = [bool]$DryRun; enrolled_groups = $groups; active_groups = $activeGroups.ToArray()
        deletion_verified = $false
    } | ConvertTo-Json -Depth 10 -Compress))
    if (-not $cutoff) { return }
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($groupId in $activeGroups) {
        if ($DryRun) { Write-Output "WOULD_DELETE_GROUP $groupId"; continue }
        try {
            $resources = @(Get-ProtectionCollection "$root$groupId/resources?api-version=2021-04-01")
            foreach ($account in @($resources | Where-Object type -EQ 'Microsoft.CognitiveServices/accounts')) {
                if ($account.id -notmatch "^$([regex]::Escape($groupId))/providers/Microsoft.CognitiveServices/accounts/[a-zA-Z0-9][a-zA-Z0-9-]{0,63}$") {
                    throw [Security.SecurityException] 'Account outside the enrolled group.'
                }
                $details = Read-ProtectionJson (Invoke-ProtectionRequest 'GET' "$root$($account.id)?api-version=2025-06-01")
                if ($details.kind -eq 'AIServices') { Remove-ProtectedFoundryProjects $account.id }
            }
            $deleted = Invoke-ProtectionRequest 'DELETE' "$root$groupId`?api-version=2022-09-01"
            if ($deleted.status -notin @(200, 202, 204, 404)) { throw "Group cutoff failed: HTTP $($deleted.status)." }
            Write-Output "GROUP_DELETE_REQUESTED $groupId HTTP $($deleted.status); asynchronous deletion is not yet verified."
        } catch [Net.Http.HttpRequestException], [Threading.Tasks.TaskCanceledException], [FormatException], [Security.SecurityException], [System.Management.Automation.RuntimeException] {
            $failures.Add("$groupId : $($_.Exception.Message)")
            Write-Error $failures[$failures.Count - 1] -ErrorAction Continue
        }
    }
    if ($failures.Count -gt 0) { throw "Spending cutoff incomplete: $($failures -join '; ')" }
} finally {
    $client.Dispose()
}
