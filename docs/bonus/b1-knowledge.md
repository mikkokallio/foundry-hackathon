# B1 - Add knowledge, then test what it changes

**After M5.** Keep the same model, instructions and tools; add retrieval to a new
candidate, not to the version you already measured.

## Understand

Inventory tools answer structured facts. A knowledge base can provide narrative
context from published documents and standards; it can also retrieve stale prose.
Read [Foundry IQ](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq)
and [knowledge base concepts](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base).
The organizer already created the reference knowledge base. Do not recreate it.

**Rehearsal blocker:** native retrieval failed, first on the MCP API version,
then on the model-less knowledge base's reasoning default. Shared configuration
is unchanged. Ask the coach to resolve and verify those prerequisites before
this exercise; no successful retrieval or citations have been demonstrated yet.

## Build

1. Inspect the existing `<workload>-<team>-knowledge` connection in your project.
   Confirm its actual Search knowledge endpoint and project-managed-identity auth.
   Indexing success alone does not establish successful agent retrieval.
   In the rehearsed portal it appears under **Tools -> Add -> Add tools ->
   Configured** as a RemoteTool connection. The separate Knowledge menu offered
   **Connect to Foundry IQ**; do not create a resource, enter a key or change a
   shared association to replace the existing MCP connection.
2. Clone/version your steward in Foundry. Add the existing knowledge/MCP
   connection through the supported tool UI. It appears under Knowledge, but
   the rehearsed card offered only Details/Remove, not approval/allowlist controls.
   Saving produced an auto-approved MCP definition with no tool allowlist.
   Before inference, have the coach create and inspect a candidate restricted to
   the actual read-only `knowledge_base_retrieve` operation, requiring approval.
   Its observed schema accepts exactly one query string of at most 400 characters.
   Do not assume the native card has established those controls.
3. Ask the same narrative question before/after, for example: "Explain the
   architecture-documentation standard's expectations for interfaces and unknown
   operational details. Cite the source." Then ask a specific owner/interface
   question that should still use the authoritative inventory.
4. Inspect retrieval arguments, source identifiers/citations and native spans.
   Compare cited prose with the real published document and inventory.
5. Run fresh required evaluations/provenance on the changed candidate. The
   existing core runner rejects unreviewed tool types/names: do not expand its
   allowlist blindly or claim a score-only run is qualification. A retrieval
   candidate may need a separately reviewed evaluator/tool contract.

## Validate

- Actual retrieval executed and cited a real source; not merely a fluent answer.
- Explain one benefit and one conflict/staleness risk using observed evidence.
- Record the changed version and evaluation/provenance status honestly.

**Discuss:** what should win when narrative prose disagrees with structured
inventory? What does a project-local connection *not* guarantee about networking?

**If stuck:** verify the existing endpoint/identity with the coach. Do not reset
reference indexes, rerun initialization or fabricate a retrieval answer.
