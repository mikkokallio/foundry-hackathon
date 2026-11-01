# Infrastructure ownership contract

> [!NOTE]
> **Preview.** Deployment testing may lead to targeted setup fixes.
> See the [deployment checklist](../DEPLOY-NEXT.md), the ordered
> [deployment walkthrough](../docs/module-0.md), and
> [deployment notes](../docs/exercise-readiness.md) for practical guidance.

## Composition

The deployment entry point selects `scenarios/<scenario>/scenario.json` and the
scenario's Terraform root. It must not import a scenario API or application into
the foundation root.

1. Validate the scenario contract, operator configuration and deployment-time
   roster.
2. Resolve work-account UPNs or object IDs in the explicitly selected tenant.
3. Check permissions, resource providers, policy restrictions, regions, model
   availability/quota and ongoing service costs.
4. Produce the foundation plan and explain its complete resource/permission list.
5. Apply only the reviewed plan after explicit organizer approval.
6. Pass a versioned, non-secret foundation output contract to the selected
   workload root. Do not copy a state file or put credentials in the contract.
7. Build workload images explicitly and record immutable digests. Plan and apply
   must use the same selected artifacts, not mutable tags or an implicit rebuild.
8. Produce and review the workload plan separately; apply only after approval.
9. Run real service/repeat-plan checks and verify effective non-admin access.
   Record deployment acceptance separately from the later curriculum and genuine
   Foundry smoke/regression/provenance qualification. Customer deployment trials
   do not require M1-M5 to be fully qualified first; failed infrastructure checks
   still block the affected exercises.

Foundation and workload have separate state. Workload destruction must not
destroy the foundation; removing a workload must not remove another workload's
resources. No hidden shell commands may create unmanaged Azure resources.
Local state must be ignored and protected; remote state is an explicit supported
choice, not silently provisioned storage with a shared key.

The **optional composition entry point** uses explicit local backends under
`out/<subscription-id>/<suffix>/state/`, with distinct foundation/access files
and a file per workload name. Provider/backend working directories are isolated
under the same deployment directory; no component reads an ambient default
state. A workload name is reserved to its scenario so a second scenario cannot
silently assume ownership of its model/application namespace. Plans are saved in
that deployment's `plans/` directory. Back up these protected state files before
destruction or moving machines. Remote-state/OIDC integration remains B6 work;
this is not a shared-team remote backend.

