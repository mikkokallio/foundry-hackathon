# Core - Review, approve, save; then human publication

This is core, not B7. Draft/validation began in M2. Perform this after the shared
frozen-corpus comparisons. Saving proposals does not publish them; coordinate
publication across **all** teams because everyone shares the published corpus.

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
6. Ask the designated **human librarian** to retrieve/review and publish through
   the API's separate human-only action. The agent must not have `publishProposal`.
   The librarian checks base version; a conflict requires review, not force.
7. Verify published version, proposal status and the changed gap result.
   Explain why frozen-corpus gap expectations can now legitimately differ.

For the local chat path, `lab chat --binding YOUR_BINDING "YOUR_REQUEST"` starts
a fresh conversation. Continue deliberately using `--previous` with the actual
last response ID when referring to a displayed draft. Approval defaults to no;
the helper displays exact tool arguments before asking. It records real
responses/approval decisions under the scenario's `.foundry/results/`.

Never paste real credentials into a document/chat. Synthetic credential-refusal
and changed-text tests are covered further in [B7](../bonus/b7-writeback.md).

## Validate

- Declining saved nothing; explicitly approving saved an actual proposal ID.
- Stored exact text and status match the reviewed submission.
- Separate human publication succeeds and changes the expected live gap state,
  without adding a publication tool, resetting data or weakening evaluations.

**If stuck:** retain the draft and actual validator errors. A reference agent or
API can help inspect the problem; do not replace the real proposal with a fixture.
