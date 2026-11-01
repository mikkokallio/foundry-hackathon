# B1 - Explore Azure AI Search and knowledge bases

Explore the indexed architecture documents and standards in Azure portal.
Run search queries, inspect the returned passages and consider how they could
support an agent's answers.

## Understand

Inventory MCP tools provide structured records: systems, owners and interfaces.
Search retrieves narrative context from documents; that prose can explain
decisions but may lag behind the current inventory or documentation standard.

The shared index combines published architecture documents and standards.
The knowledge base currently uses that index as **one configured knowledge
source**. A knowledge base can coordinate retrieval across multiple sources;
here, investigate what the existing content contributes and how to assess it.

## Build

### 1. Inspect the existing index

In **Azure portal -> Search services**, open the assigned Search service,
then **Search management -> Indexes**. Select the existing
`<workload>-knowledge` index, usually `architecture-docs-knowledge`.
Inspect the fields containing text, titles, source URLs, identifiers and vectors.
Leave the schema and data unchanged.

### 2. Query the indexed documents

Open **Search explorer** on the index and use its JSON query view. Paste this
query and select **Search**:

```json
{"search":"*","top":3,"select":"title,source_url"}
```

Expect up to three document titles and source URLs. Then retrieve passages:

```json
{"search":"interface documentation","top":3,"select":"title,content,source_url"}
```

Inspect the text and provenance. The source URL identifies the document; it may
require separate authorization to open.

Querying requires Search data-read permission, such as **Search Index Data
Reader**. If access is denied, ask the coach to demonstrate using an
already-authorized identity. Keep the existing service and permissions.

### 3. Compare prose with structured records

Ask your M2 steward for the current documentation standard or a specific system
owner using its inventory tools. Compare that answer with the indexed passages.
Which source establishes the current fact, and which explains its context?
What should happen if they disagree?

Search explorer queries the index directly. A knowledge base adds a retrieval
layer that agents can consume through MCP; its endpoint and project connection
are already configured in this lab.

## Validate

- Identify a real passage, its document title and source URL.
- Explain one useful contribution from prose and one freshness/conflict risk.
- Distinguish direct index search, knowledge-base retrieval and inventory lookup.

**Discuss:** what would adding another knowledge source contribute? What would
you need to check about access, relevance and conflicting information?

<details>
<summary>Optional: test agent retrieval with the CLI helper</summary>

Keep the model, instructions and existing tools unchanged when adding retrieval
to a new candidate. Retain the original version measured in M5.

### 1. Find the existing knowledge connection

In your Foundry project, open **Tools -> Add -> Add tools -> Configured** and
inspect `<workload>-<team>-knowledge`, shown as a RemoteTool connection.
Note its Search knowledge endpoint and project-managed-identity authentication.
Do not add it to your measured M5 agent or create a replacement service.

### 2. Create a retrieval candidate

Use the PowerShell shell from M3/M5 and a saved steward binding JSON created
by `lab agent`. Follow this optional route if you have that binding available.

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
Adding retrieval changes the agent's toolset, so treat its results as a separate
experiment from the original M5 version. Keep its actual retrieval trace and
check the cited passages rather than relying on a score alone.

</details>

Check that retrieval actually executed, its cited URL/quote occurred in the
returned passages, and inventory tools still supplied authoritative facts.
Keep the new version and actual results.

**If stuck:** verify the existing endpoint/identity with the coach. Do not reset
reference indexes, rerun initialization or fabricate a retrieval answer.

</details>

<details>
<summary>Read more about Search, knowledge bases and agent connections</summary>

- [Search explorer](https://learn.microsoft.com/en-us/azure/search/search-explorer): query and inspect an index in Azure portal.
- [Knowledge base concepts](https://learn.microsoft.com/en-us/azure/search/agentic-retrieval-how-to-create-knowledge-base): sources, models and retrieval configuration.
- [Foundry IQ](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq): the knowledge layer for agents.
- [Connect agents to knowledge bases](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/foundry-iq-connect): MCP connections, managed identity and permissions.

</details>

**Next:** [Review and save your final proposal](../modules/core-approval.md).
