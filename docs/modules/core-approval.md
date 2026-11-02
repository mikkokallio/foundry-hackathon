# Review and save your final proposal

Review the draft you started in M2, check that declining a save really prevents
it, then approve saving the exact text you reviewed. Retrieve the result to
confirm what was stored.

Use the **browser and your own M2 steward**. Either your own documentation
connection or the shared-reference shortcut works. You do not need to publish
anything to finish this activity.

**Why?** An agent can help prepare a change, but you should control whether that
change is saved. A valid saved proposal has status **`pending-review`**:
it is waiting for a designated human reviewer, not replacing the published
document.

**No draft yet?** Return to
[M2's drafting activity](m2-tools.md#6-read-evidence-and-check-a-draft), then
come back here. Keep any evaluation findings; a poor score does not authorize
skipping review or validation.

## 1. Review and validate the draft

**Here, "draft" means document text in your chat.** There is no separate Draft
status or button. Writing or checking this text does not save a proposal.

1. Open [Foundry](https://ai.azure.com), select your team project, then
   **Build -> Agents -> your M2 steward -> Playground**.
2. Reopen the conversation where the agent produced your draft. If you cannot
   return to it, start a new conversation and paste the **complete draft**,
   not just its summary.
3. Send this request:

   > Review this draft against the current inventory, documentation standard and
   > existing document, if any. Correct unsupported or missing information.
   > Use validateDocument to check the complete corrected Markdown and fix
   > validation errors. Show me the complete final text and validation findings.
   > Do not call submitProposal or publish anything.

4. Inspect the requested lookup and validation calls, then choose
   **Approve -> Approve once** for each expected call. `validateDocument`
   checks the supplied text; it stores nothing.
5. Read the **entire final Markdown**: the full document text, including headings
   and tables, not just the agent's summary. Review validation errors/warnings
   and factual changes. A structural pass does not prove that every claim is
   supported by the inventory. Require corrections and revalidation of changed text.

**Expected result:** reviewed and validated document text in the conversation.
You have not submitted a proposal in this step.

## 2. Decline a save and check that nothing new was stored

There are two different kinds of approval:

- **A chat reply** tells the agent you agree to saving the exact reviewed text.
- **The MCP tool-approval card** controls whether the actual `submitProposal`
  call can run. For this first attempt, you will decline that card.

This deliberately checks that you can cancel at the final gate, even after
agreeing in chat.

1. Send:

   > Call listProposals. Show the existing proposal IDs for the system/document
   > in my reviewed draft. Do not save or publish anything.

   Inspect the requested read and choose **Approve -> Approve once**. Keep
   the returned IDs so an older proposal is not mistaken for a new save.
2. Send:

   > I approve saving the exact final draft displayed above, which we have
   > reviewed and validated. Do not change its Markdown. Use submitProposal
   > to save it for human review. Do not publish anything.

   If the agent asks for confirmation in chat again, confirm only that same
   exact text. When the **`submitProposal` tool-approval card** appears,
   **decline it**. Do not choose Approve for this first attempt.
3. Send:

   > Call listProposals again and compare the returned proposal IDs with the
   > earlier list. Was a new proposal for my reviewed draft stored? Base your
   > answer on the tool result. Do not submit or publish anything.

   Approve only the expected read once. Inspect its returned list: there
   should be no new corresponding proposal.

If a proposal was unexpectedly saved, stop and tell the coach. Do not delete it
to hide the result or continue by submitting another copy.

**Expected result:** you declined the write, and the before/after lists show
that it did not create a proposal.

## 3. Approve saving the exact reviewed text

Stay in the same conversation. This time you will allow the write.

1. Send the save request again:

   > I approve saving the exact final draft displayed above, which we have
   > reviewed and validated. Do not change its Markdown. Use submitProposal
   > to save it for human review. Do not publish anything.

2. Open the **`submitProposal` approval card's tool-call details**. Inspect the
   full arguments, especially the `markdown` text, system/document IDs and any
   team/source fields shown. Compare with the document you reviewed, not just
   the agent's summary. If the full text is not visible, expand the details;
   ask the coach if you still cannot inspect it.
3. If anything differs from what you approved, decline. Have the agent correct
   the text, validate it again and show it for your review before another request.
   If everything matches, choose **Approve -> Approve once**, never **Always
   approve this tool** or **Always approve all tools**.
4. Open the completed tool call's result. Keep its actual **`proposal_id`**
   and check its **`status`**. Expect `pending-review`.

If there is an error, no returned proposal ID or status `needs-changes`, keep
the result and ask the coach before submitting again. A failed or interrupted
call must not be blindly retried: first establish whether it stored a proposal.

## 4. Retrieve and check the saved proposal

1. Send:

   > Use getProposal to retrieve the proposal returned by the successful
   > submitProposal call. Show its proposal ID, status and complete stored
   > Markdown without rewriting or summarizing it. Do not submit or publish
   > anything.

2. Check that the requested proposal ID matches the `proposal_id` you kept.
   Approve that read once.
3. Open the **`getProposal` tool result**, not just the agent's reply. Compare
   its complete stored Markdown with the text you approved, and check that
   its status is **`pending-review`**.

The agent saying "saved" is not a substitute for this readback. If the result
is missing, shortened or different, keep the ID/result and ask the coach rather
than marking the save as verified.

**Expected result:** the retrieved proposal has the right ID, exact reviewed
text and `pending-review` status.

## You are done when

- Declining saved nothing new.
- Explicitly approving saved an actual proposal ID.
- The retrieved text matches what you reviewed, with status `pending-review`.

**That is the participant finish line.** Publication is a separate decision and
action for the designated human reviewer, never an agent tool. An optional coach
demonstration must follow the
[publication coordination guidance](../coach-guide.md#evaluation-and-publication-coordination);
it does not block your completion.

Never paste real credentials into a document/chat. Synthetic credential-refusal
and changed-text tests are covered further in [B7](../bonus/b7-writeback.md).

**If stuck:** keep the full draft, the failed step, any returned proposal ID and
the actual error. Ask the coach to inspect the tool request/result with you,
or pair with a teammate to observe their flow. Do not edit another person's
agent/proposal, invent a successful result or repeatedly submit the same text.

<details>
<summary>Optional: continue through an existing Cloud Shell chat session</summary>

Use this only if you already have `lab` and a working agent binding in
**Cloud Shell -> PowerShell**. The browser steps do not create a binding file.

`lab chat --binding YOUR_BINDING "YOUR_REQUEST"` starts a fresh conversation.
Continue deliberately using `--previous` with the actual last response ID when
referring to a displayed draft. Approval defaults to no; the helper displays
exact tool arguments before asking. It records real responses/approval decisions
under the scenario's `.foundry/results/`.

</details>

<details>
<summary>Further reading: tool approval</summary>

[MCP tools and approval requests](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).

</details>
