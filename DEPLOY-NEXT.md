# Deployment checklist

Follow [Module 0](docs/module-0.md) for the commands and input requirements.
This checklist is a quick reference for the deployment team.

## Prepare

1. Review the [components and policy checklist](README.md#customer-deployment-components-and-policy-checklist).
2. Select the tenant, subscription, regions and naming suffix.
3. Review ongoing costs and agree who manages budget monitoring and teardown.
4. Configure team names. Add actual participant identities/team assignments
   before the access stage; foundation and image builds can start without them.
5. Select a coach as human publisher, with an optional backup. Verify target-tenant
   account readiness for publishers and participants, including accepted guest
   invitations where applicable.
6. Confirm Azure resource/role permissions, Entra app-registration permissions,
   provider registration and model/service quota.

## Deploy

Use [Module 0's native Terraform walkthrough](docs/module-0.md#1-sign-in-and-prepare-inputs)
by preference. The optional composition wrapper has a separate state layout;
an existing deployment must retain its owning route, backend and component
`TF_DATA_DIR`. Never initialize the other route to resume it.

1. Run infrastructure preflight with your private deployment inputs.
2. Review and apply the foundation plan.
3. Build application images in the foundation registry and retain their digests.
4. Complete full preflight with the actual roster, then review/apply access.
5. Review and apply the workload plan using those exact images.
6. Verify model calls, gateway/API/MCP access, Search indexing and traces.
7. Confirm the subscription owner's budget monitoring and teardown arrangements.
8. Sign in with a non-admin participant account, create a team-owned Foundry MCP
   connection, read it back and run the tool checks. Verify the configured grants
   cover the complete roster; operator access alone is not sufficient.

Use each component's recorded native context or printed wrapper state/backend
and `TF_DATA_DIR`. Keep state,
plans and roster inputs private. If an apply is interrupted, preserve its state,
confirm it has stopped and generate a new plan before resuming.
Review each exact saved-plan hash and apply only in that component's retained
backend/data directory. There is no automatic apply, backend migration or teardown.
See [deployment troubleshooting](docs/exercise-readiness.md#deployment-notes)
for current service-specific issues.

## Share the workshop

Export one [participant input pack per team](docs/exercise-readiness.md#export-after-the-workload-is-applied)
and share [Participant: start here](PARTICIPANT-START.md).
Collect M5 baseline evaluations before librarian publication changes the shared
corpus.

Optional B6 delivery setup has its own
[identity, state and GitHub prerequisites](scenarios/architecture-docs/delivery/README.md).
The B9 reference runs locally; Azure frontend hosting is a separate extension.
