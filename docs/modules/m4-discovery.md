# M4 - Find a toolkit and use it in your agent

## What you will do

Register your M2 integration in Azure API Center, inspect a published tool
description, then add the independent diagram/checking toolkit to your agent.
API Center describes endpoints; it does not grant access or make them work.

The main route is **browser-only**. The commands at the end are optional.
Examples use `alpha-p2` for Alpha participant 2; replace it with your own prefix.

<details>
<summary>Optional reading: API Center and authenticated tools</summary>

- [Inventory/discover MCP servers in API Center](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server).
- [Connect agents to authenticated MCP](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).

</details>

## Build

### 1. Open API Center and register your integration

1. Open [Azure portal](https://portal.azure.com), search for **API Centers**, and
   select the instance assigned by the coach. Open **Inventory/Assets**.
   You will register your own M2 MCP server in the following steps; do not
   edit the shared reference entries.
2. Use **Register an asset -> MCP server**. Use a short Title such as
   `alpha-p2-docs`, replacing the prefix with your own. Keep the complete title
   **at most 24 characters**. Fill the required **Description** with the owner,
   intended use, classification and limitations; Summary can be shorter.
   Add a **Remote** using your actual M2 connection endpoint. Environment is
   optional: select your assigned environment if available, otherwise leave it
   blank. Set
   version title/identification, for example `v1`, and Development lifecycle,
   then **Create**.
3. Open the saved version. Check the generated **definition(s)** and deployment
   runtime URL. Having only `default-sse` is not, by itself, an error. Compare the
   runtime URL with the actual `alpha-p2-docs-mcp` URL you copied in M2. The saved
   asset should describe your existing server; registration does not deploy a
   new server or grant access.

<details>
<summary>If registration partly fails, or its generated paths are wrong</summary>

   Generated definition titles add `SSE Definition for ` or
   `Streamable Definition for `; the service limits definition titles to 50
   characters. A longer asset title can save the asset/version, then return HTTP 400:
   `The field Title must be a string or array type with a maximum length of '50'.`
   If this occurs, shorten the title on the same owned asset and retry.
   **Check the generated contract:** OpenAPI definitions may advertise root
   `/sse` and `/message` rather than the registered APIM MCP path. Assess their paths,
   authentication and transport against the actual endpoint before reuse.
   The unchanged lab reference is a **REST record with MCP discovery links**.
   For an accurate REST contract plus MCP discovery metadata, use **Register an
   asset -> API** with the real REST definition, or the helper below; record that
   representation honestly. If native registration still fails, preserve its
   exact error/partial result and use this fallback rather than repeated creates.
</details>

### 2. Inspect the registered toolkit description

Open the **reference documentation entry** in API Center. Find its independent
toolkit discovery link and note the endpoint, owner and limitations.

Under **Versions**, expand the version's chevron, then select **OpenAPI
definition -> Download**. Clicking the version title opens its metadata editor
instead. Inspect the downloaded definition and toolkit link; use the actual
catalog export, not the repository's copy.

Would this description give you enough information to attach the toolkit to
a production agent? Identify one missing detail.

### 3. Add the toolkit to your agent

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Agents -> your steward**, for example `alpha-p2-steward`.

1. In Playground, select **Tools -> Add -> Add tools -> Configured**.
2. Select the existing `<workload>-<team>-toolkit` connection and **Add tool**.
   For Alpha, its name ends in `-alpha-toolkit`; it does not use your personal
   prefix. Do not create a replacement connection.
3. Under **Actions -> Configure**, allow these three read-only operations:

   ```text
   generate_context_diagram,lint_document,compare_with_inventory
   ```

   Auto-approve only those operations. Keep the documentation tool's existing
   proposal-approval requirement.
4. Select **Save** to create the updated steward version.

### 4. Try the tools and inspect their results

Ask:

> Read the inventory record for SYS-011, then use the toolkit to generate its
> context diagram. Explain the systems and interfaces shown. Do not save or publish.

Expect an inventory lookup followed by a `generate_context_diagram` call.
Expand the tool results and check that the diagram's systems/interfaces match
the inventory; a fluent description alone is not evidence that the toolkit ran.

Then paste your M2 draft into the conversation and ask:

> Check the draft you produced in M2 with lint_document and
> compare_with_inventory. Explain the findings. Do not save or publish.

Inspect both tool results and the matching trace. The toolkit supplements the
documentation API; it does not replace the authoritative standard or inventory.

<details>
<summary>Optional command-line alternative / registration fallback</summary>

**Skip this if the browser steps worked.** Reuse the `lab` command from M3, or
complete the [helper setup](../../PARTICIPANT-START.md#powershell-helper-setup).
No Python coding is needed. This route creates a separate toolkit-enabled agent.
Here `$prefix` is your own assigned prefix, for example `alpha-p2`.

Run `lab catalog register` only if you have not already registered that prefix.
It refuses to overwrite a differing browser-created record.

```powershell
$prefix = $global:FoundryLabSession.Prefix
$context = Get-Content -LiteralPath $global:FoundryLabSession.Pack -Raw | ConvertFrom-Json
lab catalog list
lab catalog register
$catalogExport = Join-Path 'out' "$prefix-catalog-openapi.json"
$toolkitBinding = Join-Path 'out' "$prefix-toolkit.json"
lab catalog export --output $catalogExport
lab agent --name "$prefix-steward-toolkit" --prompt instructions --docs practice --toolkit --model chat-medium --output $toolkitBinding
lab chat --binding $toolkitBinding "Use the toolkit to generate a context diagram for SYS-011. Explain what you observed."
```

`register` creates the REST record/version/definition with MCP discovery metadata.
The helper reads your existing `<prefix>-docs` connection's actual endpoint;
complete that M2 connection first. Portal-created and helper-created MCP paths
can differ, so do not reconstruct an endpoint from its display name.
Add environment/deployment and useful metadata in the portal. If export returns
an unsupported format, the helper fails explicitly: use the API Center
definition's **Export** action or the prepared CLI extension:

```powershell
$definition = "$($context.catalog_resource_id)/workspaces/default/apis/$($context.workload_name)/versions/version-1/definitions/openapi"
az apic api definition export-specification --ids $definition --file-name $catalogExport --subscription $context.subscription_id --only-show-errors --output none
if ($LASTEXITCODE -ne 0) { throw 'Actual catalog definition export failed.' }
```

Do not print temporary download URLs or mistake permission to list metadata for
permission to export definitions.

</details>

## You are done when

- Your own useful registration includes a working endpoint and limitations.
- Native registration has a persisted version, at least one definition and deployment;
  generated contract paths/authentication are assessed separately from metadata
  creation.
- You retrieved the actual registered definition and assessed the toolkit.
- Your agent demonstrably used the newly discovered toolkit.

**Discuss:** what must be governed at registration time versus invocation time?
Native Foundry private-catalog/APIM synchronization is not assumed configured.
The Azure API Center portal is the core discovery surface.

**If stuck:** inspect the unchanged reference record and connect the toolkit
through its existing connection. Keep your incomplete registration and identify
what remains unverified.

<details>
<summary>Nice to know: toolkit versus Foundry Toolbox</summary>

The lab's toolkit is a regular MCP server exposing the three tools you used.
Its `<workload>-<team>-toolkit` connection appears under your steward's **Tools**;
it is not a Foundry Toolbox.

Microsoft Foundry **Toolbox** is a separate capability for curating tools from
multiple sources behind one managed MCP endpoint, with centralized authentication,
reuse and tool search. This lab does not provision a Toolbox.
See [What is Toolbox in Microsoft Foundry?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/toolbox-overview).

</details>

**Next:** [M5 - Evaluate and choose](m5-evaluation.md).
