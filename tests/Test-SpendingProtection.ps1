#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content -LiteralPath (Join-Path $root 'infra\scripts\Protect-Spending.ps1') -Raw
$constructor = '$client = [Net.Http.HttpClient]::new()'
if ([regex]::Matches($source, [regex]::Escape($constructor)).Count -ne 1) {
    throw 'The test must replace exactly one actual HttpClient construction.'
}

# This test-only handler cannot connect to Azure or any network. The production
# runbook has no injectable client, command doubles or credential fallback.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class TestOnlySpendingHandler : HttpMessageHandler {
    public static readonly Dictionary<string,string> Bodies = new Dictionary<string,string>();
    public static readonly Dictionary<string,int> Statuses = new Dictionary<string,int>();
    public static readonly Dictionary<string,string> RetryAfter = new Dictionary<string,string>();
    public static readonly List<string> Calls = new List<string>();
    public static readonly Dictionary<string,string> RequestBodies = new Dictionary<string,string>();
    public static string OfflineKey;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        string key = request.Method.Method + " " + request.RequestUri.AbsoluteUri;
        Calls.Add(key);
        if (request.Headers.Authorization == null || request.Headers.Authorization.ToString() != "Bearer test-only-token")
            throw new InvalidOperationException("Unexpected test authorization.");
        if (request.Content != null)
            RequestBodies[key] = request.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (key == OfflineKey)
            return Task.FromException<HttpResponseMessage>(new HttpRequestException("TEST ONLY: cost transport unavailable"));
        if (!Bodies.ContainsKey(key))
            throw new InvalidOperationException("No declared test response: " + key);
        var response = new HttpResponseMessage((HttpStatusCode)Statuses[key]);
        response.Content = new StringContent(Bodies[key]);
        if (RetryAfter.ContainsKey(key)) response.Headers.Add("Retry-After", RetryAfter[key]);
        return Task.FromResult(response);
    }
}
'@
$testRunbook = [scriptblock]::Create($source.Replace($constructor,
    '$client = [Net.Http.HttpClient]::new([TestOnlySpendingHandler]::new())'))
$previousEndpoint = $env:IDENTITY_ENDPOINT
$previousHeader = $env:IDENTITY_HEADER
$env:IDENTITY_ENDPOINT = 'http://test-only.invalid/identity'
$env:IDENTITY_HEADER = 'test-only-header'
$subscription = '00000000-0000-0000-0000-000000000001'
$principal = '00000000-0000-0000-0000-000000000002'
$subscriptionRoot = "/subscriptions/$subscription"
$baseUrl = 'https://management.azure.com'
$foundationGroup = "$subscriptionRoot/resourceGroups/rg-ai-lab-test01"
$runtimeGroup = "$subscriptionRoot/resourceGroups/rg-architecture-docs-test01"
$protectionGroup = "$subscriptionRoot/resourceGroups/rg-ai-lab-test01-protection"
$role = "$subscriptionRoot/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000003"
$costUrl = "$baseUrl$subscriptionRoot/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
$bindingUrl = "$baseUrl$subscriptionRoot/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=principalId%20eq%20'$principal'"
$guardTest = @{ config = $null }

