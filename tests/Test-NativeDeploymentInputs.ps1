#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$entry = Join-Path $root 'infra\scripts\New-NativeDeploymentInputs.ps1'
$scratch = Join-Path $root "out\native-deployment-input-tests-$([guid]::NewGuid().ToString('N'))"
$previousExitCode = $global:LASTEXITCODE

# These GUIDs/contact are synthetic fixtures, never real subscription, tenant or people data.
$fixture = @{
    account = @{
        id = '00000000-0000-0000-0000-000000000001'
        tenantId = '00000000-0000-0000-0000-000000000002'
    }
    calls = 0
    fail = $false
    raw = $null
}
function az {
    $fixture.calls++
    if (($args -join ' ') -cne "account show --subscription $($fixture.requested) -o json") {
        throw "Unexpected Azure command in offline test: $args"
    }
    $global:LASTEXITCODE = if ($fixture.fail) { 1 } else { 0 }
    if ($null -ne $fixture.raw) { return $fixture.raw }
    $fixture.account | ConvertTo-Json -Compress
}
function terraform { throw 'Input generation must never invoke Terraform.' }
function Assert-Inputs([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-Inputs([string]$Directory, [string]$Stage) {
    Get-Content -LiteralPath (Join-Path $Directory "native-$Stage.tfvars.json") -Raw |
        ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
}
function Write-People($People) {
    $People | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $peoplePath -Encoding utf8NoBOM
}
function New-TestPeople {
    @{
        publisher_email = 'operator@unit-fixture.dev'
        librarians = @('00000000-0000-0000-0000-000000000020')
        teams = @{
            alpha = @('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000016')
            beta = @('00000000-0000-0000-0000-000000000012')
            gamma = @('00000000-0000-0000-0000-000000000013')
            delta = @('00000000-0000-0000-0000-000000000014')
            epsilon = @('00000000-0000-0000-0000-000000000015')
        }
    }
}
function Invoke-Generator([string]$Directory, [hashtable]$Extra = @{}) {
    $fixture.requested = if ($Extra.ContainsKey('SubscriptionId')) {
        $Extra.SubscriptionId
    } else { '00000000-0000-0000-0000-000000000001' }
    $parameters = @{
        SubscriptionId = $fixture.requested
        PeopleFile = $peoplePath
        OutputDirectory = $Directory
    }
    foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
    & $entry @parameters | Out-Null
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $rejected = $false
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $rejected = $true
    }
    Assert-Inputs $rejected "Expected rejection matching '$Pattern'."
}
function Assert-NoOutput([string]$Directory) {
    Assert-Inputs (-not (Test-Path -LiteralPath $Directory)) 'Rejected generation must not create output.'
}

New-Item -ItemType Directory -Path $scratch | Out-Null
$peoplePath = Join-Path $scratch 'people.json'
try {
    $example = Get-Content -LiteralPath (Join-Path $root 'infra\people.example.json') -Raw |
        ConvertFrom-Json -AsHashtable
    Assert-Inputs (($example.Keys | Sort-Object) -join ',' -ceq 'librarians,publisher_email,teams') 'People template must contain only private people fields.'
    Assert-Inputs ($example.publisher_email -ceq '' -and $example.librarians.Count -eq 0) 'Never invent a publisher contact or librarian.'
    Assert-Inputs (($example.teams.Keys | Sort-Object) -join ',' -ceq 'alpha,beta,delta,epsilon,gamma') 'Expected exactly five generic teams.'
    foreach ($team in $example.teams.Keys) {
        Assert-Inputs ($example.teams[$team] -is [array] -and $example.teams[$team].Count -eq 0) 'Never put invented people in the template.'
    }
    $shared = Get-Content -LiteralPath (Join-Path $root 'infra\deployment.example.json') -Raw |
        ConvertFrom-Json -AsHashtable
    Assert-Inputs ($shared.subscription_id -ceq 'REPLACE_WITH_TARGET_SUBSCRIPTION_GUID' -and
        $shared.tenant_id -ceq 'REPLACE_WITH_TARGET_TENANT_GUID' -and
        $shared.publisher_email -ceq 'REPLACE_WITH_MONITORED_EMAIL' -and
        $shared.teams.epsilon.Count -eq 0) 'Keep explicit example target/people placeholders, adding no epsilon people.'

    Write-People (New-TestPeople)
    $full = Join-Path $scratch 'full'
    New-Item -ItemType Directory -Path $full | Out-Null
    $privateCopy = Join-Path $full 'people.private.json'
    Copy-Item -LiteralPath $peoplePath -Destination $privateCopy
    $peopleHash = (Get-FileHash -LiteralPath $privateCopy).Hash
    Invoke-Generator $full @{ Suffix = 'lab123'; PeopleFile = $privateCopy }
    Assert-Inputs ($fixture.calls -eq 1) 'Exactly one cached read-only account query is allowed.'
    Assert-Inputs ((Get-FileHash -LiteralPath $privateCopy).Hash -ceq $peopleHash) 'Accept an existing output directory containing the private people file without changing it.'
    $foundation = Read-Inputs $full 'foundation'
    $access = Read-Inputs $full 'access'
    $workload = Read-Inputs $full 'workload'
    Assert-Inputs ($foundation.subscription_id -ceq $fixture.account.id -and
        $foundation.tenant_id -ceq $fixture.account.tenantId -and
        $foundation.suffix -ceq 'lab123') 'Target must come from explicit subscription and its verified account tenant.'
    Assert-Inputs ($foundation.location -ceq 'francecentral' -and
        $foundation.search_location -ceq 'francecentral' -and $foundation.profile -ceq 'lite' -and
        $foundation.enable_search) 'Preserve the tested France Central lite foundation.'
    Assert-Inputs (($foundation.team_names | Sort-Object) -join ',' -ceq 'alpha,beta,delta,epsilon,gamma') 'Generate all five team projects.'
    foreach ($key in $shared.search_configuration.Keys) {
        Assert-Inputs ($foundation.search_configuration[$key] -ceq $shared.search_configuration[$key]) "Search setting lost: $key."
    }
    Assert-Inputs ($access.expected_participant_count -eq 6 -and $access.teams.Count -eq 5) 'Derive participant count from private roster, not the example count.'
    Assert-Inputs ($workload.organization_name -ceq 'Contoso' -and
        $workload.reference_date -ceq '2026-11-01' -and $workload.embedding_dimensions -eq 3072 -and
        $workload.semantic_cache_enabled -and $workload.mcp_protocol_diagnostics_enabled -and
        $workload.gateway_tokens_per_minute -eq 100000 -and $workload.gateway_requests_per_minute -eq 60 -and
        $workload.gateway_tool_requests_per_minute -eq 300) 'Preserve every tested shared workload default.'
    $expectedModels = @{
        'chat-small' = @('gpt-5.4-nano', '2026-03-17', 300)
        'chat-medium' = @('gpt-5.4-mini', '2026-03-17', 300)
        judge = @('gpt-5.4', '2026-03-05', 75)
        embedding = @('text-embedding-3-large', '1', 20)
    }
    foreach ($alias in $expectedModels.Keys) {
        $model = $workload.models[$alias]
        $expected = $expectedModels[$alias]
        Assert-Inputs ($model.name -ceq $expected[0] -and $model.version -ceq $expected[1] -and
            $model.capacity -eq $expected[2] -and $model.sku -ceq 'GlobalStandard') "Incorrect actual model map: $alias."
    }
    Assert-Inputs ($workload.librarians.Count -eq 1 -and $workload.librarians[0] -ceq
        '00000000-0000-0000-0000-000000000020') 'Use only explicitly selected human publisher identities.'
    foreach ($inputs in @($foundation, $access, $workload)) {
        foreach ($omitted in @('foundation', 'participant_members', 'runtime_images')) {
            Assert-Inputs (-not $inputs.ContainsKey($omitted)) "Do not invent applied outputs/artifacts: $omitted."
        }
    }
    $fullSnapshot = @(Get-ChildItem -LiteralPath $full | Get-FileHash).Hash -join ','
    Assert-Rejected { Invoke-Generator $full } 'Refusing existing access/workload'
    Assert-Inputs ($fullSnapshot -ceq (@(Get-ChildItem -LiteralPath $full | Get-FileHash).Hash -join ',')) 'Never overwrite existing native inputs.'

    $subsetPeople = New-TestPeople
    $subsetPeople.teams = @{ alpha = $subsetPeople.teams.alpha }
    $subsetPeople.librarians = @($subsetPeople.teams.alpha[0])
    Write-People $subsetPeople
    $subset = Join-Path $scratch 'alpha-only'
    Invoke-Generator $subset
    $subsetFoundation = Read-Inputs $subset 'foundation'
    $subsetAccess = Read-Inputs $subset 'access'
    $subsetWorkload = Read-Inputs $subset 'workload'
    Assert-Inputs (($subsetFoundation.team_names | Sort-Object) -join ',' -ceq 'alpha,beta,delta,epsilon,gamma') 'An active roster subset must retain all five canonical foundation projects.'
    Assert-Inputs ($subsetAccess.teams.Count -eq 1 -and $subsetAccess.teams.ContainsKey('alpha') -and
        $subsetAccess.teams.alpha.Count -eq 2 -and $subsetAccess.expected_participant_count -eq 2) 'Accept the approved alpha-only two-person roster and derive count two.'
    Assert-Inputs ($subsetWorkload.librarians.Count -eq 1 -and
        $subsetWorkload.librarians[0] -ceq $subsetAccess.teams.alpha[0]) 'An explicitly selected librarian may also be a participant.'

    $staged = Join-Path $scratch 'foundation-first'
    Write-People @{ publisher_email = 'operator@unit-fixture.dev' }
    Invoke-Generator $staged @{ FoundationOnly = $true }
    $first = Read-Inputs $staged 'foundation'
    Assert-Inputs ($first.suffix -cmatch '^[a-z0-9]{4,10}$' -and $first.suffix -cne $shared.suffix) 'Generate a fresh suffix once, not the example suffix.'
    Assert-Inputs (@(Get-ChildItem -LiteralPath $staged).Count -eq 1) 'FoundationOnly must not require or generate a roster.'
    $firstHash = (Get-FileHash -LiteralPath (Join-Path $staged 'native-foundation.tfvars.json')).Hash
    Invoke-Generator $staged @{ FoundationOnly = $true }
    Write-People (New-TestPeople)
    Assert-Rejected { Invoke-Generator $staged @{ Suffix = 'other123' } } 'different suffix'
    Assert-Rejected { Invoke-Generator $staged @{ SubscriptionId = '00000000-0000-0000-0000-000000000099' } } 'different subscription'
    $fixture.account.id = '00000000-0000-0000-0000-000000000099'
    Assert-Rejected { Invoke-Generator $staged @{ SubscriptionId = $fixture.account.id } } 'foundation input/target differs'
    $fixture.account.id = '00000000-0000-0000-0000-000000000001'
    $fixture.account.tenantId = '00000000-0000-0000-0000-000000000098'
    Assert-Rejected { Invoke-Generator $staged } 'foundation input/target differs'
    $fixture.account.tenantId = '00000000-0000-0000-0000-000000000002'
    $changed = New-TestPeople
    $changed.publisher_email = 'different@unit-fixture.dev'
    Write-People $changed
    Assert-Rejected { Invoke-Generator $staged } 'foundation input/target differs'
    Assert-Inputs (@(Get-ChildItem -LiteralPath $staged).Count -eq 1 -and
        (Get-FileHash -LiteralPath (Join-Path $staged 'native-foundation.tfvars.json')).Hash -ceq $firstHash) 'Every staged rejection must preserve foundation byte-for-byte, with no appended files.'
    Write-People (New-TestPeople)
    Invoke-Generator $staged
    Assert-Inputs ((Read-Inputs $staged 'foundation').suffix -ceq $first.suffix -and
        (Get-FileHash -LiteralPath (Join-Path $staged 'native-foundation.tfvars.json')).Hash -ceq $firstHash -and
        @(Get-ChildItem -LiteralPath $staged).Count -eq 3) 'Full mode must append only access/workload, reusing unchanged target/suffix.'

    $rejectedOutput = Join-Path $scratch 'rejected'
    foreach ($invalid in @('', 'not-a-guid', '00000000-0000-0000-0000-000000000000')) {
        Assert-Rejected { Invoke-Generator $rejectedOutput @{ SubscriptionId = $invalid } } 'explicit nonempty subscription GUID'
    }
    foreach ($invalid in @('', 'ABC123', 'abc', 'abcdefghijk', 'a-bc')) {
        Assert-Rejected { Invoke-Generator $rejectedOutput @{ Suffix = $invalid } } 'Suffix must contain'
    }
    foreach ($invalid in @('', 'operator@tenant.example', 'operator@example.com', 'operator@unit.invalid',
        'operator@contoso.com', 'REPLACE_WITH_MONITORED_EMAIL', 'not-an-email', ' operator@unit-fixture.dev')) {
        Write-People @{ publisher_email = $invalid }
        Assert-Rejected { Invoke-Generator $rejectedOutput @{ FoundationOnly = $true } } 'actual monitored publisher_email'
    }
    $mutations = @(
        { param($p) $p.teams = @{} },
        { param($p) $p.teams.extra = @('00000000-0000-0000-0000-000000000030') },
        { param($p) $p.teams = @{ Alpha = $p.teams.alpha } },
        { param($p) $p.teams.epsilon = @() },
        { param($p) $p.teams.epsilon = '00000000-0000-0000-0000-000000000015' },
        { param($p) $p.teams.epsilon = @('') },
        { param($p) $p.teams.epsilon = @('participant@tenant.example') },
        { param($p) $p.teams.epsilon = @('00000000-0000-0000-0000-000000000000') },
        { param($p) $p.teams.epsilon = @($p.teams.alpha[0]) },
        { param($p) $p.teams.alpha = @('Person@unit-fixture.dev', 'person@unit-fixture.dev') },
        { param($p) $p.librarians = @() },
        { param($p) $p.librarians = @('publisher@contoso.com') },
        { param($p) $p.librarians = @($p.librarians[0], $p.librarians[0]) },
        { param($p) $p.unexpected = 'no optional configuration' }
    )
    foreach ($mutate in $mutations) {
        $invalid = New-TestPeople
        & $mutate $invalid | Out-Null
        Write-People $invalid
        Assert-Rejected { Invoke-Generator $rejectedOutput } 'teams must be a nonempty subset|nonempty JSON array|placeholder or malformed|repeated identity|containing only'
        Assert-NoOutput $rejectedOutput
    }
    Set-Content -LiteralPath $peoplePath -Value '{malformed'
    Assert-Rejected { Invoke-Generator $rejectedOutput } 'JSON'
    Write-People (New-TestPeople)
    $fixture.account.tenantId = 'malformed'
    Assert-Rejected { Invoke-Generator $rejectedOutput } 'malformed subscription/tenant GUID'
    $fixture.account.tenantId = '00000000-0000-0000-0000-000000000002'
    $fixture.fail = $true
    Assert-Rejected { Invoke-Generator $rejectedOutput } 'could not read'
    $fixture.fail = $false
    $fixture.raw = '{malformed'
    Assert-Rejected { Invoke-Generator $rejectedOutput } 'JSON'
    $fixture.raw = $null
    Assert-NoOutput $rejectedOutput

    foreach ($stage in @('access', 'workload')) {
        $partial = Join-Path $scratch "existing-$stage"
        New-Item -ItemType Directory -Path $partial | Out-Null
        $sentinel = Join-Path $partial "native-$stage.tfvars.json"
        Set-Content -LiteralPath $sentinel -Value '{"sentinel":true}'
        Assert-Rejected { Invoke-Generator $partial } 'Refusing existing access/workload'
        Assert-Inputs (@(Get-ChildItem -LiteralPath $partial).Count -eq 1 -and
            (Get-Content -LiteralPath $sentinel -Raw).Trim() -ceq '{"sentinel":true}') 'Refuse partial existing output before writing foundation.'
    }
    Write-Output 'Native deployment input tests passed: shared five-team defaults, private roster/count, staged target reuse and fail-closed paths. Azure CLI mocked; no Terraform or live Azure operations.'
} finally {
    $global:LASTEXITCODE = $previousExitCode
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
