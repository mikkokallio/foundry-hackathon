# Deployment checklist

Follow [Module 0](docs/module-0.md) for the commands and input requirements.
This checklist is a quick reference for the deployment team.

## First: published candidate and today's rehearsal

Do not execute the walkthrough until the deployment team publishes the tested
candidate. Then jointly confirm the concrete live target and original
backend/state before planning. Publication alone does not approve any apply.

Today (Sunday 1 November), use the existing approved test environment and its
existing test roster for current reference E2E and improved deployment rehearsal.
Do not request the customer roster today. It arrives Monday morning:
customer foundation infrastructure preflight/planning can precede it, but
customer access/workload require complete actual accounts/team assignments and
the selected human publisher. Infrastructure-only preflight is not Full preflight.

The deadlines are infrastructure freeze **18:00**, including successful shared
human deployment; docs **19:00**; remaining exercises preferably **21:00**, latest
**midnight**; customer **08:00 Monday**. These are deadlines, not duration
estimates. Do not promise provisioning/role propagation fits or bypass a gate.

## Prepare

1. Review the [components and policy checklist](README.md#customer-deployment-components-and-policy-checklist).
2. Select the tenant, subscription, regions and naming suffix.
3. Review ongoing costs and agree who manages budget monitoring and teardown.
4. Configure team names. When Monday's customer roster is available, add actual
   participant identities/team assignments
   before the access stage; foundation and image builds can start without them.
5. Select a coach as human publisher, with an optional backup. Verify target-tenant
   account readiness for publishers and participants, including accepted guest
   invitations where applicable.
6. Confirm Azure resource/role permissions, Entra app-registration permissions,
   provider registration and model/service quota.

## Deploy

Use [Module 0's native Terraform walkthrough](docs/module-0.md#2-choose-one-state-route)
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
8. **After the user's new deployment containing the targeted IaC fix**, sign in
   with a non-admin participant account, create a team-owned M2 Foundry MCP
   connection, read it back and run the tool checks. Verify the grant covers
   the complete roster. An Alpha-only manual grant, local tests or admin
   success do not close this gate. Continue the other non-admin exercise checks.

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

Keep evidence separate: five recovered reference cycles are not five fresh
deployments, and local regressions/preflight/build receipts do not prove the
new shared human deployment or non-admin acceptance.

Optional B6 delivery setup has its own
[identity, state and GitHub prerequisites](scenarios/architecture-docs/delivery/README.md).
The B9 reference runs locally; Azure frontend hosting is a separate extension.
