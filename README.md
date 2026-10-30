# AI platform hackathon

This repository is the replacement implementation. Earlier sibling projects
were reference material, not the deployment source.

**Status: an authorized isolated native Terraform apply and service checks have
run successfully. Module 0 is NOT accepted: genuine agent evaluation and complete
clean lifecycle rehearsals still have failures.** Rehearsals are not customer
deployment approval. Modules 1-5 follow only after Module 0 acceptance.

For the participant curriculum, start with [Participant: start here](PARTICIPANT-START.md).
The curriculum is work in progress: live browser rehearsal and genuine Foundry
smoke/regression qualification are still in progress. A Git push is a source
backup, not a readiness or deployment approval.

Local environments, Terraform state/inputs, exported packs, Foundry runtime
evidence/caches and the original organizer handoff ZIP/notes are intentionally
not committed. Export fresh packs for the actual deployment; do not reconstruct
credentials or acceptance evidence from this repository.

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
`workload_inputs.semantic_cache_enabled: true`; it remains off pending explicit
cost review. Its workload resources include RediSearch, a Key Vault-backed
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
