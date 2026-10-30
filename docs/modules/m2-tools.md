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
`$prefix/docs-api` as the URL suffix (substitute your actual prefix). Choose
**Full** to select **HTTPS**; the import otherwise offers both HTTP and HTTPS.

Read the reference documentation REST API's **Settings** to obtain the real
backend URL. Reuse it; do not deploy another backend or change the shared one.
After importing, open **your API -> Settings**, set **Web service URL** to that
backend and clear **Subscription required**, then Save. A fresh import enables
subscription keys by default; this lab uses Entra validation instead.
Inspect operation IDs such as `listSystems`, `getSystem` and `validateDocument`.
The exported specification deliberately uses these IDs as operation summaries:
the portal derives MCP tool names from display names. Descriptions retain their
full explanations. Use a fresh exported pack, not the backend's original spec.

After **Create**, wait for the import to finish and **Design** to show your API.
The form can remain visible briefly while the asynchronous import runs; do not
click Create repeatedly. Expect **14 operations** with matching operation
IDs/display names, including `listSystems`, `getSystem` and `validateDocument`.
Import success alone is not a working or secured backend:
continue with the Settings and policy steps below.

### 2. Secure and test the REST path

Read the reference REST API policy in **Design -> All operations -> Inbound
processing -> code editor**. Apply its policy to **your** API. It validates the
incoming Entra identity, determines team attribution and authenticates APIM to
the backend with managed identity. The backend URL/identity stays unchanged.

Do not replace this with a subscription key or anonymous access. In **Test**,
make an authorized `GET /systems` using your own short-lived identity. A backend
auth error is not fixed by deleting the validation policy. Test an anonymous
request separately: it must be rejected.

The Test console does **not** automatically send your portal sign-in as a
workload token. Without Authorization, expect **401: A valid
workload Entra token is required**. For an authenticated check without copying a
token into the browser, use Azure CLI and PowerShell (Python is not required):

```powershell
$pack = 'EXACT_EXPORTED_DIRECTORY\workshop.json'
$context = Get-Content $pack -Raw | ConvertFrom-Json
$prefix = 'alpha-p1' # Your own assigned prefix.
az login --tenant $context.tenant_id
$token = az account get-access-token --subscription $context.subscription_id --scope $context.gateway_scope --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Workload token acquisition failed.' }
$gateway = ([uri]$context.docs_url).GetLeftPart([System.UriPartial]::Authority)
Invoke-RestMethod "$gateway/$prefix/docs-api/systems" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
Remove-Variable token
```

Expect **200** and actual synthetic inventory. Never print/save the token or add
Authorization to diagnostic logging. In your API's **Settings -> Diagnostics
Logs -> Application Insights**, match the reference's existing destination,
sampling and W3C correlation, including **Support custom metrics**. Keep payload
logging at **0 bytes** and do not log Authorization; these diagnostics are
needed for M3's owned-route observations. Save only your API's settings.

Observe an actual system ID/name and inspect its interfaces. How does this
change the answer you received in M1?

### 3. Expose selected operations as MCP tools

APIM -> **MCP Servers -> Create MCP server -> Expose an API as an MCP server**.
Select your REST API and the documentation operations. Set the display name and
Name (`$prefix-docs-mcp`), then Create. The form generates a URL such as
`https://<gateway>/$prefix-docs-mcp/mcp`. Retain the **actual server URL**;
do not substitute the reference's or the code helper's different path.

Exclude `health` and **`publishProposal`**. Include reads, `validateDocument` and
`submitProposal`; saving must require human approval when attached to the agent.
Check the discovered names before connecting: expect `listSystems`, `getSystem`,
`validateDocument` and `submitProposal`, not summary-derived names such as
`listSystemsInTheInventory`. Different names would break adapters and approval
filters. Keep the attempt and tell the coach if they differ; do not broaden
approval or edit a pack receipt to hide the mismatch.

Open the reference MCP -> **Policies** (or **Policies -> View** from its overview).
Inspect its policy. Copy it to **your** MCP's Policies editor and change
the JSON-POST adapter's REST target from `/<workload>/docs-api` to
`/<your-prefix>/docs-api`. Keep the identity policy, query-encoding adapter and
streaming behavior. These compatibility adapters preserve actual arguments;
they are not canned answers. Do not access/log streaming response bodies.

Test a filtered read and POST validation, not just tool discovery. The validator
must receive the exact Markdown and return genuine errors/warnings.

### 4. Connect your integration to your agent

Create a separate `...-steward` agent with the exported full instructions and a
connected model; remove the default Web search tool. In its Playground, choose
**Tools -> Add -> Add tools -> Custom -> Model Context Protocol (MCP) -> Create**.
Name it `$prefix-docs` and enter your actual MCP URL. Choose **Microsoft Entra ->
Project Managed Identity** (not the default Agent Identity). For **Audience**, use
the gateway app ID from the reference documentation connection: the middle
component of the pack's `api://APP_ID/Lab.Access` scope, not the entire scope.
Select **Connect**. This creates a RemoteTool connection, visible afterwards in
**Manage -> Project details -> Connected resources**. That page's **Add connection**
picker may not offer MCP; use the agent's tool picker above.

If your own identity cannot create this connection, stop and tell the coach:
this is an access defect, not permission to borrow an organizer account.

Add **only your documentation MCP** at this stage. On its **Actions -> Configure**,
enter the twelve selected tool names under **Allowed ... tools**. Choose
**Never auto-approve tools**; this requires confirming reads as well as saves.
For each expected read, choose **Approve -> Approve once**, not an Always option.
This keeps the explicit write-approval rule required by the evaluation gate.
The helper also supports selective read approval. Never choose
**Always auto-approve all tools**. Apply, Save
and confirm the new agent version. Publication must not appear at all.

Ask:

1. "Who owns Service Order Management, and what interfaces does it use? Use the inventory."
2. "Which systems are missing architecture documentation? Do not submit anything."
3. "Draft a complete document for one missing system. Read inventory and the standard,
   validate the exact complete Markdown and correct errors. Do not save or publish."

Expected: real inventory/gap calls and genuine validator findings, not confident
guesses. Compare the first answer and trace with M1.
Does the answer preserve the exact inventory name? As an optional challenge,
ask about "Sales Order Management" instead. The synthetic inventory calls
SYS-002 **Service Order Management**; an answer that silently aliases the two
is a quality finding, even when its tool calls succeeded.

### Optional code / catch-up path

The helper **creates missing prefixed objects from the working reference** and
refuses differing existing objects instead of overwriting your attempt:

```powershell
lab practice status
lab practice docs
lab agent --name "$prefix-steward" --prompt instructions --docs practice --model chat-medium --output "out\$prefix-steward.json"
lab chat --binding "out\$prefix-steward.json" "Who owns Service Order Management? Use inventory evidence."
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
