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

Choose either **agent retrieval** below or the **existing-index exercise** at
the end. The second route is useful even if the agent connection is unavailable.
Neither route requires creating Search resources or changing infrastructure.

## Build

### 1. Find the existing knowledge connection

In your Foundry project, open **Tools -> Add -> Add tools -> Configured** and
inspect `<workload>-<team>-knowledge`, shown as a RemoteTool connection.
Note its Search knowledge endpoint and project-managed-identity authentication.
Do not add it to your measured M5 agent or create a replacement service.

### 2. Create a retrieval candidate

Use the PowerShell shell from M3/M5. You need the saved steward binding JSON
created by `lab agent`. If your steward was created only in the portal, ask the
coach for help with its binding, or use the existing-index exercise below.

Set `$baseBinding` to your actual binding file and run:

```powershell
$baseBinding = Read-Host 'Path of your saved steward binding JSON'
$knowledgeBinding = Join-Path 'out' "$prefix-knowledge-new.json"
lab knowledge --binding $baseBinding --name "$prefix-knowledge-new" --output $knowledgeBinding
```

This command creates a separately named candidate from the saved steward
version and adds the existing knowledge connection. It allows only the read-only
`knowledge_base_retrieve` operation and requires approval. No manual tool-card
configuration is needed. Use an unused name/output file; the helper refuses
to overwrite an existing one.

### 3. Compare answers with and without retrieval

Ask your original steward:

> Explain interface documentation expectations. Cite a source URL and supporting
> quote, and distinguish published prose from the current authoritative standard.

Then run the same question on the retrieval candidate:

```powershell
lab chat --binding $knowledgeBinding "Retrieve using exactly one short query. Explain interface documentation expectations, cite a source URL and supporting quote, and distinguish published prose from the current authoritative standard."
```

At **Approve this exact tool and arguments? [y/N]**, inspect the tool name and
query. Enter `y` only for `knowledge_base_retrieve` with exactly one query,
at most 150 characters and under twelve words. Otherwise enter `n` and ask for
a single short query. Expect retrieved passages followed by a sourced answer;
an answer without a retrieval result does not demonstrate the connection.

Compare the answers and inspect the tool result and trace. Do the cited URL and
quote actually occur in a returned passage? Source URLs identify provenance;
they are not necessarily public download links. If citations are missing, ask
for the filename, `source_url` and a quote from the passages already retrieved.

Finally ask both candidates a specific owner/interface question. Check that they
still use inventory tools for structured facts. The current
`getDocumentationStandard` response remains authoritative over indexed prose.

<details>
<summary>Tool-card controls and evaluation limits</summary>

The portal's Knowledge card may expose only Details/Remove and save an
auto-approved MCP definition without an allowlist. The helper above establishes
the intended controls before inference; do not assume the card has done so.
The retrieval API accepts 1-3 queries; this workshop deliberately permits only
one short query per approval.

Keep the new candidate version, actual retrieval trace and quality findings.
The core evaluator rejects this additional tool; do not expand its allowlist
or present a score-only run as qualification. A separately reviewed retrieval
evaluation is optional, not required for this exercise.

</details>

## Validate

- Actual retrieval executed and cited a real source; not merely a fluent answer.
- Explain one benefit and one conflict/staleness risk using observed evidence.
- Record the changed version and evaluation/provenance status honestly.

**Discuss:** what should win when narrative prose disagrees with structured
inventory? What does a project-local connection *not* guarantee about networking?

## Alternative: explore the existing index

If agent retrieval is blocked, investigate the indexed content instead. This is
a useful alternative exercise, not proof that the agent's retrieval connection
works.

1. In **Azure portal -> Search services**, open the assigned Search service,
   then **Search management -> Indexes**. Select the existing
   `<workload>-knowledge` index, usually `architecture-docs-knowledge`.
2. Inspect its fields: which contain searchable text, provenance, identifiers
   and vectors? Do not edit the schema, indexers or data.
3. Open **Search explorer** and use its JSON query view. With your assigned
   identity's existing data access, paste this query and select **Search**:

   ```json
   {"search":"*","top":3,"select":"title,source_url"}
   ```

   Expect up to three document titles and source URLs. Then run this targeted
   query, which also returns passage text:

   ```json
   {"search":"interface documentation","top":3,"select":"title,content,source_url"}
   ```

4. Inspect the returned passages and source URLs. Explain what an agent could
   learn from them, what is missing, and why an indexed passage might disagree
   with the current `getDocumentationStandard` response.

If Search explorer denies access, ask the coach to demonstrate the queries with
an already-authorized identity. Do not obtain admin keys, change roles or create
a replacement service just to continue this exercise.

**If stuck:** verify the existing endpoint/identity with the coach. Do not reset
reference indexes, rerun initialization or fabricate a retrieval answer.
