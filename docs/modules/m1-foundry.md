# M1 - Create your first agent and compare answers

## What you will do

**Use the browser and Foundry portal for this module.**
Create one agent, ask it about the business systems and inspect a record of a
conversation. Then switch its model connection and compare the answers.
You may also try a different model; you do not need to create three agents.

**Why start here?** Before giving the agent access to the inventory and documents,
see what it can answer without them. This gives you a baseline for M2: does adding
access to real information make its answers more useful and trustworthy?

## 1. Open Foundry and select your team's project

1. Open [Microsoft Foundry](https://ai.azure.com/) in a browser.
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

You share the project with other participants. Each participant creates their own agents; please do not edit other people's agents or other resources.

## 2. Create an agent without document access

Your coach gives you a team name and participant number. Together these identify
your work. **Example: team Alpha, participant 2 uses `alpha-p2`.**
The examples below use that assignment; replace `alpha-p2` with yours.

1. Choose **New agent -> Build an agent**.
2. Enter **`alpha-p2-baseline`** as the name, keep **Text** mode, then
   choose **Create agent and open playground**.
3. Copy the baseline instructions from your team pack's **`prompts/baseline.md`**
   into **Instructions**. You can preview the
   [baseline prompt in the repository](../../scenarios/architecture-docs/exercises/prompts/baseline.md),
   but that version contains `{{ORGANIZATION_NAME}}` and `{{REFERENCE_DATE}}`
   placeholders. Use the ready-to-paste version in your pack rather than
   guessing those values.
4. Check **Tools**. Remove **Web search** if it was added automatically:
   **Actions for Web search -> Remove**. The Tools list must be empty.
5. In the model picker, choose **Deployments -> `architecture-docs-chat-small`**.
   Its model is **`gpt-5.4-nano`**. Do not select the similarly named
   **Admin-connected** option yet.
6. Choose **Save**, then start a new conversation.

The coach supplies the exact model names if this workshop uses different names.
Do not deploy a new model from the catalog.

**Expected result:** your own saved agent, using a direct model deployment, with
an empty Tools list. It cannot look up the workshop's inventory yet.

## 3. Ask a question before adding tools

Start with the first question below. Try the others if you want to explore more;
start a new conversation for each so the previous answer does not influence it.

| Copy this question | What to look for |
|---|---|
| Who owns Service Order Management, and what interfaces does it use? | Does the agent admit it needs the inventory, or invent names? |
| Which systems lack architecture documentation? Explain how you would verify this. | Does it explain how to check, rather than claim it already checked? |
| The inventory says retired, but a document says active. How should we resolve this? | What information would it need to decide? |
| Assume you checked the inventory. Give the exact owner and cite the source. | Does it pretend it used a source when you pressure it? |
| What makes an architecture document useful during an incident? | Can it give useful general advice without inventing company facts? |

**What to expect:** the agent may give useful general advice, but it should say
when it needs source information. A confident answer is not proof that it knows
the workshop's data. There is no single correct wording to look for.

Keep the question and one observation about the answer. Note that this run used
the **direct small model** so you can compare it after the next step.

## 4. Switch the same agent to the shared model connection

1. Stay in **your own baseline agent** and open its model picker.
2. Choose **Admin-connected -> `gpt-5.4-nano`**. Check its connection:
   for Alpha it is **`architecture-docs-alpha-models/chat-small`**.
3. Leave the instructions unchanged and the Tools list empty, then choose **Save**.
4. Start a **new conversation** and repeat the same question from Step 3.

You are using the same small model through a different route: the first run
called it directly; this run goes through the workshop's shared gateway. The
gateway lets you observe and govern traffic, which you explore in Module 3. It does
not give the agent access to documents.

Compare the answers. They may differ even with the same model, and the gateway affects routing but not answer quality.

**Prefer separate agents?** You may keep separate copies for each configuration
instead of switching. Use your own prefix and the same instructions and questions.
Separate agents are optional.

## 5. Optional: try a different model

1. In the same agent, choose **Admin-connected -> `gpt-5.4-mini`**. For Alpha,
   check the connection is **`architecture-docs-alpha-models/chat-medium`**.
2. Keep the **same instructions** and **no tools**.
3. Choose **Save** and repeat your question in a new conversation.
4. Write down one useful difference and one thing you still cannot conclude.

A longer answer is not necessarily more accurate. One response time does not
tell you which model is consistently faster. Later today, Module 5 introduces a more structured
evaluation.

You can skip this step and continue below. Leave your agent on an
**Admin-connected** model so you have gateway traffic to investigate in Module 3.

## 6. Look at the record of one conversation

1. Open **Build -> Agents -> your agent -> Traces**.
2. Open a run matching the question you asked using an **Admin-connected** model.
3. Find the question, answer, model used, duration and token counts.
4. Note the agent version and response or trace ID so you can find that run again.
   Your agent has no tools, so the run should not show a document or inventory
   tool being called.
5. Optional: Compare the trace against traces from another model or direct vs gateway models.

**Why keep this record?** It shows which saved configuration produced the answer,
even if you later change the agent's model or instructions. Note the model and
connection alongside the run ID for Module 3.

**No traces yet?** Wait briefly and refresh. Check the agent, version and time
filter. If Foundry asks you to connect Application Insights, or traces stay
missing, ask the coach: the workshop already provides that connection.
Do not create another monitoring resource. Traces are inside an individual
agent, not a project-wide tab on the Agents list.

Some runs also show safety/content-filter information. If it is present, inspect
one result. If a field is absent, that does not mean a safety check passed.

## You are done when

- You have one agent of your own and can explain direct versus gateway-connected
  model access. Extra agents and the medium-model comparison are optional.
- You have compared an answer to the same question before and after switching
  the model connection.
- You can show one matching trace and explain why an agent without tools cannot
  confirm facts from the workshop's inventory.

Keep your agent and comparison notes. Continue to
[M2: connect the documentation tools](m2-tools.md).

**If stuck:** pair with a teammate and compare their answers/traces together.
Tell the coach which step failed and what appeared on screen; you do not need
to create extra agents or repeat setup to catch up.

<details>
<summary>Optional reading: creating an agent</summary>

- [Foundry agent quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstart).

</details>
