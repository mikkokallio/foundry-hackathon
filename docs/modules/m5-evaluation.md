# M5 - Compare four agent versions and investigate their failures

## What you will do

Compare **two models with two instruction sets**: four configurations in total.
Each answers the same twelve test cases using the same documentation and toolkit
tools. Compare the measured results, not just which answer sounds fluent.

This module's main route uses **PowerShell and the supplied Python helper**;
it is not browser-only. Use the
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup) and keep that
shell open. Choose **local PowerShell** or **Cloud Shell PowerShell** there.
Cloud Shell uses the public repository, your team's `workshop.json` and the
extra scoped sign-in; uploading a complete pack is not required.
For long runs, prefer local PowerShell or already-mounted persistent Cloud Shell
storage. In a temporary session, download each complete result folder immediately
after its run, before closing or resetting the shell. The commands below are the
same after setup in either shell.
You inspect the resulting evaluations and traces in Foundry.
No application coding is required.

<details>
<summary>Optional reading and evaluator background</summary>

- [Evaluate agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent).
- [Cloud evaluation](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation).

The lab pins task-adherence evaluator **v2** on its
numeric scale, plus custom fact/tool/template/safety/provenance checks. Do not
copy newer default evaluators or change thresholds to obtain a pass.
Additional built-in diagnostics such as intent resolution, tool-call accuracy,
relevance and coherence are outside this exercise's current runner.

</details>

## Build and compare

### 1. Assign the four configurations

Divide these four configurations among the people present. With four people,
each can own one; with fewer people, someone can own multiple configurations.
Keep your own participant prefix and use a distinct agent name/output file for
each cell. Do not impersonate an absent participant.

| Cell | Model alias | Instructions |
|---|---|---|
| small-standard | chat-small | instructions |
| small-concise | chat-small | instructions-concise |
| medium-standard | chat-medium | instructions |
| medium-concise | chat-medium | instructions-concise |

Use the connected models, not M1's direct deployment. M1's agents without tools
are **not** these candidates. The helper saves the exact agent version so you
do not accidentally evaluate a later edit.

Choose **one team member's working M2 documentation MCP** for all four.
For example, if it belongs to `alpha-p1`, everyone sets `$docsOwner = 'alpha-p1'`.
If its owner used a longer prefix, include that whole prefix.
Your agent still uses your own name, such as `alpha-p2`.
This keeps gateway differences from affecting the model comparison.
Do not edit that MCP or publish documents while collecting results.

### 2. Create and test your assigned configuration

This example is **Alpha participant 2 running small-concise**. It creates
`alpha-p2-comparison-small-concise`. Change `$prefix` to your own name and set
`$cell`, `$model` and `$prompt` to your row in the table:

```powershell
$prefix = 'alpha-p2'
$cell = 'small-concise'
$model = 'chat-small'
$prompt = 'instructions-concise'
$docsOwner = 'alpha-p1' # Replace with your team's chosen real practice owner.
$binding = Join-Path 'out' "$prefix-comparison-$cell.json"
lab agent --name "$prefix-comparison-$cell" --model $model --prompt $prompt --docs practice --docs-owner $docsOwner --toolkit --reasoning low --output $binding
lab eval --binding $binding --comparison
```

The helper reports the actual result folder under `.foundry\results`.
Find its `manifest.json` and keep that file's full path for Step 4. It records
which version, inputs and checks were used; do not edit it.

If using a temporary **Cloud Shell** session, keep a downloadable copy before
closing it. Paste the actual result folder reported by `lab eval`:

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
copy to the teammate doing Step 4; keep the original while this shell is open.
If download fails, tell the coach and preserve the current session;
do not treat archive creation as a successful backup.

<details>
<summary>If Cloud Shell reconnects without the original result folder</summary>

