# B9 - Build your own local client

**After M2; use the core approval flow for writes.** This remains a participant
build, not a new Azure hosting deployment. Try first; an optional
[coach/catch-up reference](../../scenarios/architecture-docs/exercises/frontend/reference/README.md)
is available if you get stuck.

## Understand

Read the [Foundry prompt-agent quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent)
and [local developer authentication](https://learn.microsoft.com/en-us/azure/developer/python/sdk/authentication/local-development-dev-accounts).
Inspect the [frontend build prompt](../../scenarios/architecture-docs/exercises/prompts/frontend-prompt.md)
and [OpenAPI contract](../../scenarios/architecture-docs/openapi.json).
The [local build bundle](../../scenarios/architecture-docs/exercises/frontend/README.md)
provides README, PROMPT, SPEC and EXTEND materials without prebuilding your app.
The separate optional reference was added at the organizer's request; using it
does not certify your own implementation or qualify the bound agent.

## Build

1. Choose a local frontend stack and thin Python backend. Bind the backend to
   your actual exported project, agent name and **immutable version**.
   Use your own server-side Entra identity; browser code receives no credentials.
2. Implement a chat panel that invokes genuine Foundry Responses with the agent
   reference. Preserve real response IDs and explicit errors. A local sample
   answer, cache or placeholder must never replace a failed invocation.
3. Add a gap list from the authenticated API and a document viewer. Render
   Markdown/Mermaid without treating model/tool output as executable HTML/code.
   Show unknown/error state honestly rather than an empty success-shaped list.
4. Implement draft -> real validation -> exact-text review -> explicit approve
   -> submit. If text changes, invalidate approval and revalidate/reapprove.
   Read the actual stored proposal back and display its status.
5. Keep publication out of the participant UI and agent toolset. A read-only
   proposals view is enough; librarian actions need a separately authorized
   human surface, not a hidden button available to everyone.
6. Test failure and cancellation states, approval denial and changed-text
   reapproval. Correlate actual agent responses with native traces/tool spans.
   Agent/output-parser/rendering changes require the applicable genuine gate.

## Validate

- A running local UI wired to the real agent/API, with no fabricated runtime data.
- Credentials stay server-side; displayed evidence/status matches real responses.
- Exact-text approval/persistence and explicit error behavior are demonstrated.

**Discuss:** what would a polished interface accidentally hide about tool failures
or pending approval? Which IDs make a user report diagnosable?

**If stuck:** reduce to one real chat call plus its error path, then extend. That
is a partial build, not a complete dashboard. Additional cloud hosting and
infrastructure changes are outside this local exercise.
