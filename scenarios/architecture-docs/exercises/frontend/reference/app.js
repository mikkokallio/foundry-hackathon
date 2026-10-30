import DOMPurify from "dompurify";
import { marked } from "marked";
import mermaid from "mermaid";

mermaid.initialize({
  startOnLoad: false, securityLevel: "strict", maxTextSize: 200000,
  flowchart: { htmlLabels: false }, suppressErrorRendering: true,
});
const $ = id => document.getElementById(id);
let review = null, previous = null, generation = 0, revision = 0, submitting = false;
const nonce = document.querySelector('meta[name="lab-session"]').content;
const text = (id, value) => { $(id).textContent = typeof value === "string" ? value : JSON.stringify(value, null, 2); };
const draft = () => ({
  system_id: $("system-id").value, doc_id: $("doc-id").value,
  markdown: $("markdown").value, summary: $("summary").value,
  author_type: $("author-type").value,
});
async function api(path, body) {
  const response = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? {} : { "Content-Type": "application/json", "X-Lab-Session": nonce },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || `HTTP ${response.status}`);
  return value;
}
async function action(work) {
  text("error", "");
  try { await work(); } catch (error) { text("error", error.message); }
}
async function render(target, markdown) {
  const safe = DOMPurify.sanitize(marked.parse(markdown), {
    FORBID_TAGS: ["style", "iframe", "object", "embed", "form", "input", "img"],
  });
  target.innerHTML = safe;
  for (const link of target.querySelectorAll("a")) {
    link.rel = "noopener noreferrer";
    link.target = "_blank";
  }
  for (const code of target.querySelectorAll("code.language-mermaid")) {
    const source = code.textContent;
    try {
      if (/%%\s*\{|^\s*---/m.test(source)) throw new Error("Diagram configuration directives are not allowed.");
      const { svg } = await mermaid.render("diagram-" + crypto.randomUUID(), source);
      const safeSvg = DOMPurify.sanitize(svg, {
        USE_PROFILES: { svg: true, svgFilters: true },
        FORBID_TAGS: ["foreignObject", "image", "script", "style", "a"],
      });
      const holder = document.createElement("div");
      holder.innerHTML = safeSvg;
      code.parentElement.replaceWith(holder);
    } catch (error) {
      const notice = document.createElement("p");
      notice.textContent = `Diagram not rendered: ${error.message}`;
      code.parentElement.after(notice);
    }
  }
}
function invalidate() {
  ++revision;
  review = null; $("review").disabled = true; $("confirm").checked = false;
  $("save").disabled = true; text("exact-review", "");
}
for (const input of $("draft-form").querySelectorAll("input,textarea,select")) input.addEventListener("input", invalidate);
$("confirm").addEventListener("change", () => { $("save").disabled = !review || !$("confirm").checked; });
$("preview").onclick = () => action(() => render($("document-preview"), $("markdown").value));
$("validate").onclick = () => action(async () => {
  invalidate();
  const currentRevision = revision;
  const frozen = draft(), result = await api("/api/validate", frozen);
  if (currentRevision !== revision || JSON.stringify(frozen) !== JSON.stringify(draft())) {
    throw new Error("Draft changed or validation was cancelled. Validate again.");
  }
  text("validation", result.validation);
  if (result.review_id) {
    review = { id: result.review_id, draft: frozen };
    $("review").disabled = false; text("exact-review", result.draft);
  }
});
$("deny").onclick = () => action(async () => {
  if (!review) throw new Error("Validate first.");
  await api("/api/approve", { review_id: review.id, draft: draft(), approved: false });
  invalidate(); text("proposal", "Approval denied. Nothing saved.");
});
$("save").onclick = () => action(async () => {
  if (!review || !$("confirm").checked || submitting) throw new Error("Explicit exact-text approval required.");
  const current = review;
  submitting = true; $("save").disabled = true; $("cancel").disabled = true; $("draft-form").inert = true;
  try {
    const approval = await api("/api/approve", { review_id: current.id, draft: draft(), approved: true });
    const result = await api("/api/submit", { review_id: current.id, approval_id: approval.approval_id, draft: draft() });
    text("proposal", result); $("proposal-id").value = result.proposal.proposal_id;
  } finally {
    submitting = false; $("cancel").disabled = false; $("draft-form").inert = false;
    $("review").disabled = true; $("confirm").checked = false;
  }
});
$("reconcile").onclick = () => action(async () => {
  if (!review) throw new Error("No write attempt in this browser session.");
  text("proposal", await api("/api/reconcile", { review_id: review.id }));
});
$("read-proposal").onclick = () => action(async () => {
  text("proposal", await api("/api/read", { kind: "proposal", id: $("proposal-id").value }));
});
$("load-gaps").onclick = () => action(async () => {
  text("gaps-state", "Loading actual gaps..."); $("gaps").replaceChildren();
  try {
    const gaps = await api("/api/read", { kind: "gaps" });
    if (!Array.isArray(gaps)) throw new Error("Unexpected gap response.");
    text("gaps-state", `${gaps.length} actual gaps.`);
    for (const gap of gaps) {
      const li = document.createElement("li"), button = document.createElement("button");
      button.textContent = `${gap.system_id}: ${gap.detail}`;
      button.onclick = () => action(async () => {
        invalidate(); $("system-id").value = gap.system_id; $("doc-id").value = gap.doc_id || "";
        $("markdown").value = ""; $("summary").value = "";
        if (gap.doc_id) {
          const doc = await api("/api/read", { kind: "document", id: gap.doc_id });
          $("markdown").value = doc.markdown;
          await render($("document-preview"), doc.markdown);
        } else text("document-preview", "No published document. Build a draft using the current standard.");
      });
      li.append(button); $("gaps").append(li);
    }
  } catch (error) { text("gaps-state", "Gap read failed; not an empty result."); throw error; }
});
async function showChat(result, turn) {
  if (turn !== generation) return;
  previous = result.id; text("chat-evidence", result); $("tool-approvals").replaceChildren();
  await render($("answer"), result.text || "");
  if (result.error || result.status !== "completed" || result.tools.some(t => t.error)) {
    throw new Error("Invocation/tool failure. Inspect actual response evidence.");
  }
  for (const request of result.tools.filter(t => t.type === "mcp_approval_request")) {
    const box = document.createElement("section"), details = document.createElement("pre");
    details.textContent = `${request.name}\n${request.arguments}`; box.append(details);
    const isWrite = request.name === "submitProposal" || request.name === "publishProposal";
    for (const approved of isWrite ? [false] : [false, true]) {
      const button = document.createElement("button");
      button.textContent = approved ? "Approve read once" : "Deny tool request";
      button.onclick = () => action(async () => {
        box.querySelectorAll("button").forEach(b => { b.disabled = true; });
        await showChat(await api("/api/chat", {
          previous: result.id, approval_id: request.id, approved,
        }), turn);
      });
      box.append(button);
    }
    if (isWrite) {
      const notice = document.createElement("p");
      notice.textContent = "Chat writes are not approved here. Review and save exact text in the document pane.";
      box.append(notice);
    }
    $("tool-approvals").append(box);
  }
}
$("chat-form").onsubmit = event => {
  event.preventDefault();
  action(async () => {
    const turn = ++generation; $("ask").disabled = true;
    try { await showChat(await api("/api/chat", { query: $("query").value, previous }), turn); }
    finally { $("ask").disabled = false; }
  });
};
$("cancel").onclick = () => action(async () => {
  if (submitting) throw new Error("A submitted request cannot be revoked.");
  ++generation;
  invalidate();
  const result = await api("/api/cancel", {});
  previous = null; invalidate(); $("tool-approvals").replaceChildren();
  text("chat-evidence", result); $("ask").disabled = false;
});
action(async () => text("context", await api("/api/context")));
