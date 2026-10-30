# Reference reuse and verification

The previous repositories are references, not this implementation's source of
truth. Do not copy their state, operator inputs, credentials, deployments or
release claims into this folder.

## Current decisions

| Reference component | Evidence and limitation | Decision here |
|---|---|---|
| Monolithic Terraform root | Existing resource provisioning worked, but scenario APIs, model choices and applications were mixed with shared services. Repeat plans had representation/bookkeeping differences and later Graph timeouts. | Not copied. New foundation, access and selected-workload roots. |
| AVM resource modules | Earlier deployment exercised pinned modules for Foundry, monitoring, storage, registry, APIM and Container Apps. This does not prove a new composition works. | Reuse public module interfaces and pinned versions selectively; locally initialize/validate again. |
| Missing Search and Key Vault prerequisites | Earlier implementation omitted them despite the agreed inventory. | New explicit foundation services. Search 0.3.0 and Key Vault 0.12.0 interfaces checked against the public Terraform registry. Live features/availability remain unverified. |
| Participant permission logic | Earlier work found missing telemetry publishing; later review found read/export-only catalog roles could not support registration exercises. It also accepted object IDs only. | New UPN/object-ID resolution and explicit authoring permissions. Four isolated native tests pass; no non-admin live acceptance yet. |
| Built-in service-contributor roles | Actual role definitions retrieved from the approved subscription permit service deletion/reconfiguration. | Do not grant wholesale. Explicit custom authoring roles exclude foundation-service write/delete. Review custom definitions before apply. |
| Foundry project association/creation | Earlier fixes preserved the full associated-project list and handled parent-account conflicts. | General team projects, explicit complete association list, parent locks and conflict retry. Models remain outside the foundation. |
| Model capacities | Earlier live usage hit real token-rate limits at smaller capacities. | Scenario-owned pinned candidates; no platform model defaults and no quota-shortfall substitution. Check fresh quota including existing deployments before apply. |
| Document backend, corpus and toolkit | Selected source and tests from reference commit `28f9017` were reviewed and imported by explicit whitelist, not whole-repository copying. Previous release attempts failed provenance-token acquisition. | Adopted locally; authenticated toolkit entry point and fail-closed storage configuration repaired. Organization branding is deployment input. Local tests are not live Foundry acceptance. |
| Gateway policies, project tool connections and catalog | Reviewed the specific reference Terraform and five policy files, including the native MCP query/body workarounds. | Adapted into the workload, with namespaced routes, configured team roles and human librarian access independent of participant membership. Shared logger stays in foundation. Live APIM policy compilation and Foundry acceptance are pending. |
| Runtime infrastructure pattern | Earlier AVM Container App 0.9.0 configuration exercised warm replicas, managed-identity image pulls and Entra/Blob settings. Its mutable-tag build/plan workflow was a real gap. | Reuse the pinned interface with mandatory digests, separate backend/toolkit identities, container-scoped backend storage rights, workload-owned group and no implicit build. New composition validates locally; live behavior is unqualified. |
| Workload API identity | Earlier tenant-only API application, CLI pre-authorization, required role assignment and project identity grants were exercised. Participant and human publisher selection must not be inferred from the operator. | Reuse the resource pattern with stable workload-namespaced role IDs and the actual applied roster. Require explicit human librarians and reject disabled/duplicate resolved librarian accounts. No normal-user live proof yet. |
| Agent/client/evaluation wrapper | Earlier draft-copy and credential/provenance failures remain relevant; local tests alone did not establish reliable acceptance. | Not copied. No automatic old-agent invocation or evaluation retry. |
| Cloud budget protector | Earlier cloud executions and a cutoff sentinel provided operational evidence, but billing lags and enrollment are deployment-specific. | New foundation-owned Automation protector, explicit group enrollment, cost/expiry checks and fail-closed tests are implemented locally. Azure execution, alerts and actual cutoff remain unverified. |
| Native Foundry trace ingestion | Current Microsoft guidance requires a project-managed-identity AppInsights connection and Monitoring Metrics Publisher; the existing facilitator project has no AppInsights connection. | Both are now declared in foundation Terraform. Managed-identity ingestion is a preview feature; actual native trace ingestion remains a live acceptance requirement. |
| Optional semantic cache | Current official APIM example uses Balanced_B0, RediSearch, EnterpriseCluster and NoEviction. APIM requires Redis access keys, not Entra Redis authentication. | Workload opt-in AVM 0.2.0, explicit key-auth update (not exposed by AVM), Key Vault storage/grants and APIM connection. Five native tests exercise the actual Terraform source with test-only Azure doubles. Off by default; no live cache acceptance. |

## What local checks establish

- Current foundation, access and workload Terraform roots pass validation.
- The access module's provider doubles exist only under its native test directory.
- Local composition checks prove model literals/resources are not in the
  foundation, Search remains a declared requirement of architecture-docs, all
  nine bonus identifiers remain declared, and example targets are rejected
  before Azure contact.
- These checks do **not** prove regional availability, quota, effective user
  permissions, gateway policies, application behavior, Search knowledge
  retrieval, live tracing or evaluation success.
- The plan-composition test uses unmistakably test-scoped `az`/`terraform`
  command doubles to verify saved input shapes and rejection paths. It does not
  run Azure operations, create a usable Terraform plan or qualify deployment.

No replacement infrastructure has been applied. Explicitly authorized builds
dt3/dt4 used the existing lab ACR; those exact AMD64, non-root images passed local
health and anonymous-access rejection checks. This is not valid-Entra, Blob,
gateway, Search or Foundry acceptance.

Trace connection references: [Microsoft Entra trace ingestion](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication)
and [official AppInsights connection target/metadata example](https://github.com/Azure-Samples/azd-ai-starter-basic/blob/5bf59a056c41ff37801dea334ba6a141e2dc5f67/infra/core/ai/ai-project.bicep).

Cache references: [APIM Redis authentication](https://learn.microsoft.com/azure/api-management/api-management-howto-cache-external)
and [official semantic-cache resource configuration](https://github.com/Azure-Samples/AI-Gateway/blob/1679e3137d2fe7592d2a668d77ff71550d35b69e/labs/semantic-caching/main.bicep).