A completed evaluation in Foundry does not replace the original local manifest,
gate results and traces. Keep the existing evaluation ID, stop before comparison,
and ask the coach for help recovering the complete folder. Do not invent a
replacement passing manifest, weaken missing-evidence checks or silently rerun
the cases. Native results can still be inspected, but incomplete evidence must
not be presented as a qualified run.

</details>

All four candidates explicitly use the same `low` reasoning setting; do not
change it for only one matrix cell.
Start collection as soon as the final configurations exist; use the waiting
time to inspect cases and predict likely failure modes. Stagger team runs if
shared gateway/model limits require it.

### 3. Open the evaluation and investigate one result

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Evaluations**. Open the evaluation created by your command and then its run.
Inspect one wrong or failed answer and its matching native trace. For an agent's
traces, use **Build -> Agents -> your comparison agent -> Traces**.

Did it invent a fact, miss a necessary tool, use malformed arguments, encounter
a service error, or fail to follow the instructions? Write down one concrete
hypothesis. A run marked `Completed`, even with 100% task adherence, can still
fail the lab's additional fact, tool, template or trace checks.

<details>
<summary>Which test files and checks does the helper use?</summary>

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

</details>

### 4. Bring together the four results

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

It verifies matrix/input/coverage compatibility, identical actual tools/settings
and project, then writes Markdown/CSV with outcome/failure clusters, quality,
latency and available token measurements. Price only when all matching
model/token-category rates are known. Otherwise compare tokens/task; missing
prices, reasoning tokens or telemetry are not zero cost. Judge and shared-service
charges are separate from agent token estimates.

Open the generated Markdown report in VS Code; **Ctrl+Shift+V** opens its preview.
Compare quality and failures, response time, and the available token measurements.
Which configuration would you choose, and what evidence supports that choice?

<details>
<summary>How failed or incomplete candidates appear in the report</summary>

An omitted expected tool remains a quality failure even when provenance verifies
the calls that actually ran. The runner records that omission separately; it
must neither invent a span for the missing call nor qualify the candidate.

The report includes fully collected failed candidates without calling them
qualified. Incomplete runs or missing provenance cannot be included or ranked;
inspect their actual manifests directly. Do not use `lab compare` to rank
incomplete evidence.

</details>

### 5. If the tests fail, record that and continue the workshop

Keep the actual responses, manifests and trace investigation. If a few genuine
attempts still fail, explicitly stop and record **workshop-only/not qualified**
with the reason: wrong/missing facts or tools, missing trace evidence, or an
incomplete run such as a 429 interruption. These are different problems.
Failed results stay failed; incomplete results stay incomplete.

You may continue to B1 and the [human approval exercise](core-approval.md) after
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

Attempted M5 is sufficient to continue to B1/B3/B6 and to the core human approval
exercise. It does not qualify an agent or require a backend/evaluator bypass.
For workshop publication, the authorized human librarian must review the exact
proposal and explicitly accept the failed/incomplete-evaluation caveat.
Real projects require their stricter release policy; B6's production-style CI
gate remains strict and must block promotion on failed or incomplete evidence.

Before any human publication, the coach records that **all teams' frozen-corpus
attempts are completed or explicitly stopped**. Retain the corpus boundary and
actual outcomes. Later runs against changed published content are a new corpus,
not the original baseline; do not compare them as unchanged-corpus evidence.

Every later run against changed published documents uses different source
content; do not present it as the original unchanged comparison.

</details>

## You are done when

- Four actual immutable configurations and comparable real evidence, or recorded
  genuine attempts and an explicit workshop-only stop with evidence limitations.
- A numerical choice only with comparable evidence; otherwise no qualified
  winner and no ranking of incomplete evidence.
- A real worst-row trace investigation and a reasoned improvement hypothesis.

**If stuck:** the coach helps with actual run IDs, coverage and ingestion/auth
errors. Do not remove cases, lower thresholds or reuse fabricated/cached answers.
Publish nothing until **all teams'** frozen-corpus attempts finish or are
explicitly stopped and the human librarian accepts the workshop caveat.
