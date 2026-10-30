# B6: separately reviewed delivery prerequisites

**Locally implemented, not deployed or live-accepted.** This separate workload
stage does not change foundation/workload state or enable a GitHub workflow.
Real repository/environment selection and a genuine passing CI run remain required.
Finish this stage during Module 0 before offering B6.

## What this native Terraform root provisions

- Dedicated managed identity and exact `repo:OWNER/REPO:environment:NAME` OIDC
  trust; no client secret or Microsoft Graph application/consent dependency.
- Dedicated Entra-only state account/container, versioning, 30-day blob/container
  recovery, an Azure account deletion lock and Terraform `prevent_destroy`.
- CI: subscription **Reader** for the foundation plan, Foundry User on one team
  project, account-wide OpenAI inference for judging, workspace log-query access,
  and Blob Data Contributor on the state container. No infrastructure apply or
  role-management permission. Account inference is not universal APIM enforcement.
- Explicitly selected state operators; the deploying human is not added silently.

The state group survives normal lab teardown/cutoff and has its own small storage
cost, included in whole-subscription costs. It is not automatically enrolled for
deletion. An account lock does not prevent data-plane blob changes: versioning and
soft delete provide recovery, not immutable or undeletable state.

## Enable only after review

1. Select the actual repository and protected GitHub environment. Configure its
   required reviewers and allowed deployment branches; Azure Terraform does not
   create or protect the GitHub environment.
2. Supply `foundation` from the applied foundation output, `project_name`,
   `suffix`, `github_repository`, `github_environment`, and actual
   `state_operator_object_ids` in a private Terraform variable file.
3. Use a separate absolute `TF_DATA_DIR` and local backend state path for this
   root. Native `terraform init`, `plan` and `apply` require explicit review.
4. **After all current Terraform operations stop**, copy
   [backend_override.tf.example](backend_override.tf.example) into the foundation
   root as `backend_override.tf`. With that root's existing applied local backend
   selected, use native `terraform init -migrate-state` with the returned account,
   resource group, container, a unique foundation state key, and
   `use_azuread_auth=true`. Retain the protected local backup. Do not initialize
   an empty remote state or use `-reconfigure` instead of migration.
5. After review, copy [foundry-gate.workflow.yml](foundry-gate.workflow.yml) to the
   selected repository's workflow directory. This is a manual-dispatch template,
   not an automatically installed workflow. Do not expose private state/rosters.

Set these GitHub environment variables from actual applied outputs:

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- `WORKSHOP_DIRECTORY`: checkout-relative directory containing this hackathon
  (`.` if it is the repository root).
- `STATE_RESOURCE_GROUP`, `STATE_ACCOUNT`, `STATE_KEY`: **existing migrated
  foundation state** in the `tfstate` container.
- `FOUNDATION_INPUTS_JSON`: actual approved native foundation input JSON.
- `PROJECT_ENDPOINT`, `APP_INSIGHTS_RESOURCE_ID`, `WORKSPACE_RESOURCE_ID`
  (workspace ARM ID), `JUDGE_DEPLOYMENT` (actual deployed model name).

Dispatch with the protected environment and actual deployed agent name/numeric
version. The unchanged runner collects fresh smoke/regression responses and
requires native provenance; any gate failure blocks the plan. Evidence is
retained on failures too. No raw state, private inputs or binary plan is uploaded.
Only foundation plans are supported: access/workload planning would need a
separately reviewed permission design. CI does not migrate state or apply changes.
An already-deployed candidate's pass does not validate undeployed source changes.
