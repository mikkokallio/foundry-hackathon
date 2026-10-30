# AI platform hackathon

> [!WARNING]
> **PREVIEW - for customer review and controlled deployment testing.**
> Minor changes to the M1-M5 exercises and instructions are likely.
> Some initial setup / Module 0 changes may also be needed as deployment
> validation continues. This is not a final, fully verified workshop release.
> Review the [known blockers and verification status](docs/exercise-readiness.md)
> before deploying. Pin the reviewed commit and re-review affected plans when
> applying updates; do not change source or inputs during an active apply.

This repository is the replacement implementation. Earlier sibling projects
were reference material, not the deployment source.

**Customer handoff: Module 0 is available for a controlled deployment trial,
not yet a fully verified clean-deployment release.** The latest fresh instance
applied its foundation and access stages and built its images. Workload
provisioning is blocked by repeated Azure API Management MCP-tool HTTP 502
responses; an earlier Microsoft Graph timeout also required a reviewed resume
plan. See the [current evidence and known blockers](docs/exercise-readiness.md).
Do not treat a partial apply as success.

Module 0 deployment readiness is separate from M1-M5 curriculum qualification.
Customers can test their subscription's deployment compatibility before the
later exercises are fully qualified. Operational prerequisites and actual
participant access must still be checked before running the affected exercises.
Infrastructure changes remain limited to explicitly reviewed targeted fixes,
not a redesign or an implied guarantee of no further fixes.

For the participant curriculum, start with [Participant: start here](PARTICIPANT-START.md).
The curriculum is work in progress: live browser rehearsal and genuine Foundry
smoke/regression qualification are still in progress. A Git push is a source
backup, not a readiness or deployment approval.

Local environments, Terraform state/inputs, exported packs, Foundry runtime
evidence/caches and the original organizer handoff ZIP/notes are intentionally
not committed. Export fresh packs for the actual deployment; do not reconstruct
credentials or acceptance evidence from this repository.

## Customer deployment: components and policy checklist

The lab uses **public, identity-protected endpoints** and synthetic workshop
data. Review the following resource types, permissions and policy requirements
with your deployment team.

This inventory covers the foundation plus the selected `architecture-docs`
workload, not just the services participants create during exercises.

