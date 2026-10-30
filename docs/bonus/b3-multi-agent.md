# B3 - Build a bounded writer/reviewer workflow

**After M5; developer track.** Two prompts are starting materials, not a workflow.

## Understand

Read [workflow orchestration](https://learn.microsoft.com/en-us/agent-framework/workflows/)
and [MCP approvals](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol).
A second agent's opinion is not independent business evidence or human approval.
Do not make the retiring Foundry visual workflow surface a required dependency.

## Build

1. Inspect the exported writer/reviewer prompts. Create two separately named,
   pinned Foundry agents in your project. Give the writer necessary read/validate
   tools; keep publication unavailable and human approval mandatory for saving.
2. Use [the runnable local coordinator](../../workshop/workflow.py) as a starting
   point. It reuses the real invocation path, allows only reviewed read/validation
   tools, refuses a missing validation call, and never saves proposals.
   Inspect it, run it, then improve one handoff or diagnostic. Use your own
   Entra identity; no fabricated local model responses.
3. Send a request to the writer. Pass the **complete returned document** and
   actual evidence/validation result to the reviewer; do not pass only a summary
   that could hide defects.
4. Require the reviewer to return a structured decision and specific findings.
   Validate that structure in the coordinator. Missing/invalid output is failure,
   not automatic approval. If revision is needed, pass findings to the writer.
5. Bound revision rounds, call timeouts and total work. Stop explicitly on
   unresolved findings; record both agents' actual versions and response IDs.
6. Inspect each agent's native traces and how the coordinator maps the handoff.
   Only after human review may the exact final text be submitted for save.
   The coordinator must never reinterpret reviewer approval as human consent.

## Validate

- Two real Foundry agents and an actually executed, bounded local handoff.
- One observed revision/decision with corresponding response/version/tool traces.
- Invalid reviewer output/unresolved findings fail explicitly; the separate
  human approval and publication boundaries still hold.

### Runnable starting point

```powershell
lab agent --name "$prefix-writer" --prompt writer --docs practice --toolkit --output "out\$prefix-writer.json"
lab agent --name "$prefix-reviewer" --prompt reviewer --docs practice --toolkit --output "out\$prefix-reviewer.json"
lab workflow --writer "out\$prefix-writer.json" --reviewer "out\$prefix-reviewer.json" --rounds 2 --timeout-seconds 600 "Draft a complete architecture document for SYS-011."
```

Both role configurations exclude proposal saving from their tool allowlists.
The coordinator retains complete responses/tool evidence and validates the
review JSON. It stops on invalid output or unresolved findings. A terminal
`ready-for-human-review` is neither provenance verification nor release acceptance;
run the unchanged gate on each actual version and inspect the handoff traces.

**Discuss:** when is one better-instructed agent simpler than two? Does the
reviewer independently verify evidence or merely repeat the writer's assertions?

**If stuck:** retain the two agent definitions and the failed handoff. A manual
two-agent conversation is a useful investigation but not a completed executable
workflow. Qualify new tool/workflow contracts before claiming release acceptance.
