# B1 - Add knowledge, then test what it changes

**After attempted M5.** Failed or explicitly stopped evaluations do not block
this bonus. Keep the same model, instructions and tools; add retrieval to a new
candidate, not to the version you already measured.

## Understand

Inventory tools answer structured facts. A knowledge base can provide narrative
context from published documents and standards; it can also retrieve stale prose.
Read [Foundry IQ](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq)
and [knowledge base concepts](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base).
The organizer already created the reference knowledge base. Do not recreate it.

The organizer repaired the reference configuration through targeted Terraform.
A fresh candidate retrieved real standard/template passages through the shared
connection. This proves retrieval, not that every generated answer is correct.

## Build

1. Inspect the existing `<workload>-<team>-knowledge` connection in your project.
   Confirm its actual Search knowledge endpoint and project-managed-identity auth.
   Indexing success alone does not establish successful agent retrieval.
   In the rehearsed portal it appears under **Tools -> Add -> Add tools ->
   Configured** as a RemoteTool connection. The separate Knowledge menu offered
   **Connect to Foundry IQ**; do not create a resource, enter a key or change a
   shared association to replace the existing MCP connection.
2. Create a newly named candidate copying your steward's configuration. A new
   prompt or chat is not a new candidate; creating an identical version can
   return the existing version. Add the existing knowledge/MCP
   connection through the supported tool UI. It appears under Knowledge, but
   the rehearsed card offered only Details/Remove, not approval/allowlist controls.
   Saving produced an auto-approved MCP definition with no tool allowlist.
   Before inference, have the coach create and inspect a candidate restricted to
   the actual read-only `knowledge_base_retrieve` operation, requiring approval.
   Post-repair discovery accepts 1-3 queries, each at most 150 characters.
   For this workshop, use exactly one short query, at most 150 characters and
   under twelve words. This is a workshop policy, not the API's query-count limit.
   Do not assume the native card has established those controls. Use a fresh
   candidate after any connection repair: an older candidate still failed
   enumeration in rehearsal while a newly created one worked.
3. Ask the same narrative question before/after, for example: "Explain the
   architecture-documentation standard's expectations for interfaces and unknown
   operational details. Retrieve using exactly one query, cite the source filename
   and source_url, and distinguish indexed prose from the current standard."
   Inspect the pending arguments before **Approve -> Approve once**. If the
   agent requests multiple queries, deny and ask it to use exactly one.
   Then ask a specific owner/interface question that should still use inventory.
4. Inspect retrieval arguments, source identifiers/citations and native spans.
   Compare cited prose with the real published document and inventory.
   If citations are blank, ask for the exact filenames, `source_url` values and
   a supporting quote from the passages already retrieved; verify them against
   the tool result. Source URLs identify provenance, not public download access.
   An indexed copy of the standard is still Search content: the current
   `getDocumentationStandard` response remains authoritative.
5. Record fresh behavior/provenance and any quality findings. The existing core
   runner rejects unreviewed tool types/names: do not expand its allowlist blindly
   or claim a score-only run is qualification. A separately reviewed retrieval
   evaluation is an extension, not a prerequisite blocking this workshop bonus.

## Validate

- Actual retrieval executed and cited a real source; not merely a fluent answer.
- Explain one benefit and one conflict/staleness risk using observed evidence.
- Record the changed version and evaluation/provenance status honestly.

**Discuss:** what should win when narrative prose disagrees with structured
inventory? What does a project-local connection *not* guarantee about networking?

**If stuck:** verify the existing endpoint/identity with the coach. Do not reset
reference indexes, rerun initialization or fabricate a retrieval answer.
