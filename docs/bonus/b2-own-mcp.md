# B2 - Build, deploy and share your own MCP tool

**After M4; developer track.** This exercise creates an additional application,
not another shared foundation. Use the existing extension authoring resources.

## Understand

Read [govern an existing MCP server](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server)
and [authenticated agent MCP tools](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).
Contrast a hosted MCP application with M2's REST operations exposed as MCP.

## Build

1. Inspect the pack's `extension_authoring`: extension resource group, shared ACA
   environment, registry and preassigned image-pull identity. Confirm your own
   build/push/app authoring access. No role-assignment permission is needed.
2. Study the actual [toolkit transport](../../scenarios/architecture-docs/toolkit-mcp/server.py)
   and [HTTP app/auth boundary](../../scenarios/architecture-docs/toolkit-mcp/app.py).
   Create your own project; do not edit the deployed reference application.
3. Implement a new read-only tool such as `impact_of_change(system_id)`, computing
   downstream systems from the synthetic interface data. Define a useful schema,
   missing-ID error and a bounded response. Test a known system and an unknown ID.
   Do not generate plausible dependency data when input is absent.
4. Configure real Entra authentication for the hosted endpoint. Reuse reviewed
   validation patterns, not the trusted backend's identity or Blob permissions.
   Build/push a uniquely tagged image in the provided registry and record its digest.
5. Create a prefixed ACA app in the **extension** group/environment, attaching the
   preassigned pull identity. Use the actual image and auth configuration.
   Test anonymous denial and an authorized call before attaching it to an agent.
6. APIM -> MCP Servers -> **Expose an existing MCP server**. Use a prefixed
   server/path and the app's actual endpoint. Apply Entra validation, compatible
   upstream auth and a bounded rate limit to your practice route.
7. Register it in API Center with version, owner, endpoint and limitations.
   Create the appropriate authenticated project connection and add the tool to
   your agent. Ask a question that genuinely needs the new operation.

## Validate

- A real new application/image, authenticated endpoint and anonymous denial.
- A real tool result matching the underlying synthetic interfaces, visible in
  Foundry tool spans and APIM telemetry.
- A usable catalog registration and honest evaluation status for the changed
  agent. New tool allowlists/evaluators require review; do not bypass the gate.

**Discuss:** who owns the tool contract, input validation and upstream identity?

**If stuck:** preserve the source/image and report the failing operation. Do not
give the app the reference runtime identity, publish an anonymous demo, create
shared services or ask for broad administrator credentials.
