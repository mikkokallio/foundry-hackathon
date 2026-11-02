# M2 - Give your agent access to the inventory and documents

## What you will do

Give an agent access to the inventory, documents and documentation standard.
It can then look up evidence, find gaps and check a draft instead of guessing
from its general knowledge, as it had to in M1.

The build route imports an API into Azure API Management (APIM), exposes its
operations as MCP tools, then attaches them to your agent. The backend is already
running: you are connecting to it, not writing an application. Most steps use
the browser; Step 3 uses **Cloud Shell** for an authenticated request.

Examples use **Alpha participant 2**, whose prefix is `alpha-p2`. Replace that
with your own assigned prefix; for example, Beta participant 3 uses `beta-p3`.
Only change objects with your own prefix. Leave the shared reference alone.

**Shortcut: use the existing team connection.** If you want to focus on the
agent, or the API build gets you stuck, go straight to
[Step 5](#5-connect-the-tools-to-a-new-agent). Create your own steward and choose
the existing team Docs connection there. This route uses only the browser.
You can still read inventory, draft/check a document, continue through M3-M5
and save a proposal for human review.

The shortcut skips building your own API/MCP integration; it does not complete
or verify that work. Keep any unfinished attempt. Do not edit the shared
connection, API or policy. In M3, skip the optional tool-policy experiment unless
you have your own MCP server; in M4, use the reference-registration shortcut.

<details>
<summary>Optional reading: APIs and MCP</summary>

- [Import/test an OpenAPI API](https://learn.microsoft.com/en-us/azure/api-management/import-and-publish).
- [Expose REST operations as MCP tools](https://learn.microsoft.com/en-us/azure/api-management/export-rest-mcp-server).

</details>

## Build

### 1. Import an API with your own name and path

1. Open [Azure portal](https://portal.azure.com). Search for **API Management
   services** and open the instance assigned by the coach.
2. Select **APIs**, then **OpenAPI** in the add-API choices.
3. Select `openapi.json` from your team pack, not the original backend
   specification in the repository. If clicking **Select a file** does nothing,
   focus the button with **Tab** and press **Enter**.
4. Choose **Full** and enter:

   | Field | Alpha participant 2 example |
   |---|---|
   | Display name | `alpha-p2-docs-api` |
   | Name | `alpha-p2-docs-api` |
   | API URL suffix | `alpha-p2/docs-api` |
   | URL scheme | HTTPS |

5. Select **Create** once. Wait until the import finishes and **Design** shows
   your API. The form can remain visible while the import runs; do not repeatedly
   click Create.

**Expected result:** an API with your own name and path. Importing describes the
available operations; it does not yet configure their backend access.

### 2. Explore the imported API before changing it

In **Design**, look at these examples from the API's **14 operations**:

| Operation | What it does |
|---|---|
| `listSystems` / `getSystem` (GET) | Read the inventory: which systems exist and what is known about one system. |
| `validateDocument` (POST) | Send draft text for checking without saving it. |
| `submitProposal` (POST) | Save a proposal for human review, not publication. |
| `publishProposal` (POST) | Publish after human review. You will not expose this operation to the agent. |

Open `getSystem` and `validateDocument`. Notice how the system ID is part of
the GET request's path, while the POST validator receives text in a request body.
GET reads information; POST requests an action, which does not always mean saving.

**Expected result:** you can distinguish reading, checking, saving and publishing.
An API being imported does not yet prove that any of those requests work.

The operation IDs and display names should match, such as `listSystems`.
The team pack deliberately makes them match because APIM uses display names
when creating MCP tools. If you see names such as `listSystemsInTheInventory`,
keep the attempt and tell the coach.

### 3. Configure, secure and check your API

1. In **Azure portal -> your assigned API Management instance -> APIs**, select
   the existing reference **Architecture Docs API**, then open **Settings** and
   copy **Web service URL**. This is the reference REST API, not your
   `alpha-p2-docs-api`, a model API or an MCP server. If the coach uses another
   organisation label, its name ends in **Architecture Docs API**; ask the coach
   to identify it if several match. Do not deploy another backend.
2. Still on the **reference REST API from Step 1**, open **Design -> All
   operations -> Inbound processing -> code editor**. Copy the complete policy
   from that reference API to **your** `alpha-p2-docs-api` (using your own prefix)
   and save it. These XML
   rules check the caller's sign-in, identify the team, and let APIM authenticate
   to the backend. Keep those rules intact.
3. Return to **your API -> Settings**. Set **Web service URL** to the copied
   backend address. Confirm **API URL suffix** is `alpha-p2/docs-api` for Alpha
   participant 2, using your own prefix, and clear **Subscription required**.
   Then Save. The suffix is not the API's Name or Display name: `alpha/docs-api`
   and `alpha-p2/docs-api` are different routes. You have
   replaced the default key requirement with the copied Entra identity checks,
   not anonymous access.

In **Test**, send `GET /systems` without Authorization. It must be rejected:
expect **401: A valid workload Entra token is required**. The Test console does
not automatically send your portal sign-in as a workload token.

Now send an authenticated request using **Cloud Shell**:

1. In Azure portal, select the **Cloud Shell** toolbar button and choose
   **PowerShell**.
2. Use **Manage files -> Upload** to upload `workshop.json` from the same team
   pack you imported above. Upload just that file, not the whole pack.
3. Use `./workshop.json` if it is in your current folder, or its full uploaded
   path, usually `/home/<your-user>/workshop.json`. Cloud Shell cannot read a
   path on your laptop.

No Python setup or repository upload is needed for this check. Pair up if
Cloud Shell feels unfamiliar: one person can drive while the others inspect
the address and response. Use that person's own account, prefix and API.

Use the following short blocks in the **same Cloud Shell session**.

**A. Load your team pack and prefix**

Enter the file path when prompted. In Cloud Shell, `./workshop.json` works if
you uploaded the file into your current folder. Replace `alpha-p2` with your
assigned prefix.

```powershell
$pack = Read-Host 'Path to your team pack workshop.json'
$context = Get-Content $pack -Raw | ConvertFrom-Json
$prefix = 'alpha-p2' # Replace with your own assigned prefix.
$env:AZURE_CONFIG_DIR = Join-Path $HOME ".foundry-hackathon-$prefix"
```

The last line keeps this workshop sign-in separate from other Azure CLI accounts.
If the file cannot be found, correct its path before continuing.

**B. Sign in, if needed**

Skip this block if you already completed this scoped workshop sign-in in the
same shell and sign-in folder. Cloud Shell's automatic sign-in alone is not
enough: this command requests access to the documentation API.

```powershell
az login --tenant $context.tenant_id --scope $context.gateway_scope --use-device-code
if ($LASTEXITCODE -ne 0) { throw 'Workshop sign-in failed.' }
```

When a device code appears, open its sign-in page in your browser, enter the code and
finish signing in with **your own workshop account**. If asked to select a
subscription, choose the one supplied by the coach. If sign-in fails, finish
this step before continuing; do not remove the API's identity policy.

**C. Select the subscription and your API address**

```powershell
az account set --subscription $context.subscription_id
if ($LASTEXITCODE -ne 0) { throw 'Workshop subscription selection failed.' }
$gateway = ([uri]$context.docs_url).GetLeftPart([System.UriPartial]::Authority)
$systemsUrl = "$gateway/$prefix/docs-api/systems"
Write-Output "Testing your API: $systemsUrl"
```

Check the printed address against **your API -> Settings -> API URL suffix**.
For Alpha participant 2, it should end in `/alpha-p2/docs-api/systems`.
If subscription selection fails, check that you used the assigned account and
team pack; tell the coach if that subscription is unavailable.

**D. Send the authenticated request**

```powershell
try {
    $token = az account get-access-token --subscription $context.subscription_id --scope $context.gateway_scope --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw 'Workload token acquisition failed.' }
    Invoke-RestMethod $systemsUrl -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
} finally {
    $token = $null
}
```

Expect **200** and the synthetic inventory. Never print/save the token or add
Authorization to diagnostic logging. If token acquisition fails, complete
Block B's scoped sign-in, then rerun Block D. You do not need another login
after a successful request.

**404 / Resource not found:** compare the printed URL with your API's saved
**API URL suffix** and assigned APIM instance. Correct only your own API's
suffix, Save, then rerun Block D. Another login
will not repair a missing route; do not remove authentication.

In your API's **Settings -> Diagnostics
Logs -> Application Insights**, match the reference's existing destination,
sampling and W3C correlation, including **Support custom metrics**. Keep payload
logging at **0 bytes** and do not log Authorization; these diagnostics are
needed for M3's owned-route observations. Save only your API's settings.

**Expected result:** your own API rejects the unauthenticated request and returns
the inventory for your authenticated request. This checks both access protection
and the connection to the backend.

Observe an actual system ID/name and inspect its interfaces. If this information
is given to an agent, how might its response differ from M1?
This REST check has not given the information to the agent yet; the next steps
connect the API as tools.

### 4. Turn the operations into MCP tools

APIM -> **MCP Servers -> Create MCP server -> Expose an API as an MCP server**.
Select your REST API, for example `alpha-p2-docs-api`. Set both display name and
Name to `alpha-p2-docs-mcp` (using your own prefix). Select these twelve operations:

```text
listSystems
getSystem
listInterfaces
listDataProducts
listDocuments
getDocument
findDocumentationGaps
getDocumentationStandard
validateDocument
submitProposal
listProposals
getProposal
```

Then Create. Copy the **actual server URL** displayed by APIM, for example
`https://<your-gateway>/alpha-p2-docs-mcp/mcp`;
do not substitute the reference's or the code helper's different path.

**Why another step?** The REST API offers operations to callers. MCP presents
those operations as tools the agent can discover and choose to call.

Exclude `health` and **`publishProposal`**. Include reads, `validateDocument` and
`submitProposal`; saving must require human approval when attached to the agent.
Check the discovered names before connecting: expect `listSystems`, `getSystem`,
`validateDocument` and `submitProposal`, not summary-derived names such as
`listSystemsInTheInventory`. Different names would break adapters and approval
filters. Keep the attempt and tell the coach if they differ; do not broaden
approval or edit a pack receipt to hide the mismatch.

In **Azure portal -> your assigned API Management instance -> MCP Servers**,
select the **reference documentation MCP server** (`architecture-docs-docs-mcp`
in this deployment). In that server's menu, under **MCP**, select **Policies**.
This is the MCP server's policy editor, not the REST API's **Design** page.
For help with the editor and building policies, see
[Set or edit APIM policies](https://learn.microsoft.com/en-us/azure/api-management/set-edit-policies).

Copying the reference policy keeps the existing authentication, team checks
and request handling. You will change only the target REST path in your own copy.

<details>
<summary>Nice to know: what the MCP policy does</summary>

The policy configures:

- **Authentication:** `<validate-jwt>` checks the caller's Entra token. Find
  the tenant, issuer and audience values.
- **Team identity:** `<set-variable name="labTeam">` and the following
  `<choose>` block check the caller's team role. The `<set-header>` blocks
  pass verified team/reviewer information onward and remove unwanted key headers.
- **Request limits:** `<rate-limit-by-key>` sets the number of calls and the
  time window. Its `counter-key` separates counters by API and team.
- **Filtered-read arguments:** a `<choose>` / `<set-body>` block uses
  `EscapeDataString` so a domain filter reaches the REST API correctly.
- **JSON POST requests:** another `<choose>` block handles `validateDocument`
  and `submitProposal`. Its `<send-request>` forwards the actual arguments to
  the REST API; `<return-response>` wraps the real result as an MCP response.
- **Diagnostics and inherited policies:** `<trace source="mcp-protocol">`
  records response/error metadata, not request or response bodies. `<base />`
  keeps inherited policies in effect.

These are gateway checks and adapters; the agent's human-approval settings are
configured separately in Step 5. You can inspect the configured values without
changing the reference.

</details>

**Do not change the reference policy.** Copy it to your own server:

1. Copy the reference policy's **complete XML**, from `<policies>` through
   `</policies>`. Do not save changes on the reference.
2. Return to **MCP Servers**, select **your** server, for example
   `alpha-p2-docs-mcp`, then open **MCP -> Policies**. Replace its policy XML
   with the copied XML.
3. In **your editor**, find `<send-request>`, then the `<set-url>` block inside
   it. Find this line (the reference's REST path is the part to change):

   ```csharp
   return "https://" + context.Request.OriginalUrl.Host + "/architecture-docs/docs-api" + path;
   ```

   For Alpha participant 2, change it to:

   ```csharp
   return "https://" + context.Request.OriginalUrl.Host + "/alpha-p2/docs-api" + path;
   ```

   Use your own assigned prefix. This points validation and proposal requests
   at **your REST API**. Keep the host expression and `+ path` unchanged.
   If the coach's reference uses another prefix, replace that reference's
   `/.../docs-api` fragment instead.
4. Leave the other policy blocks unchanged. Select **Save**, confirm the save
   succeeds, then reopen the policy and check the target still contains your
   prefix.

Do not add response-body logging or expressions that read
`context.Response.Body`: they can break MCP streaming. The existing
`docsJsonResponse` variable holds the separate REST request's result; leave
that adapter code intact.

**Expected result:** your own MCP server exposes the twelve intended operations,
and its policy points POST requests to your own REST API. Next, connect an agent
and check a real read and validation call; seeing tool names alone is not enough.

### 5. Connect the tools to a new agent

Both the build route and the shortcut start here. Keep your M1 baseline for
comparison; create a steward with instructions for using the documentation tools.

**A. Create your own steward**

1. Open [Foundry](https://ai.azure.com), select your team project, then
   **Build -> Agents -> New agent -> Build an agent**.
2. Name it `alpha-p2-steward`, using your own prefix.
3. Copy the full text of your pack's **`prompts/instructions.md`** into
   **Instructions**. You can preview the
   [instructions in the repository](../../scenarios/architecture-docs/exercises/prompts/instructions.md);
   use your pack's ready-to-paste version rather than leaving template
   placeholders in the agent.
4. Select **Admin-connected -> `gpt-5.4-mini`**, using the connection ending in
   `/chat-medium`, and remove the default **Web search** tool. Use the coach's
   model names if they differ.

**B. Choose one connection route**

**Shortcut: attach the existing team Docs connection**

1. In Playground, choose **Tools -> Add -> Add tools -> Configured**.
2. Select the existing **`<workload>-<team>-docs`** connection. For Alpha, its
   name ends in **`-alpha-docs`**, not your personal prefix and not `-toolkit`.
   Select **Add tool**. Ask the coach to identify it if several names look similar.
3. Leave the shared connection unchanged and continue to **C** below.

**Build route: connect your own M2 MCP server**

In Playground, choose **Tools -> Add -> Add tools -> Custom ->
Model Context Protocol (MCP) -> Create**. Name the connection `alpha-p2-docs`,
using your own prefix, and enter the actual MCP URL you copied in Step 4.
Choose **Microsoft Entra -> Project Managed Identity**, not the default
Agent Identity.

For **Audience**, open your team pack's `workshop.json` in a text editor and
search for **`gateway_scope`**. For example, if it contains:

```json
"gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access"
```

paste only `33333333-3333-3333-3333-333333333333` into **Audience**. This is an
example ID: copy the actual ID from **your pack**. Remove the `api://` at the
start and `/Lab.Access` at the end; do not paste the whole scope, your tenant ID
or the MCP URL. You do not need to locate the reference connection in the portal.

Select **Connect**. This creates a RemoteTool connection, visible afterwards in
**Manage -> Project details -> Connected resources**. That page's **Add connection**
picker may not offer MCP; use the agent's tool picker above.

If **Connect** is disabled, hover over it to read the explanation.
**"You do not have permissions to create a connection"** is an access defect.
Tell the coach rather than switching shells, removing authentication or borrowing
an organizer account. If the existing team connection is available to you, you
can use the explicit shortcut while keeping your own connection attempt unfinished.

**C. Limit the tools and require approval**

For either route, add **only the documentation connection you selected** at this
stage. In your agent's tool **Actions -> Configure**, under **Allowed ... tools**,
paste this **comma-separated** list:

```text
listDocuments,getDocument,listSystems,getSystem,listInterfaces,listDataProducts,findDocumentationGaps,getDocumentationStandard,validateDocument,submitProposal,listProposals,getProposal
```

Use the exact MCP operation names, for example `findDocumentationGaps`, not a
display label such as "Find documentation gaps". Do not use semicolons.
Leaving this field blank can expose all tools from the server; it does not mean
the connection is broken. The explicit list limits this agent to the twelve
intended tools, even if the server later adds others. It does not replace the
server-side exclusion of `publishProposal`.

Choose
**Never auto-approve tools**; this requires confirming reads as well as saves.
For each expected read, choose **Approve -> Approve once**, not an Always option.
This keeps control of each tool call with you, including any later save.
Never choose **Always auto-approve all tools**. Apply, Save
and confirm the new agent version. Publication must not appear at all.

**Expected result:** your own steward has documentation tools and asks before
using them. Attaching a tool makes it available; the following calls check that
it actually works.

<details>
<summary>Optional reading: choosing tools and checking their behavior</summary>

[Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)
covers clear tool instructions, inspecting traces and requiring approval for
consequential actions. Tool availability and approval are separate settings.

</details>

### 6. Read evidence and check a draft

First, check the connection with one read and one validation request. Approve
only the expected calls; neither request should save anything.

1. Ask: `Call listSystems once with domain "Parts & Logistics". Report the
   returned system IDs and names. Do not submit or publish anything.`
   Inspect the pending arguments, then choose **Approve -> Approve once**.
   Expect `SYS-004` / **Spare Parts Catalogue**. This checks that the `&` in the
   filter reaches the API correctly.
2. Ask: `Call validateDocument with markdown exactly "# Validation test".
   Do not fix the text, submit or publish anything.`
   Check that the pending `markdown` argument is exactly `# Validation test`,
   then choose **Approve -> Approve once**. Expect `valid: false` and real
   validation errors: the deliberately incomplete document should not pass.
   This checks the POST request body; validation stores nothing.

If either call fails, keep the error and ask the coach before continuing.

Now try the business questions and draft:

1. "Who owns Service Order Management, and what interfaces does it use? Use the inventory."
2. "Which systems are missing architecture documentation? Do not submit anything."
3. "Draft a complete document for one missing system. Read inventory and the standard,
   validate the exact complete Markdown and correct errors. Do not save or publish."

**Expected result:** actual inventory/gap calls and genuine validator findings,
not confident guesses. Compare the first answer and trace with M1. What can
the steward now support with evidence that the baseline could not?

Keep the draft for M4's toolkit checks and the
[final proposal-saving activity](core-approval.md). Do not save or publish it yet.

The gap tool compares the supplied inventory with published documents. It can
flag missing documents, old reviews, owner mismatches and missing interfaces.
It does not discover unknown systems elsewhere in the customer's environment.

Does the answer preserve the exact inventory name? As an optional challenge,
ask about "Sales Order Management" instead. The synthetic inventory calls
SYS-002 **Service Order Management**; an answer that silently aliases the two
is a quality finding, even when its tool calls succeeded.

<details>
<summary>Optional Cloud Shell helper for building your own integration</summary>

Use **Cloud Shell -> PowerShell** and follow the Cloud Shell instructions in
[helper setup](../../PARTICIPANT-START.md#powershell-helper-setup).
Keep that session open. Here `$prefix` means your assigned name, for example
`alpha-p2`. The browser-only reference shortcut is in Step 5; these commands
are an alternative for creating owned resources.

The helper **creates missing prefixed objects from the working reference** and
refuses differing existing objects instead of overwriting your attempt:
it creates the MCP server and its selected tools together, like the working
reference. A server merely appearing in APIM does not prove its tools work.

```powershell
lab practice status
lab practice docs
$stewardBinding = Join-Path 'out' "$prefix-steward.json"
lab agent --name "$prefix-steward" --prompt instructions --docs practice --model chat-medium --output $stewardBinding
lab chat --binding $stewardBinding "Who owns Service Order Management? Use inventory evidence."
```

If your partially built objects differ, inspect/fix them in the portal or use a
new personal suffix. Do not delete the attempt. For explicit reference catch-up,
create a new binding with `--docs reference`; record that your own integration
remains unverified. It is not equivalent to completing the API build.

</details>

## You are done when

- Your own steward has made an actual inventory read and a validation call
  handling the exact submitted text; inspect their results and matching trace.
- You can explain how source access changes its answer compared with M1.
- Publication is not available, and saves still require your explicit approval.

If you built your own integration, also keep the results showing that your REST
API rejects anonymous requests, accepts your authenticated request and works
through your own MCP server. If you used the reference shortcut, that owned build
remains unfinished; you can still continue with the agent activities.

**If stuck:** keep the failed step and actual error. Ask the coach or pair with
a teammate. Use the reference shortcut rather than deleting an attempt, changing
shared resources or weakening authentication. Do not treat a failed tool call
as a successful lookup.

**Discuss:** what did MCP standardize, what did APIM govern, and what still depends
on the agent's choices? Return to your draft in
[Review and save your final proposal](core-approval.md) after evaluation.

**Next:** [M3 - Observe gateway traffic and explore limits](m3-governance.md).
