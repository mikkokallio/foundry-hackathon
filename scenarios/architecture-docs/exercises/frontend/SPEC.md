# Local client specification

## Context and boundaries

- One loopback-only browser UI plus server-side adapter; no new Azure hosting.
- Use the actual exported project, team, reference date, endpoints and immutable
  agent version. Credentials stay server-side; never expose a token endpoint.
- Use the exported OpenAPI for all bodies/status codes. An SDK response ID and
  actual tool results are evidence; generated placeholder data is not.

## Required screens and behavior

| Surface | Real behavior | Explicit failure behavior |
|---|---|---|
| Context | Show project, team, agent/version and reference date. | Refuse missing/invalid binding instead of selecting a default agent. |
| Chat | Invoke genuine Foundry Responses, preserve conversation/response IDs and expose sources. | Show invocation/tool failure; never replace it with a canned answer. |
| Gaps | Read the authenticated live gap API; select a returned system. | Distinguish loading/error from a genuine empty list. |
| Document | Show the complete current/proposed Markdown and safe Mermaid rendering. | Do not execute embedded HTML, JavaScript or tool-supplied code. |
| Validation | Send exact edited Markdown to the governed API; show genuine findings. | Invalid/unavailable validation prevents saving. |
| Human save | Preview exact text, explicit default-no approval, then submit that same validated text. | Editing, cancellation or expired/rejected approval invalidates consent and causes no save. |
| Proposal | Read back actual proposal ID, full text and stored status. | A rejected/needs-changes response is not a successful pending proposal. |

No participant/agent publication button. A librarian operates through a
separately authorized human-only surface after shared evaluation completes.
Do not silently reattempt a write after an ambiguous transport failure: first
reconcile the actual stored proposal using the contract's identifiers.

## Acceptance evidence

Show actual participant authentication and response/version/native tool traces.
Demonstrate approval denial, changed-text revalidation/reapproval and approved
stored-text equality. Exercise service failure and cancellation explicitly.
Keep fresh genuine evaluation/provenance under the selected scenario's
`.foundry` directory. Compilation and screenshots alone do not qualify the app.
