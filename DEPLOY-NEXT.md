# Resume after the knowledge initializer failure

**Latest clean-redeploy fixes:** The organizer approved purging only the
soft-deleted rehearsal Content Safety account; its absence was verified.
Content Safety now uses the native AzureRM resource instead of AVM 0.11.1,
which did not expose purge/restore. This workload explicitly enables
`cognitive_account.purge_soft_delete_on_destroy`: future Terraform destruction
permanently purges this disposable Content Safety account, allowing name reuse.
This feature does not affect the AzAPI-managed foundation Foundry account.
No existing Content Safety account was present in the current workload state;
if migrating another successfully deployed old AVM instance, review its state
migration before applying rather than recreating an existing account blindly.
Do not destroy the whole workload again.
The initializer now retries the specific "cannot reset/run indexer while it is
running" conflict within its existing deadline and still requires fresh successful
positive-item indexing. Local tests pass; live verification remains pending.
APIM management-service 422 timeouts and local Graph connection failures are
separate failures, not evidence that these lifecycle defects were harmless.

The initializer now launches its bounded CLI children with `-NoNewWindow`.
Earlier versions opened extra console windows; closing one interrupted the CLI
with `^C` and correctly failed initialization. No extra windows should appear
with the corrected source. Ctrl+C still means cancellation, never acceptance.
The clean redeployment passed published indexing (10 documents); both published
and standards indexers subsequently showed success with zero failed items.
This second interruption does not require another workload destroy.

The initializer incorrectly treated Search's temporary `reset` result as a
completed failed run. The actual published indexer subsequently processed
10 documents successfully; the standards indexer processed 3, both with zero
failures. The bounded wait now ignores reset markers while still requiring
a fresh successful positive-item run. Local regression/lifecycle/deadline tests
pass; live initialization and the Foundry acceptance gate are not yet accepted.

**First let the current apply finish. Do not start another while it runs.**
Preserve any other errors it reports. Then generate a NEW plan from the saved
partial state and corrected initializer; do not reuse the original saved plan:

```powershell
Set-Location 'C:\Users\mikkokallio\dev\manu\hackathon'
$ErrorActionPreference = 'Stop'
$base = "$PWD\out\rehearsals\cycle-two"
$env:TF_DATA_DIR = "$base\workload-data"
terraform -chdir=scenarios\architecture-docs\infra plan `
  -var-file="$base\foundation-bindings.tfvars.json" `
  -var-file="$base\access-bindings.tfvars.json" `
  -var-file="$base\workload-selections.tfvars.json" `
  -var-file="$base\runtime-images.tfvars.json" `
  -out="$base\workload-repair.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Repair plan failed; do not apply.' }
```

Review the remaining creates/changes and replacement of the failed
`terraform_data.knowledge_initialize`. No unrelated foundation/reference
destruction is expected. Apply the reviewed repair plan:

```powershell
terraform -chdir=scenarios\architecture-docs\infra apply "$base\workload-repair.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Workload apply failed; retain its state and error.' }
```

This stage runs the actual knowledge initializer. Its failure is a failed apply,
not an optional exercise to ignore. Do not start a second apply while one runs.

## 3. Export the participant input pack after successful apply

Do not distribute Terraform state, plan JSON or roster files. The existing
exporter creates a separate endpoint/prompt/evaluation input pack without tokens.

```powershell
$env:TF_DATA_DIR = "$base\foundation-data"
$foundationJson = terraform -chdir=infra\foundation output -json
if ($LASTEXITCODE -ne 0) { throw 'Foundation output failed.' }
$foundationJson | Set-Content "$base\foundation.outputs.json" -Encoding utf8NoBOM

$env:TF_DATA_DIR = "$base\workload-data"
$workloadJson = terraform -chdir=scenarios\architecture-docs\infra output -json
if ($LASTEXITCODE -ne 0) { throw 'Workload output failed.' }
$workloadJson | Set-Content "$base\workload.outputs.json" -Encoding utf8NoBOM
$f = ($foundationJson | ConvertFrom-Json).foundation.value
$selections = Get-Content "$base\workload-selections.tfvars.json" -Raw | ConvertFrom-Json
@{
  subscription_id = $f.subscription_id
  tenant_id = $f.tenant_id
  workload_name = $selections.workload_name
  workload_inputs = @{
    organization_name = $selections.organization_name
    reference_date = $selections.reference_date
  }
} | ConvertTo-Json -Depth 5 |
  Set-Content "$base\exercise-settings.json" -Encoding utf8NoBOM

.\scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1 `
  -FoundationOutputs "$base\foundation.outputs.json" `
  -WorkloadOutputs "$base\workload.outputs.json" `
  -Inputs "$base\exercise-settings.json" -Team alpha `
  -OutputDirectory "$base\participant-alpha"
```

The exporter refuses to overwrite an existing pack. Export is not a service test
or a passing evaluation. Give the participant their pack and
[participant instructions](PARTICIPANT-START.md), then rehearse the real path.

## Before the customer event

The organizer must pass actual service/agent/evaluation/provenance checks, verify
non-admin access, and confirm the deletion deadline and alert inbox. Baseline
evaluations run BEFORE librarian publication changes shared corpus expectations.
The current rehearsal expiry is 2026-11-03T16:42:33Z; the future date-only UX is
not implemented and does not change this deployment.

For 16 people: configure four foundation team names and map four actual enabled
Entra users to each team in access inputs; set expected count to 16. Guests must
already have accepted their invitations. Team names are configurable project
keys, not accounts. Customer librarians are selected explicitly in workload
inputs. Do not copy this one-person rehearsal roster as the customer roster.

B6 additionally needs its separately reviewed identity/state deployment, protected
GitHub environment and actual passing CI run. It is not installed merely by
copying a workflow. See [delivery prerequisites](scenarios/architecture-docs/delivery/README.md).
