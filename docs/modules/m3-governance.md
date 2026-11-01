# M3 - See the traffic and test gateway limits

## What you will do

Find your agent's model request in APIM logs, test separate request and token
limits on your own APIs, then test a tool limit and restore it.

This module uses the **browser and PowerShell commands**. Complete the
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup) and keep that
shell open. Choose **local PowerShell** or **Cloud Shell PowerShell** there;
Cloud Shell needs scoped sign-in: the linked setup shows how to clone the
public repository, supply only your team's JSON configuration and enable `lab`.
The starter assembles the common exercise files locally; no complete pack upload
is needed. Input assembly is not proof of effective participant permissions.
The `lab` commands below are the same after setup in either shell.
No application coding is required. For these examples, `$prefix`
is `alpha-p2`, meaning Alpha participant 2; use your own assigned prefix.
Never change the shared reference's limits.

<details>
<summary>Optional reading: gateway policies</summary>

- [APIM AI gateway capabilities](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities).
- [Token rate/quota policy](https://learn.microsoft.com/en-us/azure/api-management/llm-token-limit-policy).
  Existing reference policies may retain the older Azure OpenAI-specific names.

</details>

## Build and investigate

### 1. Find an agent's model request in the gateway logs

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Agents**. Revisit your M1 direct and connected-small agents, for example
`alpha-p2-baseline-direct` and `alpha-p2-baseline-small`. Inspect the saved definitions:
the direct model is a deployment; the connected ID is `<connection>/<alias>`.
Read that connection's actual target in **Manage -> Project details ->
Connected resources**.

In [Azure portal](https://portal.azure.com), search for **Application Insights**
and open the instance assigned by the coach. Select **Logs**. Use the
[gateway request query](../../scenarios/architecture-docs/exercises/queries/gateway-observations.kql);
Step 5 explains switching the editor to KQL mode.

Find the **connected model request** in APIM/Application Insights using its API,
timestamp and available correlation identifiers. Do not mistake an MCP request
for the agent's model request. The direct deployment bypasses this explicit
route unless another routing mechanism applies; absence of a log alone is not
proof. The unconfigured native **Manage -> AI Gateway** view is not this custom
APIM connection's traffic dashboard.

### 2. Send one normal model request

If you have finished Step 1, continue here; do not repeat M1 or M2. If `lab`
is not available yet, open **Cloud Shell -> PowerShell** and follow the
[public clone + team JSON setup](../../PARTICIPANT-START.md#1-clone-the-public-tools),
then return here. Keep the same assigned prefix and your existing M2 MCP server
and steward. Setup does not recreate them or deploy infrastructure.

Make a normal authenticated request, inspect actual usage/status and available
remaining-token/retry headers:

```powershell
lab practice status
lab gateway
```

`lab practice status` only reads your owned routes, using the native MCP API
version for the MCP server. `Missing` means that route returned 404; permission
or service errors stop the command instead. It does not create missing routes.

`lab gateway` directly exercises the model gateway. It is useful policy evidence,
but **not** substitute proof that your agent's model traffic uses that route.

### 3. Test request and token limits separately

Create your own model practice APIs. Reuse existing model deployments and the
reference auth/routing policy. Keep one API request-limited with a generous
token allowance, and another token-limited with a higher request allowance.
If both are tight on one route, the first failure can mask the other.

The helper creates two model APIs with your own prefix. For example, Alpha
participant 2's names start with `alpha-p2-`; the helper reports the actual names.
It does not create new model deployments:

```powershell
lab practice models
lab gateway --route requests --burst
lab gateway --route tokens --burst
```

The bounded burst stops on a real 429 or fails after six attempts. Inspect the
originating policy/upstream result; respect `Retry-After` and demonstrate a later
successful request. If the token test does not trigger, use one deliberately
longer synthetic prompt or adjust **your practice policy**, rather than hammering
shared capacity. Never change shared reference limits or bypass the gateway.

<details>
<summary>If the token test did not reach the limit</summary>

Try this longer synthetic prompt once. The helper still stops after six attempts:

```powershell
lab gateway --route tokens --burst --query 'Write a detailed synthetic explanation of how a fictional architecture team maintains documentation. Use at least 200 words. Do not describe any real customer.'
```

The response length is capped by the helper; this is a traffic-limit test, not a
test of whether the model writes 200 words. Stop when you see 429, respect
`Retry-After`, then make one normal request to check recovery.

</details>

In Azure portal, open your assigned **API Management services** instance ->
**APIs**, then select one of the new APIs with your prefix. In **Design ->
All operations -> Inbound processing -> code editor**, inspect its request and
token limits. Only edit your own practice APIs; predict the outcome before
calling again.

<details>
<summary>Why the measured limit may not be an exact counter</summary>

Rehearsal observed three successes with a 2/minute request
policy, and 344 tokens with a 256-TPM policy, before the respective 429s.
Limits are not exact counters or a guaranteed billing hard cap.

</details>

### 4. Test a tool limit, then restore it

Use the browser for this experiment:

1. In **Azure portal -> your APIM instance -> MCP Servers**, select **your**
   documentation MCP server, for example `alpha-p2-docs-mcp`, then **MCP -> Policies**. Do not select the
   reference or somebody else's server. Copy the complete original policy
   before editing; preserve its exact text for restoration.
2. Locate its inbound `rate-limit-by-key` block and note the existing `calls`
   and `renewal-period` values. Temporarily use a small limit, such as
   `calls="1" renewal-period="60"`. Keep authentication/routing
   intact. A unique practice counter suffix avoids reusing an earlier
   experiment's counter; retain API/team isolation. Select **Save**, confirm
   **Policy saved**, and allow propagation. Rehearsal waited 65 seconds;
   this is an observed wait, not a propagation guarantee.
3. In Foundry, open your steward, for example `alpha-p2-steward`, then its
   **Playground**. Select a known saved version with the
   intended owned MCP server. Start a **New chat** and ask for exactly one
   fresh `listSystems` call, no automatic retries and no writes. If a call
   reaches approval, choose **Approve -> Approve once**, not an always-approve
   option. Bound the experiment to six fresh requests at most; stop on the
   observed throttle rather than hammering the endpoint.
4. Record the actual failure stage, status, body and any exposed retry headers.
   MCP discovery (`initialize`/`tools/list`) and `tools/call` are different
   stages. A discovery throttle prevents the inventory tool from running;
   it is not evidence that an inventory operation itself returned 429.
   A retry interval in an error body is not proof of a `Retry-After` header.
5. In a cleanup/finally step, restore the **complete original policy through
   the same editor**, even after a failed experiment. Save, reopen/reload the
   policy independently and compare its full text/hash with the original.
   Compare the same representation: Monaco can normalize line endings, so its
   hash can differ from raw ARM XML without a policy change.
   Respect the observed retry interval and propagation, then make one fresh
   read-only call to verify recovery.

<details>
<summary>Optional explanation: discovery failures versus tool-call failures</summary>

A low limit may produce a 429 during
Foundry's **tool enumeration**, before inventory execution or approval, with a
message such as `Rate limit is exceeded. Try again in 60 seconds.` In that case,
you may see a service error rather than an agent explanation. Distinguish this
from a later business-operation `tools/call` throttle.

Allow time for policy propagation before drawing conclusions. After restoring
the policy, make a fresh inventory request and confirm recovery in its tool trace.
Use **Approve -> Approve once** when asked; opening the Approve menu alone does
not approve the call.

If browser editing or playground use is blocked, record the exact blocker.
A coach-approved direct MCP probe is a diagnostic fallback, not proof of the
browser path or an agent explanation. Do not compensate by changing shared
deployment capacity or repeatedly increasing traffic.

Within a team, nominate one owned practice API and call it from two agents.
Its counter is keyed by API/team: separate agents do not necessarily get
separate allowances. Different API IDs can have separate counters.

</details>

### 5. Make a token-use chart

Open the assigned Application Insights **Logs** context and inspect the
[request query](../../scenarios/architecture-docs/exercises/queries/gateway-observations.kql)
and [token query](../../scenarios/architecture-docs/exercises/queries/token-usage.kql).
Run a fresh call before querying. Discover real metric names/dimensions first.
Dismiss the first-time **Welcome to Log Analytics** panel if shown. Logs may
open in **Agent** mode: leave that unused chat, then choose **Simple mode ->
KQL mode** using **Choose working mode**. Discard only an empty welcome chat,
not any analysis you want to keep. This exercise runs KQL, not an observability
agent conversation.

Reference routes emit Team/API. The owned model practice policy also emits Model
and Project, derived from the validated model route and assigned team project.
Filter to your API and render a token-use chart. Project identity is not the
human caller; detailed caller attribution and money estimates belong in B5.
For example, Alpha participant 2 uses this filter. Replace `alpha-p2-` with your
own prefix followed by `-`:

```kusto
customMetrics
| where timestamp > ago(1h) and name == "Total Tokens"
| where tostring(customDimensions["API"]) startswith "alpha-p2-"
| summarize Tokens=sum(valueSum) by bin(timestamp, 1m), API=tostring(customDimensions["API"])
| render timechart
```

Select one metric family; summing both `Total Tokens` and all token-detail
metrics would count the same usage more than once.

What would be misleading about pricing all tokens with one model's rate?

## You are done when

- Positive evidence for a connected agent's **model** request through APIM.
- Actual model and tool throttles, identified limiter and recovery behavior.
- A real chart with honest available dimensions. Empty telemetry is not zero.

**If stuck:** inspect the prebuilt normal/tight route using `lab gateway --route
models-tight --burst`, recording that it does not prove your own policy.
Ask the coach about missing telemetry.

401/403 often concern auth, but some token **quota** policies intentionally
return 403. Inspect the body/policy rather than diagnosing from status alone.
