# M3 - Observe gateway traffic and explore limits

## What you will do

Find a model request from your agent in the gateway logs and make a chart of
token usage. These two activities use the **browser**.

**Why?** The gateway is a checkpoint between the agent and a service. Its logs
help explain which requests reached it and what happened. Token measurements
help you understand model usage; limits help protect shared capacity.

**Optional, but worth exploring:** Steps 3-5 let you make a normal request from
Cloud Shell, try request/token limits, and temporarily change a limit on your
own tool server. They are not required for M4, portal-based M5 or saving your
final proposal.

**Pair up if this feels heavy.** One person can drive while the others predict
what will happen and inspect the results. Watching a teammate or coach is also
a useful way to learn. Keep experiments on the driver's own practice resources;
never change shared reference limits or somebody else's resources.

<details>
<summary>Optional reading: gateway policies</summary>

- [APIM AI gateway capabilities](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities).
- [Token rate/quota policy](https://learn.microsoft.com/en-us/azure/api-management/llm-token-limit-policy).
  Existing reference policies may retain the older Azure OpenAI-specific names.

</details>

## Build and investigate

### 1. Find an agent's model request in the gateway logs

1. Open [Foundry](https://ai.azure.com), select your team project, then
   **Build -> Agents -> your M1 baseline agent**, for example `alpha-p2-baseline`.
   Check that its selected model is **Admin-connected**, not a direct deployment.
   You do not need separate direct and connected agents.
2. Read the selected connection's target in **Manage -> Project details ->
   Connected resources**. For Alpha, the model selection might be
   `architecture-docs-alpha-models/chat-small`; use your actual selection.
   Leave the shared connection unchanged.
3. In the agent's Playground, start a new conversation and ask one question.
   Note the time, selected model and available response/trace ID, as in M1.
4. Open [Azure portal](https://portal.azure.com), search for **Application
   Insights** and open the instance assigned by the coach. Select **Logs**.
   If a welcome panel appears, dismiss it. If Logs opens in **Agent** mode,
   use **Choose working mode -> Simple mode -> KQL mode**; do not start an
   observability-agent conversation.
5. Open the [gateway request query](../../scenarios/architecture-docs/exercises/queries/gateway-observations.kql).
   Copy its text into the Logs editor and select **Run**.
6. Look for your connected **model** request using its time, API/URL and available
   correlation identifiers. Do not mistake an MCP tool request for a model request.

**Expected result:** a gateway request you can relate to the connected agent run.
This is stronger evidence of routing than an agent's name or a missing log.
If you kept a direct-model run from M1, you may compare its saved configuration;
there is no need to recreate it.

The direct deployment bypasses this explicit gateway route unless another routing
mechanism applies. The native **Manage -> AI Gateway** view is not the traffic
dashboard for this workshop's custom APIM connection.

### 2. Make a token-use chart

**Why?** Requests can use different amounts of text. Tokens measure that model
input/output usage; counting requests alone does not tell you how much was used.

1. In the same Application Insights **Logs** editor, replace the previous query
   with the [token discovery query](../../scenarios/architecture-docs/exercises/queries/token-usage.kql)
   and select **Run**.
2. Inspect the returned `name`, `team` and `api` columns. Find the model route for
   your team, using the request/connection you inspected above. Keep its exact
   `api` value.
3. Copy the chart query below. Replace `alpha` with your team and
   `PASTE_API_VALUE_HERE` with that exact `api` value, keeping the quotes.
   The example uses the metric name `Total Tokens`; if your discovery results
   show a different token-total name, use that actual name.
4. Select **Run** to render the chart. If needed, make one more question in the
   connected agent, allow time for telemetry to arrive, then rerun the query.
   Adjust the query's `ago(1h)` window if your earlier call was more than an hour ago.

```kusto
let team = "alpha";
let modelApi = "PASTE_API_VALUE_HERE";
customMetrics
| where timestamp > ago(1h) and name == "Total Tokens"
| where tostring(customDimensions["Team"]) == team
| where tostring(customDimensions["API"]) == modelApi
| summarize Tokens=sum(valueSum) by bin(timestamp, 1m), API=tostring(customDimensions["API"])
| render timechart
```

**Expected result:** a chart of the selected model API's token usage for your
team. With only a few calls it may contain just one or two points. This works
with the shared connected-model route; you do not need to create practice APIs
or use Cloud Shell first.

The team can include several participants: this is not necessarily your personal
usage. Reference routes emit Team/API dimensions; inspect the actual dimensions
before drawing conclusions. If you later create owned practice APIs, you can
chart one by selecting its actual API value instead.

Use one metric family. Adding `Total Tokens` to its input/output token-detail
metrics would count the same usage twice. Tokens are not the Azure bill; pricing
and detailed caller attribution belong in [B5](../bonus/b5-cost-identity.md).

**Shortcut:** after these observations, you can continue to
[M4 - Find a toolkit](m4-discovery.md). The following experiments are optional.

### 3. Optional: send a normal request from Cloud Shell

This calls the gateway directly so you can inspect its response and headers
without an agent in between. Pair up if you prefer: one person runs the commands,
and you inspect the results together.

Open **Cloud Shell** from the top bar of [Azure portal](https://portal.azure.com)
and choose **PowerShell**. Follow the Cloud Shell instructions in
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup) using your own
team configuration and prefix. If `lab` already works in your Cloud Shell session,
reuse it; do not repeat setup.

For these examples, `$prefix` is `alpha-p2`, meaning Alpha participant 2.
Use your own assigned prefix throughout. Keep the shell open. If setup or
`lab check` fails, keep the error and ask the coach; do not borrow an administrator's
account. A successful read check does not prove authoring permissions.

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

**Expected result:** a real gateway response with usage/status and any available
limit headers. Missing headers are not evidence of an unlimited allowance.

### 4. Optional: test request and token limits separately

Complete the Cloud Shell setup in Step 3 first. These practice routes let you
compare two different protections: a request limit counts calls; a token limit
measures model usage. You do not need an owned M2 MCP server for this experiment.

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

### 5. Optional: test a tool limit, then restore it

**Requires your own working M2 MCP server and steward.** If you used the shared
reference connection as a shortcut, skip this experiment or watch a teammate
who has an owned server. Never edit the shared server's policy.

Use the browser for this experiment. You do not need to complete the Cloud Shell
experiments first. The aim is to see how a tool limit affects an agent, then
restore normal access:

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

- You can relate a connected agent's **model** request to a gateway log entry.
- You have made a token-use chart and can explain whose traffic it includes.
- You can describe why request counts and token usage are different.

The limit experiments are optional, not completion requirements. If you tried
one, keep the actual result even if no 429 occurred. If you edited a policy,
restoring it and checking recovery remain required.

**If stuck:** check the selected connected model, Application Insights instance,
time window and query filters with a teammate or coach. Missing telemetry is not
zero usage. If access or telemetry still blocks you, keep the error and continue
to M4; do not create monitoring resources, disable authentication or repeatedly
send requests to force a result.

401/403 often concern auth, but some token **quota** policies intentionally
return 403. Inspect the body/policy rather than diagnosing from status alone.

**Next:** [M4 - Find a toolkit](m4-discovery.md).
