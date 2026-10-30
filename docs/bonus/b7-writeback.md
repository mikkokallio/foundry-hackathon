# B7 - Challenge the write-back boundaries

**After the [core approval exercise](../modules/core-approval.md).** Saving is
already core; this bonus explores harder cases.

## Understand

Read [MCP tool approvals](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol)
alongside the [local API contract](../../scenarios/architecture-docs/openapi.json).
Approval is bound to an operation and exact content, not a permanent permission.

## Build

1. Change a validated draft after approval. Verify the changed text requires new
   validation and renewed explicit approval before submission.
2. Submit an intentionally incomplete synthetic draft to the validator, not to
   publication. Inspect real findings and verify the agent does not describe
   invalid/needs-changes content as a successful pending-review proposal.
3. Use an unmistakably synthetic credential example, never a real secret.
   The agent should refuse without echoing/saving it or producing a partial
   credential-containing draft. A subsequent redacted request is separate.
4. Compare a declined write, a successful save and stored proposal text/status.
   Verify team attribution comes from authenticated identity, not supplied text.
5. With the librarian, inspect two proposals based on the same document version.
   After an authorized publication, verify the stale one requires review rather
   than forced overwrite. Do not publish while other teams still evaluate.

## Validate

- Real approval decisions, validator results and proposal readback evidence.
- Changed text cannot reuse old approval; no agent publication operation.
- Conflicts/refusals remain explicit, with no silent fallback or altered corpus
  expectations to make evaluation results green.

**Discuss:** what would constitute proof that the approved and stored texts match?
What is the difference between a failed request and a rejected business proposal?

**If stuck:** retain actual IDs and content, ask the librarian/coach to inspect,
and do not bypass validation or force publication.
