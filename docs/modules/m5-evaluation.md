# M5 - Evaluate an agent and investigate the results

## What you will do

Study the test data, run an evaluation in Foundry, then investigate the answers
and scores. Use what you find to suggest an improvement to the agent.
The goal is to understand its behavior, not to make every result green.
No shell setup or application coding is required.

**Why?** One convincing answer is not enough to judge an agent. Evaluation asks
a set of questions and helps you spot patterns: missing facts, unsupported
claims, tool problems or instructions that need clarification.

Use **your own M2 steward**, with either your own documentation connection or
the shared-reference shortcut. M3's optional experiments and registering your
own API in M4 are not prerequisites.

## Evaluate and investigate

### 1. Inspect the test cases

Open [the evaluation cases](../../scenarios/architecture-docs/exercises/evaluation/eval_set.jsonl)
in the repository browser. The file contains 25 cases: factual
questions, missing-document checks, drafting tasks and guardrail tests.
Each line is one case.

Choose one factual question and one guardrail case. Read their `query`,
`ground_truth`, `expected_facts` and `expected_tools`. What would a good answer
contain? Could another tool call support the same correct answer? Keep these
expectations beside the Foundry results. The fact/tool annotations describe
the expected behavior; uploading them does not automatically turn every
annotation into an evaluator.

**Expected result:** you can describe what a good answer to your two selected
cases would contain before looking at a score.

### 2. Run an evaluation in Foundry

First, download [the evaluation data file](../../scenarios/architecture-docs/exercises/evaluation/eval_set.jsonl):
on its GitHub page, use **Download raw file**. Keep the filename
`eval_set.jsonl`. You need the data file, not a saved copy of the GitHub web page;
you do not need to clone the repository.

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Evaluations -> Create new evaluation**.

- Select **your steward** and note the saved version you want to examine.
- Add the downloaded **`eval_set.jsonl`** as the dataset.
- Choose ready-made evaluators and read their descriptions. Start with the
  defaults that fit your questions; you do not need to configure every metric.
- Check the field mappings: `query` is the question and `ground_truth` is the
  reference answer where required. Score actual agent responses, not the
  reference answer copied into the response field.
- Start the evaluation and open its results. Note which evaluators you chose
  so you know what the scores measure.

The dataset includes proposal-submission tests. Keep human approval required
for write tools; do not enable unattended saving to obtain better scores.
Evaluation does not authorize saving or publishing a document.

**Expected result:** a recorded evaluation of your selected agent version.
Some cases may score poorly or report errors; those are results to investigate,
not instructions to keep rerunning until everything passes.

Evaluation and **Optimize** need a supported deployed model. If the portal does
not accept your connected gateway model, record that setting and temporarily
select the corresponding direct deployment, such as `architecture-docs-chat-small`.
Restore the gateway model afterward. A direct-model run does not test the M3
gateway policies.

**If setup is blocked:** keep the actual error and ask the coach. You can pair
with a teammate to inspect their evaluation instead. Note that you observed
their run rather than completing one of your own.

### 3. Investigate the scores and consider an improvement

Open a lower-scoring row and read the question, actual answer, reference answer
and evaluator's explanation. Inspect a higher-scoring row too. Does the score
match your judgment? `Completed` means the evaluation finished, not that every
answer is correct.

For a matching agent invocation, inspect **Build -> Agents -> your agent ->
Traces**. Check which tools actually ran, their arguments and returned evidence.
An evaluation of previously collected responses does not create a new agent
invocation; use the original trace when available.

Was an answer incomplete, an instruction ambiguous, a lookup unsuccessful,
or a service call blocked? Distinguish an answer-quality problem from an
execution error or a metric that measures something different from your goal.
Record one concrete finding and one possible improvement.

**Expected result:** a finding such as "the answer omitted an interface even
though the inventory lookup returned it", plus an idea for improving it.
There is no single correct conclusion, and you can finish the module here.

**Optional: try your improvement.** Change one instruction in your own agent
and rerun the same cases, keeping the original version and results for comparison.
Change one thing at a time so you can explain what differed.

<details>
<summary>Optional: explore Optimize</summary>

