# Deployment checklist

Follow [Module 0](docs/module-0.md) for the commands and input requirements.
This checklist is a quick reference for the deployment team.

## Prepare

1. Review the [components and policy checklist](README.md#customer-deployment-components-and-policy-checklist).
2. Select the tenant, subscription, regions, naming suffix and lab expiry.
3. Agree spending-protection settings for the whole subscription, including
   existing spend and deletion of the designated disposable lab groups.
4. Configure team names and the actual participant roster. For sixteen people,
   use four teams of four. Guests must have accepted their invitations.
5. Select the human librarians separately from participants.
6. Confirm Azure resource/role permissions, Entra app-registration permissions,
   provider registration and model/service quota.

## Deploy

1. Run read-only preflight with your private deployment inputs.
2. Review and apply the foundation plan.
3. Review and apply the access plan.
4. Build application images in the foundation registry and retain their digests.
5. Review and apply the workload plan using those exact images.
6. Verify model calls, gateway/API/MCP access, Search indexing and traces.
7. Check the spending protector, alert destination and expiry.
8. Sign in with a non-admin participant account and check the exercise actions.

Use the state/backend and `TF_DATA_DIR` printed for each component. Keep state,
plans and roster inputs private. If an apply is interrupted, preserve its state,
confirm it has stopped and generate a new plan before resuming.
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