| Component | Azure resource type / provider | Current configuration and purpose |
|---|---|---|
| Dedicated resource groups | `Microsoft.Resources/subscriptions/resourceGroups` | Foundation, workload runtime, extension-authoring boundary and separate surviving protection group. Use new lab groups, not production groups. |
| Microsoft Foundry | `Microsoft.CognitiveServices/accounts`, `/projects`, `/deployments` | AIServices S0 account, team/facilitator projects and workload-owned chat, judge and embedding deployments. Model/version/SKU/capacity are explicit deployment inputs; verify quota and availability. |
| API Management | `Microsoft.ApiManagement/service` | BasicV2 capacity 1 in the rehearsed `lite` profile; StandardV2 capacity 1 in the alternative profile. Public gateway, managed identity, model/API routes, policies, native MCP APIs/tools and project connections. Not the separate preview AI Gateway resource. |
| API Center | `Microsoft.ApiCenter/services` | Free tier; API/MCP catalog registrations, versions, definitions and metadata. |
| Azure AI Search | `Microsoft.Search/searchServices` | Basic, one replica/partition, Entra authentication; indexes, indexers, embedding/vectorizer and preview knowledge source/base/MCP connection. Required for this scenario even if B1 is not attempted. |
| Blob Storage | `Microsoft.Storage/storageAccounts` | Standard LRS; shared keys and anonymous blob access disabled. Synthetic documents/proposals/templates/glossary and Search ingestion. |
| Key Vault | `Microsoft.KeyVault/vaults` | Standard, RBAC; seven-day soft delete and purge protection disabled in the current disposable-lab profile. Check any policy requiring purge protection. |
| Container Registry | `Microsoft.ContainerRegistry/registries` | Basic, admin account disabled; remote Linux image builds and immutable application images. Build access to required base-image/package registries is needed. |
| Container Apps | `Microsoft.App/managedEnvironments`, `/containerApps` | Shared environment and two externally reachable authenticated apps: documentation backend and toolkit. Each app has one replica, 0.25 vCPU and 0.5 GiB. Separate extension group supports B2 authoring. |
| Content Safety | `Microsoft.CognitiveServices/accounts` | Separate ContentSafety S0 account and gateway backend for B4. This prerequisite is provisioned even if the bonus is not attempted. |
| Traces and logs | `Microsoft.OperationalInsights/workspaces`, `Microsoft.Insights/components` | Log Analytics PerGB2018 and workspace-based Application Insights, project connections and ingestion/query grants. |
| Spending/expiry protector | `Microsoft.Automation/automationAccounts` | Basic account, managed identity, PowerShell runbook, variables and schedules. Reads whole-subscription costs and can delete explicitly enrolled disposable lab groups. |
| Monitoring | `Microsoft.Insights/diagnosticSettings`, `/actionGroups`, `/metricAlerts` | Application/container diagnostics and protector alerting. |
| Identity and authorization | `Microsoft.ManagedIdentity/userAssignedIdentities`, `Microsoft.Authorization/roleDefinitions`, `/roleAssignments` | Application/service managed identities, scoped runtime/participant grants and custom authoring/protection roles; some definitions/grants are subscription-scoped. |
| Optional semantic cache | `Microsoft.Cache/redisEnterprise`, `/databases` | Only when `semantic_cache_enabled` is true: Balanced_B0, RediSearch, TLS, no HA, public endpoint and explicitly enabled access-key authentication, with a Key Vault-backed APIM connection. Separate cost/key-policy approval required. |

**Entra tenant changes are also required:** workload app registration, service
principal, exposed delegated scope, Azure CLI preauthorization and application
role assignments for teams, gateway and separately selected human librarians.
Azure subscription permissions alone do not authorize these tenant operations.
Participant grants are direct roster assignments, not membership in a workshop
group, and shared-service authoring is not hard team isolation.

**Before applying in a customer subscription, check:**

- **Policy and regions:** allow the listed resource providers, child-resource
  types, SKUs and public endpoints, including Storage, Key Vault, Search, ACR,
  Automation and Container Apps ingress. France Central is preferred; Sweden
  Central and West Europe are supported selections. Validate each service/model
  in the selected region. A public-endpoint exception for one service does not
  automatically cover the rest. Review model deployment SKU/data-processing
  geography separately: a `GlobalStandard` deployment in a European resource
  region is not a guarantee of EU-only inference processing.
- **Operator rights:** resource creation, custom-role definition and assignment
  rights at the plan's actual scopes, subscription cost reads, and tenant-approved
  Graph/app-registration/app-role operations. Resource-group Contributor alone
  is insufficient. Have administrators approve/register missing providers;
  preflight does not silently register them or repair permissions.
- **Quota and network access:** model deployments/TPM, Search, APIM and container
  capacity; operator/participant access to Azure, Entra, package sources and
  required public service endpoints. No private-endpoint/VNet alternative is
  provided by the frozen profile.
- **Shared-subscription spending and deletion:** current protection uses EUR and
  whole-subscription month-to-date costs, including unrelated existing spend.
  Customer-approved limits, reserve and expiry must fit that subscription;
  do not copy organizer limits or an old expiry. Explicitly approve deletion of
  only the new enrolled disposable groups and their data on cutoff, expiry or
  cost-visibility failure. The monitoring group survives; delayed billing means
  this is not a guaranteed hard cap. Review the saved plan's exact scopes.
- **Execution and evidence:** run [Module 0](docs/module-0.md)'s read-only
  preflight, then review separate foundation/access/workload plans before any
  apply. Retain private state and failure receipts. The fresh MCP 502 blocker
  remains open; a successful preflight is not proof of a complete deployment.

