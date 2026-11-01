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

If your coach already enabled `lab`, keep that shell open. Otherwise use
**Cloud Shell PowerShell**, or local **PowerShell 7.5+** with Git, Azure CLI and
Python 3.11+. Cloud Shell has these tools already and runs Linux; it cannot see
your laptop's files.

For long M5 runs, prefer local PowerShell or already-mounted persistent Cloud
Shell storage. Temporary-session files can become unavailable after a reconnect;
keep the shell open and download each complete result folder using the
[M5 preservation steps](docs/modules/m5-evaluation.md#2-create-and-test-your-assigned-configuration).

### 1. Clone the public tools

No GitHub sign-in or coach-prepared shell is needed.
In Azure portal open **Cloud Shell -> PowerShell**, then:

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

### 2. Supply only your deployment configuration

You need only the coach-supplied **`workshop.json`**, not a ZIP, prompts,
evaluation files or an integrity receipt. In Cloud Shell use
**Manage files -> Upload** for that one JSON file. Locally, use its existing
path. `./workshop.json` works when that file is in your current directory.
Keep configuration private; do not commit it to the repository.

```powershell
$configuration = Read-Host 'Path of your workshop.json in this shell'
$team = 'alpha'       # Your assigned team.
$prefix = 'alpha-p2'  # Your assigned team and participant.
```

Use the JSON from the **same deployment and team** you are rehearsing.
Matching exercise files alone do not prove that your account has access.
If the coach supplies a common deployment JSON instead, its `projects` map must
declare your actual team endpoint. Do not invent a team or edit model bindings.

### 3. Assemble the local inputs and enable `lab`

From the clone's root run the following. The **dot followed by a space** matters:
it keeps the command available in this PowerShell session.

```powershell
. ./workshop/Start-Lab.ps1 -Configuration $configuration -Team $team -Prefix $prefix
```

The starter assembles the prompts, portal OpenAPI, unchanged evaluation inputs
and a new integrity receipt from this checkout under ignored `out/`.
It prints their location and records the source revision. It uses `.venv`,
installing the declared dependencies only when required modules are missing.
It installs prebuilt wheels, not local compiler builds. If compatible wheels
are unavailable on your computer, keep the error and use Cloud Shell; do not
install Rust or change package versions to get past it.
It does not deploy infrastructure, create agents or run evaluations.

If sign-in is needed, open the printed device-login page in Edge and use
**your own workshop account**. The starter uses a separate Azure CLI profile for
your prefix, not the organizer's login. Cloud Shell's automatic sign-in does not
necessarily include the required `Lab.Access` scope. A token acquisition error
before the sign-in prompt means this isolated profile needs authentication;
if sign-in itself fails, stop and report that error.

### 4. Check access, then continue M3

```powershell
lab check
lab practice status
```

Keep this shell open. `lab check` performs real Foundry agent-list and
authenticated documentation-read checks; it is **not** authoring-permission or
release acceptance. `lab practice status` reports your own existing practice
APIs; missing ones are expected until you create them in the exercises.
If a command reports a missing permission, stop and give the coach the operation
and error. Input assembly cannot repair access; do not borrow an administrator's
account. Successful read checks do not prove authoring permissions.

Cloud Shell sessions without storage are temporary; local files can become
unavailable after reconnecting. Use `download $archive` in Cloud Shell PowerShell, followed
by clicking the filename in its **Download file** notification. The command alone
does not save a copy on your laptop. Do not rely on leaving the browser open or
merely creating an archive. Before M5, verify that a small file can
actually be downloaded and opened locally. Then archive each complete result
folder and verify its downloaded copy before ending the session. A manifest path
alone is not a copy of the results. M5 shows the archive and hash commands. If
download fails, keep the current shell open and tell the coach; do not create storage,
share links or change access permissions as an improvised workaround.

The helper checks the generated files against their receipt. If they change,
keep the error and rerun setup from the correct unchanged source/configuration.
Do not edit the receipt or change `runtime_accepted`. New setup creates a fresh
input directory rather than overwriting old evidence.

</details>

## When something fails

Record operation, endpoint, timestamp, status and response/trace ID, without
credentials. Respect `Retry-After` on throttling; separate agents still share
capacity and some counters. Do not retry indefinitely, disable auth or substitute
fake responses. Longer diagnostics belong in the [coach guide](docs/coach-guide.md).
