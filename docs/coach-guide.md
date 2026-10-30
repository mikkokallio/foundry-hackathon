# Coach guide

## Before the event

The customer event is a full day with **4.5 hours of hands-on work**, sixteen
people in four teams of four. Provisioning is outside participant time. Plan
breaks separately and allow for model calls, tracing and evaluation collection.

Terraform owns the hack-ready starting resources and reference implementations.
Participants are encouraged to author their own APIs, MCPs, agents, connections,
catalog records and extension apps. Do not reapply Terraform over their work.
Do not modify shared references to rescue an exercise.

### Effective-access checklist

Check with a **non-admin participant identity**, not only the deployer:

| Surface | Required real action |
|---|---|
| Foundry project | Create/version an agent; invoke actual model/tool; create an authenticated connection for an owned MCP. |
| APIM | Import owned REST, add MCP/tools/policy/diagnostics and call through valid Entra auth. |
| API Center | Create owned record/version/definition and retrieve actual exported specification, not merely list metadata. |
| Insights/workspace | Query the assigned traces/logs/metrics and inspect a run. |
| Evaluation | Invoke judge, collect real responses and verify remote scores/native provenance. |
| Extensions (B2) | Build/push image; create app in extension group; attach preassigned pull identity/environment. |
| Librarian | Separate authorized human can review/publish; participants/agents cannot impersonate that role. |

Include MCP connection creation in the participant access check: Foundry User
does not explicitly grant ARM connection writes. If the supported portal path is
denied, arrange a scoped permission review before the event.

## Module facilitation

Give context, then let everyone build/investigate. Each person has an owned prefix;
the team coordinates shared-policy experiments and divides the four M5 matrix
cells. Do not leave three people idle watching a driver unless they choose that.

| Module | Observe before moving on | Useful question |
|---|---|---|
| M1 | Own baselines, real trace/tokens/latency; limitation and model-choice observation. | Which part of the answer came from evidence? |
| M2 | Own authenticated REST/MCP, actual GET/POST behavior, genuine agent/tool spans. | What does selecting fewer operations protect? |
| M3 | Positive model-route evidence, isolated model/tool throttles and real chart. | Which counter/identity did this request use? |
| M4 | Own useful registration, actual definition retrieval, first toolkit use. | Why can discoverable still mean unauthorized? |
| M5 | Comparable real results and numerical choice, or genuine attempts explicitly stopped as workshop-only/not qualified; worst-row investigation. | Is a lower token price a lower cost per successful task? |
| Core approval | Denial saves nothing, approval matches stored text, separate librarian publication. | Exactly what did the human authorize? |

**Reference catch-up:** inspect current state; add missing owned objects or attach
the unchanged reference to a new owned agent. Never delete an attempt. Record
what was bypassed; reference use does not certify the participant's integration.
`lab practice status` helps identify which owned API objects already exist.
Check their behavior and participant access separately.

## Gateway and tracing distinctions

