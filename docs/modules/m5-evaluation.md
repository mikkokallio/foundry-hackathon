# M5 - Evaluate an agent and investigate the results

## What you will do

Run twelve test cases, then compare the Foundry score with an actual answer and
its tool trace. Optionally compare **two models with two instruction sets**:
four configurations using the same cases and tools.

Use the **PowerShell shell from M3**, where `lab` already works, and inspect
results in Foundry. No application coding is required. If you need a new shell,
use [M3's expandable setup](m3-governance.md#2-send-one-normal-model-request).
Choose **local PowerShell** or **Cloud Shell PowerShell**; keep it open during
the run. In temporary Cloud Shell, download the results afterward as shown below.

**The CLI comparison workflow is experimental.** It runs real Foundry evaluations
and adds local lab checks. Some require a particular tool call even when another
call supports a correct answer. A red CLI result therefore needs interpretation,
not automatic retries. All-green results are not required.

<details>
<summary>Optional: explore portal evaluation and evaluator background</summary>

- [Evaluate agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent).
- [Cloud evaluation](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation).

You can explore creating a separate evaluation in the portal: prepare/import
suitable test data, choose the agent and evaluators, and check the field mappings.
The helper supplies cases and collected response IDs directly to its evaluation
run; it does **not** register a reusable dataset ready for a new portal run.
This optional portal setup is not a tested step-by-step lab path.

The lab pins task-adherence evaluator **v2** on its
numeric scale, plus custom fact/tool/template/safety/provenance checks. Do not
copy newer default evaluators or change thresholds to obtain a pass.
Additional built-in diagnostics such as intent resolution, tool-call accuracy,
relevance and coherence are outside this exercise's current runner.

</details>

## Build and compare

### 1. Inspect the test cases

Open [the evaluation cases](../../scenarios/architecture-docs/exercises/evaluation/eval_set.jsonl)
in VS Code or the repository browser. Each line is one case.
[The selection plan](../../scenarios/architecture-docs/exercises/evaluation/plan.json)
lists the twelve comparison cases under `comparison_case_ids`.

Choose one factual question and one guardrail case. Read their `query`,
`ground_truth`, `expected_facts` and `expected_tools`. What would a good answer
contain? Could another tool call support the same correct answer? Keep these
expectations beside the Foundry results when you inspect them in Step 4.

### 2. Choose a configuration

Start with one configuration from the table. For the optional four-way
comparison, divide the configurations among the people present; one person
can run multiple cells. Use your own participant prefix and a distinct agent
name/output file for each cell.

| Cell | Model alias | Instructions |
|---|---|---|
| small-standard | chat-small | instructions |
| small-concise | chat-small | instructions-concise |
| medium-standard | chat-medium | instructions |
| medium-concise | chat-medium | instructions-concise |

Use the connected models, not M1's direct deployment. M1's agents without tools
are **not** these candidates. The helper saves the exact agent version so you
do not accidentally evaluate a later edit.

Use **your own working M2 documentation MCP** when working alone or at your own
pace: set `$docsOwner = $prefix`. Include the whole prefix if it has a suffix;
participant `p1` is not required.

For a coordinated four-way comparison, choose one working MCP owner in your
team project and use that same owner for all four cells. Your agents still use
your own prefixes. This controls gateway differences; do not edit that MCP or
publish documents while collecting results.

### 3. Create and test your chosen configuration

**A. Create your comparison agent.** Change `$prefix` to your assigned prefix,
set `$cell`, `$model` and `$prompt` from your table row, and set `$docsOwner`
to the working M2 MCP owner's prefix. Then run this block; the helper creates
the agent and saves its version binding. You do not need to create it in the
portal first.

```powershell
$prefix = 'alpha-p2'
$cell = 'small-concise'
$model = 'chat-small'
$prompt = 'instructions-concise'
$docsOwner = $prefix # Your working M2 MCP owner; use the shared owner for a team comparison.
$binding = Join-Path 'out' "$prefix-comparison-$cell.json"
lab agent --name "$prefix-comparison-$cell" --model $model --prompt $prompt --docs practice --docs-owner $docsOwner --toolkit --reasoning low --output $binding
```

**B. Run the twelve-case evaluation**

```powershell
lab eval --binding $binding --comparison
```

This collects real agent responses and submits them to Foundry's task-adherence
evaluator, then checks local facts, tool use, templates and native traces.
It automates the experiment; it does not replace inspecting the results.

Keep the reported `Evidence:` folder under `.foundry\results` and its
`manifest.json`, including when checks fail. Early setup failures may not create
a run folder. The manifest records the version, inputs and checks; do not edit it.
All candidates use `low` reasoning. Coordinate runs if shared capacity is throttled.

<details>
<summary>Cloud Shell: download and verify the complete result folder before closing</summary>

Paste the actual result folder reported by `lab eval`:

```powershell
$resultFolder = (Resolve-Path (Read-Host 'Paste the full evaluation result folder path')).Path
$archive = Join-Path $HOME "$prefix-$cell-results.tar.gz"
tar -czf $archive -C $resultFolder .
if ($LASTEXITCODE -ne 0) { throw 'Result archive failed; do not close this shell yet.' }
Write-Output $archive
Get-FileHash $archive -Algorithm SHA256
download $archive
if ($LASTEXITCODE -ne 0) { throw 'Download link creation failed; keep this shell open.' }
```

Click the archive filename in the **Download file** notification that appears
in Cloud Shell. **Running `download` alone is not the download:** follow that
filename link and confirm the file actually appears in your laptop's downloads.

On your laptop, run `Get-FileHash` on the downloaded file and compare the SHA256
with the value printed in Cloud Shell. Extract the archive and confirm it includes
the complete run folder's contents, not only its manifest. Give that complete
copy to the teammate doing the optional Step 5; keep the original while this shell
is open. Matching hashes verify the downloaded copy, not the agent's quality.
If download fails, tell the coach and preserve the current session;
do not treat archive creation as a successful backup.

</details>

<details>
<summary>If Cloud Shell reconnects without the original result folder</summary>

A completed evaluation in Foundry does not replace the original local manifest,
gate results and traces. Keep the existing evaluation ID, stop before comparison,
and ask the coach for help recovering the complete folder. Do not invent a
replacement passing manifest, weaken missing-evidence checks or silently rerun
the cases. Native results can still be inspected, but incomplete evidence must
not be presented as a qualified run.

</details>

### 4. Open the evaluation and investigate one result

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Evaluations**. Open the evaluation created by your command and then its run.
Inspect one answer, including a green result if needed, and its matching native
trace. For an agent's
traces, use **Build -> Agents -> your comparison agent -> Traces**.

Did it invent a fact, miss a necessary tool, use malformed arguments, encounter
a service error, or fail to follow the instructions? Write down one concrete
hypothesis. `Completed` means the remote evaluation finished; task adherence is
not a guarantee of factual completeness. A green score can still accompany an
unanswered question.

If the CLI is red, inspect `failure_clusters` in `manifest.json`. Distinguish
missing facts from an exact-tool requirement, a recorded failed tool call,
authentication/service errors or genuinely missing trace evidence. For example,
a correct owner lookup using `listSystems` can fail the helper's `getSystem`
requirement. Do not describe that alone as an incorrect answer or a runner crash.

<details>
<summary>A trace contains a discovery 400, but tools subsequently work</summary>

A client can try `server/discover` before the supported MCP initialization.
The helper records that rejected probe separately only when the same declared
endpoint and native trace show successful `initialize` and `tools/list`, and
the completed response contains the real tool list. Those diagnostics remain
in the trace file. Failed business-tool calls, authorization errors and missing
execution evidence still fail verification.

</details>

<details>
<summary>Which test files and checks does the helper use?</summary>

| Input / activity | Purpose |
|---|---|
| `smoke.jsonl` | Four categories, four cases. |
| `plan.json` + `eval_set.jsonl` | Select twelve non-write-back comparison cases: 5 QA, 3 gap, 1 draft, 3 guardrails. Same cases for every cell. |
| `eval_set.jsonl` | All 25 unchanged regression cases. Required for release qualification. |
| `write-back.jsonl` | Three write-back cases; genuine human approval/persistence checks remain necessary. |
| Legacy `quick.jsonl` | Four-case smoke compatibility name, **not** the twelve-case teaching comparison. |

The comparison command collects fresh Foundry responses, invokes the remote
evaluator and checks matching native response/version/tool traces. Missing,
cancelled, incomplete or failed evidence does not become a pass.

</details>

### 5. Optional: bring together all four results

<details>
<summary>Run the four-way comparison</summary>

Only when all four manifests have complete collection and required provenance,
give their actual manifest paths to the comparison command. All four files
must be accessible on the computer running this command; a path on a teammate's
laptop is not accessible on yours. Keep the complete run folders as evidence.
The prompts below ask for each actual path, rather than example filenames that
do not exist:

```powershell
$smallStandard = Read-Host 'Manifest path for small-standard'
$smallConcise = Read-Host 'Manifest path for small-concise'
$mediumStandard = Read-Host 'Manifest path for medium-standard'
$mediumConcise = Read-Host 'Manifest path for medium-concise'
$comparisonFolder = Join-Path 'out' "$prefix-team-comparison"
lab compare $smallStandard $smallConcise $mediumStandard $mediumConcise --output $comparisonFolder
```

The command checks that the four runs are comparable, then writes Markdown/CSV
reports with quality, failure groups, latency and available token measurements.
If it refuses incomplete or incompatible evidence, inspect the individual runs
instead; do not force a ranking. Compare tokens rather than cost when prices
are unavailable; missing prices or telemetry do not mean zero cost.

Open the generated Markdown report in VS Code; **Ctrl+Shift+V** opens its preview.
Compare quality and failures, response time, and the available token measurements.
Which configuration would you choose, and what evidence supports that choice?

<details>
<summary>How failed or incomplete candidates appear in the report</summary>

An omitted expected tool remains a failed helper check even when provenance
verifies the calls that actually ran. Investigate whether it represents a
necessary missing operation or an overly specific tool requirement; the report
does not make that judgment for you. Never invent a span or qualify the candidate.

The report includes fully collected failed candidates without calling them
qualified. Incomplete runs or missing provenance cannot be included or ranked;
inspect their actual manifests directly. Do not use `lab compare` to rank
incomplete evidence.

</details>

</details>

### 6. Record one finding and continue

Record one concrete finding from the answer, Foundry score and tool trace.
Note any helper limitation separately from the agent's behavior. One collected
run and this investigation are sufficient for the module; no all-green result
or four-way ranking is required.

If you want to explore an improvement:

- Inspect the worst answer and its tool trace before changing the instructions.
- Clarify tool-use order and name/ID resolution; add a short example of the
  expected behavior, rather than a test-case answer.
- Change one thing at a time and rerun the same cases. Keep the original versions,
  inputs, thresholds and results unchanged.
- Optionally explore [Prompt Optimizer](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/prompt-optimizer)
  for instruction suggestions, or [Agent optimizer](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-optimizer-overview)
  as a further experiment if available. Review every proposed change; an
  optimization is not proof of improvement. Neither feature is required.

Keep the actual responses, manifests and trace investigation. If collection
is blocked, record **workshop-only/not qualified** with the actual reason:
authentication/service error, missing evidence or an incomplete run such as a
429 interruption. Do not repeatedly rerun to obtain green.
Failed results stay failed; incomplete results stay incomplete.

You may continue to [B1](../bonus/b1-knowledge.md) and the [human approval exercise](core-approval.md) after
an attempted M5. This does not qualify an agent for production, approve a write,
or authorize publication. Do not rank candidates with incomplete evidence.

<details>
<summary>Optional: strict qualification and coach-only publication conditions</summary>

Qualification is a stronger claim than the twelve-case workshop comparison:

```powershell
lab eval --binding $binding
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

#### Workshop publication conditions

After a few genuine attempts, preserve the actual manifests, failures and trace
investigation, then explicitly stop rather than repeat indefinitely. Record
**workshop-only/not qualified** and the reason: quality (missing facts/expected
tools), missing native provenance, or incomplete collection (for example 429).
These are different failures, not all a difficult-prompt problem. Actual failed
results stay failed; incomplete collection stays incomplete, never a pass.

Attempted M5 is sufficient to continue to B1/B3/B6 and to review and save your
final proposal. It does not qualify an agent or require a backend/evaluator bypass.
For workshop publication, the authorized human librarian must review the exact
proposal and explicitly accept the failed/incomplete-evaluation caveat.
Real projects require their stricter release policy; B6's production-style CI
gate remains strict and must block promotion on failed or incomplete evidence.

Before any human publication, the coach records that **all teams' frozen-corpus
attempts are completed or explicitly stopped**. Retain the corpus boundary and
actual outcomes. Later runs against changed published content are a new corpus,
not the original baseline; do not compare them as unchanged-corpus evidence.

</details>

## You are done when

- One actual agent version evaluated, with an answer/trace investigation and
  one concrete finding; or an explicit blocked attempt and its evidence limitation.
- Foundry scores, additional helper checks and technical/evidence problems
  distinguished rather than reduced to one green/red verdict.
- If comparing configurations: a numerical choice only with comparable evidence,
  never a ranking of incomplete runs or a claim of production qualification.

**If stuck:** the coach helps with actual run IDs, coverage and ingestion/auth
errors. Do not remove cases, lower thresholds or reuse fabricated/cached answers.
Publish nothing until **all teams'** frozen-corpus attempts finish or are
explicitly stopped and the human librarian accepts the workshop caveat.

**Next:** [B1 - Explore Azure AI Search and knowledge bases](../bonus/b1-knowledge.md),
or [review and save your final proposal](core-approval.md).
