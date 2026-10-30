# M4 - Register, discover, assess and reuse

## Understand

A registry helps somebody decide whether a tool is useful and trustworthy.
It does not proxy traffic, issue credentials or make a broken endpoint callable.
You now discover the independent toolkit **for the first time**.

Suggested reading:
- [Inventory/discover MCP servers in API Center](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server).
- [Connect agents to authenticated MCP](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).

## Build

1. Open the assigned **Azure API Center** in Azure Portal -> **Inventory/Assets**.
   Register your documentation API/MCP with its actual endpoint, version,
   deployment/environment, owner, intended use, lifecycle, classification and
   limitations. Use your personal prefix. Do not edit Terraform-owned entries.
2. Use the supported MCP asset shape if available. The lab's reference is a
   **REST record with MCP discovery links**; do not label it native MCP-kind
   registration. Record the representation you actually used.
3. Find the reference documentation entry and inspect its independent-toolkit
   discovery link. Examine the actual endpoint, owner, contract and limitations.
   Export/retrieve the registered OpenAPI definition rather than substituting the
   copy in the source repository.
4. Ask: would you attach this endpoint to a production agent? What is missing
   from its metadata or access contract?
5. Add the discovered toolkit to a new version of your steward, using the
   existing `<workload>-<team>-toolkit` project-managed-identity connection.
   Inspect the actual discovered operations: `generate_context_diagram`,
   `lint_document` and `compare_with_inventory`.
6. Ask for a context diagram of a system returned by inventory, then compare a
   draft with the inventory. Inspect genuine toolkit calls/results and native
   tool spans. Its results complement the authoritative documentation API.

### Optional code path

```powershell
lab catalog list
lab catalog register
lab catalog export --output "out\$prefix-catalog-openapi.json"
lab agent --name "$prefix-steward-toolkit" --prompt instructions --docs practice --toolkit --model chat-medium --output "out\$prefix-toolkit.json"
lab chat --binding "out\$prefix-toolkit.json" "Use the toolkit to generate a context diagram for SYS-011. Explain what you observed."
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
az apic api definition export-specification --ids $definition --file-name "out\$prefix-catalog-openapi.json" --subscription $context.subscription_id --only-show-errors --output none
if ($LASTEXITCODE -ne 0) { throw 'Actual catalog definition export failed.' }
```

Do not print temporary download URLs or mistake permission to list metadata for
permission to export definitions.

## Validate

- Your own useful registration includes a working endpoint and limitations.
- You retrieved the actual registered definition and assessed the toolkit.
- Your agent demonstrably used the newly discovered toolkit.

**Discuss:** what must be governed at registration time versus invocation time?
Native Foundry private-catalog/APIM synchronization is not assumed configured.
The Azure API Center portal is the core discovery surface.

**If stuck:** inspect the unchanged reference record and connect the toolkit
through its existing connection. Keep your incomplete registration and identify
what remains unverified.