The [APIM Microsoft Foundry import wizard](https://learn.microsoft.com/en-us/azure/api-management/azure-ai-foundry-api)
creates an API/backend/managed-identity route and optional AI policies. The lab's
Terraform follows that architecture but customizes aliases, deployment-path
rewrites, team checks, limits and its single chat operation. It additionally
creates explicit project model connections. This is not an exact wizard export.

The [native Foundry gateway association](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)
is a different setup surface, with resource association and existing-project
enablement. Do not attribute its absence simply to using Terraform.
The [new AI Gateway public-preview product](https://learn.microsoft.com/en-us/azure/ai-gateway/overview)
is in public preview as checked at the end of October 2026. It is a distinct
`Microsoft.ApiManagement/aigateways` resource type, not merely a new SKU of
this lab's `Microsoft.ApiManagement/service`. Its preview includes Sweden
Central, not France Central. Mention the emerging option; it is not a required
migration or a change to the lab.

The explicit APIM model connection is not the native Manage -> AI Gateway
association. The native association is not required for M3.

The [native setup prerequisites](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)
require Foundry resource administration plus APIM Service Contributor/Owner.
Association is resource-wide, with existing projects enabled separately.
Keep this an overview rather than a participant setup task: changing the
association would need an infrastructure/role review and routing checks.

Server-side tracing starts after Insights linkage; allow ingestion time. Verify
the existing connection's portal recognition. Do not create duplicates or turn
on APIM body/token logging. Content-filter metadata is inspected when emitted,
not promised for every model/span. Missing trace evidence blocks the checkpoint.

Rehearsed navigation: **Build -> Agents -> open the agent -> Traces**.
The Agents list itself has Agents/Routines/Workflows tabs, not all-project
Traces; Operate has Overview/Assets/Compliance. Newly created agents may start
with Web search and a connected medium model: remove the tool and explicitly
select the intended model before a no-tools baseline. Save and record the
tested version, not merely the agent name.

Direct deployment selection bypasses the explicit APIM model route if no other
routing applies. Prove the connected route positively using saved configuration
and matching **model** traffic; a separate APIM call or MCP request is not enough.

## Evaluation and publication coordination

Four-case smoke, twelve-case educational comparison and twenty-five-case
regression are distinct. Legacy `quick` still means four-case smoke. Do not
silently promote twelve educational rows into full qualification.

Pin evaluator version/scale and thresholds. Additional intended built-in
diagnostics are not all implemented; say so. Keep failed/incomplete runs and
failure clusters. Fresh real responses, evaluation IDs and matching native
response/version/tool traces belong under the scenario's `.foundry/`.
No mocked answers, cached responses, fabricated traces or blanket write approval.

**Workshop stop rule:** after a few genuine attempts, keep the actual failures,
record **workshop-only/not qualified**, and continue to bonuses/core approval.
Attempted M5 is sufficient for B1/B3/B6; it is not release qualification. No
backend/evaluator bypass is needed or authorized. B6 still demonstrates a strict
production-style CI gate: failed/incomplete evidence blocks promotion.

Distinguish missing facts/tools (quality), missing native provenance and
incomplete collection caused by 429s. These need different follow-up actions.
Inspect incomplete manifests directly rather than ranking them with `lab compare`.

**Across all teams:** record collection closure only after every team's
frozen-corpus attempts completed or were explicitly stopped, before any librarian
publication. Proposals can be drafted/saved beforehand. Record the corpus
boundary; later changed-corpus runs are not the original baseline. Publication
legitimately changes gaps; never reset shared data or weaken expectations to hide
that. Stale-base conflicts require review, not force.

As librarian: retrieve the exact saved proposal; review text, findings and base
version and authenticated team scope; explicitly authorize the human-only
publish operation and accept any failed/incomplete-M5 workshop caveat; verify
stored document/proposal/gap state. Exact-text approval and structural validation
remain mandatory. Agent review is not human approval, and human publication is
not evaluation qualification. Real projects retain stricter release requirements.

## Short error triage

| Signal | Investigate |
|---|---|
| 401/403 | Tenant, audience, own authorized role, propagation and actual policy body. Token quota can intentionally return 403. No shared-token workaround. |
| 429 | Identify request/token/upstream/tool limit and API/team counter. Respect retry information; stagger real work instead of hammering or bypassing. |
| Empty result | Actual arguments/filter and equivalent authenticated REST, not guessed facts. |
| GET works, POST fails | Exact body, JSON POST adapter and owned REST target. |
| No trace | Project/Insights recognition, time filters, ingestion and query access. Missing is not zero. |
| Evaluation mismatch/failure | Actual evaluator contract/IDs/coverage/provenance; keep the gate red, but use the explicit workshop stop rule rather than block bonuses or authorized human publication. |
| CLI pack hash mismatch | Export a fresh actual-output pack. Never edit receipts or overwrite old evidence. |

One repair attempt per failed live activity, then preserve evidence/report and
move to independent work. Missing prerequisite or shared infrastructure/access
defect requires an explicit scoped exception, not hidden deployment changes.

## Final preparation

Check the participant path with a non-admin account, including connections,
authoring, export and save/readback. B6 needs its separate delivery setup.
B3/B9 invite participant implementation; B9 also has an optional local reference.
Consult [preview notes and troubleshooting](exercise-readiness.md) for current
exercise guidance.
