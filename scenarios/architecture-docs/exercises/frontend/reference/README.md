# Optional B9 local reference

Try the [participant build](../README.md) first. This coach/catch-up application
uses actual exported services and an actual immutable Foundry agent. There is no
sample-data fallback, publication endpoint or cloud-hosting deployment.

## Run on Windows

Complete the [participant setup](../../../../../PARTICIPANT-START.md) first.
Use your exported pack and saved steward binding, not another team's files.
From the repository root, build the declared browser dependencies:

```powershell
Push-Location scenarios\architecture-docs\exercises\frontend\reference
npm ci --ignore-scripts
npm run check
npm run build
Pop-Location

.\.venv\Scripts\python.exe scenarios\architecture-docs\exercises\frontend\reference\app.py `
  --pack "out\YOUR-PACK\workshop.json" --binding "out\YOUR-STEWARD.json"
```

Open `http://127.0.0.1:8766`. Stop with Ctrl+C. Build output/dependencies,
credentials, participant exports and immutable bindings remain ignored.
No Linux startup/deployment acceptance is claimed.

**Identity matters:** the Python server uses its Azure CLI identity, displayed
at the top of the UI. Signing the browser into another account does not change
it. For a non-admin rehearsal, use a separate terminal with an isolated
`AZURE_CONFIG_DIR`, sign in as the actual participant, and launch the server
from that terminal. Do not overwrite another terminal's organizer credentials.

## Exercise the real path

1. Load live gaps and open an affected published document. Unknown/error state
   is not an empty inventory.
2. Ask the actual agent. Inspect response/tool IDs and arguments. Read approvals
   require an explicit decision; chat writes cannot be approved here.
3. Paste or edit complete Markdown and metadata. Preview uses sanitized Markdown
   and strict Mermaid, without permitting diagram configuration directives.
4. Validate the exact text. A failure shows actual errors and cannot enable save.
   Review the full text/metadata and explicitly check the approval box.
5. Deny first: nothing is submitted. Editing any field invalidates the decision.
   Revalidate and reapprove before saving once.
6. Read back the genuine proposal. Every submitted field, team, ID and
   pending-review status is checked. An uncertain write is never retried:
   use **Reconcile last write** or the known proposal ID.

Reviews expire after five minutes. Cancellation clears pending consent and
discards late read/validation results; it cannot revoke an already submitted
write. Reconcile an uncertain write before starting another save.

## Verification and boundaries

The local adapter contracts run with:

```powershell
.\.venv\Scripts\python.exe -m pytest scenarios\architecture-docs\tests\test_frontend_reference.py -q
```

Those tests use explicit service doubles; they are not live acceptance evidence.
Browser rehearsal separately demonstrated genuine gaps, agent invocation and
approved inventory retrieval, valid/invalid validation, denial, edit invalidation,
cancellation and actual Mermaid rendering. Script/event-handler probes did not
execute. That rehearsal used the organizer's server identity and performed no
writes to the original instance.

Configuration checks, local tests and browser operation do not grant full agent
qualification. Agent/output-parser/rendering changes still require applicable
genuine evaluation and native provenance evidence.

**Hosting continuation:** do not put this development server in ACA as-is.
It binds to loopback and intentionally uses the local person's CLI identity.
A hosted version needs a separately reviewed user sign-in/delegation/consent
design; a shared managed identity must not silently impersonate participants.
