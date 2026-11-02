# M4 - Find a toolkit and use it in your agent

## What you will do

Find a reusable toolkit in Azure API Center and add it to your M2 steward.
The toolkit can draw a system's connections and check a draft against the
inventory. You can also register the integration you built in M2.

**Why?** An agent does not need every capability built from scratch. A catalog
helps people find existing tools, understand their purpose and decide whether
to use them. API Center is that directory; it is not in the agent's request
path and does not grant access to the tools it describes.

Use the **browser** for this module. You do not need to have completed M3's
optional experiments. Examples use `alpha-p2` for Alpha participant 2; replace
it with your own prefix.

**Shortcut:** if your own M2 integration is unfinished, or you want to focus on
discovery and tool use, skip registration in Step 1 and start at Step 2.
Inspect the shared reference entry without editing it, then add the toolkit to
**your own steward**. You still need that steward's working documentation tools
for inventory lookups. Skipping registration does not block M5 or saving a
proposal; it does not mean you completed your own registration.

<details>
<summary>Optional reading: API Center and authenticated tools</summary>

- [Inventory/discover MCP servers in API Center](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server).
- [Connect agents to authenticated MCP](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).

</details>

## Build

### 1. Open API Center and register your integration

**Do this if you have your own working M2 MCP server.** Otherwise use the
shortcut above. Registration makes your integration discoverable; it does not
deploy another server.

1. Open [Azure portal](https://portal.azure.com), search for **API Centers**, and
   select the instance assigned by the coach. Open **Inventory/Assets**.
   You will register your own M2 MCP server in the following steps; do not
   edit the shared reference entries.
2. Use **Register an asset -> MCP server**. Use a short Title such as
   `alpha-p2-docs`, replacing the prefix with your own. Keep the complete title
   **at most 24 characters**. Fill the required **Description** with the owner,
   intended use, classification and limitations; Summary can be shorter.
   For example: your team owns it, it reads the workshop inventory and prepares
   documentation proposals, it uses workshop data, and publication requires
   separate human review.
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

**Expected result:** a saved entry for your own server with a version, definition
and deployment URL. Check the URL and generated definition rather than treating
the entry's existence as proof that the integration works.

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

1. Open [Azure portal](https://portal.azure.com), search for **API Centers**, and
   select the instance assigned by the coach. Open **Inventory/Assets** if you
   are not already there.
2. Open the **shared reference documentation entry**, not your own registration.
   Ask the coach which entry to use if it is unclear. Leave the reference unchanged.
3. Find its toolkit discovery link and note the toolkit's endpoint, owner and
   limitations.
4. Under **Versions**, expand the version's chevron, then select **OpenAPI
   definition -> Download**. Clicking the version title opens its metadata
   editor instead. Open the downloaded file and inspect its contents and toolkit
   link. Use this actual catalog export, not the repository's copy.

**Expected result:** you can explain what the toolkit offers and where its
description came from. A catalog entry helps discovery; it is not proof that
the tool is suitable, authorized or working.

Would this description give you enough information to attach the toolkit to
a production agent? Identify one missing detail.

### 3. Add the toolkit to your agent

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Agents -> your steward**, for example `alpha-p2-steward`.

The workshop already provides an authenticated toolkit connection in your team
project. You will attach that connection to your own agent, not change the
shared connection or create a toolkit server.

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

**Expected result:** your steward has both the documentation tools from M2 and
the three toolkit operations. Adding the toolkit does not authorize saving or
publishing documents.

### 4. Try the tools and inspect their results

**First, generate a diagram.** Ask:

> Read the inventory record for SYS-011, then use the toolkit to generate its
> context diagram. Explain the systems and interfaces shown. Do not save or publish.

Expect an inventory lookup followed by a `generate_context_diagram` call.
Expand the tool results and check that the diagram's systems/interfaces match
the inventory; a fluent description alone is not evidence that the toolkit ran.
The layout can vary. Look for correct systems and connections, not one
particular arrangement.

**Then, check a draft.** Paste your M2 draft into the conversation and ask:

> Check the Markdown I pasted above with lint_document and
> compare_with_inventory. Explain the findings. Do not save or publish.

Inspect both tool results and the matching trace. The toolkit supplements the
documentation API; it does not replace the authoritative standard or inventory.

**No draft yet?** You can explore the diagram now and return to the draft checks
after [M2's drafting activity](m2-tools.md#5-connect-the-tools-to-a-new-agent).
You do not need to rebuild an API to continue exploring the toolkit.

**Expected result:** you can point to an actual toolkit call and explain what
it added to the agent's answer. A finding in your draft is something to investigate,
not a requirement to get everything green before continuing.

<details>
<summary>Optional Cloud Shell alternative / registration fallback</summary>

**Skip this if the browser steps worked.** These commands require your own
working M2 `<prefix>-docs` connection; they are not the shared-reference shortcut.
Use **Cloud Shell -> PowerShell** and reuse `lab` if it is already set up, or
follow the Cloud Shell instructions in
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup).
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

- You have inspected the reference entry and its actual exported definition,
  and can explain what the toolkit offers.
- Your own steward has used a toolkit operation, and you have inspected its result.
- You can explain why finding a tool in a catalog is different from having
  permission to call it.

If you also registered your integration, keep its actual status: check the
saved version, definition and deployment URL, and note any generated-contract
problems. An unfinished or skipped registration does not block continuing.

**If stuck:** use the reference-entry shortcut rather than repeatedly creating
catalog entries. If access or a tool call fails, keep the error and ask the coach,
or inspect a teammate's result together. Do not edit shared resources, replace
authentication or claim that a failed call succeeded.

<details>
<summary>Nice to know: catalog discovery versus automatic connection</summary>

This workshop uses the Azure API Center inventory in Azure portal. Registering
an entry does not automatically add it to Foundry, and native Foundry
private-catalog/APIM synchronization is not assumed configured. You explicitly
attached the existing toolkit connection in Step 3.

</details>

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
