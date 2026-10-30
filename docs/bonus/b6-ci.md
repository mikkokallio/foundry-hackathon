# B6 - Ship through a genuine evaluation gate

**After attempted M5; a pass is not required for workshop entry. Live execution
is blocked until organizer delivery setup is accepted.** The production-style
CI gate remains strict; a failed/incomplete evaluation must block promotion,
not be relabeled as a passing deployment.

## Understand

Read [GitHub Actions OIDC](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
and [agent evaluation](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent).
OIDC removes a long-lived client secret; it does not supply appropriate
permissions, protected branches or correct Terraform state automatically.

## Build

1. Inspect the existing [delivery stage](../../scenarios/architecture-docs/delivery/README.md)
   and [workflow template](../../scenarios/architecture-docs/delivery/foundry-gate.workflow.yml).
   Identify the repository/environment trust, identity grants, real state and
   agent/evaluator bindings the workflow expects.
2. Ask the coach to verify: selected authorized repository, accepted federation,
   environment reviewers/branch protection, state binding and genuine evaluation
   access. Current initial foundation/access/workload does **not** complete this.
3. Only after separately approved organizer setup, create a candidate change and
   run the actual workflow against the exact immutable agent version.
4. Inspect genuine smoke/regression evaluation IDs, native response/version/tool
   provenance, failures and the plan's actual state/backend target.
5. Introduce a safe, test-scoped failing condition or rejected candidate and
   verify the workflow blocks promotion. Restore your candidate source through
   a normal change; never lower thresholds or manufacture a pass manifest.

## Validate

- A real federated CI run with correct scoped identity/state and fresh evaluation
  evidence; missing/cancelled/incomplete gates prevent promotion.
- A demonstrated failed gate, not merely a green workflow that never evaluated.

**If prerequisites are missing:** inspect/discuss the template, record the missing
setup and stop live execution. That discussion is useful, but is **not completion
of B6**. Curriculum approval does not authorize role/trust changes, GitHub settings
changes, state migration or applying the separate delivery stage.

**Discuss:** what can the CI identity change, and who approves promotion?
Never use an organizer token, empty replacement state or local fake evaluation.
