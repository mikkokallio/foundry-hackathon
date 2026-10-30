#requires -Version 7.5
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\knowledge.tf') -Raw
$data = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\data.tf') -Raw
$runtime = Get-Content -LiteralPath (Join-Path $root 'scenarios\architecture-docs\infra\runtime.tf') -Raw
if ($source -notmatch '(?s)  provisioner "local-exec" \{.*?\r?\n  \}') {
    throw 'Cannot locate the actual native-apply knowledge initializer.'
}
$provisioner = $Matches[0].Replace(
    'abspath("${path.module}/../../../infra/scripts/Initialize-Knowledge.ps1")',
    'abspath("${path.module}/TestInitializer.ps1")'
)
if ($source -notmatch '(?s)  provisioner "local-exec" \{\r?\n    when\s*=\s*destroy.*?\r?\n  \}') {
    throw 'Cannot locate the actual persisted-contract knowledge cleanup hook.'
}
$cleanupProvisioner = $Matches[0].Replace(
    'abspath("${path.module}/../../../infra/scripts/Remove-Knowledge.ps1")',
    'abspath("${path.module}/TestCleanup.ps1")'
)
if ($data -notmatch 'resource "azurerm_storage_blob" "document_seed"' -or
    $data -notmatch 'ignore_changes = \[source_content, content_md5\]' -or
    $runtime -notmatch 'name = "SEED_ON_START", value = "false"' -or
    $runtime -notmatch 'depends_on\s*= \[[^\]]*azurerm_storage_blob\.document_seed' -or
    $source -notmatch 'depends_on = \[azurerm_storage_blob\.knowledge_standard, azurerm_storage_blob\.document_seed\]') {
    throw 'Corpus must precede runtime/indexers, and subsequent applies must preserve librarian edits.'
}
$scratch = Join-Path $root "out\knowledge-lifecycle-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratch | Out-Null
$previousContract = $env:TF_VAR_contract
$previousData = $env:TF_DATA_DIR
try {
    $env:TF_DATA_DIR = Join-Path $scratch 'terraform-data'
    @'
variable "contract" { type = string }
locals { knowledge_contract = jsondecode(var.contract) }
resource "terraform_data" "knowledge_initialize" {
  input = local.knowledge_contract
  triggers_replace = [var.contract]
'@ + "`n$provisioner`n$cleanupProvisioner`n}" |
        Set-Content -LiteralPath (Join-Path $scratch 'main.tf') -Encoding utf8NoBOM
    # This unmistakably test-scoped initializer cannot call Azure or Foundry.
    @'
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([hashtable]$Knowledge, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess('test-only', 'test-only initialization')) { throw 'Unexpected confirmation.' }
if ($Knowledge.fail) { throw 'Test-only ingestion failure.' }
if ($Knowledge.marker -cne 'test-only') { throw 'Lost applied contract.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
'test-only; never runtime acceptance' | Set-Content -LiteralPath (Join-Path $OutputDirectory 'test-receipt.txt')
'@ | Set-Content -LiteralPath (Join-Path $scratch 'TestInitializer.ps1') -Encoding utf8NoBOM
    @'
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([hashtable]$Knowledge, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess('test-only', 'test-only cleanup')) { throw 'Unexpected confirmation.' }
if ($Knowledge.marker -cne 'test-only' -or $Knowledge.contract_version -notin @(1, 2)) { throw 'Lost persisted cleanup contract.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$Knowledge.contract_version | Add-Content -LiteralPath (Join-Path $OutputDirectory 'test-cleanup.txt')
'@ | Set-Content -LiteralPath (Join-Path $scratch 'TestCleanup.ps1') -Encoding utf8NoBOM
    & terraform "-chdir=$scratch" init -backend=false -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Provider-free knowledge lifecycle initialization failed.' }
    $env:TF_VAR_contract = '{"marker":"test-only","fail":true,"contract_version":1}'
    $failure = (& terraform "-chdir=$scratch" apply -auto-approve -input=false -no-color 2>&1 |
        ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -eq 0 -or $failure -notmatch 'Test-only ingestion failure') {
        throw "Native apply did not fail closed on initialization failure: $failure"
    }
    $receipt = Join-Path $scratch 'out\knowledge\test-receipt.txt'
    if (Test-Path -LiteralPath $receipt) { throw 'Failed apply wrote a completion receipt.' }
    $env:TF_VAR_contract = '{"marker":"test-only","fail":false,"contract_version":1}'
    $success = (& terraform "-chdir=$scratch" apply -auto-approve -input=false -no-color 2>&1 |
        ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $receipt)) {
        throw "Native apply did not recover and persist successful test-only initialization: $success"
    }
    $env:TF_VAR_contract = '{"marker":"test-only","fail":false,"contract_version":2}'
    $replacement = (& terraform "-chdir=$scratch" apply -auto-approve -input=false -no-color 2>&1 |
        ForEach-Object { "$_" }) -join "`n"
    $cleanupReceipt = Join-Path $scratch 'out\knowledge-cleanup\test-cleanup.txt'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cleanupReceipt) -or
        (Get-Content -LiteralPath $cleanupReceipt -Raw).Trim() -cne '1') {
        throw "Replacement must clean up with the legacy self.input before initializing the new contract: $replacement"
    }
    Write-Output 'Actual native-apply hooks failed closed, recovered and replaced with legacy persisted-contract cleanup, without prompts or Azure calls; corpus dependencies passed.'
} finally {
    $env:TF_VAR_contract = $previousContract
    $env:TF_DATA_DIR = $previousData
    Remove-Item -LiteralPath $scratch -Recurse
}
