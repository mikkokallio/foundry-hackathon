# M3 - See the traffic and test gateway limits

## What you will do

Find your agent's model request in APIM logs, test separate request and token
limits on your own APIs, then test a tool limit and restore it.

This module uses the **browser and PowerShell commands**. Step 2 includes
expandable Cloud Shell setup instructions; if `lab` already works, skip setup
and keep using that shell. You can also use
[local PowerShell](../../PARTICIPANT-START.md#powershell-helper-setup).
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

If you have finished Step 1, continue here; do not repeat M1 or M2.
Keep the same assigned prefix and your existing M2 MCP server and steward.
If `lab` is not available in your shell, expand the instructions below.

<details>
<summary>Set up Cloud Shell PowerShell here (skip if lab already works)</summary>

In [Azure portal](https://portal.azure.com), open **Cloud Shell** using the
terminal icon in the top bar, then choose **PowerShell**.
Cloud Shell runs separately from your laptop; files on your laptop are not
automatically available there. Keep this shell open through the exercises.

**A. Clone the public tools**

No GitHub sign-in is needed. Run:

```powershell
Set-Location $HOME
git clone --depth 1 https://github.com/mikkokallio/foundry-hackathon.git
if ($LASTEXITCODE -ne 0) { throw 'Workshop repository download failed.' }
Set-Location (Join-Path $HOME 'foundry-hackathon')
git rev-parse HEAD
```

If `foundry-hackathon` already exists, enter that checkout instead of cloning
over it. Do not overwrite your work or pull changes during an exercise.

**B. Upload your team configuration**

Use **Manage files -> Upload** in Cloud Shell to upload the coach-supplied
**`workshop.json`** for your team. You supply only that JSON file, not a ZIP or
complete pack. Keep it private; do not commit it to Git.
For an upload to your home directory, run:

```powershell
$configuration = Join-Path $HOME 'workshop.json'
if (-not (Test-Path -LiteralPath $configuration)) {
  throw 'Upload your team workshop.json to your Cloud Shell home directory first.'
}
$team = 'alpha'       # Replace with your assigned team.
$prefix = 'alpha-p2'  # Use the same prefix as your M2 MCP server and steward.
```

**C. Enable the lab commands and sign in**

Run this from the checkout's root. The **dot followed by a space** matters:

```powershell
. ./workshop/Start-Lab.ps1 -Configuration $configuration -Team $team -Prefix $prefix
lab check
```

The starter prepares the exercise files and installs missing declared Python
dependencies. It does not deploy infrastructure or recreate your agents/APIs.
If it prints a device-login code, open the printed login page and sign in as
**your own workshop account**. Cloud Shell's automatic sign-in may not include
the gateway scope; the starter uses an isolated profile for your prefix.
If setup or `lab check` fails, keep the error and ask the coach before continuing.
A successful read check does not prove authoring permissions.

</details>

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

**Run this command first.** It creates both practice APIs and configures their
limits; no manual API creation or policy editing is needed beforehand.
It reuses the existing models and authentication/routing policy:

```powershell
lab practice models
```

The helper reports two APIs with your prefix, such as `alpha-p2-models-requests`
and `alpha-p2-models-tokens`. Their limits deliberately isolate the two tests:

| Route | Request limit | Token limit |
|---|---|---|
| `requests` | 2 requests/minute | 50,000 tokens/minute |
| `tokens` | 30 requests/minute | 256 tokens/minute |

**Run each test separately and inspect its output before continuing.**
Each `--burst` sends at most six requests and stops at the first 429.
If all six succeed, it reports `Bounded burst did not observe a 429`.
That means this test did not reach a limit, not that API creation failed.

**A. Request-limit test**

```powershell
lab gateway --route requests --burst
```

Expect initial successful responses followed by a 429 from the request limiter.
This limit is low enough to test on your own; another participant's traffic is
not required. Timing and gateway counter behavior can affect exactly when it
triggers, so six requests do not guarantee a 429.

**B. Token-limit test with a short prompt**

```powershell
lab gateway --route tokens --burst
```

Inspect the returned token usage. These short requests may all succeed without
reaching 256 tokens within the limiter's window. That is a useful contrast with
the request-limit test: request count alone does not determine token usage.

**C. If the short token test did not return 429, run this longer-prompt test once**

```powershell
lab gateway --route tokens --burst --query 'Write a detailed synthetic explanation of how a fictional architecture team maintains documentation. Use at least 200 words. Do not describe any real customer.'
```

The longer prompt increases token demand and is more likely to trigger the
token limiter. The helper still caps output at 64 tokens and sends at most six
requests; this is not a test of whether the model writes 200 words.
If B already returned 429, skip C.

**After a 429**, record `retry_after`, wait that many seconds, then make one
non-burst request on the same route to check recovery:

```powershell
lab gateway --route requests
# After a token-route 429 and its wait, use this instead:
lab gateway --route tokens
```

Confirm a successful response with token usage. Check the logs to distinguish
your practice limiter from an upstream/shared-capacity 429; the status alone
does not identify the cause. If neither token test throttles, inspect the policy
below rather than repeating bursts. Never change shared reference limits or
bypass the gateway.

APIM limits are not exact counters or guaranteed billing caps.

In Azure portal, open your assigned **API Management services** instance ->
**APIs**, then select one of the new APIs with your prefix. In **Design ->
All operations -> Inbound processing -> code editor**, inspect its request and
token limits. Only edit your own practice APIs; predict the outcome before
calling again.

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
   **Policy saved**, and allow propagation. Wait 1-2 minutes;
   it is probably enough for the policy to become active.
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

<details>
<summary>Diagnostic settings vs Application Insights</summary>

APIM offers complementary monitoring options. This workshop uses **Application Insights**
to demonstrate several use cases through one integration: performance monitoring,
troubleshooting model and MCP requests, and token-use charts. The token metrics
are emitted by gateway policies.

**Diagnostic settings** provide another route: exporting APIM resource logs,
including the **generative AI gateway** and **MCP server usage** categories, to
destinations such as Log Analytics.

| Capability | Application Insights integration | Resource logs via Diagnostic settings |
|---|---|---|
| Performance and failures | Requests, dependencies, exceptions and correlated traces | Gateway request timings, status and error details |
| Token usage | Policy-emitted token metrics with configured dimensions | Detailed LLM request records, including model and token usage |
| MCP monitoring | MCP operations, tool names, latency and success/failure telemetry | MCP-specific request and usage records |
| Consumption reporting | Aggregate usage by the dimensions you configure | Per-request analysis that can support allocation and reconciliation |

Both can use the same Log Analytics workspace; they do not necessarily require
separate monitoring infrastructures.

For **cost allocation or chargeback**, either approach needs trustworthy consumer
attribution, appropriate model/deployment pricing, and checks for missing or
sampled telemetry. Token consumption is not automatically equivalent to the Azure bill.

The default **Metrics** view remains useful for request volumes, latency and
errors. The richer token attribution and MCP analysis used here come from
configured telemetry.

Further reading:
- [Monitor Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/monitor-api-management)
- [Integrate Azure API Management with Application Insights](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-app-insights?tabs=rest)
- [Monitor MCP server traffic](https://learn.microsoft.com/en-us/azure/api-management/monitor-mcp-servers)

</details>

## You are done when

- Positive evidence for a connected agent's **model** request through APIM.
- Actual model and tool throttles, identified limiter and recovery behavior.
- A real chart with honest available dimensions. Empty telemetry is not zero.

**If stuck:** inspect the prebuilt normal/tight route using `lab gateway --route
models-tight --burst`, recording that it does not prove your own policy.
Ask the coach about missing telemetry.

401/403 often concern auth, but some token **quota** policies intentionally
return 403. Inspect the body/policy rather than diagnosing from status alone.

**Next:** [M4 - Find a toolkit](m4-discovery.md).
