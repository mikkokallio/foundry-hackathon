#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$export = Join-Path $root 'scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1'
$starter = Join-Path $root 'workshop\Start-Lab.ps1'
$scratch = Join-Path $root "out\lab-setup-tests-$([guid]::NewGuid().ToString('N'))"
$preparedDirectory = $null
New-Item -ItemType Directory -Path $scratch | Out-Null
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
function Write-Config {
    $script:config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $script:inputFile -Encoding utf8NoBOM
}
try {
    $subscription = '11111111-1111-1111-1111-111111111111'
    $resource = "/subscriptions/$subscription/resourceGroups/test-lab/providers"
    $plan = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\exercises\evaluation\plan.json') -Raw |
        ConvertFrom-Json -AsHashtable
    $config = @{
        schema_version = 1; runtime_accepted = $false
        subscription_id = $subscription; tenant_id = '22222222-2222-2222-2222-222222222222'
        team = 'alpha'; workload_name = 'architecture-docs'
        organization_name = 'Example & Co [QA]'; reference_date = $plan.reference_date
        project_endpoint = 'https://aif-test.services.ai.azure.com/api/projects/alpha'
        docs_url = 'https://apim-test.azure-api.net/architecture-docs/docs-api'
        docs_mcp = 'https://apim-test.azure-api.net/architecture-docs/docs-mcp/mcp'
        toolkit_mcp = 'https://apim-test.azure-api.net/architecture-docs/toolkit/mcp'
        gateway_models = @{
            models = 'https://apim-test.azure-api.net/architecture-docs/models/chat/completions?api-version=2024-10-21'
            'models-tight' = 'https://apim-test.azure-api.net/architecture-docs/models-tight/chat/completions?api-version=2024-10-21'
        }
        gateway_scope = 'api://33333333-3333-3333-3333-333333333333/Lab.Access'
        workspace_resource_id = "$resource/Microsoft.OperationalInsights/workspaces/log-test"
        application_insights_resource_id = "$resource/Microsoft.Insights/components/appi-test"
        foundry_resource_id = "$resource/Microsoft.CognitiveServices/accounts/aif-test"
        catalog_resource_id = "$resource/Microsoft.ApiCenter/services/apic-test"
        gateway_resource_id = "$resource/Microsoft.ApiManagement/service/apim-test"
        extension_authoring = @{ resource_group_id = "/subscriptions/$subscription/resourceGroups/extensions" }
        gateway_exercises = @{
            live_accepted = $false
            model_backend_ids = @{ 'chat-small' = "$resource/Microsoft.ApiManagement/service/apim-test/backends/architecture-docs-chat-small" }
        }
        model_variants = @(
            foreach ($alias in $plan.model_aliases) {
                foreach ($instructions in $plan.instruction_files) {
                    @{
                        model_alias = $alias; deployment = "architecture-docs-$alias"
                        agent_model_id = "architecture-docs-alpha-models/$alias"
                        instructions = "prompts\$instructions"
                    }
                }
            }
        )
    }
    $inputFile = Join-Path $scratch 'workshop.json'
    Write-Config
    $destination = Join-Path $scratch 'assembled'
    & $export -Configuration $inputFile -Team alpha -OutputDirectory $destination -WarningAction SilentlyContinue | Out-Null
    $pack = Get-Content -LiteralPath (Join-Path $destination 'workshop.json') -Raw | ConvertFrom-Json -AsHashtable
    $receipt = Get-Content -LiteralPath (Join-Path $destination 'assembly-receipt.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert ($pack.team -ceq 'alpha' -and $pack.runtime_accepted -eq $false) 'Assembly must not claim runtime acceptance.'
    Assert ($receipt.sha256.Count -eq 21 -and $receipt.source_revision -match '^[0-9a-f]{40}$') 'Need all common assets and source revision.'
    Assert ($receipt.assembly_source -ceq 'Configuration' -and $receipt.runtime_accepted -eq $false) 'Receipt must distinguish config assembly from live proof.'
    foreach ($entry in $receipt.sha256.GetEnumerator()) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $destination $entry.Key)).Hash -ieq $entry.Value) 'Pack receipt hash mismatch.'
    }
    $rendered = Get-Content -LiteralPath (Join-Path $destination 'prompts\instructions.md') -Raw
    Assert ($rendered.Contains($config.organization_name) -and $rendered -notmatch '\{\{[^}]+\}\}') 'Prompts must be rendered from actual config.'
    $prepared = @(& $starter -Configuration $inputFile -Team alpha -Prefix alpha-p2 -PrepareOnly -WarningAction SilentlyContinue)
    $preparedDirectory = Split-Path -Parent $prepared[-1]
    $oldProfile = $env:AZURE_CONFIG_DIR
    & {
        $global:LabTestNeedsLogin = $false
        $global:LabTestTenant = $config.tenant_id
        $global:LabTestAzCalls = [Collections.Generic.List[object]]::new()
        function global:az {
            $global:LabTestAzCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            if ($args -contains '--tenant' -and $args -contains '--subscription') {
                throw 'Azure CLI does not accept tenant and subscription together.'
            }
            switch ("$($args[0]) $($args[1])") {
                'account show' {
                    if ($global:LabTestNeedsLogin) {
                        $global:LASTEXITCODE = 1
                    } else {
                        Write-Output $global:LabTestTenant
                    }
                }
                'account get-access-token' { Write-Output 'fixture-expiry-not-a-token' }
                'login --tenant' { $global:LabTestNeedsLogin = $false }
                'account set' {}
                default { throw 'Unexpected Azure CLI call in the offline setup test.' }
            }
        }
        try {
            . $starter -Configuration $inputFile -Team alpha -Prefix alpha-p2 -WarningAction SilentlyContinue
            Assert ($global:FoundryLabSession.Prefix -ceq 'alpha-p2') 'Dot-sourced function lost its prefix.'
            & $global:FoundryLabSession.Python -c 'from pathlib import Path; import sys; from workshop.__main__ import load_pack; assert load_pack(Path(sys.argv[1]))["team"] == "alpha"' $global:FoundryLabSession.Pack
            Assert ($LASTEXITCODE -eq 0) 'Python helper rejected assembled inputs.'
            Push-Location $scratch
            try { lab --help | Out-Null } finally { Pop-Location }
            Assert ($LASTEXITCODE -eq 0) 'lab must remain callable from another directory.'
            Assert (@($global:LabTestAzCalls | Where-Object { $_[0] -ceq 'login' }).Count -eq 0) 'Reuse valid scoped sign-in.'
            Remove-Item -LiteralPath (Split-Path -Parent $global:FoundryLabSession.Pack) -Recurse
            $global:LabTestNeedsLogin = $true
            . $starter -Configuration $inputFile -Team alpha -Prefix alpha-p2 -WarningAction SilentlyContinue
            $loginCalls = @($global:LabTestAzCalls | Where-Object { $_[0] -ceq 'login' })
            Assert ($loginCalls.Count -eq 1 -and $loginCalls[0] -contains '--scope' -and $loginCalls[0] -contains '--use-device-code') 'Missing profile requires one explicit scoped device sign-in.'
        } finally {
            if ($global:FoundryLabSession) {
                Remove-Item -LiteralPath (Split-Path -Parent $global:FoundryLabSession.Pack) -Recurse
                Remove-Variable FoundryLabSession -Scope Global
                Remove-Item Function:\lab
            }
            Remove-Item Function:\az
            Remove-Variable LabTestNeedsLogin,LabTestTenant,LabTestAzCalls -Scope Global
            $env:AZURE_CONFIG_DIR = $oldProfile
        }
    }
    Assert-Throws { & $starter -Configuration $inputFile -Team alpha -Prefix beta-p2 -PrepareOnly } 'actual team'
    Assert-Throws { & $starter -Configuration $inputFile -Team alpha -Prefix alpha-p2 } 'Dot-source'
    Assert-Throws { & $export -Configuration $inputFile -Team beta -OutputDirectory (Join-Path $scratch 'wrong-team') } 'team'
    Assert-Throws { & $export -Configuration $inputFile -Team alpha -OutputDirectory $destination } 'already exists'
    Assert-Throws { & $export -Configuration $inputFile -Team alpha -OutputDirectory (Join-Path $root 'must-not-write-pack') } 'ignored out'
    $datasetText = (Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\exercises\evaluation\eval_set.jsonl') -Raw).Replace("`r`n", "`n")
    foreach ($text in @($datasetText, $datasetText.Replace("`n", "`r`n"))) {
        $config.evaluation_dataset_sha256 = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))
        ).ToLowerInvariant()
        Write-Config
        $encodingPack = Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        & $export -Configuration $inputFile -Team alpha -OutputDirectory $encodingPack -WarningAction SilentlyContinue | Out-Null
    }
    $config.evaluation_dataset_sha256 = '0' * 64
    Write-Config
    Assert-Throws { & $export -Configuration $inputFile -Team alpha } 'beyond LF/CRLF'
    $config.Remove('evaluation_dataset_sha256')
    $config.gateway_scope = 'api://bad/Lab.Access'
    Write-Config
    Assert-Throws { & $export -Configuration $inputFile -Team alpha } 'gateway_scope'
    $config.gateway_scope = 'api://33333333-3333-3333-3333-333333333333/Lab.Access'
    $config.model_variants[0].agent_model_id = 'different-model'
    Write-Config
    Assert-Throws { & $export -Configuration $inputFile -Team alpha } 'model bindings'
    $config.model_variants[0].agent_model_id = "architecture-docs-alpha-models/$($config.model_variants[0].model_alias)"
    $config.docs_mcp = 'https://other.invalid/mcp'
    Write-Config
    Assert-Throws { & $export -Configuration $inputFile -Team alpha } 'does not match'
    $config.docs_mcp = 'https://apim-test.azure-api.net/architecture-docs/docs-mcp/mcp'
    $config.extension_authoring.api_key = 'synthetic-not-a-secret'
    Write-Config
    Assert-Throws { & $export -Configuration $inputFile -Team alpha } 'credentials'
    $config.extension_authoring.Remove('api_key')
    $config.projects = @{
        alpha = 'https://aif-test.services.ai.azure.com/api/projects/alpha'
        beta = 'https://aif-test.services.ai.azure.com/api/projects/beta'
    }
    Write-Config
    $beta = Join-Path $scratch 'beta'
    & $export -Configuration $inputFile -Team beta -OutputDirectory $beta -WarningAction SilentlyContinue | Out-Null
    $betaPack = Get-Content -LiteralPath (Join-Path $beta 'workshop.json') -Raw | ConvertFrom-Json
    Assert ($betaPack.team -ceq 'beta' -and $betaPack.model_variants[0].agent_model_id -like 'architecture-docs-beta-models/*') 'Common config must select only actual declared teams.'
    Assert-Throws { & $export -Configuration $inputFile -Team gamma } 'declared'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse
    if ($preparedDirectory) { Remove-Item -LiteralPath $preparedDirectory -Recurse }
}
Write-Output 'Config-only assembly, complete receipt, rendering, actual team selection, scope/model/route/secret validation and non-overwrite tests passed. No Azure operations.'
