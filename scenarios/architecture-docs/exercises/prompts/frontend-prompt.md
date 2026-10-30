# B9: build a small local client, not a new Azure deployment

Build a minimal local UI for the {{ORGANIZATION_NAME}} architecture-docs exercise.
Use the exported workshop connection file for actual endpoints; the lab reference
date is {{REFERENCE_DATE}}. Require an explicitly selected, real Foundry agent
name and immutable version. Do not invent an agent binding.

Use a local server-side adapter authenticated as the signed-in participant with
the current supported Foundry SDK/Responses API. Keep Azure credentials and
access tokens out of browser storage, browser bundles and source control. The
adapter must be loopback-only by default; do not create an unauthenticated public
proxy, use a shared service identity, or add cloud hosting automatically.

Required UI:
- Show the selected project, agent/version, team and reference date.
- Ask a question; show the genuine answer, source IDs, response ID and any error.
- Preview the complete proposed Markdown, not just a summary.
- Validate the exact text through the governed Docs API.
- Require a deliberate human confirmation before saving that exact text.
- Display the actual saved proposal ID/status; never claim it was published.

Use the exported `openapi.json` for request/response shapes. `submitProposal` is a
write and `publishProposal` is human-librarian-only, never an agent tool.
Respect MCP approval requests; do not auto-approve a pending write to make chat
continue. A rejected/expired approval must cause no write.

Use real backend data only. No mock answers, cached responses, fixture documents
or simulated success paths in normal app/demo execution. An unavailable service
must produce an explicit error. Do not prebuild an app before the exercise.

Acceptance requires real participant authentication, genuine Foundry response
IDs/traces, approved-save evidence and the repository's unchanged smoke and
regression gates. Local compilation or a polished screenshot is not acceptance.
