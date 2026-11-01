# Preview notes and troubleshooting

Minor M1-M5 updates are likely during the preview. Deployment testing may also
identify targeted infrastructure fixes. This page collects practical notes for
deployment teams and facilitators.

## Deployment notes

Complete foundation, access, workload initialization and pack export before
participant checks. Verify the deployed environment using a participant account;
successful planning or administrator access does not prove the exercise works.

| Issue | What to do |
|---|---|
| APIM native MCP setup | The workload defines all twelve tools together on the MCP API rather than through separate tool writes. Check both an actual filtered GET and validator POST. For an existing state, follow the [native MCP update notes](../infra/README.md#native-documentation-mcp) and review a new plan before resuming. |
| Microsoft Graph timeout during app registration | A timeout can occur after the application has been created. Check the application and Terraform state, then review a new plan before resuming. Avoid creating a duplicate application manually. |
| Interrupted apply | Confirm the original process has stopped, preserve state and inspect the lock before generating a new plan. Use the same component backend and data directory. |
| Linux / Cloud Shell | The main deployment walkthrough uses local PowerShell. If choosing a different deployment shell, verify that route separately. For participant Cloud Shell, check the processing region and persistence choice before uploading inputs, and export results before session expiry. |
| Non-admin access | Verify actual participant sign-in, project connection creation and service authoring before the event. Inspect effective role scopes if an operation is denied; do not use administrator access as a substitute. |

See [Module 0](module-0.md) for deployment commands and
[the component/policy checklist](../README.md#customer-deployment-components-and-policy-checklist)
for subscription preparation.

## Exercise notes

| Activity | Practical guidance |
|---|---|
| M1 models and traces | Check direct and gateway-connected models separately. Allow trace ingestion time and inspect the actual tested agent version. Missing cost data is not zero cost. |
| M2 REST and MCP | Check all 14 imported REST operations, expose only the twelve allowed MCP tools, then execute a filtered inventory read and exact-text validator POST. The deployed participant role includes project connection writes; a disabled Connect button still requires effective-access investigation. |
| M3 throttling | Distinguish your practice limiter from shared capacity, and discovery throttles from business-tool throttles. Coordinate temporary policy changes, retain the original XML and verify restoration plus recovery. |
| M4 catalog registration | If the native wizard rejects a generated definition title, shorten it and retry. Generated `/sse` and `/message` examples and missing auth metadata may not describe the actual endpoint: inspect the registered specification and use the pack's real URL/auth settings. |
| M5 evaluations | This is an intentionally difficult challenge, not a requirement for four passing candidates. Preserve complete result folders and investigate an actual native trace. Record quality failures separately from service errors, missing provenance or incomplete collection. Do not rank incomplete evidence or weaken gates. Download archives through their filename links and verify local hashes/content before closing Cloud Shell. |
| B1 knowledge | Approve one short retrieval query, inspect its source URLs/quotes and compare indexed prose with the current authoritative standard. If retrieval is blocked, use B1's existing-index exercise; do not recreate infrastructure. |
| Core approval and publication | Require exact-text human consent, valid proposal saving and stored-text/status readback. Publication is a separate human action, only after teams have completed or stopped baseline collection. |
| B3 multi-agent | Inspect child traces to check that the reviewer independently used the necessary tools; a fluent review alone is insufficient. |
| B6 CI | Requires separate delivery-stage, GitHub environment and state/identity setup. Verify that route separately; failed or incomplete qualification must block production-style promotion. |
| B9 local app | Verify live data, approval controls and stored-text readback with the intended identity. Azure hosting is a separate extension, not a prerequisite for the local app. |

The [coach guide](coach-guide.md) has module-specific checks and short error triage.
For workshop progression and evaluation interpretation, see
[M5](modules/m5-evaluation.md#5-if-the-tests-fail-record-that-and-continue-the-workshop).

## Workshop materials

- [Core/bonus module manifest](../scenarios/architecture-docs/exercises/modules.json).
- [Agent and frontend prompts](../scenarios/architecture-docs/exercises/prompts/).
- [Evaluation datasets](../scenarios/architecture-docs/exercises/evaluation/).
- [Catalog metadata](../scenarios/architecture-docs/exercises/catalog-metadata.json)
  and [gateway/usage query starters](../scenarios/architecture-docs/exercises/queries/).
- [EUR model-price inputs and their scope](../scenarios/architecture-docs/exercises/pricing.json).
- [Bonus prerequisites](../scenarios/architecture-docs/exercises/bonus-prerequisites.md).

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

The new output directory contains rendered prompts, actual endpoints, model/prompt
combinations, token-free MCP configuration, evaluation inputs and a file-hash
receipt. The exporter keeps existing packs intact and checks that the
subscription/team/workload outputs match. Share the team pack, not Terraform
state or private roster inputs.

For B8 obtain a short-lived token using the exported scope:

```powershell
$workshop = Get-Content 'EXACT_EXPORTED_DIRECTORY\workshop.json' -Raw | ConvertFrom-Json
# Interactive only: use the token at the generated MCP config's password prompt.
# Keep it out of files, terminal transcripts, source control and chat.
az account get-access-token --tenant $workshop.tenant_id `
  --scope $workshop.gateway_scope --query accessToken -o tsv
```

Open the generated MCP config through the client's configuration UI; merge server
entries with any existing configuration. Keep write approvals enabled.
REST clients can hold the token in memory instead of using a coding agent.
