# Preview notes and troubleshooting

Minor M1-M5 updates are likely during the preview. Deployment testing may also
identify targeted infrastructure fixes. This page collects practical notes for
deployment teams and facilitators.

## Deployment notes

Foundation and access stages, remote image builds and knowledge initialization
have been exercised in a fresh environment. Full workload deployment and
non-admin participant checks are still being completed.

| Issue | What to do |
|---|---|
| APIM native MCP tool creation returns HTTP 502 | A fresh deployment created the expected REST operations but could not complete its MCP tools. This remains open; no reliable workaround is established. Preserve the partial state and error details, and contact the deployment team before retrying. M2 needs a working MCP endpoint; a REST import alone is not sufficient. |
| Microsoft Graph timeout during app registration | A timeout can occur after the application has been created. Check the application and Terraform state, then review a new plan before resuming. Avoid creating a duplicate application manually. |
| Interrupted apply | Confirm the original process has stopped, preserve state and inspect the lock before generating a new plan. Use the same component backend and data directory. |
| Linux / Cloud Shell | Commands are supplied but have not yet been deployment-tested end to end. The Windows path has been tested. Verify Cloud Shell's processing region and persistent storage before uploading private inputs. |
| Non-admin access | Role assignments are configured; effective participant sign-in and authoring checks are still in progress. Verify with a participant account before the event. |

See [Module 0](module-0.md) for deployment commands and
[the component/policy checklist](../README.md#customer-deployment-components-and-policy-checklist)
for subscription preparation.

## Exercise notes

| Activity | Practical guidance |
|---|---|
| M1 models and traces | Direct and gateway-connected requests and native traces have been exercised. Allow ingestion time and inspect the tested agent version. |
| M2 REST and MCP | Portal import has created all 14 expected REST operations. Complete the backend, authentication and policy steps before testing tools. If stuck, use the reference integration as described in M2; a fresh non-admin end-to-end pass remains pending. |
| M3 throttling | Model request/token limits and usage charts have been observed. MCP discovery returned 429 and recovered after restoring the owned policy; a business-operation tool-call 429 has not yet been demonstrated. Coordinate any temporary limit changes and restore them afterward. |
| M4 catalog registration | If the native wizard rejects a generated definition title, shorten it and retry. Generated `/sse` and `/message` examples and missing auth metadata may not describe the actual endpoint: inspect the registered specification and use the pack's real URL/auth settings. |
| M5 evaluations | A complete passing four-way comparison/full qualification has not yet been achieved. Use the documented stop rule: investigate a real failure, retain the result and continue to bonuses/core approval. Failed or incomplete runs do not prevent workshop participation. |
| B1 knowledge | Retrieval through the shared connection and restricted helper has been verified. Create a newly named candidate after connection changes, approve one short query and check source URLs/quotes. If citations are missing, ask for filenames, source URLs and a quote from the retrieved passages. |
| Core approval and publication | Proposal saving and separate human publication remain distinct. Complete participant save/readback and librarian checks in the deployed environment. Publish after all teams have completed or stopped their baseline collection. |
| B3 multi-agent | Writer/reviewer prompts and workflow helpers are available. Independent reviewer tool use still needs attention; inspect child traces before accepting a review. |
| B6 CI | Requires the separate delivery stage, GitHub environment and state/identity setup. The live CI path has not yet been verified. |
| B9 local app | The optional reference has exercised live reads, agent/tool calls, validation, approval controls and rendering. Participant save/readback remains to be verified. Azure hosting is a separate extension. |

The [coach guide](coach-guide.md) has module-specific checks and short error triage.
For workshop progression and evaluation interpretation, see
[M5](modules/m5-evaluation.md#5-workshop-stopfallback).

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
