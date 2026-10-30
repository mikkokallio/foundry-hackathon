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
before calling again. Limits are not a guaranteed billing hard cap.

### 4. Throttle a tool

On **your** documentation MCP policy, temporarily change the request limiter
from 60 calls/minute to a deliberately small value. Use your own steward to make
fresh inventory requests until the tool receives a real throttle. Inspect the
tool failure and the agent's explanation. Restore **your** intended policy after
the experiment. Do not modify the reference or somebody else's server.

Within a team, nominate one owned practice API and call it from two agents.
Its counter is keyed by API/team: separate agents do not necessarily get
separate allowances. Different API IDs can have separate counters.

### 5. Read and chart actual metrics

Open the assigned Application Insights **Logs** context and inspect the
[request query](../../scenarios/architecture-docs/exercises/queries/gateway-observations.kql)
and [token query](../../scenarios/architecture-docs/exercises/queries/token-usage.kql).
Run a fresh call before querying. Discover real metric names/dimensions first.

Reference routes emit Team/API. The owned model practice policy also emits Model
and Project, derived from the validated model route and assigned team project.
Filter to your API and render a token-use chart. Project identity is not the
human caller; detailed caller attribution and money estimates belong in B5.

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
