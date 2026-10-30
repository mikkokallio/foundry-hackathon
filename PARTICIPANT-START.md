# Participant: start here

A full-day hackathon with **4.5 hours of hands-on work**. Build an architecture
documentation steward, connect real tools, govern traffic, discover reusable
capabilities and compare agent configurations. All business data is synthetic.

**Preview:** minor updates to the M1-M5 exercises are likely.
Your coach provides the environment details and helps with any setup issues.

## What is already there, and what you build

Terraform provides the hack-ready starting point: foundation services,
workload/project resources, model deployments and working reference integrations.
**You are encouraged to build your own APIs, MCP servers, agents and catalog
entries.** Do not deploy Terraform or edit Terraform-owned reference resources.

Four people share each project. Use `<team>-p1` through `<team>-p4` as personal
prefixes, for example `alpha-p1-steward`. Each person owns their agents, versions,
conversations, practice APIs and findings. Share the existing services, models,
project identity and corpus. Names are a coordination convention, not isolation:
service-scoped authoring can affect other teams. Never edit somebody else's work.

Your coach provides the tenant/project, actual service names and a fresh exported
team pack. Sign in with **your own authorized identity** in that tenant. Missing
access goes to the coach; do not borrow an administrator's token or create a
replacement service.

## The learning journey

Each guide follows **Understand -> Build -> Validate**. Questions invite you to
interpret what you observe; a plausible answer is not evidence of tool execution.

| Module | What you build or investigate |
|---|---|
| [M1: Foundry, models and traces](docs/modules/m1-foundry.md) | Useful tour, no-tools baselines, controlled model/routing comparison and a real trace. |
| [M2: REST -> MCP -> agent](docs/modules/m2-tools.md) | Your own authenticated documentation integration, real inventory lookup and document validation. |
| [M3: Gateway governance](docs/modules/m3-governance.md) | Routing evidence, separate request/token experiments, tool throttles and usage charts. |
| [M4: Register, discover and reuse](docs/modules/m4-discovery.md) | A useful catalog entry, then discovery and first use of the independent toolkit. |
| [M5: Evaluate and choose](docs/modules/m5-evaluation.md) | Four controlled configurations, fresh evaluations, comparison and worst-row investigation. |
| [Core: review and save](docs/modules/core-approval.md) | Exact-text approval, persisted proposal and separate human-only publication. This is not a bonus. |

Try building first. The **reference implementations** and code/checkpoint paths
help if you get stuck. If you use one, compare it with your own integration.
Catch-up never deletes your work.

## Optional local code path

Portal steps do not require a Copilot license. For the Python alternative, run
from this workspace root in PowerShell 7, with Python 3.11+ and the repository's
environment. If creating a new environment, install the declared dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\scenarios\architecture-docs\scripts\requirements-gate.txt
$python = (Resolve-Path .\.venv\Scripts\python.exe).Path
$pack = 'EXACT_EXPORTED_DIRECTORY\workshop.json'
$prefix = 'alpha-p1' # Replace with your assigned team and participant.
$context = Get-Content $pack -Raw | ConvertFrom-Json
az login --tenant $context.tenant_id
az account set --subscription $context.subscription_id
function lab {
    & $python -m workshop --pack $pack --prefix $prefix @args
    if ($LASTEXITCODE -ne 0) { throw 'Workshop command failed; inspect the error above.' }
}
lab check
```

`lab` above is a local PowerShell function around the implemented Python module,
not an installed Azure command. Keep this shell open. `check` verifies real
Foundry listing and authenticated REST reading, **not all authoring permissions**.
The helper verifies the pack's file hashes; export a fresh pack if they differ.
Do not edit receipts or set `runtime_accepted` to true.

## Choose further depth

[Knowledge](docs/bonus/b1-knowledge.md) /
[own MCP](docs/bonus/b2-own-mcp.md) /
[multi-agent](docs/bonus/b3-multi-agent.md) /
[resilience/safety/cache](docs/bonus/b4-resilience.md) /
[cost and identity](docs/bonus/b5-cost-identity.md) /
[CI](docs/bonus/b6-ci.md) /
[write-back boundaries](docs/bonus/b7-writeback.md) /
[coding client](docs/bonus/b8-coding-client.md) /
[local app](docs/bonus/b9-local-app.md).

Check each bonus's prerequisites before starting. Publication changes everyone's
corpus: coordinate it **after all
teams' frozen-corpus evaluations**. Saving a proposal does not publish it.

## When something fails

Record operation, endpoint, timestamp, status and response/trace ID, without
credentials. Respect `Retry-After` on throttling; separate agents still share
capacity and some counters. Do not retry indefinitely, disable auth or substitute
fake responses. Longer diagnostics belong in the [coach guide](docs/coach-guide.md).
