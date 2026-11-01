# Module 0 - Review and deploy the foundation and selected workload

> [!NOTE]
> **Preview.** Minor M1-M5 updates are likely. Deployment testing may lead to
> targeted infrastructure fixes.

Prepare the subscription, deploy the shared services and scenario, then verify
participant access. Start with the
[resource and policy checklist](../README.md#customer-deployment-components-and-policy-checklist)
and agree the target environment, costs and permissions with your deployment team.

Module 0 can be tested independently of the later exercises. Deployment-specific
issues and recovery guidance are collected in the
[preview notes](exercise-readiness.md).

## 1. Choose today's work, not tomorrow's roster

**Release gate:** the commands below are a walkthrough for the tested candidate
the deployment team publishes. Do not start them against an unpublished working
tree. Publication is not approval to apply: confirm the concrete live target and
review each saved plan with the deployment team before any mutation.

On **Sunday 1 November**, rehearse the current reference E2E and the improved
deployment in the **existing approved test environment with its existing test
roster**. Preserve that environment's original backend and state. Do not ask for
the customer roster today, substitute test people into a customer roster, or
weaken the participant count checks.

The customer roster arrives **Monday morning**. Before then, customer foundation
infrastructure preflight/planning can proceed with approved target inputs and
team keys. Infrastructure-only checks deliberately defer identity checks; they
are **not full preflight**. Customer access/workload planning waits for complete
actual accounts, team assignments and the separately selected human publisher.
The APIM `publisher_email` is a monitored contact address, not a publisher grant.

The closeout deadlines are **18:00 infrastructure freeze with a successful shared
human deployment**, **19:00 documentation**, remaining exercises preferably
**21:00**, no later than **midnight**, and customer readiness **08:00 Monday**.
These are deadlines, not provisioning estimates or a promise that Azure
provisioning/role propagation will fit. Report a missed gate rather than skip it.

## Required inventory

| Capability | Ownership | Required for |
|---|---|---|
| Explicit subscription, tenant, regions, naming overrides and tags | Composition/foundation | Customer-owned deployment; no ambient account selection |
| Deployment-time UPN/object-ID roster and enabled/accepted-user checks | Composition/access | Complete actual roster before access/workload; foundation planning can precede it |
| Resource-provider, policy, quota and operator-permission checks | Composition | Fail before partial provisioning where checks are possible |
| Service/model cost review and operator-managed teardown | Operations | Subscription-owner control of spending and lifecycle |
| Workspace-based App Insights and Log Analytics, Entra ingestion/querying | Foundation | Agent traces, gateway/token metrics and provenance |
| Foundry resource with generic team/facilitator projects | Foundation | M1-M5 and agent bonuses |
| Scenario-selected model deployments, including embeddings | Workload | Agent/model comparison, judges, B1 knowledge retrieval, B4 resilience |
| API Management with managed identity and generic caller/team authentication | Foundation | M2, M3, B2, B4, B5, B8 |
| API Center | Foundation | M4 register, discover and export real definitions |
| Azure AI Search with separate configurable region and managed identity | Foundation capability, required by this scenario | B1; not a paragraph saying "investigate" |
| Key Vault, RBAC-based | Foundation capability | Any verified secret exception; no unnecessary shared keys |
| Storage account, shared keys disabled | Foundation | Shared data capability |
| Published documents, proposals, templates and glossary containers/content | Workload | Core approved write-back, separate human publication and B1 |
| Container Registry and Container Apps environment | Foundation | M2 services and B2 additional MCP application |
| Document API and toolkit applications with immutable images | Workload | M2, M4 and approved write-back |
| API routes, REST-to-MCP and existing-MCP registrations and connections | Workload | M2, M3, M4, B2, B8 |
| Explicit human approval, separate librarian authorization | Workload | Core write-back; never an agent publication tool |
| Search index, ingestion, embedding/vectorizer, knowledge source/base and connection | Workload/B1 exercise | Working knowledge exercise, with permissions provisioned before the event |
| Two usable model backends and content-safety prerequisites | Workload | B4 resilience and safety exercise |
| Optional semantic-cache infrastructure and complete identity/network configuration | Explicit workload option | B4 cache branch, when selected |
| Price inputs and caller/team token dimensions | Workload/operations | B5 usage and cost investigation |
| OIDC/remote-state setup and evaluation-gated CI | Optional delivery integration | B6; no secret credentials committed or demanded in chat |
| Coding-agent MCP configuration and CLI alternative | Workload exercise | B8; no Copilot license required for the core |
| Local-front-end prompt pack, API contract and optional reference implementation | Workload exercise | B9 |
| Teardown, preservation boundaries and soft-delete/redeployment procedure | Operations | Jointly reviewed destruction; no automatic deletion after success |

## Workshop scope

- All five core modules remain required.
- Human-approved proposal saving is part of the core journey.
- Publication is a separate human operation, never an agent tool.
- AI Search and B1 prerequisites are included in this scenario.
- Model deployments belong to the workload.
- The lab uses public, identity-protected endpoints.
- Participant permissions are scoped to the required learning activities.
- Resolve and check the actual participant roster before the event.

## Participant access

M2/M3 require API-management changes, M4 requires catalog writes, B1 needs Search
authoring, and B2 needs application creation. Review each operation, principal,
role and scope before applying the access plan.

The lab uses **service-scoped authoring on shared services**, rather than
resource-group Contributor. The access Terraform accepts team membership as UPNs
or tenant object IDs and resolves the actual users with the AzureAD provider.
Access is a separate deployment stage. Check guest invitation acceptance and
sign in with a non-admin participant account to verify effective access.

The actual built-in APIM, API Center and Search service-contributor definitions
also permit foundation-service deletion or reconfiguration. They are therefore
not assigned wholesale: the access module declares lab-scoped custom authoring
roles that exclude service-level write/delete, while retaining child-resource
authoring. Search admin/query-key management is excluded; local auth is disabled.
Those custom role definitions and their exact actions must be reviewed before
apply, and the deployment operator needs role-definition creation rights as well
as assignment rights. Existing unrelated grants are not automatically revoked.
Search document data access remains explicit and shared for the synthetic lab.

**Shared authoring:** teams share APIM/API Center/Search configuration and
synthetic Search data. Use team-prefixed names and coordinate shared changes;
the authoring grants do not isolate teams.
APIM policy authors can also alter gateway-enforced controls, including team and
librarian checks. Treat them as trusted lab operators, not isolated tenants.

B2 extension apps have a separate workload group with scoped app/identity
authoring, ACA-environment join and ACR build/push grants. Teams can modify each
other's extension apps, but these grants exclude the trusted backend/toolkit
group and identities and do not permit role assignments.

## 2. Choose one state route

See the [preview reference settings](../infra/README.md#preview-reference-settings)
for the selected gateway, Search capacity, separate retrieval billing and B4
prerequisite. Search capacity can be set independently of the gateway profile.

| Route | State and working metadata | When to use |
|---|---|---|
| **Preferred native Terraform** | Each root's own `terraform.tfstate` and `.terraform` directory | New approved deployment, or resuming an existing native deployment with its recorded context |
| Optional composition wrapper | Explicit `out/<subscription>/<suffix>/state/` and isolated `terraform-data/` directories printed by the script | Existing wrapper deployment, or explicitly selected new wrapper deployment |

**Existing test rehearsal:** first identify its original route and all three
component contexts. Do not initialize the other route against those resources.
Never use an empty state to "resume" an existing environment. Remote state is a
separately approved configuration, not an automatic switch or part of these
local-backend examples. B6 is optional and separate.

All Windows commands below use **PowerShell 7.5+**, from the repository root
`hackathon`, with Terraform >=1.9 and <2.0 and Azure CLI installed. Use the
published candidate checkout and the approved tenant login. A fresh terminal
avoids inherited `TF_DATA_DIR`; it does not recover missing state or authorize a
new backend. Do not clear or overwrite recorded context on a resumed deployment.

### 3. Native foundation: inputs, plan, approval, apply

For a **new native local-state deployment only**, prepare these ignored private
files in `out/` using your editor. Do not paste roster/state into chat or commit
it. Keep the approved inputs and plans securely backed up.

| Private file | Contents and source |
|---|---|
| `out\native-foundation.tfvars.json` | JSON object with approved `subscription_id`, `tenant_id`, `location`, `search_location`, unique `suffix`, explicit `profile`, monitored APIM `publisher_email`, `team_names`, `enable_search: true`, reviewed `search_configuration` and `tags`. Names/types are in [foundation variables](../infra/foundation/variables.tf). Team keys do not require member identities yet. |
| `out\native-access.tfvars.json` | Once the actual roster is available: JSON object with complete `teams` (team key to UPN/object-ID arrays) and `expected_participant_count`. The applied `foundation` object is added below; do not invent it. |
| `out\native-workload.tfvars.json` | Once roster/publisher/images are ready: JSON object with approved `workload_name`, `organization_name`, `models`, `reference_date`, explicit `semantic_cache_enabled`, `librarians` and both `runtime_images`. Applied `foundation` and `participant_members` are added below. See [workload variables](../scenarios/architecture-docs/infra/variables.tf) and the [scenario manifest](../scenarios/architecture-docs/scenario.json). |

The composition JSON example is **not** a native `.tfvars` file. In particular,
native workload inputs are `models`, `librarians`, `runtime_images` and
`semantic_cache_enabled`, not `model_overrides` or a `workload_inputs` envelope.
Use actual approved values; example teams, hashes and identity addresses are not
deployable inputs. Review the reference Search/model allocations in the
[infrastructure guide](../infra/README.md#preview-reference-settings), not just
the gateway profile. The scenario and composition example use different model
capacity selections; approve one explicit map, do not silently interchange them.

Run infrastructure-only preflight using the optional read-only checker below,
with a private composition input matching your native target/service/model
choices. It does not initialize or change Terraform backends. Resolve any
provider/permission/policy/quota failure before applying. Native model planning
also checks live availability and lifecycle; a previously observed catalog/quota
result is not a reservation.

In the **same PowerShell session**, record native context and save the foundation
plan. The commands below assume the new native default local backend, not an
existing wrapper or remote backend:

```powershell
$repo = (Get-Location).Path
$foundationData = Join-Path $repo 'infra\foundation\.terraform'
$accessData = Join-Path $repo 'infra\access\.terraform'
$workloadData = Join-Path $repo 'scenarios\architecture-docs\infra\.terraform'
$foundationVars = Join-Path $repo 'out\native-foundation.tfvars.json'
$foundationPlan = Join-Path $repo 'out\native-foundation.tfplan'
if (Test-Path -LiteralPath $foundationPlan) { throw 'Keep the previous plan; choose a new plan filename.' }
$env:TF_DATA_DIR = $foundationData
terraform -chdir=infra\foundation init
if ($LASTEXITCODE -ne 0) { throw 'Stop: foundation init failed.' }
terraform -chdir=infra\foundation plan "-var-file=$foundationVars" "-out=$foundationPlan"
if ($LASTEXITCODE -ne 0) { throw 'Stop: foundation plan failed.' }
terraform -chdir=infra\foundation show -no-color $foundationPlan
Get-FileHash -LiteralPath $foundationPlan -Algorithm SHA256
```

**Expected:** saved binary plan; foundation resources only, no scenario models or
apps. Retain the plan/hash, input file, `$foundationData`, and native state path
`infra\foundation\terraform.tfstate`. If a path already contains another
deployment's plan/state, stop; do not overwrite it. For subsequent plans use a
new filename and retain the prior reviewed artifact.

**STOP for joint approval:** verify target IDs, both regions, names, SKUs,
ongoing charges, custom roles/assignments and every destroy/replace action.
The region allowlist is not approval for this particular deployment. See the
[component checklist](../README.md#customer-deployment-components-and-policy-checklist).
Then, only in the retained foundation context, apply the exact approved plan:

```powershell
$env:TF_DATA_DIR = $foundationData
terraform -chdir=infra\foundation apply $foundationPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve state and reconcile the failed apply.' }
$foundation = terraform -chdir=infra\foundation output -json foundation |
  ConvertFrom-Json -AsHashtable -Depth 50
if ($LASTEXITCODE -ne 0) { throw 'Stop: applied foundation output failed.' }
```

**Expected:** real applied version-1 `foundation` object, including registry,
projects and service IDs. This is the named output's object, not the
`terraform output -json` envelope and not a readiness receipt.

### 4. Native access: wait for the real roster

For today's existing test deployment use its existing test roster. For the
customer, wait until Monday's complete roster and selected publisher are ready.
Verify target-tenant enabled accounts, accepted guest invitations where relevant,
team assignments and sign-in/MFA. Full read-only preflight must pass; an
Infrastructure receipt cannot stand in for it.

Add the **unchanged applied** foundation object to the private access file:

```powershell
$accessVars = Join-Path $repo 'out\native-access.tfvars.json'
$accessInputs = Get-Content -LiteralPath $accessVars -Raw |
  ConvertFrom-Json -AsHashtable -Depth 50
$accessInputs.foundation = $foundation
$accessInputs | ConvertTo-Json -Depth 50 |
  Set-Content -LiteralPath $accessVars -Encoding utf8NoBOM
$accessPlan = Join-Path $repo 'out\native-access.tfplan'
if (Test-Path -LiteralPath $accessPlan) { throw 'Keep the previous plan; choose a new plan filename.' }
$env:TF_DATA_DIR = $accessData
terraform -chdir=infra\access init
if ($LASTEXITCODE -ne 0) { throw 'Stop: access init failed.' }
terraform -chdir=infra\access plan "-var-file=$accessVars" "-out=$accessPlan"
if ($LASTEXITCODE -ne 0) { throw 'Stop: access plan failed.' }
terraform -chdir=infra\access show -no-color $accessPlan
Get-FileHash -LiteralPath $accessPlan -Algorithm SHA256
```

**Expected:** every actual user resolves once to the correct team; count and
duplicate/guest checks are not relaxed. **STOP for approval** of each custom
role/action/scope, including the targeted M2 project connection-write fix.
An Alpha-only manual grant does not make the deployment reproducible.
Retain `$accessData` and `infra\access\terraform.tfstate`, then apply:

```powershell
$env:TF_DATA_DIR = $accessData
terraform -chdir=infra\access apply $accessPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve access state.' }
$access = terraform -chdir=infra\access output -json deployment_access |
  ConvertFrom-Json -AsHashtable -Depth 50
if ($LASTEXITCODE -ne 0) { throw 'Stop: applied access output failed.' }
```

**Expected:** applied `deployment_access` with matching tenant/subscription/group,
complete `teams` and resolved `members`. Assignment existence is not effective
non-admin access.

### 5. Native images: an explicit billable boundary

After foundation apply, image building can run independently of roster arrival.
The build helper reads the actual applied foundation object; it does not select
or migrate Terraform state. **STOP for approval** of source and ACR build cost.

```powershell
.\infra\scripts\Build-WorkloadImages.ps1 -Scenario architecture-docs `
  -WorkloadName architecture-docs -Foundation $foundation `
  -OutputDirectory .\out\native-image-artifacts
```

Use your approved `workload_name` in place of `architecture-docs` if different.
This queues remote Linux/amd64 builds in the applied foundation registry; no
local Docker daemon is required. **Expected:** printed `runtime-images.json`
containing real `backend` and `toolkit` `repository@sha256` values, plus build
receipts/source hashes. Copy that exact object into native workload
`runtime_images`. Keep receipts; they say `release_accepted: false` because a
successful build is not runtime acceptance.

**STOP** on a failed/incomplete build, wrong registry or missing digest. Do not
invent hashes, use mutable tags or automatically rebuild during plan/apply.
After interruption inspect the specific recorded ACR run before retrying;
timeout/disconnect does not prove the remote run stopped.

### 6. Native workload and knowledge

Before planning, compare `$access.teams` with the complete current roster and
verify that `$access` and `$foundation` refer to the same target/group. Reapply
a newly reviewed access plan first if membership changed. Native Terraform does
not perform the wrapper's stale-roster comparison on your behalf.

```powershell
$workloadVars = Join-Path $repo 'out\native-workload.tfvars.json'
$workloadInputs = Get-Content -LiteralPath $workloadVars -Raw |
  ConvertFrom-Json -AsHashtable -Depth 50
$workloadInputs.foundation = $foundation
$workloadInputs.participant_members = $access.members
$workloadInputs | ConvertTo-Json -Depth 50 |
  Set-Content -LiteralPath $workloadVars -Encoding utf8NoBOM
$workloadPlan = Join-Path $repo 'out\native-workload.tfplan'
if (Test-Path -LiteralPath $workloadPlan) { throw 'Keep the previous plan; choose a new plan filename.' }
$env:TF_DATA_DIR = $workloadData
terraform -chdir=scenarios\architecture-docs\infra init
if ($LASTEXITCODE -ne 0) { throw 'Stop: workload init failed.' }
terraform -chdir=scenarios\architecture-docs\infra plan "-var-file=$workloadVars" "-out=$workloadPlan"
if ($LASTEXITCODE -ne 0) { throw 'Stop: workload plan failed.' }
terraform -chdir=scenarios\architecture-docs\infra show -no-color $workloadPlan
Get-FileHash -LiteralPath $workloadPlan -Algorithm SHA256
```

**Expected:** selected models, runtime apps, synthetic content, API/MCP/catalog
wiring and Search resources. **STOP for approval**, including tenant application
changes, selected human librarian grants, model quota/cost and any optional
Redis key-auth exception. Confirm the plan contains both approved image digests.
Retain `$workloadData` and
`scenarios\architecture-docs\infra\terraform.tfstate`.

Workload apply also invokes the bounded knowledge initializer: it resets/runs
both source indexers, verifies fresh successful ingestion, and creates the
knowledge source/base and project MCP connections. This mutation is part of the
plan approval; it is not a separate hidden deployment.

```powershell
$env:TF_DATA_DIR = $workloadData
terraform -chdir=scenarios\architecture-docs\infra apply $workloadPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve workload state and inspect the failing operation.' }
terraform -chdir=scenarios\architecture-docs\infra output -json knowledge
```

**Expected:** successful apply and knowledge receipt under
`scenarios\architecture-docs\infra\out\knowledge`. Inspect ingestion results and
connection readback; `live_accepted: false` remains deliberate until real
retrieval/agent verification. Do not rerun indexing to conceal an error.
For explicitly approved reinitialization only, read `output -json knowledge`
from this same workload context and pass its parsed object to
`Initialize-Knowledge.ps1 -Knowledge ... -OutputDirectory ...`; review that
script's mutating reset/run behavior first.

### 7. Safe resumption, no automatic destruction

After any error, **stop dependent stages**. Keep the exact backend configuration,
component `TF_DATA_DIR`, state, plans, inputs and receipts. Check the original
process/lock and remote operation before resuming; never blindly force-unlock,
duplicate a Graph application or queue another ACR build. Once the original
operation has stopped, reconcile actual resources against the same state and
create a **new** plan for joint review. Do not replay a stale plan, change
backends, import/remove state or run `init -reconfigure` as a recovery shortcut.

For a new terminal restore the recorded component data-directory variables and
backend configuration before any `output`, `plan` or `apply`. A fresh plan must
show no unexplained functional drift after success. No stage auto-applies or
auto-destroys; destruction needs separate approval and a fresh reviewed destroy
plan from the owning state. Knowledge cleanup has an ordered destroy hook; do
not bypass it. Budget monitoring and eventual teardown belong to the
subscription owner.

## Optional composition route (not the native backend)

These commands make no Azure deployment changes:

```powershell
.\infra\scripts\Inspect-Deployment.ps1 -Scenario architecture-docs -Profile lite
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs -Action Validate
.\tests\Test-DeploymentContract.ps1
.\tests\Test-DeploymentPlan.ps1
terraform -chdir=infra\foundation validate
terraform -chdir=scenarios\architecture-docs\infra validate
```

The inspector selects the actual workload root and displays its model
requirements separately from the foundation. Its result explicitly says
`deployment_ready: false` because inspection checks configuration only.
Continue with preflight and planning to check the actual environment.

The composition entry point has `Inspect`, `Validate`, `Preflight`, `Plan`,
`BuildImages` and `InitializeKnowledge` operations.
It intentionally has no automatic apply operation. Planning requires real
operator inputs; examples are rejected before contacting Azure. Foundation,
access and workload are separate selectable components. Access/workload planning
requires actual applied foundation outputs and refuses a fabricated replacement.
Saved binary plans and input files are sensitive operational artifacts under
ignored `out/`; protect them and do not commit them.

Workload inputs are declared by the selected scenario, not imposed by the
foundation. Architecture-docs currently requires two immutable ACR images and
explicit librarian UPNs/object IDs, with a scenario-owned reference-date default.
Both application images are required. The workload plan
uses the real access-stage output and rejects a different foundation or stale
roster. Verify effective access with a non-admin participant account after applying.

The [runtime declaration](../scenarios/architecture-docs/infra/runtime.tf) gives
backend and toolkit distinct identities. Both can pull from the selected ACR;
only backend gets document-container-scoped Blob Data Contributor. Both apps use
one warm replica and explicit Entra/Blob settings. The
[workload identity declaration](../scenarios/architecture-docs/infra/identity.tf)
creates its own API application, team/project grants and separate human-only
librarian role. The CLI delegated scope is explicitly pre-authorized; no secret
client credential or automatic operator/librarian grant is created.

The workload configures the applications, gateway/catalog/tools, Search ingestion
and knowledge initialization.
Budget monitoring and teardown remain under the subscription owner's control.
Native project tracing connections and ingestion grants are declared in the
foundation; verify ingestion by opening a real agent trace.

The B4 cache branch is a real opt-in workload deployment:
`workload_inputs.semantic_cache_enabled: true`. It creates Balanced_B0 Redis
with RediSearch, EnterpriseCluster/NoEviction, TLS and no HA, plus a Key
Vault-backed APIM connection and selected embedding backend. APIM does not
support Entra authentication to Redis: the key stays in sensitive state/Key
Vault, and the gateway gets secret-scoped read access. The deployment operator's
secret-management role is declared too. No cache policy is pre-solved; the
exercise must use `embeddings-backend-auth="system-assigned"`. Another workload's
active external cache is rejected rather than overwritten.

Before enabling this branch, check `Microsoft.Cache` provider registration,
approve its cost/key-auth requirements and plan a live cache test.

## Linux workstations and Azure Cloud Shell

The composition scripts run in **PowerShell Core 7.5+**, including on Linux.
Bash can launch them; PowerShell syntax is not Bash syntax. Terraform must be
>=1.9 and <2.0, with Azure CLI and the required Azure/Graph permissions.
Image builds use remote `az acr build --platform linux/amd64`; a local Docker
daemon is not required.

For Cloud Shell, select **Mount storage account**, not an ephemeral session.
Use approved persistent storage, with bootstrap resources reviewed separately
from the hack deployment. Before uploading private source or inputs, verify
the shell's actual processing region, not only the storage account's region.
Only France Central, Sweden Central and West Europe are approved here.
Keep the checkout, `out/`, plans, receipts and state on the mounted drive.
Existing Azure sign-in does not prove Graph consent or deployment permission.
See [Cloud Shell persistence](https://learn.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage).

**Linux/Cloud Shell deployment commands have not yet been tested end to end.**
Use the tested Windows path if needed. Cloud Shell processing can be in a
different region from its storage account: check `$ACC_LOCATION` in Bash
(or `$env:ACC_LOCATION` in PowerShell) before uploading private inputs.

From the repository directory, these are **Bash** launch commands:

```bash
pwsh --version
terraform version
az version
mkdir -p out
test ! -e out/deployment.private.json || { echo "Keep your existing inputs"; exit 1; }
cp infra/deployment.example.json out/deployment.private.json
# Edit the private JSON: actual target, team names, roster and regions.
pwsh -NoLogo -NoProfile -File ./infra/scripts/Invoke-Deployment.ps1 \
  -Scenario architecture-docs -Action Preflight -PreflightScope Infrastructure \
  -Inputs ./out/deployment.private.json
pwsh -NoLogo -NoProfile -File ./infra/scripts/Invoke-Deployment.ps1 \
  -Scenario architecture-docs -Action Plan -Component Foundation \
  -Inputs ./out/deployment.private.json
```

In PowerShell on Linux, use the same commands as below with `/` in paths.
Do not copy Windows `C:\...` paths or Bash `export` statements into that shell.
Clone the repository or use a source archive from the selected commit. Keep
private deployment inputs and machine credentials out of source control.

Planning prints the exact backend/state, `TF_DATA_DIR`, plan path and SHA256.
All reviewed applies must retain those exact values; do not use an ambient
default backend. A Cloud Shell disconnect is not proof a process stopped.
Before resuming, inspect the original process, state lock and any recorded ACR
run ID. Do not blindly force-unlock state or queue duplicate builds. Persistent
local state is not a shared remote backend.

### Wrapper foundation: read-only checks, then save a plan

### Optional composition-script plan (PowerShell 7.5+)

Run from the repository's `hackathon` folder:

```powershell
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs -Action Inspect
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs -Action Validate
.\tests\Test-DeploymentContract.ps1
.\tests\Test-DeploymentPlan.ps1

New-Item -ItemType Directory -Path .\out -Force | Out-Null
if (Test-Path .\out\deployment.private.json) { throw 'Keep your existing private inputs.' }
Copy-Item .\infra\deployment.example.json .\out\deployment.private.json
# Edit the private JSON before the following commands.
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Preflight -PreflightScope Infrastructure -Inputs .\out\deployment.private.json
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Foundation -Inputs .\out\deployment.private.json
```

Do not overwrite an existing private input file with the example. Replace the
target GUIDs, suffix and publisher contact email. Choose team
keys now; their member arrays may be empty during infrastructure checks,
foundation planning and image builds. Infrastructure preflight explicitly defers
participant/publisher identity checks; it is not a full preflight pass.
Access/workload planning requires the complete roster. `organization_name`, librarian selection
and foundation-registry image digests are also required before workload planning.
Review fixed services and inference costs before applying.

The foundation command prints the exact saved-plan path, SHA256, state path and
`TF_DATA_DIR`. In this shell set `$foundationPlan` to that **exact printed saved
plan path** and `$foundationData` to that **exact printed `TF_DATA_DIR`** (quoted
absolute strings). Do not use the native values from section 3. Record both and
the printed state path privately. To inspect without applying:

```powershell
$env:TF_DATA_DIR = $foundationData
terraform -chdir=infra\foundation show -no-color $foundationPlan
Get-FileHash -LiteralPath $foundationPlan -Algorithm SHA256
```

Before applying the saved plan, check:

- Correct tenant/subscription, regions, names and team projects.
- APIM/Search/ACR/ACA SKUs, warm replicas and **all** ongoing costs.
- No scenario models/apps in foundation; Search is present for this scenario.
- No unexpected destroy/replace actions, broad participant roles or missing
  identity grants. Review custom role actions, not just role names.
- Optional Redis stays off unless its provider, cost and access-key exception
  were approved. Preflight never registers providers or repairs permissions.

**STOP:** publication of a tested candidate, approval of this live target and
approval of this exact plan/hash must all exist before apply. With the retained
wrapper backend/data directory, the foundation apply is:

```powershell
$env:TF_DATA_DIR = $foundationData
terraform -chdir=infra\foundation apply $foundationPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve foundation state.' }
```

### Wrapper access, immutable images and workload

Access and workload plans come **after** the jointly applied foundation:

```powershell
# Once real participant accounts and the selected human publisher are ready:
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Preflight -PreflightScope Full -Inputs .\out\deployment.private.json
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Access -Inputs .\out\deployment.private.json
```

Set `$accessData` and `$accessPlan` from this plan's printed values, not the
foundation/native context. Review the saved plan and hash, then **STOP for joint
approval** of complete roster, roles/actions/scopes and the M2 fix before apply:

```powershell
$env:TF_DATA_DIR = $accessData
terraform -chdir=infra\access show -no-color $accessPlan
Get-FileHash -LiteralPath $accessPlan -Algorithm SHA256
# Run the next command only after the separate plan approval.
terraform -chdir=infra\access apply $accessPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve access state.' }
```

After foundation apply, builds may also precede access while the roster is
pending. **STOP for explicit billable-build approval**, then:

```powershell
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action BuildImages -Inputs .\out\deployment.private.json
```

**Expected:** both actual foundation-registry digests in the printed
`runtime-images.json` and source/build receipts. Copy that exact object into
`workload_inputs.runtime_images` in the same private inputs. Supply the actual
organization name and selected human librarians too. Never plan with invented
digests or treat build success as acceptance.

```powershell
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Workload -Inputs .\out\deployment.private.json
```

Set `$workloadPlan` and `$workloadData` from the workload's printed values.
Review its plan/hash including models, images, identities, knowledge mutations
and optional Redis costs. **STOP for separate workload approval**, then:

```powershell
$env:TF_DATA_DIR = $workloadData
terraform -chdir=scenarios\architecture-docs\infra show -no-color $workloadPlan
Get-FileHash -LiteralPath $workloadPlan -Algorithm SHA256
# Run the next command only after the separate plan approval.
terraform -chdir=scenarios\architecture-docs\infra apply $workloadPlan
if ($LASTEXITCODE -ne 0) { throw 'Stop: preserve workload state.' }
terraform -chdir=scenarios\architecture-docs\infra output -json knowledge
```

Workload apply invokes the same bounded knowledge initializer described in
section 6. Do not automatically follow it with `-Action InitializeKnowledge`;
that action repeats mutating reset/run work and requires separate approval.

For each participant and selected human publisher, verify an enabled account in
the target tenant, accepted guest invitation where applicable, and working
target-tenant sign-in/MFA. Use the actual tenant UPN or object ID. A coach can be
the selected human publisher; participants need only their team assignment.

There is deliberately no wrapper `Apply` action: direct Terraform applies above
preserve the printed component backend/`TF_DATA_DIR` and exact approved plan.
Do not share state, full plan JSON or private roster files with participants.

## 8. Verify as operator, then as a non-admin participant

Use the [export steps](exercise-readiness.md#export-after-the-workload-is-applied)
with `$foundationData` and `$workloadData` from the **chosen route** to produce one
team input pack. Native and wrapper output envelopes are the same; their
state/data directories are not. Export is a local handoff, not access proof.

After the user's **new deployment containing the targeted IaC fix**, sign in as
a real non-admin test participant in its own session. Follow
[M2](modules/m2-tools.md): create a new team-owned Foundry MCP connection and
read it back, then exercise actual REST/MCP calls. Record deployment/candidate,
team/project, test identity, operation/result and time without tokens.
Verify the intended grant applies to the complete roster, not just Alpha.
**STOP acceptance** if creation/readback fails. A local Terraform test, admin
success, configured assignment or Alpha-only live grant cannot close this gate;
old reference evidence cannot substitute for this new-deployment check.

Then verify non-admin M1 models/traces, M3 policy authoring, M4 catalog writes,
proposal save/readback and a short knowledge query with actual source citations.
Keep librarian publication separate and after baseline collection.

- Start with subscription compatibility and preflight; check the following
  after applying the foundation, access and workload stages.
- No unexplained or functional Terraform changes on a fresh repeat plan.
- Every actual assignment is checked; propagation and non-admin effective access
  are tested separately from configured-role existence.
- Actual model call, gateway limits, APIs, both MCP paths and catalog access work.
- Search service authentication and embedding access work; B1 has a real,
  executable indexing/knowledge path. Exercise steps may build their intended
  artifacts, but may not require unplanned infrastructure or elevated grants.
- Record any incomplete checks so the deployment team can follow up.
- Allow time for provisioning, role propagation and service checks.
- Note environment-specific quotas, subscription policy and billing currency.

Five recovered reference E2E cycles are historical reference evidence, not five
fresh human deployments or a clean uninterrupted run. Preserve recovery notes.
Local tests, read-only preflight, image builds, Terraform apply, current reference
E2E and non-admin acceptance are different evidence classes; report each
separately. Do not claim today's new-deployment gate passed until it actually did.

## Continue to the exercises

Export a team pack using the [export steps](exercise-readiness.md#export-after-the-workload-is-applied)
and share [Participant: start here](../PARTICIPANT-START.md).
M1-M5 build and test the agents after deployment. M5 explains how to interpret
evaluation results and continue the workshop when an attempted run does not pass.
