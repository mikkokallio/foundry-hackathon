# Core - Review, approve and verify the saved proposal

This is core, not B7. Draft/validation began in M2. Attempted M5 is sufficient;
failed evaluation does not block this workshop exercise. Complete it by saving
and reading back an approved, valid proposal. No librarian or other team is
required for your completion. Saving proposals does not publish them.

## Understand

The agent prepares a proposal, the human approves **exact text**, and a separately
authorized human librarian decides publication. Neither another agent's review
nor clicking "save" authorizes publication.

Suggested reading: [MCP tools and approval requests](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).

## Build and investigate

1. Ask your steward to read the selected system/interfaces, current standard and
   existing document (if any), draft a complete document, run `validateDocument`
   and fix errors. Say **do not save**.
2. Read the entire final Markdown, validation errors/warnings and factual changes.
   A structural pass does not prove unsupported security claims. Require
   corrections and revalidation of changed text.
3. Request saving and **decline** the MCP write approval once. Verify through
   `listProposals` that no corresponding proposal was saved. If the agent first
   asks for chat consent, confirm the exact text there; the MCP approval card is
   a separate final gate. Deny that card for this test.
4. In a subsequent request explicitly approve saving the exact displayed,
   validated text. Inspect the MCP request's full `submitProposal` arguments.
   Check system/document IDs, team, source and raw Markdown, not just its summary.
   If anything differs, decline and ask for correction/revalidation/reapproval.
5. Choose **Approve -> Approve once** for only that operation, never **Always
   approve this tool** or **Always approve all tools**. Retrieve the actual
   proposal by returned ID and compare its raw stored text/status with your
   approval. A validator error or `needs-changes` status is not a successful
   pending-review proposal.
For the local chat path, `lab chat --binding YOUR_BINDING "YOUR_REQUEST"` starts
a fresh conversation. Continue deliberately using `--previous` with the actual
last response ID when referring to a displayed draft. Approval defaults to no;
the helper displays exact tool arguments before asking. It records real
responses/approval decisions under the scenario's `.foundry/results/`.

## Validate core completion

- Declining saved nothing; explicitly approving saved an actual proposal ID.
- Stored exact text and `pending-review` status match the reviewed submission.
- Exact-text approval, structural validation, authenticated team isolation,
  concurrency checks and stored-text/status readback remain mandatory even
  when M5 ended with failed/incomplete evidence.

## Optional coach demonstration: publication

This demonstration does not block team completion. Before it begins, the coach
records that **all teams'** frozen-corpus attempts completed or were explicitly
stopped. Publication changes the shared corpus.

1. The designated **human librarian** retrieves/reviews and publishes through
   the API's separate human-only action:
   [`POST /proposals/{proposal_id}/publish`](../../scenarios/architecture-docs/openapi.json).
   Use the librarian's authenticated Entra identity/role, not a supplied role
   header or an agent identity. There is no `lab publish` subcommand; the agent
   must not have `publishProposal`. Review the actual pending-review proposal,
   document ID, team and base version; a conflict requires review, not force.
   If M5 failed or stopped incomplete, explicitly accept and record
   **workshop-only/not qualified** before publication. Publication does not turn
   evaluation results green; real-project release requirements remain stricter.
2. Verify published version, proposal status and the changed gap result.
   Explain why frozen-corpus gap expectations can now legitimately differ.
   Retain the pre-publication corpus boundary; later changed-corpus runs cannot
   be claimed as the original baseline.

Never paste real credentials into a document/chat. Synthetic credential-refusal
and changed-text tests are covered further in [B7](../bonus/b7-writeback.md).

Publication succeeds only through the separate human action, without adding a
publication tool, resetting data or weakening evaluations.

**If stuck:** retain the draft and actual validator errors. A reference agent or
API can help inspect the problem; do not replace the real proposal with a fixture.
