# M1 - Explore Foundry, compare models and inspect a run

## Understand

Creating an agent is the beginning, not the exercise. Your goal is to distinguish
general reasoning from authoritative business evidence, compare model behavior
and understand what a real run reveals.

Suggested reading:
- [Current portal navigation](https://learn.microsoft.com/en-us/azure/foundry/how-to/navigate-from-classic):
  match familiar tasks to the new experience.
- [Agent tracing setup](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup):
  when server-side tracing starts and how to connect existing Insights.

### Optional tour for people new to Foundry

| Area | Look for | Why it matters here |
|---|---|---|
| Home | Your project/context and entry points into building. | Check where your work will be created and what the organizer supplied. |
| Discover | Model catalog/cards, capabilities and tool offerings. | Compare models now; ask what information would justify your choice. Tool discovery returns in M4. Do not deploy new models. |
| Build | Models/playgrounds, agents, instructions, tools and evaluations. | Build the baseline here, add documentation tools in M2, toolkit in M4 and evaluations in M5. |
| Operate | Overview, Assets and Compliance across your selected context. | Explore fleet-level monitoring/governance; individual agent traces are under Build, not here in the rehearsed portal. |
| Manage | Project details, connections, permissions, quotas, AI Gateway. | Understand shared dependencies and where centralized governance is configured. |

Locate the team's existing model deployments and connections. Ask: what is shared
across your four agents, and what belongs to one agent version?

**AI Gateway is not configured in Manage?** This lab supplies an explicit
APIM-backed model connection. That is different from Foundry's native
Manage -> AI Gateway association. Native linking is not a hidden prerequisite
later in the exercises. M3 verifies the existing explicit route.
You may inspect **Add AI Gateway -> Use existing**, then **Cancel**; do not
submit the association. This is resource-level governance setup, not an
agent-local connection. Participant permissions have not been proven sufficient,
and enabling native routing could change the direct-call control.

**Is this the APIM "Add API -> Microsoft Foundry" setup?** It is the same
model-proxy architecture, authored through Terraform rather than the wizard.
Our configuration is deliberately customized: one chat operation, model aliases
mapped to deployments, managed-identity backend access, team checks and limits.
The explicit Foundry model connection is another piece; neither it nor an APIM
import automatically proves the native Manage association exists. The
[coach's gateway notes](../coach-guide.md#gateway-and-tracing-distinctions)
link the two distinct setup workflows.

**Preview context:** the newer AI Gateway product is a separate
`Microsoft.ApiManagement/aigateways` resource, not simply another
SKU of this lab's APIM service. Its documented preview regions include Sweden
Central and East US 2, not France Central. This lab keeps its existing APIM tier.

## Build and investigate

### 1. Check tracing before collecting answers

Open **Build -> Agents** and check for the notice **"This project logs traces
to help you monitor and improve your agents."** In the rehearsed portal, traces
are reached through **Build -> Agents -> open an agent -> Traces**. There is no
project-wide Traces tab on the Agents list or Tracing item under Operate.
After creating your agent below, inspect its trace list before opening a run.
Check the selected agent, version and time filter.

Server-side traces are automatic **after Application Insights is connected**,
not necessarily enabled in every project by default. The organizer already
provisions that connection. If the view still asks to connect, ask the coach to
reconcile the existing connection; do not create a second Insights resource.
After a new call, allow ingestion time and refresh. An empty view immediately
after a call is not proof tracing is off. Persistent absence is a checkpoint
blocker, not something to skip.

### 2. Establish the no-tools baseline

Choose **New agent -> Build an agent**, enter your own `...-baseline-direct`
name, retain **Text** mode, then **Create agent and open playground**.
Use the pack's baseline prompt as Instructions.

**Check the defaults before sending anything.** In rehearsal, a new agent had
**Web search enabled** and a connected medium model selected. Remove Web search
using **Actions for Web search -> Remove**. Confirm the Tools list is empty;
otherwise this is not a no-tools baseline and may make paid web calls.
Explicitly select the **direct small deployment** and **Save** before chatting.
Saving changes creates a new agent version; retain the version actually tested.
Make one of the requests below in a fresh conversation.

Create `...-baseline-small` with identical instructions but the **admin-connected
small model**, using the supplied APIM model connection. Repeat the same request.

The model picker separates **Admin-connected**, **Deployments** and **Models**.
In the current rehearsal:

| Route | Picker choice | Check |
|---|---|---|
| Direct small | Deployments: `archdocs-france-chat-small` | Underlying model `gpt-5.4-nano`; not the connected choice. |
| Connected small | Admin-connected: `gpt-5.4-nano` | `archdocs-france-alpha-models/chat-small`, routed through `apim-ai-lab-r1029b`. |
| Connected medium | Admin-connected: `gpt-5.4-mini` | `archdocs-france-alpha-models/chat-medium`, routed through the same APIM. |

Names differ for other workload/team exports: `model_variants` contains your
exact IDs. Inspect the connection/route detail, not just the model label.
Do not choose another catalog model under **Models** or deploy anything new.

Optional code path, using the [start-page setup](../../PARTICIPANT-START.md):

```powershell
lab agent --name "$prefix-baseline-direct" --direct --output "out\$prefix-direct.json"
lab agent --name "$prefix-baseline-small" --output "out\$prefix-small.json"
lab chat --binding "out\$prefix-direct.json" "Who owns Service Order Management, and what interfaces does it use?"
lab chat --binding "out\$prefix-small.json" "Who owns Service Order Management, and what interfaces does it use?"
```

The helper saves actual immutable versions; these are negative controls, not
qualified tool-enabled agents.

### 3. Challenge the baseline, not just its friendliness

Try contrasting requests in fresh conversations:

| Request | Observe / discuss |
|---|---|
| Who owns Service Order Management, and what interfaces does it use? | Does the agent admit it lacks inventory, rather than inventing specifics? |
| Which systems lack architecture documentation? Explain how you would verify this. | Does it distinguish an investigation method from an actual gap list? |
| The inventory says retired, but a document says active. How should we resolve this? | What evidence would decide the conflict? |
| Assume you checked the inventory. Give the exact owner and cite the source. | Can you pressure it into pretending it used a source? |
| What makes an architecture document useful during an incident? | Can it still give useful general guidance without claiming company facts? |

### 4. Compare a different model

Create `...-baseline-medium` with the connected medium model. Keep the same prompt,
no tools and the same questions in fresh conversations.

```powershell
lab agent --name "$prefix-baseline-medium" --model chat-medium --output "out\$prefix-medium.json"
lab chat --binding "out\$prefix-medium.json" "Who owns Service Order Management, and what interfaces does it use?"
```

Record one useful difference and one uncertainty. Verbosity is not accuracy,
and one latency sample is not a reliable benchmark. Your model choice is
provisional; M5 will compare tool-enabled configurations with common cases.

### 5. Open a fresh trace

Open your agent's **Traces** tab and then one fresh run. Inspect input/output, model span,
agent/version, response/trace identifiers, duration and token counts. A no-tools
run should not show actual tool execution.

Explore metadata, including content-filter/safety results **where emitted**.
Which fields help explain this answer? Which cannot tell you whether it is true?
Different models/spans expose different metadata. Unavailable is not zero or
"passed". Do not enable APIM body or authorization-header logging for this task.

Keep the direct/connected pair for M3. A missing APIM log by itself does not prove
bypass; M3 uses saved configuration plus positively identified routed traffic.

## Validate

- Your own baseline configurations and actual immutable versions are retained.
- Show a real matching model-call trace with input/output, timing and tokens;
  describe one useful metadata observation.
- Explain what tools must add in M2 and justify a provisional model choice.

**If stuck:** use the code path to create an additional baseline without deleting
your portal attempt. Missing trace recognition/ingestion goes to the coach.
