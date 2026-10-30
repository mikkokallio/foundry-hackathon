# Exercise readiness

**Curriculum candidate, not live participant acceptance or permission to deploy.**

## Current curriculum repair

- [Participant navigation](../PARTICIPANT-START.md) links to five core module
  guides, the core approval exercise, nine bonus journeys and separate coach
  support. Each has Understand/Build/Validate, observation questions and
  purposeful official references.
- The [participant helper](../workshop/__main__.py) implements actual agent,
  chat/approval, practice integration, gateway, catalog and evaluation/report
  operations. It never deploys Terraform or modifies reference resources.
- A fresh actual-output alpha pack has been exported; older edited packs are
  preserved, not repaired by silently changing their hash receipts.
- Four-case smoke, twelve-case educational comparison and full twenty-five-case
  regression have distinct names. Legacy quick remains four-case smoke.
- M2 teaches building the documentation integration; the independent toolkit is
  first added after discovery in M4. Reference endpoints are explicitly catch-up.

**Still required:** focused helper validation, actual portal rehearsal,
non-admin authoring/connection/export tests, direct/routed trace correlation,
real throttle/chart experiments, four-way fresh evaluation/provenance and the
human save/librarian loop. Local files and an owner-created candidate do not
prove those checks passed. Native Manage -> AI Gateway linkage is not configured
merely because an explicit APIM model connection exists. Live B6 additionally
requires separately approved organizer delivery setup.

## Historical artifact audit

The earlier attempt does **not** contain every promised artifact. It has the
synthetic corpus, API/toolkit, two agent instruction variants, a 25-case dataset,
deterministic evaluators and a genuine evaluation/provenance CLI. It lacks the
handoff's named quick/portal/write-back datasets, variants file, current KQL
files and complete module/checkpoint tree. B3 orchestration and B9 frontend were
not completed applications.

Prepared here, independently of Terraform:

- [All-module/bonus manifest](../scenarios/architecture-docs/exercises/modules.json).
- [Baseline, full/concise, writer/reviewer, coding-agent and frontend prompts](../scenarios/architecture-docs/exercises/prompts/).
- [Inherited 25-case evaluation inputs and frozen thresholds](../scenarios/architecture-docs/exercises/evaluation/).
- [Catalog metadata](../scenarios/architecture-docs/exercises/catalog-metadata.json)
  and [gateway/usage query starters](../scenarios/architecture-docs/exercises/queries/).
- [Dated EUR retail model-price inputs](../scenarios/architecture-docs/exercises/pricing.json),
  with actual meter IDs and explicit exclusions, not a complete cost envelope.
- [Remaining deployment and exercise prerequisites](../scenarios/architecture-docs/exercises/bonus-prerequisites.md).

No Terraform, model deployments, container sources or published documents are
changed by preparing/exporting these inputs. The prepared prompts need real
Foundry acceptance before being called reliable. Prompt files alone do not
create agents or runnable workflows.

## Export after the workload is applied

Use the **printed component `TF_DATA_DIR` values**, not default state. In one
PowerShell session, with `$foundationData` and `$workloadData` set to those exact
printed directories:

```powershell
$previous = $env:TF_DATA_DIR
try {
    $env:TF_DATA_DIR = $foundationData
    terraform -chdir=infra\foundation output -json |
      Set-Content .\out\foundation.outputs.json -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) { throw 'Foundation output failed.' }
    $env:TF_DATA_DIR = $workloadData
    terraform -chdir=scenarios\architecture-docs\infra output -json |
      Set-Content .\out\workload.outputs.json -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) { throw 'Workload output failed.' }
} finally {
    $env:TF_DATA_DIR = $previous
}
.\scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1 `
  -FoundationOutputs .\out\foundation.outputs.json `
  -WorkloadOutputs .\out\workload.outputs.json `
  -Inputs .\out\deployment.private.json -Team YOUR_ACTUAL_TEAM_KEY
```

This writes a new ignored output directory with rendered prompts, actual
endpoints, four model/prompt combinations, token-free MCP configuration, derived
quick/portal/write-back inputs and a local file-hash receipt. It refuses to
overwrite an existing pack or mix subscription/team/workload outputs. It makes
no Azure calls and never invents an agent/version or marks live acceptance true.
Do not distribute Terraform state or private roster input files.

For B8 obtain a short-lived token using the exported scope:

```powershell
$workshop = Get-Content 'EXACT_EXPORTED_DIRECTORY\workshop.json' -Raw | ConvertFrom-Json
# Interactive only: this prints a token for the password prompt in generated MCP config.
# Do not paste it into a file, terminal transcript, source control or chat.
az account get-access-token --tenant $workshop.tenant_id `
  --scope $workshop.gateway_scope --query accessToken -o tsv
```

Open the generated MCP config through the client's supported configuration UI;
merge server entries rather than replacing an existing configuration blindly.
Keep write approvals enabled. REST clients can hold this token in memory instead
of using a coding agent.

## Still not ready

Real cloud access, native tracing, initialized knowledge, approval-driven
write-back and genuine evaluation/provenance must pass after joint deployment.
B6 additionally needs the real repository/federation/state decisions and
provisioning **before** participants try it. B2 deploys a new app during the
exercise; B3/B9 deliberately require participant implementation. Thus the event
is not exclusively clicking through Foundry/APIM/API Center.
