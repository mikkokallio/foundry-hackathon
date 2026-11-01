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
   Register your documentation API/MCP with its actual endpoint, version,
   deployment/environment, owner, intended use, lifecycle, classification and
   limitations. Use your personal prefix. Do not edit Terraform-owned entries.
2. Use **Register an asset -> MCP server**. Use a short Title such as
   `alpha-p2-docs`, replacing the prefix with your own. Keep the complete title
   **at most 24 characters**; put longer explanations in Summary/Description.
   Add a **Remote** using your actual M2
   connection endpoint and select your existing development environment. Set
   version title/identification, for example `v1`, and Development lifecycle,
   then **Create**.
3. Open the saved version. Check **both definitions** and the deployment runtime
   URL. Compare that URL with the actual `alpha-p2-docs-mcp` URL you copied in
   M2. Seeing the asset in the list is not enough.

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

Find the reference documentation entry and inspect its independent-toolkit
   discovery link. Examine the actual endpoint, owner, contract and limitations.
   Export/retrieve the registered OpenAPI definition rather than substituting the
   copy in the source repository. In **Versions**, expand the version's chevron
   and open **OpenAPI definition -> Download**. Clicking the version title
   instead opens its metadata editor.
Ask: would you attach this endpoint to a production agent? What is missing
   from its metadata or access contract?

### 3. Add the toolkit to your agent

Open [Foundry](https://ai.azure.com), select your team project, then **Build ->
Agents -> your steward**, for example `alpha-p2-steward`.
Add the discovered toolkit to a new version of your steward, using the
   existing `<workload>-<team>-toolkit` project-managed-identity connection.
   For Alpha, find the configured connection whose name ends in `-alpha-toolkit`;
   the workload prefix comes from the deployment, not your personal name.
   Inspect the actual discovered operations: `generate_context_diagram`,
   `lint_document` and `compare_with_inventory`. In Playground use **Tools ->
   Add -> Add tools -> Configured**, select that existing connection and
   **Add tool**. Under its **Actions -> Configure**, restrict allowed tools to
   those three names and auto-approve only those read-only operations. Preserve
   the documentation tool's proposal-approval requirement, then **Save**.
### 4. Try the tools and inspect their results

Ask:

> Read the inventory record for SYS-011, then use the toolkit to generate its
> context diagram. Explain the systems and interfaces shown. Do not save or publish.

Then ask for a context diagram of another system returned by inventory and compare a
   draft with the inventory. Inspect genuine toolkit calls/results and native
   tool spans. Its results complement the authoritative documentation API.

<details>
<summary>Optional Python helper / registration fallback</summary>

Use the [helper setup](../../PARTICIPANT-START.md#powershell-helper-setup) first.
For these commands, `$prefix` is your own assigned prefix, for example `alpha-p2`.

```powershell
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
- Native registration has a persisted version, definitions and deployment;
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
