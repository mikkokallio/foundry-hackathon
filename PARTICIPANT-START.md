# Participant: start here

A full-day hackathon with **4.5 hours of hands-on work**. Build an agent that
answers questions about systems and helps write their documentation. Connect it
to real tools, investigate traffic limits and compare its answers across models.
The workshop's business data is made up, not real customer data.

**Preview:** minor updates to the M1-M5 exercises are likely.
Your coach provides the environment details and helps with any setup issues.

**Start with [M1](docs/modules/m1-foundry.md) in Microsoft Edge.**
M1 explains how to open Foundry and choose your team's project. You do not need
Python, a terminal or a Copilot license for M1.

## Before you start

Your coach has already set up the shared services, projects, models and working
example integrations.
**You are encouraged to build your own APIs, MCP servers, agents and catalog
entries.** Do not run the infrastructure deployment or change the coach's shared
resources and example integrations.

Four people share each project. Your coach assigns a team and participant number.
For example, **team Alpha, participant 2 uses `alpha-p2`** at the start of names:
`alpha-p2-baseline-direct`. Participant 1 uses `alpha-p1`; participants 3 and 4
use `alpha-p3` and `alpha-p4`.

You will see other people's agents in the same project. These names identify
your work; they do not restrict access. Only edit agents and practice resources
you created. Changes to shared services can affect other teams too.

Your coach provides the sign-in account/directory, project and service names, and
an exercise folder containing prompts, test questions and your team's
`workshop.json` configuration. Sign in with **your own assigned account**.
If something is missing or you cannot access it, ask the coach. Do not use an
administrator's account or create a replacement service.

## The learning journey

Follow these guides in order. Each asks you to build something, try it and check
what actually happened.

| Module | What you build or investigate |
|---|---|
| [M1: Foundry, models and traces](docs/modules/m1-foundry.md) | Create three agents, compare their answers and inspect a conversation record. |
| [M2: REST -> MCP -> agent](docs/modules/m2-tools.md) | Your own authenticated documentation integration, real inventory lookup and document validation. |
| [M3: Gateway governance](docs/modules/m3-governance.md) | Routing evidence, separate request/token experiments, tool throttles and usage charts. |
| [M4: Register, discover and reuse](docs/modules/m4-discovery.md) | A useful catalog entry, then discovery and first use of the independent toolkit. |
| [M5: Evaluate and choose](docs/modules/m5-evaluation.md) | Four controlled configurations, fresh evaluations, comparison and worst-row investigation. |
| [Core: review and save](docs/modules/core-approval.md) | Review a draft, approve its exact text, save it and check the saved copy matches. |

Try building first. If you get stuck, ask the coach or use a working example.
Compare that example with your own attempt; you do not need to delete your work.

## Optional bonus tasks

After the main exercises, you can explore a topic in more depth. Knowledge
retrieval is the recommended next task: let your agent find answers in documents.
The other links cover advanced extensions. Ask the coach which are available
for this workshop; you do not need to complete them all.

[Knowledge retrieval](docs/bonus/b1-knowledge.md) /
[build your own MCP server](docs/bonus/b2-own-mcp.md) /
[multiple agents working together](docs/bonus/b3-multi-agent.md) /
[reliability, safety and caching](docs/bonus/b4-resilience.md) /
[cost and access control](docs/bonus/b5-cost-identity.md) /
[automated testing](docs/bonus/b6-ci.md) /
[advanced saving rules](docs/bonus/b7-writeback.md) /
[coding client](docs/bonus/b8-coding-client.md) /
[local app](docs/bonus/b9-local-app.md).

## PowerShell helper setup

<details>
<summary>Setup for M3 and M5 commands; optional for M1, M2 and M4</summary>

M3 uses `lab` commands to generate bounded test traffic; M5 uses them to create
and compare evaluation runs. They are not just emergency fallbacks in those
modules. M1, M2 and M4 have browser routes without the Python helper.
You do not need to write application code.

If your coach already set up the terminal, reuse that setup rather than creating
another Python environment or changing its sign-in. Choose one option:

### Option A: local Windows PowerShell

Use PowerShell 7, Azure CLI and Python 3.11+. Open the terminal at the repository
root, where the `workshop` folder is. Keep your coach-supplied team pack on this
computer. For a new setup, create the Python environment and install its
dependencies **only if `.venv` does not already exist**:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\scenarios\architecture-docs\scripts\requirements-gate.txt
```

Set the interpreter:

```powershell
$python = (Resolve-Path .\.venv\Scripts\python.exe).Path
```

### Option B: Cloud Shell PowerShell

In Azure portal select the **Cloud Shell** toolbar button and choose
**PowerShell**. Azure CLI and Python are already available. Cloud Shell runs
Linux and cannot see files on your laptop.

For M3/M5, you need the **repository and complete team pack** in this shell.
Clone the public repository yourself; no GitHub sign-in or coach-prepared shell
is needed:

```powershell
Set-Location $HOME
git clone --depth 1 https://github.com/mikkokallio/foundry-hackathon.git
if ($LASTEXITCODE -ne 0) { throw 'Workshop repository download failed.' }
Set-Location (Join-Path $HOME 'foundry-hackathon')
git rev-parse HEAD
```

If that folder already exists, reuse the workshop checkout rather than cloning
over it. Do not overwrite an existing exercise or pull changes during a run.
Record the printed source revision with your results. A clone contains the
published commit, not unpublished changes on somebody else's laptop.

Use **Manage files -> Upload** to upload your assigned **complete team pack ZIP**,
then extract it. The team pack contains deployment-specific settings and exercise
files; cloning the repository does not replace it.

```powershell
$packArchive = Read-Host 'Path of the uploaded team pack ZIP'
$packFolder = Join-Path $HOME 'workshop-team-pack'
Expand-Archive -LiteralPath $packArchive -DestinationPath $packFolder
Get-ChildItem -LiteralPath $packFolder -Filter workshop.json -Recurse |
    Select-Object -ExpandProperty FullName
