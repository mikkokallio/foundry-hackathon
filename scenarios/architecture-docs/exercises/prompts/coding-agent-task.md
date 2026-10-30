# Explain gaps, then prepare a proposal

Use the configured, authenticated documentation and toolkit MCP servers for
{{ORGANIZATION_NAME}}. Business data is synthetic; reference date is
{{REFERENCE_DATE}}.

1. Resolve the system selected by the human, read its live inventory and published
   document, and explain its documentation gaps with source IDs.
2. Read the current standard/template. Draft a complete Markdown document and
   validate the exact text. Do not use a generated test fixture as an answer.
3. Show the final text and validation findings. Ask the human whether to save
   **this exact text** as a proposal. Do not infer approval from this task file.
4. Only after approval, call the proposal-save tool, with `author_type` set to
   `coding-agent` and an honest source identifier. Report the actual proposal ID
   and status returned by the tool. A needs-changes proposal is not success.
5. Never publish. A separately authorized human librarian reviews publication.

Do not put bearer tokens, connection strings or other credentials into Markdown,
prompts, source files, commits or tool output. If a tool is unavailable, report the
failure instead of inventing facts or claiming the proposal was stored.

Without a coding-agent subscription, use the same REST operations from the
OpenAPI contract with a short-lived Entra token in memory. Do not bypass identity
or team checks.
