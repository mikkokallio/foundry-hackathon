# Bonus prerequisites, not completed exercises

The [module manifest](modules.json) lists all core/bonus activities and their
inputs. Working reference infrastructure does not mean the learner's artifacts
already exist. Use team-prefixed practice resources; do not overwrite
Terraform-owned reference APIs, policies, indexes or catalog registrations.
Reapplying Terraform after portal edits can reset those edits. Shared authoring
is not team isolation.

## What happens after the initial Terraform stages

- **Module 0:** build/import immutable application images before workload apply.
  Workload Terraform starts the apps, seeds Blob content and runs the bounded
  knowledge initializer, including indexers and private project connections.
  Fresh live agent evaluations and trace verification remain acceptance work.
- **M1-M5:** create/version agents, connect tools, create team-prefixed APIM/API
  Center exercise objects, invoke real services and register/run evaluations.
  Models, shared services and core runtime are already workload/foundation-owned.
- **M3:** workload Terraform creates private, project-specific native model
  connections to APIM. Select the actual team's `native_gateway_models` output
  when creating an agent; a direct deployment name bypasses this route.
  The normal per-team throttle is configurable with
  `gateway_tokens_per_minute` (default 50000); the deliberately restrictive
  exercise route remains 256. Multiple model/tool steps share that minute's
  allowance. Neither setting replaces the subscription spending protector.
  Connection existence is not proof of a passed agent/provenance gate.
- **M5 access:** remote evaluators invoke the judge using the participant's
  identity. The workload grants selected participants `Cognitive Services
  OpenAI User` on the shared Foundry account. This allows direct inference,
  including other account deployments; it is not universal APIM enforcement
  or cross-workload model isolation. It grants no deployment-management rights.
- **B2:** participants build/push a new image and **deploy an additional ACA app**.
  The extension resource group, shared ACA environment, ACR build/push grants and
  preassigned pull identity exist in initial TF. Use the actual
  `extension_authoring` output; do not create or assign a new pull identity live.
  New services must authenticate Entra callers and be routed through APIM, not
  publish an unauthenticated tool. Reuse reviewed transport/auth patterns from
  the toolkit, not its trusted runtime identity or storage permissions.
- **B3:** prompts are provided; participants still create two real agents and
  assemble the workflow. Require writer/reviewer child spans, bounded revision
  rounds, explicit failure on unresolved issues, and exact-text human approval
  before saving. A second agent's approval is not human approval.
- **B4:** two deployments/pool and Content Safety prerequisites are initial
  workload resources. They are in one account/region: not regional failover.
  Validate request parameters against both models before pooling. Redis exists
  only if explicitly selected, reviewed and provisioned. Enabling it later
  means another reviewed workload TF change/provider approval, not a portal
  toggle. Policies are the exercise, not silently installed solutions.
- **B6:** **not provisioned by current initial TF.** Select the actual GitHub
  repository/protected environment first. The separate native
  [delivery stage](../delivery/README.md) implements OIDC, scoped evaluation
  access, retained state and a fail-closed workflow template. It has not been
  deployed or live-accepted. Review the subscription read/account inference grants,
  configure environment reviewers/branches and migrate the real foundation state
  before running it. No client secret, borrowed administrator identity, empty CI
  state or fabricated passing report is an acceptable substitute.
- **B8:** generated MCP config prompts for a short-lived participant Entra token;
  it contains no token. A coding-agent subscription is optional. REST via the
  OpenAPI contract is the no-license alternative. Keep write confirmations on.
- **B9:** prompt/spec is supplied, not a completed frontend. Participants build
  a local client with server-side participant authentication and actual agent
  binding. Additional Azure hosting is not selected or required.

## Data and evaluation cautions

The corpus has 13 systems, 10 published documents and deliberately planted
defects. Missing/stale/wrong facts are the exercise, not unfinished seeding.
Never replace missing published documents with generated answer fixtures.
Run baseline evaluations **before librarian publication changes this shared
corpus**. Publication can legitimately invalidate frozen gap expectations.
Coordinate publication; do not weaken expectations or silently reset documents.

The 25 inherited evaluation cases and numeric thresholds are retained. Only two
ground-truth mailbox addresses follow the already-neutralized `.invalid`
inventory. Prompts are adapted for configurable branding/reference date and
explicit exact-text approval; they need fresh live acceptance.

The exporter derives explicit four-case `smoke.jsonl`, twelve-case
`comparison-12.jsonl` (5 QA, 3 gap, 1 draft, 3 guardrails), their portal mappings
and three-case `write-back.jsonl`, without removing regression cases.
Legacy `quick.jsonl` remains a four-case smoke compatibility name, not the
twelve-case teaching comparison. Portal files are **input rows**, not
registered suites or passed results.
Map `query` and `ground_truth` in the current evaluation UI and preserve case IDs.
Built-in score-only evaluation does not prove tool usage, document validity,
approval or trace provenance.

Write-back cases require real multi-turn approval, actual stored-text/status
checks and no publication. A single-turn portal run cannot prove those steps.
The current genuine evaluation/provenance runner is implemented with explicit
deployment inputs. Passing fresh smoke/regression and native provenance remains
Module 0 acceptance work; local runner tests are not a live pass.

For M5 compare the same twelve teaching cases/corpus across two deployments and
two instruction variants; full 25-case regression remains required for release
qualification. No latency/cost pass threshold was approved. Record actual latency,
input/output/reasoning tokens and date/region/SKU-specific prices; missing values
are unknown, not zero. Frozen quality thresholds remain task_adherence >= 3.0
and template_compliance >= 0.5; they are inherited, not a guarantee of reliability.
The mandatory provenance/safety gate still applies to every case.

KQL files target the **Application Insights query context**, not raw Log
Analytics `App*` table names. Current reference policies emit Team/API, not the
per-caller/model dimensions B5 asks participants to add. Inspect actual metric
names/dimensions first; empty telemetry is not a successful cost calculation.