```

Keep the printed `workshop.json` path for the sign-in step below. Do not use
`-Force` to overwrite an earlier pack. Uploading only `workshop.json` is enough
for M2's REST check, but not for the Python helper, which checks the other files
against the pack's integrity receipt.

From the cloned repository root, create an environment **only if `.venv`
does not already exist**, then select its Linux interpreter:

```powershell
python -m venv .venv
./.venv/bin/python -m pip install -r ./scenarios/architecture-docs/scripts/requirements-gate.txt
$python = (Resolve-Path ./.venv/bin/python).Path
```

**Test coverage:** Cloud Shell PowerShell setup, authenticated reads, practice
API/MCP creation, model calls and request/token throttling have passed rehearsal.
MCP connection creation required a separately approved Alpha participant
permission fix; do not assume every team's access is ready. One real evaluation
completed with failed checks, and knowledge retrieval executed. The complete
four-way Cloud evaluation/comparison route is not yet verified. Result export
using the native `download` command passed with a nested 6 MiB test and with
four real result folders uploaded from local evaluation, repacked in Cloud Shell
and downloaded: archive SHA256 matched and all 172 result files matched locally.
That transfer check does not turn local evaluations into Cloud execution.
Verify that export works in your session before starting M5.

### Continue in either shell: sign in and enable the commands

Use the location of `workshop.json` **in the shell you chose**, not its path on
another computer. In Cloud Shell, use the path printed after extraction above;
`./workshop.json` also works if your current folder contains that file.
This example is for Alpha participant 2.
When `az login` prints a device code, open its sign-in page in Edge, enter the
code and finish signing in with your **own workshop account**. If asked, select
the coach's subscription. Cloud Shell's automatic sign-in alone does not give
access to the documentation API; the `--scope` below is required.
If you completed M2's login in this same shell, reuse it and skip `az login`
and `az account set`.

```powershell
$pack = Read-Host 'Paste the full path of your team pack workshop.json in this shell'
$prefix = 'alpha-p2' # Replace with your assigned team and participant.
$context = Get-Content $pack -Raw | ConvertFrom-Json
$env:AZURE_CONFIG_DIR = Join-Path $HOME ".foundry-hackathon-$prefix"
az login --tenant $context.tenant_id --scope $context.gateway_scope --use-device-code
if ($LASTEXITCODE -ne 0) { throw 'Workshop sign-in failed.' }
az account set --subscription $context.subscription_id
if ($LASTEXITCODE -ne 0) { throw 'Workshop subscription selection failed.' }
function lab {
    & $python -m workshop --pack $pack --prefix $prefix @args
    if ($LASTEXITCODE -ne 0) { throw 'Workshop command failed; inspect the error above.' }
}
lab check
```

The separate sign-in folder avoids replacing the coach's Azure CLI login.

Keep this shell open: `lab` is the function you just defined, not a built-in Azure
command. `lab check` checks that it can list agents and read the documentation
API. It does not prove you have permission for every later task.

Cloud Shell sessions without storage are temporary. Rehearsal lost its workspace
after a disconnected session expired, and **Manage files -> Download** failed.
The tested alternative is `download $archive` in Cloud Shell PowerShell, followed
by clicking the filename in its **Download file** notification. The command alone
does not save a copy on your laptop. Do not rely on leaving the browser open or
merely creating an archive. Before M5, verify that a small file can
actually be downloaded and opened locally. Then archive each complete result
folder and verify its downloaded copy before ending the session. A manifest path
alone is not a copy of the results. M5 shows the archive and hash commands. If
download fails, keep the current shell open and tell the coach; do not create storage,
share links or change access permissions as an improvised workaround.

The helper checks that the exercise files have not changed. If it reports a
file mismatch, ask the coach for a fresh export. Do not edit the integrity receipt
or change `runtime_accepted`.

</details>

## When something fails

Record operation, endpoint, timestamp, status and response/trace ID, without
credentials. Respect `Retry-After` on throttling; separate agents still share
capacity and some counters. Do not retry indefinitely, disable auth or substitute
fake responses. Longer diagnostics belong in the [coach guide](docs/coach-guide.md).
