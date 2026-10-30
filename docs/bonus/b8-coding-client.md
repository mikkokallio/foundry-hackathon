# B8 - Use the same governed tools from a coding client

**After M2; core approval knowledge required for saves. Copilot is optional.**

## Understand

Read [VS Code MCP setup](https://code.visualstudio.com/docs/agent-customization/mcp-servers)
and [authenticated MCP concepts](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).
The registry, gateway and approval boundary still matter outside the playground.

## Build

1. Inspect the exported `mcp.json` and
   [coding-client task prompt](../../scenarios/architecture-docs/exercises/prompts/coding-agent-task.md).
   The configuration contains a **password prompt**, not a stored bearer token.
2. In your chosen supported MCP client, merge the relevant server entry without
   overwriting unrelated configuration. Supply your own short-lived participant
   token for the exact exported audience/scope through the secret input.
   Never paste it into source, chat, logs or a committed environment file.
3. Discover/read the actual tool schemas, then ask for a real gap investigation
   and a complete draft. Inspect actual tool results; local invented JSON is not
   evidence that the remote service ran.
4. Validate the complete text and inspect the write confirmation. Decline once,
   then explicitly approve exact text if appropriate. Retrieve the actual saved
   proposal/status. Publication is still a separate human operation.
5. With no coding-agent license, perform equivalent authenticated REST requests
   from the local Python helper pattern or portal/client using the OpenAPI
   contract and your own in-memory token. This is a real alternative, not a
   requirement to purchase an assistant.

## Validate

- A real governed read/validation from the selected client and no token in files.
- Human-approved proposal with exact stored text, or an explicit read-only
  completion scope if you chose not to save.
- Relevant real response/tool/request IDs and honest qualification status.

**Discuss:** what is shared between a coding client and a Foundry agent, and whose
identity actually reaches APIM? Does one client's approval UI change server rules?

**If stuck:** record the auth/client operation and use the explicit REST path.
GitHub export/PR is a stretch requiring an authorized destination; shared Blob
proposals do not depend on GitHub or automatic publication.
