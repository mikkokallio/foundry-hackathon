# Infrastructure ownership contract

> [!WARNING]
> **PREVIEW.** Initial setup may still need targeted fixes during deployment
> validation. See the [repository preview notice and deployment checklist](../README.md)
> and [known blockers](../docs/exercise-readiness.md) before planning or applying.

## Composition

The deployment entry point selects `scenarios/<scenario>/scenario.json` and the
scenario's Terraform root. It must not import a scenario API or application into
the foundation root.

1. Validate the scenario contract, operator configuration and deployment-time
   roster.
2. Resolve work-account UPNs or object IDs in the explicitly selected tenant.
3. Check permissions, resource providers, policy restrictions, regions, model
   availability/quota, budget protection and authorization expiry.
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

The current entry point uses explicit local backends under
`out/<subscription-id>/<suffix>/state/`, with distinct foundation/access files
and a file per workload name. Provider/backend working directories are isolated
under the same deployment directory; no component reads an ambient default
state. A workload name is reserved to its scenario so a second scenario cannot
silently assume ownership of its model/application namespace. Plans are saved in
that deployment's `plans/` directory. Back up these protected state files before
destruction or moving machines. Remote-state/OIDC integration remains B6 work;
this is not a shared-team remote backend.

Native Terraform is supported and preferred for transparent review. In a fresh
terminal run `terraform -chdir=infra\foundation init`, then
`terraform -chdir=infra\foundation plan`. Terraform itself prompts for required
variables, including profile (which has no default). It prompts once per
top-level variable; objects/lists are entered as a whole, not field-by-field.
There is no shell input wizard.

Core and Search regions default to France Central (`francecentral`). Only
`francecentral`, `swedencentral` and `westeurope` are allowed; North Europe is banned.

With the native default local backend, each root keeps its own
`terraform.tfstate`. For multiple environments select a separate backend
configuration per environment. The optional PowerShell composition path instead
uses the `out/` state layout described above and prints `TF_DATA_DIR`. **Do not
mix these state locations for one deployment**, migrate old state, or apply a
plan against a different backend. All applies remain explicitly reviewed.

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
| `Preflight` | Read actual Azure/Graph configuration, quotas and subscription costs; write a local receipt. No provider registration or role repair. |
| `Plan -Component Foundation` | Save the foundation plan; requires team keys and reviewed protection limits, not participant emails yet. |
| `Plan -Component Access` | Resolve the complete real roster against the applied foundation. |
| `BuildImages` | Explicitly build/push into the selected applied foundation ACR and record source/digest receipts. Billable; separate approval required. |
| `Plan -Component Workload` | Save the selected scenario plan using applied foundation/access and immutable images. |
| `InitializeKnowledge` | Reset/run actual Search indexers, verify fresh successful ingestion, then create knowledge/MCP connections. Mutating; separate approval required. |

There is no `Apply` action. Joint application must use the exact approved saved
plan with its printed component backend and `TF_DATA_DIR`. Successful preflight
or local tests are not deployment approval or live acceptance. The independent
protector deletes enrolled disposable groups, including documents; its monitoring
group survives. Delayed billing prevents a guaranteed hard spending cap.

Preflight CLI reads have a 35-second deadline and at most one logged transient
retry. Persistent Graph transport failure stops further roster lookups and fails
the receipt; it never substitutes cached users. Redis is workload opt-in via
`workload_inputs.semantic_cache_enabled`; it requires separate provider/cost
review and the documented Key Vault-backed access-key exception.

The native workload initializes Search knowledge through the bounded initializer
because the pinned AzAPI provider lacks those GA resource types. Its Terraform
destroy hook removes the private knowledge connections, base and source before
deleting the index; otherwise Search rejects the index deletion.

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
| Budget/expiry protection and operational diagnostics | Workload token limits and incremental cost envelope |

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