function Assert-Protection([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-AutomationVariable {
    param([string]$Name)
    Assert-Protection ($Name -ceq 'SpendingProtection') 'Use only the declared Automation configuration.'
    $guardTest.config | ConvertTo-Json -Depth 20
}
function Invoke-RestMethod {
    param([string]$Uri, [hashtable]$Headers, [int]$TimeoutSec)
    Assert-Protection ($Uri -ceq "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01") 'Only the test-scoped Automation identity endpoint is permitted.'
    Assert-Protection ($Headers['X-IDENTITY-HEADER'] -ceq 'test-only-header') 'Do not use cached host credentials.'
    @{ access_token = 'test-only-token' }
}
function Set-TestResponse([string]$Method, [string]$Url, [object]$Body, [int]$Status = 200) {
    $key = "$Method $(([uri]$Url).AbsoluteUri)"
    [TestOnlySpendingHandler]::Statuses[$key] = $Status
    [TestOnlySpendingHandler]::Bodies[$key] = if ($null -eq $Body) { '' } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    return $key
}
function Initialize-TestCase([string]$Mode) {
    [TestOnlySpendingHandler]::Bodies.Clear()
    [TestOnlySpendingHandler]::Statuses.Clear()
    [TestOnlySpendingHandler]::RetryAfter.Clear()
    [TestOnlySpendingHandler]::Calls.Clear()
    [TestOnlySpendingHandler]::RequestBodies.Clear()
    [TestOnlySpendingHandler]::OfflineKey = $null
    $guardTest.config = @{
        subscription_id = $subscription
        principal_id = $principal
        tenant_id = '00000000-0000-0000-0000-000000000004'
        deployment = 'test01'
        cutoff_role_id = $role
        protection_group = $protectionGroup
        expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o')
        limits = @{ monthly_cap_eur = 130; reserve_eur = 30; max_hourly_eur = 1 }
    }
    $amount = if ($Mode -eq 'over-budget') { 100 } else { 1 }
    $currency = if ($Mode -eq 'wrong-currency') { 'USD' } else { 'EUR' }
    $cost = @{
        properties = @{
            columns = @(@{ name = 'PreTaxCost' }, @{ name = 'UsageDate' }, @{ name = 'Currency' })
            rows = ,@($amount, 20261029, $currency)
        }
    }
    if ($Mode -eq 'missing-costs') { $cost.properties.Remove('rows') }
    if ($Mode -eq 'partial-costs') { $cost.properties.nextLink = "$baseUrl$subscriptionRoot/unsafe-page" }
    if ($Mode -eq 'expiry') { $guardTest.config.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o') }
    $key = Set-TestResponse 'POST' $costUrl $cost
    if ($Mode -eq 'offline') { [TestOnlySpendingHandler]::OfflineKey = $key }
    if ($Mode -eq 'throttled') {
        [TestOnlySpendingHandler]::Statuses[$key] = 429
        [TestOnlySpendingHandler]::RetryAfter[$key] = '1000'
    }
    $bindings = @($foundationGroup, $runtimeGroup) | ForEach-Object {
        @{ properties = @{ principalId = $principal; roleDefinitionId = $role; scope = $_ } }
    }
    if ($Mode -eq 'unsafe-scope') { $bindings[0].properties.scope = $subscriptionRoot }
    $null = Set-TestResponse 'GET' $bindingUrl @{ value = @($bindings) }
    foreach ($groupId in @($foundationGroup, $runtimeGroup)) {
        $groupTags = @{ deployment = 'test01'; workload = 'ai-lab' }
        if ($Mode -eq 'wrong-tags' -and $groupId -ceq $foundationGroup) { $groupTags.deployment = 'other' }
        $null = Set-TestResponse 'GET' "$baseUrl$groupId`?api-version=2022-09-01" @{ tags = $groupTags }
        $null = Set-TestResponse 'GET' "$baseUrl$groupId/resources?api-version=2021-04-01" @{ value = @() }
        $null = Set-TestResponse 'DELETE' "$baseUrl$groupId`?api-version=2022-09-01" $null 202
    }
}
function Read-TestGuardResult([object[]]$Output) {
    $line = @($Output | Where-Object { "$_".StartsWith('SPENDING_PROTECTION ') })
    Assert-Protection ($line.Count -eq 1) 'The protector must emit exactly one explicit decision record.'
    $line[0].Substring('SPENDING_PROTECTION '.Length) | ConvertFrom-Json
}
try {
    Initialize-TestCase 'healthy'
    $result = Read-TestGuardResult @(& $testRunbook)
    Assert-Protection (-not $result.cutoff -and $result.costs.actual_eur -eq 1 -and $result.costs.buffered_eur -eq 55) 'Use actual costs plus the declared reserve/exposure buffer, never a placeholder amount.'
    Assert-Protection (@([TestOnlySpendingHandler]::Calls | Where-Object { $_ -match '^(DELETE|PATCH) ' }).Count -eq 0) 'Healthy operation must not mutate resources.'
    foreach ($mode in @('over-budget', 'expiry', 'missing-costs', 'partial-costs', 'wrong-currency', 'offline', 'throttled')) {
        Initialize-TestCase $mode
        $output = @(& $testRunbook -WarningAction SilentlyContinue)
        $result = Read-TestGuardResult $output
        Assert-Protection ($result.cutoff -and -not $result.deletion_verified) "Fail closed for '$mode', without claiming asynchronous deletion was verified."
        Assert-Protection (@([TestOnlySpendingHandler]::Calls | Where-Object { $_ -match '^DELETE ' }).Count -eq 2) 'Delete only the two actually enrolled disposable groups.'
        Assert-Protection (@([TestOnlySpendingHandler]::Calls | Where-Object { $_ -match '^DELETE ' -and $_ -like "*$protectionGroup*" }).Count -eq 0) 'Never delete the independent protection group.'
    }
    Initialize-TestCase 'over-budget'
    $output = @(& $testRunbook -DryRun)
    Assert-Protection (@($output | Where-Object { $_ -like 'WOULD_DELETE_GROUP *' }).Count -eq 2) 'DryRun must identify both actual enrolled targets.'
    Assert-Protection (@([TestOnlySpendingHandler]::Calls | Where-Object { $_ -match '^(DELETE|PATCH) ' }).Count -eq 0) 'DryRun must never mutate resources.'
    Initialize-TestCase 'over-budget'
    $accountId = "$foundationGroup/providers/Microsoft.CognitiveServices/accounts/test-only"
    $projectId = "$accountId/projects/alpha"
    $deploymentId = "$accountId/deployments/test-only"
    $null = Set-TestResponse 'GET' "$baseUrl$foundationGroup/resources?api-version=2021-04-01" @{
        value = @(@{ id = $accountId; type = 'Microsoft.CognitiveServices/accounts' })
    }
    $null = Set-TestResponse 'GET' "$baseUrl$accountId`?api-version=2025-06-01" @{
        kind = 'AIServices'
        properties = @{ associatedProjects = @(); provisioningState = 'Succeeded' }
    }
    $null = Set-TestResponse 'GET' "$baseUrl$accountId/deployments?api-version=2025-06-01" @{ value = @(@{ id = $deploymentId }) }
    $null = Set-TestResponse 'DELETE' "$baseUrl$deploymentId`?api-version=2025-06-01" $null 202
    $null = Set-TestResponse 'GET' "$baseUrl$accountId/projects?api-version=2025-06-01" @{ value = @(@{ id = $projectId }) }
    $null = Set-TestResponse 'DELETE' "$baseUrl$projectId`?api-version=2025-06-01" $null 202
    $null = Set-TestResponse 'GET' "$baseUrl$projectId`?api-version=2025-06-01" $null 404
    $null = Set-TestResponse 'PATCH' "$baseUrl$accountId`?api-version=2025-06-01" @{ properties = @{ associatedProjects = @() } }
    & $testRunbook | Out-Null
    $calls = @([TestOnlySpendingHandler]::Calls)
    $projectDelete = [array]::IndexOf($calls, "DELETE $(([uri]("$baseUrl$projectId`?api-version=2025-06-01")).AbsoluteUri)")
    $groupDelete = [array]::IndexOf($calls, "DELETE $(([uri]("$baseUrl$foundationGroup`?api-version=2022-09-01")).AbsoluteUri)")
    Assert-Protection ($projectDelete -ge 0 -and $groupDelete -gt $projectDelete) 'Stop deployments and remove/verify Foundry projects before requesting parent-group deletion.'
    $patch = [TestOnlySpendingHandler]::RequestBodies["PATCH $(([uri]("$baseUrl$accountId`?api-version=2025-06-01")).AbsoluteUri)"] |
        ConvertFrom-Json
    Assert-Protection (@($patch.properties.associatedProjects).Count -eq 0) 'Explicitly clear parent project associations.'
    $patchIndex = [array]::IndexOf($calls, "PATCH $(([uri]("$baseUrl$accountId`?api-version=2025-06-01")).AbsoluteUri)")
    $accountRead = "GET $(([uri]("$baseUrl$accountId`?api-version=2025-06-01")).AbsoluteUri)"
    Assert-Protection ($patchIndex -gt $projectDelete -and $calls[$patchIndex + 1] -ceq $accountRead -and
        $groupDelete -gt ($patchIndex + 1)) 'Verify completed association cleanup before deleting the group.'
    [TestOnlySpendingHandler]::Calls.Clear()
    $null = Set-TestResponse 'GET' "$baseUrl$accountId`?api-version=2025-06-01" @{
        kind = 'AIServices'
        properties = @{ associatedProjects = @('unremoved'); provisioningState = 'Failed' }
    }
    $rejected = $false
    try {
        & $testRunbook 2>$null | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'Spending cutoff incomplete:.*Foundry association cleanup was not verified') { throw }
        $rejected = $true
    }
    Assert-Protection $rejected 'Failed association cleanup must report incomplete cutoff.'
    Assert-Protection (-not [TestOnlySpendingHandler]::Calls.Contains(
        "DELETE $(([uri]("$baseUrl$foundationGroup`?api-version=2022-09-01")).AbsoluteUri)")) 'Do not claim parent cleanup before association deletion is verified.'
    foreach ($mode in @('unsafe-scope', 'wrong-tags')) {
        Initialize-TestCase $mode
        $rejected = $false
        try {
            & $testRunbook | Out-Null
        } catch {
            if ($_.Exception.Message -notmatch 'resource-group boundary|group tags') { throw }
            $rejected = $true
        }
        Assert-Protection $rejected "Reject '$mode' explicitly."
        Assert-Protection (@([TestOnlySpendingHandler]::Calls | Where-Object { $_ -match '^(DELETE|PATCH) ' }).Count -eq 0) 'Reject invalid enrollment before any destructive operation.'
    }
    Write-Output 'Spending protector contracts passed using a test-only HTTP handler. No real resource deletion, cloud timer or budget protection was verified.'
} finally {
    $env:IDENTITY_ENDPOINT = $previousEndpoint
    $env:IDENTITY_HEADER = $previousHeader
}