If available, **Optimize** can suggest changes:
[Prompt Optimizer](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/prompt-optimizer)
suggests instruction changes, while [Agent optimizer](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-optimizer-overview)
supports broader experiments. Review the suggestions and their evidence;
an optimized prompt is not automatically a better prompt.

Keep the supported-model caveat from Step 2 in mind, and restore your connected
model if you temporarily switched to a direct deployment.

</details>

<details>
<summary>Further reading: evaluations and evaluator choices</summary>

- [Evaluate agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent).
- [Cloud evaluation](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation).

</details>

## Optional automation

<details>
<summary>Optional: automate a controlled comparison with the CLI</summary>

Compare **two models with two instruction sets**: four configurations using
the same twelve non-write-back cases and tools.

Use **Cloud Shell -> PowerShell**, where `lab` already works, and inspect results
in Foundry. If you need setup, follow the Cloud Shell instructions in
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup).
Keep the session open and download the results afterward as shown below.

These commands require a working **owned M2 MCP connection**. If you used the
shared-reference shortcut, stay with the portal exercise above or pair with
someone who completed that owned integration. Do not edit the shared connection
to make these commands work.

**The CLI comparison workflow is experimental.** It runs real Foundry evaluations
and adds local lab checks. Some require a particular tool call even when another
call supports a correct answer. A red CLI result therefore needs interpretation,
not automatic retries. All-green results are not required.

[The selection plan](../../scenarios/architecture-docs/exercises/evaluation/plan.json)
lists the twelve comparison cases under `comparison_case_ids`. This is a subset
of the 25-case file used above. The helper pins task-adherence evaluator **v2**
and adds fact/tool/template/safety/provenance checks; its verdict is not the same
as the portal evaluators you chose. Leave its cases and thresholds unchanged.

### A. Choose a configuration

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

### B. Create and test your chosen configuration

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

Open the downloaded archive and confirm it includes the complete run folder's
contents, not only its manifest. To compare hashes without a local terminal,
rename the downloaded copy in your file manager, then upload that copy through
Cloud Shell's **Manage files -> Upload**. Use a different filename so you do not
overwrite the original archive. Run:

```powershell
$downloadedCopy = Read-Host 'Cloud Shell path to the uploaded downloaded archive'
Get-FileHash -LiteralPath $downloadedCopy -Algorithm SHA256
```

Compare this SHA256 with the value printed for the original archive above.
Give the complete verified copy to the teammate doing the four-way comparison;
keep the original while this shell is open. Matching hashes verify the
downloaded copy, not the agent's quality.
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

### C. Open the helper's evaluation and investigate one result

Open Foundry, select your team project, then **Build ->
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

### D. Bring together all four results

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

Read the generated Markdown or CSV report using its actual reported output path.
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

### E. Keep the evidence

Record one concrete finding from the answer, Foundry score and tool trace.
Note any helper limitation separately from the agent's behavior. Use the same
analysis and improvement approach as Step 3 above; no all-green result or
four-way ranking is required.

Keep the actual responses, manifests and trace investigation. If collection
is blocked, record **workshop-only/not qualified** with the actual reason:
authentication/service error, missing evidence or an incomplete run such as a
429 interruption. Do not repeatedly rerun to obtain green.
Failed results stay failed; incomplete results stay incomplete.

You may continue to [B1](../bonus/b1-knowledge.md) and the [human approval exercise](core-approval.md) after
an attempted M5. This does not qualify an agent for production, approve a write,
or authorize publication. Do not rank candidates with incomplete evidence.

Strict qualification and publication coordination are separate from this
learning exercise; they belong in the
[coach guidance](../coach-guide.md#evaluation-and-publication-coordination).
This comparison does not change release thresholds, authorize a write or turn
failed/incomplete evidence into a pass.

</details>

## You are done when

- You have inspected the test data and run an evaluation in Foundry.
- You can explain one result using the answer, evaluator reasoning and available
  execution evidence, and suggest an improvement.
- You have kept the original results, including unsuccessful ones. If the run
  was blocked, record the error and ask the coach for help.

Continue after this investigation; an all-green result and the optional CLI
comparison are not required. Saving a proposal still requires your explicit
approval; publication remains the librarian's separate decision.

**Next:** [B1 - Explore Azure AI Search and knowledge bases](../bonus/b1-knowledge.md),
or [review and save your final proposal](core-approval.md).
