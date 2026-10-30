# M5 - Compare configurations, investigate failures and choose

## Understand

Compare **two models x two instruction variants**, with the same documentation
and toolkit tools, corpus, case IDs and explicit reasoning settings where
supported. A model's name or a fluent demo does not establish quality.

Suggested reading:
- [Evaluate agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent).
- [Cloud evaluation](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation).

The lab deliberately pins task-adherence evaluator **v2** on its inherited
numeric scale, plus custom fact/tool/template/safety/provenance checks. Do not
copy newer default evaluators or change thresholds to obtain a pass.
Cowork also proposed intent resolution, tool-call accuracy, relevance and
coherence; those additional built-in diagnostics are **not implemented in the
current runner**. Do not claim their custom-check counterparts are those built-ins.

## Build and measure

### 1. Divide the matrix, not participation

Each person creates/owns one configuration, then the team compares all four:

| Person | Model alias | Instructions |
|---|---|---|
| p1 | chat-small | instructions |
| p2 | chat-small | instructions-concise |
| p3 | chat-medium | instructions |
| p4 | chat-medium | instructions-concise |

Use the connected model IDs and the same actual tools. M1's intentionally
tool-less negative control is **not** one of these candidates. Pin versions;
never evaluate `latest`.

Choose **one team member's already working practice documentation MCP** for this
controlled experiment. Everyone sets `$docsOwner` to that exact participant
prefix (including any suffix). Your agent still belongs to your own `$prefix`;
reusing the same MCP prevents endpoint/policy differences confounding the model
comparison. Do not edit that MCP or publish documents while collecting results.

For your assigned `$model` and `$prompt`:

```powershell
$model = 'chat-small' # Your row above.
$prompt = 'instructions'
$docsOwner = 'alpha-p1' # Replace with your team's chosen real practice owner.
lab agent --name "$prefix-comparison" --model $model --prompt $prompt --docs practice --docs-owner $docsOwner --toolkit --reasoning low --output "out\$prefix-comparison.json"
lab eval --binding "out\$prefix-comparison.json" --comparison
```

The helper prints the actual `.foundry\results\...` evidence destination.
All four candidates explicitly use the same `low` reasoning setting; do not
change it for only one matrix cell.
Start collection as soon as the final configurations exist; use the waiting
time to inspect cases and predict likely failure modes. Stagger team runs if
shared gateway/model limits require it.

### 2. Know which dataset you are using

| Input / activity | Purpose |
|---|---|
| `smoke.jsonl` | Four categories, four cases. |
| `comparison-12.jsonl` | Twelve non-write-back cases: 5 QA, 3 gap, 1 draft, 3 guardrails. Same cases for every matrix cell. |
| `eval_set.jsonl` | All 25 unchanged regression cases. Required for release qualification. |
| `write-back.jsonl` | Three write-back cases; genuine human approval/persistence checks remain necessary. |
| Legacy `quick.jsonl` | Four-case smoke compatibility name, **not** the twelve-case teaching comparison. |

The comparison command collects fresh Foundry responses, invokes the remote
evaluator and checks matching native response/version/tool traces. Missing,
cancelled, incomplete or failed evidence does not become a pass.

### 3. Assemble and investigate

Give the four actual manifest paths to the comparison command:

```powershell
lab compare ACTUAL_P1_MANIFEST ACTUAL_P2_MANIFEST ACTUAL_P3_MANIFEST ACTUAL_P4_MANIFEST --output "out\$prefix-team-comparison"
```

It verifies matrix/input/coverage compatibility, identical actual tools/settings
and project, then writes Markdown/CSV with outcome/failure clusters, quality,
latency and available token measurements. Price only when all matching
model/token-category rates are known. Otherwise compare tokens/task; missing
prices, reasoning tokens or telemetry are not zero cost. Judge and shared-service
charges are separate from agent token estimates.

Open a worst/failed real row's response and matching native trace in Foundry.
In **Build -> Evaluations**, open your evaluation, then its run. `Completed`
and even 100% task adherence do not establish that the repository's additional
fact/tool/template/provenance checks passed.
Was the cause unsupported facts, missing evidence, malformed arguments, a failed
tool/transport, approval handling or instructions? Record a concrete hypothesis.
A failed run remains evidence worth investigating, not something to hide.
An omitted expected tool remains a quality failure even when provenance verifies
the calls that actually ran. The runner records that omission separately; it
must neither invent a span for the missing call nor qualify the candidate.

The report includes fully collected failed candidates without calling them
qualified. Incomplete runs or missing provenance cannot be included; inspect
their actual manifests directly before retrying.

### 4. Qualification is a different claim

```powershell
lab eval --binding "out\$prefix-comparison.json"
```

This runs unchanged four-case smoke, then **full 25-case regression**, with fresh
responses, remote IDs and native provenance. A failed smoke stops before
regression: report failed qualification, not a completed regression. Keep task adherence >= 3.0 and draft
template compliance >= 0.5, plus required fact/tool/safety/provenance checks.
The educational comparison is not a substitute. Writes default to denied in
unattended runs; the [human approval/persistence exercise](core-approval.md)
is additional evidence, not silently auto-approved by the evaluator.

If collection/qualification is not finished, label it pending/failed. A historical
facilitator pass does not qualify your version. Any changed model, reasoning,
tools or instructions requires fresh qualification.

## Validate

- Four actual immutable configurations and comparable real evidence.
- A numerical choice of configuration, including a limitation/uncertainty.
- A real worst-row trace investigation and a reasoned improvement hypothesis.

**If stuck:** the coach helps with actual run IDs, coverage and ingestion/auth
errors. Do not remove cases, lower thresholds or reuse fabricated/cached answers.
Publish nothing until **all teams'** frozen-corpus comparisons finish.
