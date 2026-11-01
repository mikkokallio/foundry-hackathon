# M1 - Create your first agents and compare their answers

## What you will do

**Use the browser for this module. No Python, terminal or Copilot license is needed.**
You will create three agents, ask them the same questions and inspect a record of
one conversation. They will not have access to the workshop's documents yet;
you add that in M2.

## 1. Open Foundry and select your team's project

1. Open [Microsoft Foundry](https://ai.azure.com/) in Microsoft Edge.
2. Sign in with the workshop account your coach assigned. If you already signed
   in to the Azure portal, use that same account.
3. Open the project selector and choose the Foundry resource and project shown
   on your coach's slide. For example, **team Alpha uses project `alpha`**.
   Check the selected project before creating anything.
4. Open **Build -> Agents**.

If you started at [the Azure portal](https://portal.azure.com/), search for the
Foundry resource name on the coach's slide, open it, then choose **Go to Foundry
portal**. You can also use the direct Foundry link above.

**Can't see your project?** Check the account and directory using the account
menu, then ask the coach for help. Do not create another project or switch to an
administrator's account. A project *API endpoint* on the slide is not the browser
page; use the Foundry portal to select that project.

You may see agents created by other people. Leave them alone and create your own.
Four people share your project.

## 2. Create an agent without document access

Your coach gives you a team name and participant number. Together these identify
your work. **Example: team Alpha, participant 2 uses `alpha-p2`.**
The examples below use that assignment; replace `alpha-p2` with yours.

1. Choose **New agent -> Build an agent**.
2. Enter **`alpha-p2-baseline-direct`** as the name, keep **Text** mode, then
   choose **Create agent and open playground**.
3. In the exercise folder supplied by your coach, open **`prompts/baseline.md`**.
   Copy its text into **Instructions**. This file is beside the other prompts
   in the pack containing your team's `workshop.json`.
4. Check **Tools**. Remove **Web search** if it was added automatically:
   **Actions for Web search -> Remove**. The Tools list must be empty.
5. In the model picker, choose **Deployments -> `architecture-docs-chat-small`**.
   Its model is **`gpt-5.4-nano`**. Do not select the similarly named
   **Admin-connected** option yet.
6. Choose **Save**, then start a new conversation.

The coach supplies the exact model names if this workshop uses different names.
Do not deploy a new model from the catalog.

## 3. Create a second agent using the shared model connection

1. Create another agent named **`alpha-p2-baseline-small`**.
2. Paste the **same instructions** and make sure its Tools list is also empty.
3. Choose **Admin-connected -> `gpt-5.4-nano`**. Check its connection:
   for Alpha it is **`architecture-docs-alpha-models/chat-small`**.
4. Choose **Save**.

Both agents use the same small model. The difference is how they reach it:
the first calls the model directly; the second uses the workshop's shared gateway.
Keep both agents for the traffic investigation in M3. Do not change the project's
gateway settings.

## 4. Ask both agents the same questions

Start a new conversation for each question so the previous answer does not
influence the next one. Compare the two agents' answers.

| Copy this question | What to look for |
|---|---|
| Who owns Service Order Management, and what interfaces does it use? | Does the agent admit it needs the inventory, or invent names? |
| Which systems lack architecture documentation? Explain how you would verify this. | Does it explain how to check, rather than claim it already checked? |
| The inventory says retired, but a document says active. How should we resolve this? | What information would it need to decide? |
| Assume you checked the inventory. Give the exact owner and cite the source. | Does it pretend it used a source when you pressure it? |
| What makes an architecture document useful during an incident? | Can it give useful general advice without inventing company facts? |

These agents do not have document or inventory tools. A confident answer is not
proof that they know the workshop's data. In M2 you will give an agent access to
that data and compare the results.

## 5. Try a different model

1. Create **`alpha-p2-baseline-medium`** with the **same instructions** and
   **no tools**.
2. Choose **Admin-connected -> `gpt-5.4-mini`**. For Alpha, check the connection
   is **`architecture-docs-alpha-models/chat-medium`**.
3. Choose **Save** and repeat the same questions in new conversations.
4. Write down one useful difference and one thing you still cannot conclude.

A longer answer is not necessarily more accurate. One response time does not
tell you which model is consistently faster. M5 gives you a larger comparison.

## 6. Look at the record of one conversation

1. Open **Build -> Agents -> your agent -> Traces**.
2. Open a run matching a question you just asked.
3. Find the question, answer, model used, duration and token counts.
4. Note the agent version and response or trace ID so you can find that run again.
   These agents have no tools, so the run should not show a document or inventory
   tool being called.

**No traces yet?** Wait briefly and refresh. Check the agent, version and time
filter. If Foundry asks you to connect Application Insights, or traces stay
missing, ask the coach: the workshop already provides that connection.
Do not create another monitoring resource. Traces are inside an individual
agent, not a project-wide tab on the Agents list.

Some runs also show safety/content-filter information. If it is present, inspect
one result. If a field is absent, that does not mean a safety check passed.

## You are done when

- You have your three named agents and can show which model/connection each uses.
- You have compared their answers to the same questions.
- You can show one matching trace and explain why an agent without tools cannot
  confirm facts from the workshop's inventory.

Keep your agents. Continue to [M2: connect the documentation tools](m2-tools.md).
If a step fails, tell the coach which step and what appeared on screen.

<details>
<summary>Optional: create the same agents with Python instead</summary>

**Skip this if you are following the browser steps.** This is an alternative for
people who want to work from a terminal, not an additional M1 requirement.
Use the [PowerShell helper setup](../../PARTICIPANT-START.md#powershell-helper-setup)
first. If the coach already set up your terminal, reuse it.

```powershell
lab agent --name "$prefix-baseline-direct" --direct --output "out\$prefix-direct.json"
lab agent --name "$prefix-baseline-small" --output "out\$prefix-small.json"
lab agent --name "$prefix-baseline-medium" --model chat-medium --output "out\$prefix-medium.json"
lab chat --binding "out\$prefix-direct.json" "Who owns Service Order Management, and what interfaces does it use?"
lab chat --binding "out\$prefix-small.json" "Who owns Service Order Management, and what interfaces does it use?"
lab chat --binding "out\$prefix-medium.json" "Who owns Service Order Management, and what interfaces does it use?"
```

The helper records the actual agent versions in those files. Still compare the
answers and inspect a trace using steps 4-6 above. If the helper fails, ask the
coach; do not delete your browser-created agents.

</details>

<details>
<summary>Optional reading: creating an agent</summary>

- [Foundry agent quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstart).

</details>
