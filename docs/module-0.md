# Module 0 - Review and deploy the foundation and selected workload

**Status: local foundation/access/model/runtime declarations validate; Module 0
implementation and all live acceptance remain incomplete.** No deployment-time target, resources, costs or role
assignments are approved by this document.

The organizer reviews every part before we deploy together. Modules 1-5 are
not started until Module 0 is accepted.

## Required inventory

| Capability | Ownership | Required for |
|---|---|---|
| Explicit subscription, tenant, regions, naming overrides and tags | Composition/foundation | Customer-owned deployment; no ambient account selection |
| Deployment-time UPN/object-ID roster and enabled/accepted-user checks | Composition/access | Every module; roster need not exist before deployment |
| Resource-provider, policy, quota and operator-permission checks | Composition | Fail before partial provisioning where checks are possible |
| Whole-subscription cost awareness, verified cloud protection and expiry | Operations | Safe deployment and operation alongside existing resources |
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
| Optional semantic-cache infrastructure and complete identity/network configuration | Explicit workload option | B4 cache branch; disabled must mean clearly unavailable, not silently simulated |
| Price inputs and caller/team token dimensions | Workload/operations | B5; never fabricated prices or a promise that TPM is a billing cap |
| OIDC/remote-state setup and evaluation-gated CI | Optional delivery integration | B6; no secret credentials committed or demanded in chat |
| Coding-agent MCP configuration and CLI alternative | Workload exercise | B8; no Copilot license required for the core |
| Local-front-end prompt pack and API contract, not a prebuilt app | Workload exercise | B9 |
| Teardown, preservation boundaries and soft-delete/redeployment procedure | Operations | Jointly reviewed destruction; no automatic deletion after success |

## Scope decisions that override the old handoff

- All five core modules remain required.
- Human-approved proposal saving is core, not deferred to B7.
- Publication is a separate human operation, never an agent tool.
- AI Search and B1 prerequisites must be deployable as part of this scenario.
- Model deployments belong to the workload, not a foundation default.
- Public, identity-protected endpoints are the agreed sandbox profile, not a
  production network landing zone.
- No participant-wide resource-group Contributor by default.
- No event-time permission repair or invented placeholder users.
- No production license, public-repository release or automatic publication is
  inferred from the old handoff.
- The old "Search must never use Sweden Central" assertion requires current
  availability/capacity verification; it is not a permanent technical rule.
- Cold-start, model-capacity, API export and telemetry-publishing lessons from the
  earlier deployment must be reflected explicitly and verified again.

## Access decisions to show before implementation

Reading tools alone is not enough: M2/M3 require API-management changes, M4
requires catalog writes, B1 needs Search authoring, and B2 needs application
creation. The earlier read/export-only participant grants did not cover those
learning activities.

The permissions matrix must list each operation, principal, role and scope.
Shared-service authoring can let participants alter another team's lab resources;
that tradeoff must be approved explicitly. Do not hide it behind "least privilege"
or silently assign resource-group Contributor.

The organizer approved **service-scoped authoring on shared lab services**,
including the cross-team configuration risk. No blanket resource-group
Contributor is approved. The access Terraform accepts team membership as UPNs
or tenant object IDs and resolves the actual users with the AzureAD provider.
It is a separate reviewed stage, not hidden side effects in the foundation.
Guest invitation acceptance and effective non-admin sign-in still require
explicit preflight/rehearsal; Azure role declarations alone do not prove them.

The actual built-in APIM, API Center and Search service-contributor definitions
also permit foundation-service deletion or reconfiguration. They are therefore
not assigned wholesale: the access module declares lab-scoped custom authoring
roles that exclude service-level write/delete, while retaining child-resource
authoring. Search admin/query-key management is excluded; local auth is disabled.
Those custom role definitions and their exact actions must be reviewed before
apply, and the deployment operator needs role-definition creation rights as well
as assignment rights. Existing unrelated grants are not automatically revoked.
Search document data access remains explicit and shared for the synthetic lab.

