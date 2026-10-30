# Component design notes

The lab separates shared infrastructure, participant access and scenario resources
so each stage can be reviewed and deployed independently.

| Area | Design |
|---|---|
| Foundation | Shared Foundry projects, APIM, API Center, Search, storage, Key Vault, registry, container environment, monitoring and spending protection. |
| Access | Deployment-time UPN/object-ID resolution and scoped authoring roles for the participant roster. |
| Workload | Model deployments, application identities/runtime, synthetic data, API/MCP routes, catalog entries and Search knowledge setup. |
| Application images | Remote Linux builds with immutable image digests supplied to the workload plan. |
| Runtime identities | Separate backend/toolkit identities; document storage access is scoped to the backend's required containers. |
| Participant authoring | Custom roles permit exercise-level authoring without granting foundation-service deletion or resource-group Contributor. Shared services still require naming and coordination across teams. |
| Publication | Proposal saving uses exact-text approval; publication belongs to separately selected human librarians. |
| Traces | Project Application Insights connections and managed-identity ingestion/query permissions. |
| Spending protection | A foundation-owned Automation protector checks whole-subscription costs and expiry, deleting only enrolled disposable lab groups. Billing lag means this is not a hard spending cap. |
| Optional cache | Redis is opt-in. APIM's access-key requirement uses Key Vault storage and scoped gateway access. Cache policies are built in B4. |

Use the [infrastructure guide](../infra/README.md) for state and stage ownership,
[Module 0](module-0.md) for deployment steps, and the
[preview notes](exercise-readiness.md) for current deployment/exercise details.

## Further reading

- [Microsoft Entra trace ingestion](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-ingestion-entra-authentication).
- [APIM external cache authentication](https://learn.microsoft.com/azure/api-management/api-management-howto-cache-external).
