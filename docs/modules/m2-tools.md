# M2 - Build REST -> MCP -> agent

## Understand

You will turn the scenario's existing backend into **your own governed API and
MCP server**, then give an agent genuine inventory/document access.

**A reference implementation exists if you get stuck. Try first.** Do not edit
the workload-prefixed reference APIs, policies, identities or connections.

Suggested reading:
- [Import/test an OpenAPI API](https://learn.microsoft.com/en-us/azure/api-management/import-and-publish).
- [Expose REST operations as MCP tools](https://learn.microsoft.com/en-us/azure/api-management/export-rest-mcp-server).

The backend already exists. Your integration reuses APIM's managed identity and
the existing Entra audience/roles. Importing an API alone does not secure it.

## Build

### 1. Import an API with your own name and path

In Azure Portal, open the assigned APIM -> **APIs -> OpenAPI**. Import
`openapi.json` from your exported pack. Use `$prefix-docs-api` as the name and
`$prefix/docs-api` as the URL suffix (substitute your actual prefix).

Read the reference documentation REST API's **Settings** to obtain the real
backend URL. Reuse it; do not deploy another backend or change the shared one.
Inspect operation IDs such as `listSystems`, `getSystem` and `validateDocument`.

### 2. Secure and test the REST path

Read the reference REST API policy in **Design -> All operations -> Inbound
processing -> code editor**. Apply its policy to **your** API. It validates the
incoming Entra identity, determines team attribution and authenticates APIM to
the backend with managed identity. The backend URL/identity stays unchanged.

Do not replace this with a subscription key or anonymous access. In **Test**,
make an authorized `GET /systems` using your own short-lived identity. A backend
auth error is not fixed by deleting the validation policy. Test an anonymous
request separately: it must be rejected.

Observe an actual system ID/name and inspect its interfaces. How does this
change the answer you received in M1?

### 3. Expose selected operations as MCP tools

APIM -> **MCP Servers -> Create -> Expose an API as an MCP server**. Select your
REST API and the documentation operations. Name the server `$prefix-docs-mcp`,
with path `$prefix/docs-mcp`; retain the resulting actual `/mcp` endpoint.

Exclude `health` and **`publishProposal`**. Include reads, `validateDocument` and
`submitProposal`; saving must require human approval when attached to the agent.

Inspect the reference documentation MCP policy. Copy it to your MCP and change
the JSON-POST adapter's REST target from `/<workload>/docs-api` to
`/<your-prefix>/docs-api`. Keep the identity policy, query-encoding adapter and
streaming behavior. These compatibility adapters preserve actual arguments;
they are not canned answers. Do not access/log streaming response bodies.

Test a filtered read and POST validation, not just tool discovery. The validator
must receive the exact Markdown and return genuine errors/warnings.

### 4. Connect your integration to your agent

In the team project's connected resources, create a **RemoteTool** connection
to your actual MCP URL, using **ProjectManagedIdentity** and the same gateway
audience as the reference documentation connection. No copied credentials.
Name it `$prefix-docs`.

If your own identity cannot create this connection, stop and tell the coach:
this is an access defect, not permission to borrow an organizer account.

Create a separate `...-steward` agent with the exported full instructions and a
connected model. Add **only your documentation MCP** at this stage. Allow its
selected tools; reads can run without approval, but `submitProposal` must always
require explicit approval. Publication must not appear at all.

Ask:

1. "Who owns Sales Order Management, and what interfaces does it use? Use the inventory."
2. "Which systems are missing architecture documentation? Do not submit anything."
3. "Draft a complete document for one missing system. Read inventory and the standard,
   validate the exact complete Markdown and correct errors. Do not save or publish."

Expected: real inventory/gap calls and genuine validator findings, not confident
guesses. Compare the first answer and trace with M1.

### Optional code / catch-up path

The helper **creates missing prefixed objects from the working reference** and
refuses differing existing objects instead of overwriting your attempt:

```powershell
lab practice status
lab practice docs
lab agent --name "$prefix-steward" --prompt instructions --docs practice --model chat-medium --output "out\$prefix-steward.json"
lab chat --binding "out\$prefix-steward.json" "Who owns Sales Order Management? Use inventory evidence."
```

If your partially built objects differ, inspect/fix them in the portal or use a
new personal suffix. Do not delete the attempt. For explicit reference catch-up,
create a new binding with `--docs reference`; record that your own integration
remains unverified. It is not equivalent to completing the API build.

## Validate

- Your own authenticated REST API and MCP exist; real reads succeed and anonymous
  access is rejected.
- A genuine POST validation handles the exact submitted text.
- The agent uses actual documentation tools; native tool spans and the correct
  APIM API appear in telemetry. No publication tool or automatic save approval.

**Discuss:** what did MCP standardize, what did APIM govern, and what still depends
on the agent's choices? Save/publication happens in the [core approval exercise](core-approval.md)
after the shared-corpus comparisons.
