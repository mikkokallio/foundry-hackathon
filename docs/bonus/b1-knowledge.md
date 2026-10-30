# B1 - Add knowledge, then test what it changes

**After M5.** Keep the same model, instructions and tools; add retrieval to a new
candidate, not to the version you already measured.

## Understand

Inventory tools answer structured facts. A knowledge base can provide narrative
context from published documents and standards; it can also retrieve stale prose.
Read [Foundry IQ](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq)
and [knowledge base concepts](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base).
The organizer already created the reference knowledge base. Do not recreate it.

## Build

1. Inspect the existing `<workload>-<team>-knowledge` connection in your project.
   Confirm its actual Search knowledge endpoint and project-managed-identity auth.
   Indexing success alone does not establish successful agent retrieval.
2. Clone/version your steward in Foundry. Add the existing knowledge/MCP
   connection through the supported tool UI; inspect the actual discovered
   retrieval operation and require a sensible explicit allowlist.
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
