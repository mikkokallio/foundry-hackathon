# Participant: start here

Build an agent that answers questions about business systems and helps write
their documentation. Give it access to evidence, explore reusable tools and
investigate how well its answers hold up.

**Start with [M1](docs/modules/m1-foundry.md) in your browser.**
It explains how to open Foundry and choose your team's project; no developer
tools need installing to begin.

## Before you start

Your coach provides:

1. **Your workshop account, directory and team project.** Sign in with your own
   assigned account.
2. **Your team's pack.** Unzip it so you can open the ready-to-paste prompts and
   your team's `workshop.json`.
3. **Your team and participant number.** Use them at the start of names:
   Alpha participant 2 uses **`alpha-p2`**, for example `alpha-p2-baseline`.

The shared services and working examples are already set up. You are encouraged
to create your own agents, APIs, MCP servers and catalog entries, but **only edit
resources you created**. Leave shared examples and other participants' work alone.
Names help identify your work; they are not access barriers. Changes to shared
services can affect other teams.

## Choose your pace

- **Pair up or observe.** One person can drive while others discuss the answers
  and inspect results. If you have no environment access, follow a teammate
  or the coach's demonstration.
- **Use the marked shortcuts.** They let you continue with an existing
  integration if building takes longer. You can return to your own attempt later.
- **Focus on learning.** Useful findings and questions matter more than finishing
  every task. You do not need a production-ready application or every bonus completed.

## The learning journey

Follow these guides in order. Each explains the purpose, actions and expected
observations. The module tells you when an activity is optional or can be skipped.

| Module | What you build or investigate |
|---|---|
| [M1: Create an agent and compare answers](docs/modules/m1-foundry.md) | Use one agent, switch its model connection and inspect a conversation record. |
| [M2: Connect inventory and documents](docs/modules/m2-tools.md) | Build your own integration or attach the existing team connection; look up evidence and check a draft. |
| [M3: Observe traffic and explore limits](docs/modules/m3-governance.md) | Find a model request and chart token usage; optionally explore request, token and tool limits. |
| [M4: Discover and reuse a toolkit](docs/modules/m4-discovery.md) | Find and use diagram/checking tools; register your own integration if you want to. |
| [M5: Evaluate and investigate](docs/modules/m5-evaluation.md) | Inspect test cases, run a Foundry portal evaluation and investigate the scores; consider a prompt improvement. |
| [Review and save your final proposal](docs/modules/core-approval.md) | Return to your draft, approve its exact text, save it and check the saved copy matches. |

## Optional bonus tasks

Pick a topic that interests you. Knowledge retrieval is a recommended next task:
explore indexed documents and how their passages can support an agent's answers.
Ask the coach which extensions are available for this workshop.

[Knowledge retrieval](docs/bonus/b1-knowledge.md) /
[build your own MCP server](docs/bonus/b2-own-mcp.md) /
[multiple agents working together](docs/bonus/b3-multi-agent.md) /
[reliability, safety and caching](docs/bonus/b4-resilience.md) /
[cost and access control](docs/bonus/b5-cost-identity.md) /
[automated testing](docs/bonus/b6-ci.md) /
[advanced saving rules](docs/bonus/b7-writeback.md) /
[coding client](docs/bonus/b8-coding-client.md) /
[local app](docs/bonus/b9-local-app.md).

<a id="powershell-helper-setup"></a>

## Optional Cloud Shell helper setup

<details>
<summary>Expand only when an exercise asks you to use the lab commands</summary>

This enables the `lab` commands when an exercise asks for them. You can pair
with someone rather than set up a second session.

If `lab` already works in your Cloud Shell session, keep using it. Otherwise
open [Azure portal](https://portal.azure.com), select the **Cloud Shell** toolbar
button and choose **PowerShell**. Cloud Shell has the required tools and runs
separately from your laptop; files on your laptop are not automatically available.

Keep the session open. Temporary-session files can become unavailable after a
reconnect; download any results you want to keep before closing it.

### 1. Clone the public tools

No GitHub sign-in or coach-prepared shell is needed.
In Azure portal open **Cloud Shell -> PowerShell**, then:

```powershell
Set-Location $HOME
git clone --depth 1 https://github.com/mikkokallio/foundry-hackathon.git
if ($LASTEXITCODE -ne 0) { throw 'Workshop repository download failed.' }
Set-Location (Join-Path $HOME 'foundry-hackathon')
```

If that folder already exists, reuse the workshop checkout rather than cloning
over it. Do not overwrite an existing exercise or pull changes during a run.
### 2. Upload your team configuration

Use **Manage files -> Upload** for the coach-supplied **`workshop.json`** from
your own team pack. You need only that file, not the ZIP or the rest of the pack.
`./workshop.json` works when the uploaded file is in your current directory;
otherwise use its full Cloud Shell path.
Keep configuration private; do not commit it to the repository.

```powershell
$configuration = Read-Host 'Path of your workshop.json in this shell'
$team = 'alpha'       # Your assigned team.
$prefix = 'alpha-p2'  # Your assigned team and participant.
```

Check that `$team` and `$prefix` match your assigned team and participant.
Do not change the configuration's endpoints or model bindings to bypass an error.

### 3. Enable the lab commands

From the clone's root run the following. The **dot followed by a space** matters:
it keeps the command available in this PowerShell session.

```powershell
. ./workshop/Start-Lab.ps1 -Configuration $configuration -Team $team -Prefix $prefix
```

The starter prepares the exercise inputs and installs missing declared Python
dependencies. It does not deploy infrastructure, create agents or run evaluations.
If setup fails, keep the error and ask the coach rather than changing packages.

If sign-in is requested, open the printed device-login page in your browser and
use **your own workshop account**. Cloud Shell's automatic sign-in is not always
enough for these commands. If sign-in fails, keep the error and ask the coach.

### 4. Check access, then return to your exercise

```powershell
lab check
lab practice status
```

Keep this shell open. `lab check` performs real Foundry agent-list and
authenticated documentation-read checks. It does not prove that you can create
or edit resources. `lab practice status` reports your own existing practice
APIs; missing ones are expected until you create them in the exercises.
If a command reports a missing permission, keep the operation and error and ask
the coach. Do not borrow an administrator's account.

Return to [M3's optional requests](docs/modules/m3-governance.md#3-optional-send-a-normal-request-from-cloud-shell)
or the exercise that sent you here.

</details>

## When something fails

Keep the step, selected project, error message and time, plus any available
response/trace ID. Do not include credentials. Ask the coach or inspect the
problem with a teammate.

If throttled, respect `Retry-After`; separate agents still share capacity and
some counters. Do not retry indefinitely, disable authentication or substitute
invented results.