Linux/Cloud Shell commands are supplied but **not deployment-tested**; the
actual Cloud Shell trial could not establish an approved processing region and
used the authorized local Windows fallback. Cloud Shell storage is an optional,
separately approved portal prerequisite, not silently added by these Terraform
roots. B6 remote-state/OIDC integration and B9 hosting are also not automatically
provisioned by Module 0; the optional B9 reference runs locally.

## Deployment boundaries

- **Foundation:** reusable services and infrastructure capabilities. No scenario
  imports, document APIs, agents, prompts, model deployments or hard-coded model
  choices. Shared project tracing is a foundation capability.
- **Selected workload:** its model deployments, applications, APIs, MCP tools,
  data containers, Search indexes, knowledge sources, connections, permissions,
  prompts and evaluations.
- **Composition:** select a scenario at deployment time. Its declared requirements
  select the necessary foundation capabilities; deploy the foundation and then
  the workload, with separate Terraform ownership and reviewed plans.

The architecture-docs scenario requires Azure AI Search. Optional participation
in the knowledge exercise does **not** make its prerequisites optional.

Start with [Module 0's inventory and acceptance requirements](docs/module-0.md).
The [infrastructure contract](infra/README.md) defines the separation. Neither
document is a claim of working code or live verification.
The [exercise-readiness audit and input pack](docs/exercise-readiness.md) covers
all core/bonus activities, reusable materials and the remaining post-TF work.

## Current code

- [Generic foundation](infra/foundation/) contains no model deployments.
- [Selected architecture-docs workload](scenarios/architecture-docs/infra/)
  owns its models, data container, API identity, app identities and runtime.
- [Access stage](infra/access/) resolves deployment-time membership and declares
  scoped grants; [its small module](infra/modules/participant-access/) is tested
  independently of AVM internals.
- [Scenario-selecting entry point](infra/scripts/Invoke-Deployment.ps1) supports
  local inspection/validation and separate saved plans. It has no automatic
  apply operation.
- [Reference reuse record](docs/reuse-evidence.md) distinguishes evidence from
  assumptions and components not yet adopted.

Runtime applications, API/MCP/catalog wiring, Search ingestion/knowledge setup,
extension authoring permissions, Content Safety/model-pool prerequisites,
read-only preflight and independent spending/expiry protection are implemented
locally. Current-source images built in the existing ACR and passed local
startup/authentication checks. Isolated replacement deployment, cloud protection
and several real runtime paths are verified; complete lifecycle cleanup,
non-admin participant rehearsal and genuine Foundry acceptance remain unaccepted.

The optional Redis branch is selectable with
`workload_inputs.semantic_cache_enabled: true`; it defaults to off and requires
explicit cost review before enabling it. Its workload resources include RediSearch, a Key Vault-backed
APIM connection, scoped secret grants and an embedding backend. It does not
activate caching policies or permit cached responses as Foundry evaluation
evidence. APIM currently requires a Redis access key; that exception is explicit.

Set `workload_inputs.organization_name` in your deployment inputs to your chosen
real or fictional name. There is no default company name. Both apps receive
`ORGANIZATION_NAME`; the API display text, MCP instructions and documentation
standard use it. Lab business data remains synthetic and contact addresses use
the reserved `.invalid` domain.

## Authority and safety

The organizer's decisions override the original handoff and earlier code.
Conflicting requirements are surfaced, not silently dropped. The supplied ZIP,
notes and attached editor snapshots are reference material and remain unchanged.

No whole-repository copying, copied Terraform state, migration of the old lab,
automatic apply, production-data access, publication, or new paid environment is
authorized by the local build. Old infrastructure still incurs charges until
separately reviewed; its costs cannot be ignored when considering a new deployment.
The protector deletes explicitly enrolled disposable resource groups, including
their document data, on expiry, buffered-cost cutoff or cost-visibility failure. Its monitoring group
survives. Delayed PAYG billing means it is not a guaranteed hard spending cap.