**Workshop warning:** teams can change other teams' shared APIM/API Center/Search
configuration and synthetic Search data. Use team-prefixed names and coordinate
shared changes. These grants are not team isolation.
APIM policy authors can also alter gateway-enforced controls, including team and
librarian checks. Treat them as trusted lab operators, not isolated tenants.

B2 extension apps have a separate workload group with scoped app/identity
authoring, ACA-environment join and ACR build/push grants. Teams can modify each
other's extension apps, but these grants exclude the trusted backend/toolkit
group and identities and do not permit role assignments.

Guidance to prepare after Module 0: keep participant and coach instructions
concise and role-specific (actions, expected results, relevant troubleshooting
and this warning), without engineering logs or unrelated implementation history.

## Local implementation checks

### Preferred: native Terraform

Open a **fresh terminal** so the earlier shell `TF_DATA_DIR` setting is not
inherited. From the `hackathon` folder:

```powershell
terraform -chdir=infra\foundation init
terraform -chdir=infra\foundation plan
```

Terraform itself asks for profile, target IDs, regions, suffix, team names,
publisher email, expiry and protection inputs. No PowerShell `Read-Host`, shell
variables or `-var` selection is needed. Profile has **no default**. Terraform
asks once per top-level variable: a `set(string)` uses a list such as
`["alpha","beta"]`; the protection object is entered as one object with
`monthly_cap_eur`, `reserve_eur` and reviewed `max_hourly_eur` fields.
Terraform does not provide a recursive Bicep-style object wizard.

This uses the foundation root's normal local backend/state. Do not mix it with
the optional wrapper's separate `out/` state for the same deployment. Stop at
the plan: the destructive protector and every resource/permission still need
joint approval. The foundation creates no models.

The workload now selects GA GPT-5.4 nano/mini/full candidates and embeddings,
not Legacy GPT-4.1. Their exact versions, regional support and free quota were
read on 2026-10-29. Native workload Terraform also checks live catalog lifecycle
and retirement metadata; it rejects Legacy, deprecated, preview, retired and
unknown lifecycle status even without the PowerShell preflight.

### Optional composition checks

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
`deployment_ready: false`. Local initialization/validation is not a live plan,
working application, completed Module 0, or authorization to apply.

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
No application is silently omitted when an image is missing. The workload plan
uses the real access-stage output and rejects a different foundation or stale
roster. Applied state is not proof of effective access; the non-admin rehearsal
remains mandatory.

The [runtime declaration](../scenarios/architecture-docs/infra/runtime.tf) gives
backend and toolkit distinct identities. Both can pull from the selected ACR;
only backend gets document-container-scoped Blob Data Contributor. Both apps use
one warm replica and explicit Entra/Blob settings. The
[workload identity declaration](../scenarios/architecture-docs/infra/identity.tf)
creates its own API application, team/project grants and separate human-only
librarian role. The CLI delegated scope is explicitly pre-authorized; no secret
client credential or automatic operator/librarian grant is created.

Application sources, gateway/catalog/tool wiring, Search ingestion and explicit
knowledge initialization are implemented locally. Existing-ACR image builds and
local startup checks passed; replacement Azure behavior remains unverified.
Runtime and extension groups are explicitly enrolled in the independent
foundation spending protector. Cutoff deletes enrolled groups and their data;
the monitoring group survives. Billing is delayed: this is not a hard cap.
Native project tracing connections and ingestion grants are declared in the
foundation; live trace/provenance checks remain mandatory.

The B4 cache branch is a real opt-in workload deployment:
`workload_inputs.semantic_cache_enabled: true`. It creates Balanced_B0 Redis
with RediSearch, EnterpriseCluster/NoEviction, TLS and no HA, plus a Key
Vault-backed APIM connection and selected embedding backend. APIM does not
support Entra authentication to Redis: the key stays in sensitive state/Key
Vault, and the gateway gets secret-scoped read access. The deployment operator's
secret-management role is declared too. No cache policy is pre-solved; the
exercise must use `embeddings-backend-auth="system-assigned"`. Another workload's
active external cache is rejected rather than overwritten.