Native Terraform is supported and preferred for transparent review. Follow
[Module 0](../docs/module-0.md#3-native-foundation-inputs-plan-approval-apply)
for private native variable files, exact saved plans, retained component context
and approval/apply commands across all three roots. Without variable files,
Terraform itself prompts for required variables, including profile (which has
no default). It prompts once per
top-level variable; objects/lists are entered as a whole, not field-by-field.
There is no shell input wizard.

An existing deployment must retain its recorded backend/state and `TF_DATA_DIR`,
regardless of which route is preferred for a new deployment. A fresh terminal
does not select the correct existing state. Do not execute candidate commands
before publication, and do not infer live target or apply approval from
publication, a passing test or preflight.

Core and Search regions default to France Central (`francecentral`). Only
`francecentral`, `swedencentral` and `westeurope` are allowed; North Europe is banned.

With the native default local backend, each root keeps its own
`terraform.tfstate`. For multiple environments select a separate backend
configuration per environment. The optional PowerShell composition path instead
uses the `out/` state layout described above and prints `TF_DATA_DIR`. **Do not
mix these state locations for one deployment**, migrate old state, or apply a
plan against a different backend. All applies remain explicitly reviewed.

Infrastructure-only preflight permits foundation planning before a customer
roster exists; its receipt explicitly defers identity checks and cannot claim
Full readiness. Sunday's rehearsal uses the existing approved test environment
and existing test roster. Monday's customer access/workload require complete
actual accounts/team assignments and explicit human librarian selection.

**Open acceptance gate:** verify non-admin M2 connection creation and readback
after the user's new deployment containing the targeted project-scoped IaC fix.
Source/local validation and Alpha-only manual connection-write access cannot
close it. Review the exact custom action and per-team scope in the access plan;
retain existing Azure AI User access rather than broadening to Contributor.

Knowledge cleanup verifies absence before finishing. GET requests interrupted
by HTTP client timeouts have at most three attempts within the overall cleanup
deadline. Authorization failures, caller cancellation and uncertain DELETE
outcomes remain errors; DELETE is never automatically retried. After an
interrupted destroy, reconcile the owned resources and review a fresh destroy
plan from the same isolated state, not the stale saved plan. Cleanup-script
changes participate in the knowledge initializer's replacement trigger, so
review and requalify that scoped replacement before applying to an existing
environment.

### Preview reference settings

The preview reference configuration uses one Basic v2 API Management unit and
Azure AI Search S1 with three replicas and one partition. Semantic ranker and
agentic retrieval use standard billing. Redis provides the B4 prerequisite;
teams add the cache policies during the exercise. Check regional availability,
quota and pricing before applying your reviewed plan.

Search settings are independent of the gateway profile. For native foundation
Terraform, include these values in your private `.tfvars` file alongside the
other deployment inputs:

```hcl
profile = "lite"
search_configuration = {
  sku                 = "standard"
  replica_count       = 3
  partition_count     = 1
  semantic_search_sku = "standard"
  knowledge_retrieval = "standard"
}
```

Here `standard` is the Search S1 tier. Without overrides, existing inputs retain
Basic Search with one replica and one partition, with semantic billing selected
by the profile. Omitting `knowledge_retrieval` leaves agentic billing unmanaged;
to switch previously enabled paid agentic retrieval back, explicitly set it to
`"free"`. Semantic ranker billing is a separate setting.

The [composition input example](deployment.example.json) shows these settings
alongside the workload's model overrides and Redis selection. It is not a native
foundation variable file: native workload Terraform takes the model map as
`models` and the B4 switch as `semantic_cache_enabled`. The reference allocations
are 300 units each for `chat-small` and `chat-medium`, 75 for `judge`, and 20 for
`embedding`; units are model/SKU-specific, not a universal TPM measure. Other
required identities, outputs and image digests still come from your deployment.

Workspace retention remains 30 days. Log Analytics and Application Insights have
no daily ingestion cutoff; financial monitoring and teardown remain under the
subscription owner's control.

## Explicit stages

Linux and Cloud Shell use the same PowerShell Core 7.5+ orchestration, not a
separate Bash deployment implementation. Bash launches it with
`pwsh -NoProfile -File ./infra/scripts/Invoke-Deployment.ps1 ...`.
Use native Linux paths and preserve the printed state/backend/data directory.
Cloud Shell additionally requires approved mounted storage and processing-region
verification before private inputs are uploaded. Remote ACR builds need no local
Docker daemon. See [Module 0's Linux/Cloud Shell steps](../docs/module-0.md#linux-workstations-and-azure-cloud-shell)
for startup, private-source handling and reconnect boundaries.

Use the scenario-selecting entry point with `-Scenario architecture-docs` and
your private deployment JSON passed as `-Inputs`.

| Action | Effect |
|---|---|
| `Inspect` / `Validate` | Inspect composition or initialize providers and validate local code; no Azure deployment. |
| `Preflight -PreflightScope Infrastructure` | Check actual Azure/Graph operator prerequisites and quotas before the roster is ready. Receipt explicitly defers participant/publisher identity checks. |
| `Preflight` / `Preflight -PreflightScope Full` | Also resolve the complete roster and selected human publishers; required before Access/Workload. No provider registration or role repair. |
| `Plan -Component Foundation` | Save the foundation plan; requires team keys, not participant emails yet. |
| `Plan -Component Access` | Resolve the complete real roster against the applied foundation. |
| `BuildImages` | Explicitly build/push into the selected applied foundation ACR and record source/digest receipts. Billable; separate approval required. |
| `Plan -Component Workload` | Save the selected scenario plan using applied foundation/access and immutable images. |
| `InitializeKnowledge` | Reset/run actual Search indexers, verify fresh successful ingestion, then create knowledge/MCP connections. Mutating; separate approval required. |

There is no `Apply` action. Joint application must use the exact approved saved
plan with its printed component backend and `TF_DATA_DIR`. Successful preflight
or local tests are not deployment approval or live acceptance. Budget monitoring
and teardown remain under the subscription owner's control.

Preflight CLI reads have a 35-second deadline and at most one logged transient
retry. Persistent Graph transport failure stops further roster lookups and fails
the receipt; it never substitutes cached users. Redis is workload opt-in via
`workload_inputs.semantic_cache_enabled`; it requires separate provider/cost
review and the documented Key Vault-backed access-key exception.

The native workload initializes Search knowledge through the bounded initializer
because the pinned AzAPI provider lacks those GA resource types. Its Terraform
destroy hook removes the private knowledge connections, base and source before
deleting the index; otherwise Search rejects the index deletion.
Workload apply therefore includes indexer reset/run, fresh-ingestion checks and
knowledge/project-connection writes. Approve those effects with the workload
plan; `InitializeKnowledge` is an explicit reinitialization, not an automatically
required second apply step. Knowledge output intentionally retains
`live_accepted: false` until actual retrieval/agent acceptance.

### Native documentation MCP

The workload defines the twelve documentation tools together on the MCP API.
Canonical operation names, Entra policies and query/JSON compatibility adapters
remain in place; health and human publication are not exposed as tools.
The native MCP management API uses `2025-09-01-preview`. Its inline `mcpTools`
field is accepted by the service but not yet recognized by AzAPI's embedded
schema, so schema validation is disabled for that resource only.

When updating an existing workload state, Terraform forgets the former separate
tool addresses **without deleting their cloud resources**. The parent API then
owns the inline definitions. Keep the `removed` block for this transition and
review the fresh plan with the original workload backend/data directory; no
manual state removal or separate tool deletion is needed.

## Ownership

| Foundation owns | Workload owns |
|---|---|
| Resource groups and naming/tagging conventions | Workload-specific resource groups where needed |
| Foundry resource and generic team projects | Model deployments, versions, SKUs and capacities |
| Log Analytics and Application Insights | Application instrumentation and evaluation definitions |
| Generic project trace connections and ingestion grants | Agent-specific trace content and provenance checks |
| API Management service and generic identity/authentication | APIs, products/policies for its exercises, model routes and MCP servers |
| API Center service | API/MCP registrations, definitions and metadata |
| Container Registry and Container Apps environment | Applications, images, scaling, environment variables and application identities |
| Storage account and Key Vault service capabilities | Data containers, data contents and any justified secret values |
| AI Search service when requested by the composition | Indexes, ingestion, vectorizers, knowledge sources/bases and project connections |
| Generic team identity and baseline access | Additional permissions required by the workload's declared exercises |
| Operational diagnostics | Workload token limits and incremental cost envelope |

Foundation capability switches choose infrastructure, not model policy. Selecting
architecture-docs requests Search; a future scenario without retrieval need not
deploy Search. The foundation must never enforce `chat-small`, `judge`,
`embedding`, a document schema, a publication role or a scenario reference date.

Search stays enabled by default, independently of scenario changes. An explicit
`enable_search: false` input can turn it off only for a scenario that does not
require it. A scenario switch never silently disables this shared capability.
Removing an existing service still requires review of all consuming workloads
and its destructive Terraform plan.

Scenario-specific values are declared in `terraform_inputs` in the selected
manifest and supplied through `workload_inputs` in the operator configuration.
Unknown keys are rejected instead of becoming ignored Terraform arguments.
The architecture-docs manifest requires immutable runtime images and explicitly
selected human librarians. Its reference date is a workload default, not a
platform setting. Scenarios that require resolved participant membership declare
`requires_participant_access`; their workload plan checks the applied access
contract's target and complete roster before passing member IDs to Terraform.

## Reference reuse

Earlier code is reusable only after checking its contract, relevant tests,
observed live behavior, and suitability for this boundary. Document each adopted
component and its limitations. Passing unit tests are not deployment acceptance.
The old application's draft-copy failures and local credential/Graph failures
must not be carried over as unexplained assumptions.

Use pinned, fit-for-purpose Azure Verified Modules. Document direct-resource
exceptions. Test small local modules independently where AVM ephemeral resources
prevent root-level provider mocking. Do not manipulate state or ignore functional
drift merely to obtain a no-change plan.
