# M3 - Prove routing and govern traffic

## Understand

M1 introduced model traces; M2 added tool spans. Now investigate the gateway's
enforcement, usage and failures. Foundry traces, APIM logs and token metrics are
related evidence sources, not interchangeable views.

Suggested reading:
- [APIM AI gateway capabilities](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities).
- [Token rate/quota policy](https://learn.microsoft.com/en-us/azure/api-management/llm-token-limit-policy).
  Existing reference policies may retain the older Azure OpenAI-specific names.

## Build and investigate

### 1. Prove the route, not the model-picker label

Revisit M1's same-model direct and connected calls. Inspect the saved definitions:
the direct model is a deployment; the connected ID is `<connection>/<alias>`.
Read that connection's actual target.

Find the **connected model request** in APIM/Application Insights using its API,
timestamp and available correlation identifiers. Do not mistake an MCP request
for the agent's model request. The direct deployment bypasses this explicit
route unless another routing mechanism applies; absence of a log alone is not
proof. The unconfigured native **Manage -> AI Gateway** view is not this custom
APIM connection's traffic dashboard.

### 2. Establish normal behavior

Make a normal authenticated request, inspect actual usage/status and available
remaining-token/retry headers:

```powershell
lab gateway
```

This command directly exercises the model gateway. It is useful policy evidence,
but **not** substitute proof that your agent's model traffic uses that route.

### 3. Isolate two different limiters

Create your own model practice APIs. Reuse existing model deployments and the
reference auth/routing policy. Keep one API request-limited with a generous
token allowance, and another token-limited with a higher request allowance.
If both are tight on one route, the first failure can mask the other.

The code path creates two separate prefixed routes with corresponding policies:

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

In the portal, inspect/change the limits on your own APIs and predict the outcome
before calling again. Rehearsal observed three successes with a 2/minute request
policy, and 344 tokens with a 256-TPM policy, before the respective 429s.
Limits are not exact counters or a guaranteed billing hard cap.

### 4. Throttle a tool

Use the browser for this experiment:

1. In **Azure portal -> your APIM instance -> MCP Servers**, select **your**
   documentation MCP server, then **MCP -> Policies**. Do not select the
   reference or somebody else's server. Copy the complete original policy
   before editing; preserve its exact text for restoration.
2. Temporarily change its request limiter from 60 calls/minute to a small
   value, such as `calls="1" renewal-period="60"`. Keep authentication/routing
   intact. A unique practice counter suffix avoids reusing an earlier
   experiment's counter; retain API/team isolation. Select **Save**, confirm
   **Policy saved**, and allow propagation. Rehearsal waited 65 seconds;
   this is an observed wait, not a propagation guarantee.
3. In your steward's **Playground**, select a known saved version with the
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

**Observed browser result: 429 during MCP discovery/enumeration; recovery after
restoration.** The owned 1/minute policy was followed by a 429 during Foundry's
**tool enumeration**, with body `Rate limit is exceeded. Try again in 60 seconds.`
Gateway attribution is strongly supported by the controlled policy change and
error body, but is **not independently trace-confirmed**.
Foundry displayed a service error before inventory
execution/approval, not a generated agent explanation. Earlier six-response
probes had completed their entire save/probe/restore cycle in only 12–13
seconds; their 200s did not establish that the edited policy had propagated.
The browser result supports limiter enforcement, not fully proven origin or the
exact cause of those earlier misses. One bounded tool-only conditional-policy correction reached a real
inventory result but did **not** demonstrate a business-tool 429; its approval
automation also encountered the menu/running-state boundary. Both experiments
restored the exact original policy, independently hash-verified after a reload.
A subsequent browser call with **Approve once** returned 13 systems, confirmed
in the native tool trace. A post-discovery `tools/call` throttle remains a
separate check; do not mark it passed from the enumeration error.

If browser editing or playground use is blocked, record the exact blocker.
A coach-approved direct MCP probe is a diagnostic fallback, not proof of the
browser path or an agent explanation. Do not compensate by changing shared
deployment capacity or repeatedly increasing traffic.

Within a team, nominate one owned practice API and call it from two agents.
Its counter is keyed by API/team: separate agents do not necessarily get
separate allowances. Different API IDs can have separate counters.

### 5. Read and chart actual metrics

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
For example, after replacing the prefix below:

```kusto
customMetrics
| where timestamp > ago(1h) and name == "Total Tokens"
| where tostring(customDimensions["API"]) startswith "YOUR-PREFIX-"
| summarize Tokens=sum(valueSum) by bin(timestamp, 1m), API=tostring(customDimensions["API"])
| render timechart
```

Select one metric family; summing both `Total Tokens` and all token-detail
metrics would count the same usage more than once.

What would be misleading about pricing all tokens with one model's rate?

## Validate

- Positive evidence for a connected agent's **model** request through APIM.
- Actual model and tool throttles, identified limiter and recovery behavior.
- A real chart with honest available dimensions. Empty telemetry is not zero.

**If stuck:** inspect the prebuilt normal/tight route using `lab gateway --route
models-tight --burst`, recording that it does not prove your own policy.
Ask the coach about missing telemetry.

401/403 often concern auth, but some token **quota** policies intentionally
return 403. Inspect the body/policy rather than diagnosing from status alone.