Cache provider registration, cost/secret exception approval and genuine live
cache verification are required before enabling this branch. Current target:
Microsoft.Cache is not registered; no registration was performed. Cost-visibility
failure also triggers the destructive protector; review that tradeoff before apply.

## Review order

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
  -Action Preflight -Inputs .\out\deployment.private.json
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Foundation -Inputs .\out\deployment.private.json
```

Do not overwrite an existing private input file with the example. Replace the
target GUIDs, suffix, monitored email, expiry and protection limits. Choose team
keys now; their member arrays may be empty for the **foundation plan only**.
Preflight reports missing real members/librarians as failures; access/workload
planning requires the complete roster. `organization_name`, librarian selection
and foundation-registry image digests are also required before workload planning.
Do not guess `protection.max_hourly_eur`: review fixed services, inference,
existing resources and delayed billing first.

The foundation command prints the exact saved-plan path, SHA256, state path and
`TF_DATA_DIR`. To inspect that binary plan without applying:

```powershell
# Replace with the exact path printed above; do not select "the latest" blindly.
terraform -chdir=infra\foundation show -no-color 'C:\EXACT\PRINTED\Foundation-TIMESTAMP.tfplan'
```

Stop after review; no apply is authorized by these commands. Check:

- Correct tenant/subscription, regions, names, team projects and expiry.
- APIM/Search/ACR/ACA SKUs, warm replicas and **all** ongoing costs.
- No scenario models/apps in foundation; Search is present for this scenario.
- No unexpected destroy/replace actions, broad participant roles or missing
  identity grants. Review custom role actions, not just role names.
- Protector scope, its separate surviving monitoring group, and deletion of
  document data on expiry/cost cutoff/**cost-visibility failure**.
- Optional Redis stays off unless its provider, cost and access-key exception
  were approved. Preflight never registers providers or repairs permissions.

Access and workload plans come **after** the jointly applied foundation:

```powershell
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Access -Inputs .\out\deployment.private.json
# Jointly review/apply access, then explicitly approve BuildImages or an image import.
# Supply resulting foundation-registry digests in workload_inputs.runtime_images.
.\infra\scripts\Invoke-Deployment.ps1 -Scenario architecture-docs `
  -Action Plan -Component Workload -Inputs .\out\deployment.private.json
```

There is deliberately no generic `terraform apply` shortcut here: applying must
preserve the printed component backend/`TF_DATA_DIR` and exact approved plan.
Do not share state, full plan JSON or private roster files with participants.

1. Requirements inventory and foundation/workload ownership.
2. Every resource, SKU, region, model, capacity and incremental cost.
3. Complete human and managed-identity permissions.
4. Input/roster resolution, preflight and independent budget protection.
5. Foundation Terraform plan.
6. Workload artifact build and workload Terraform plan.
7. Joint apply, with explicit approval at each mutation boundary.
8. Readiness evidence and non-admin acceptance.

## Acceptance, not just successful apply

- No unexplained or functional Terraform changes on a fresh repeat plan.
- Every actual assignment is checked; propagation and non-admin effective access
  are tested separately from configured-role existence.
- Actual model call, gateway limits, APIs, both MCP paths and catalog access work.
- Search service authentication and embedding access work; B1 has a real,
  executable indexing/knowledge path. Exercise steps may build their intended
  artifacts, but may not require unplanned infrastructure or elevated grants.
- Fresh Foundry smoke and regression evaluations pass unchanged thresholds with
  real response IDs, matching agent versions and actual tool spans. Evidence,
  evaluation IDs and failure clusters stay under the selected agent's `.foundry/`.
- No skipped, mocked, cached-response, incomplete or cancelled acceptance is a pass.
- Deployment duration and repeatability are measured, not promised as 30 minutes.
- Customer-specific quotas, subscription policy and billing currency limitations
  are reported explicitly.
