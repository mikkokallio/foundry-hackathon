# Extend only after the real-data path works

Choose one extension and define observable acceptance before coding:

- **Evidence drawer:** show response/version/trace identifiers and source links;
  show missing provenance as unavailable, never as verified.
- **Draft comparison:** compare old/new exact Markdown and genuine validation
  findings. Any edited text invalidates previous consent.
- **Proposal history:** read real proposal/status records and handle stale-base
  conflicts explicitly. Never add force-publish or an agent publish tool.
- **Diagnostics:** distinguish auth, quota/throttle, tool, validation and
  transport failures. Respect actual retry information; never retry a write
  blindly after a lost response.
- **Accessibility:** keyboard navigation, readable errors and long-document
  review without hiding content or changing the approved text.

Keep tokens out of logs/browser storage. Do not enable APIM body/header logging
to implement diagnostics. Add focused local tests, then rerun the applicable
genuine gates and native provenance after rendering/parser/agent changes.
