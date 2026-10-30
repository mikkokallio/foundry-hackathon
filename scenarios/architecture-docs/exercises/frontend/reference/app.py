"""Loopback-only B9 reference. Real service calls; no publication surface."""

from __future__ import annotations

import argparse
import copy
import json
import logging
import re
import secrets
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT))
from azure.ai.projects import AIProjectClient
from azure.core.exceptions import AzureError
from azure.identity import AzureCliCredential
from openai import OpenAIError

from workshop import __main__ as workshop

STATIC = Path(__file__).resolve().parent
log = logging.getLogger("b9")


def draft_fields(value: dict[str, Any]) -> dict[str, Any]:
    result = {key: value.get(key) for key in (
        "system_id", "doc_id", "markdown", "summary", "author_type"
    )}
    if not isinstance(result["system_id"], str) or not re.fullmatch(r"SYS-\d{3}", result["system_id"]):
        raise ValueError("Select an actual SYS-NNN system.")
    if result["doc_id"] == "":
        result["doc_id"] = None
    if result["doc_id"] is not None and (
        not isinstance(result["doc_id"], str) or not re.fullmatch(r"ARCH-[A-Z]{2,6}", result["doc_id"])
    ):
        raise ValueError("Document ID must be ARCH-XXX or empty.")
    for key, limit in (("markdown", 200000), ("summary", 1000)):
        text = result[key]
        if not isinstance(text, str) or not 0 < len(text) <= limit:
            raise ValueError(f"{key} must contain 1..{limit} characters.")
    if result["author_type"] not in ("human", "agent", "coding-agent"):
        raise ValueError("Choose the actual draft author type.")
    return result


class Adapter:
    def __init__(self, pack: dict[str, Any], binding: dict[str, Any], identity: Any, user: str):
        self.pack, self.binding, self.identity, self.user = pack, binding, identity, user
        self.lock = threading.Lock()
        self.reviews: dict[str, dict[str, Any]] = {}
        self.responses: dict[str, dict[str, Any]] = {}
        self.epoch = 0
        self.review_generation = 0

    def context(self) -> dict[str, Any]:
        return {
            "project": self.pack["project_endpoint"], "team": self.pack["team"],
            "reference_date": self.pack["reference_date"],
            "agent": self.binding["agent_name"], "version": self.binding["agent_version"],
            "identity": self.user, "release_accepted": False,
        }

    def docs(self, path: str, *, body: Any = None) -> Any:
        return workshop.request_json(
            self.pack["docs_url"] + path, workshop.gateway_token(self.pack),
            method="POST" if body is not None else "GET", body=body,
        )

    def read(self, kind: str, identifier: str = "") -> Any:
        if kind == "gaps":
            return self.docs("/gaps")
        patterns = {"document": r"ARCH-[A-Z]{2,6}", "proposal": r"P-[A-Za-z0-9-]+"}
        if kind not in patterns or not re.fullmatch(patterns[kind], identifier):
            raise ValueError("Invalid read target.")
        collection = "documents" if kind == "document" else "proposals"
        return self.docs(f"/{collection}/{quote(identifier, safe='')}")

    def validate(self, value: dict[str, Any]) -> dict[str, Any]:
        draft = draft_fields(value)
        with self.lock:
            if any(r["state"] in ("submitting", "ambiguous") for r in self.reviews.values()):
                raise ValueError("Reconcile the previous write before starting another save.")
            self.reviews.clear()
            self.review_generation += 1
            generation, epoch = self.review_generation, self.epoch
        validation = self.docs("/validate", body={"markdown": draft["markdown"]})
        if not isinstance(validation, dict) or type(validation.get("valid")) is not bool:
            raise ValueError("Validation service returned an unexpected response.")
        metadata = validation.get("metadata")
        if not isinstance(metadata, dict):
            raise TypeError("Validation service returned no metadata object.")
        if validation["valid"] and (
            metadata.get("system_id") != draft["system_id"]
            or not isinstance(metadata.get("doc_id"), str)
            or not re.fullmatch(r"ARCH-[A-Z]{2,6}", metadata["doc_id"])
            or (draft["doc_id"] is not None and metadata["doc_id"] != draft["doc_id"])
        ):
            raise ValueError("Validated front matter differs from the selected system/document.")
        with self.lock:
            if epoch != self.epoch or generation != self.review_generation:
                raise ValueError("Validation was cancelled or superseded; no consent was created.")
            review_id = secrets.token_hex(16)
            frozen = {
                **draft, "doc_id": metadata.get("doc_id") if validation["valid"] else draft["doc_id"],
                "source": f"B9/{review_id}; {self.binding['agent_name']}"[:200],
            }
            if validation["valid"]:
                self.reviews[review_id] = {
                    "input": draft, "draft": frozen, "expires": time.monotonic() + 300,
                    "state": "validated", "validation": validation,
                }
        return {"review_id": review_id if validation["valid"] else None,
                "draft": frozen, "validation": validation}

    def _review(self, value: dict[str, Any], state: str) -> dict[str, Any]:
        review_id = value.get("review_id")
        if not isinstance(review_id, str):
            raise TypeError("A review ID is required.")
        record = self.reviews.get(review_id)
        if record is None or record["state"] != state:
            raise ValueError("No matching review in the required state. Validate again.")
        if record["expires"] < time.monotonic() or draft_fields(value["draft"]) != record["input"]:
            self.reviews.pop(value["review_id"])
            raise ValueError("Text/metadata changed or review expired. Revalidate and reapprove.")
        return record

    def approve(self, value: dict[str, Any]) -> dict[str, Any]:
        if type(value.get("approved")) is not bool:
            raise ValueError("An explicit true/false human decision is required.")
        with self.lock:
            record = self._review(value, "validated")
            if not value["approved"]:
                self.reviews.pop(value["review_id"])
                return {"saved": False, "cancelled": True}
            record.update(state="approved", approval_id=secrets.token_hex(16))
            return {"approval_id": record["approval_id"], "saved": False}

    def submit(self, value: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            record = self._review(value, "approved")
            if not secrets.compare_digest(str(value.get("approval_id", "")), record["approval_id"]):
                raise ValueError("Approval does not match this exact draft.")
            record["state"] = "submitting"
            frozen = copy.deepcopy(record["draft"])
        try:
            receipt = self.docs("/proposals", body=frozen)
        except HTTPError as exc:
            rejected = exc.code in (400, 401, 403, 404, 413, 415, 422)
            with self.lock:
                record["state"] = "rejected" if rejected else "ambiguous"
            if rejected:
                raise ValueError(f"Proposal rejected with HTTP {exc.code}; no retry is automatic.") from exc
            raise ValueError("Write outcome unconfirmed. Do not retry; use Reconcile last write.") from exc
        except (URLError, TimeoutError, json.JSONDecodeError) as exc:
            with self.lock:
                record["state"] = "ambiguous"
            raise ValueError("Write outcome unconfirmed. Do not retry; use Reconcile last write.") from exc
        if (
            not isinstance(receipt, dict) or not isinstance(receipt.get("proposal_id"), str)
            or not re.fullmatch(r"P-[A-Za-z0-9-]+", receipt["proposal_id"])
        ):
            with self.lock:
                record["state"] = "ambiguous"
            raise ValueError("Write outcome unconfirmed: invalid receipt. Reconcile; do not retry.")
        with self.lock:
            record.update(state="stored", receipt=receipt)
        try:
            proposal = self.read("proposal", receipt["proposal_id"])
        except (URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise ValueError(f"Stored {receipt['proposal_id']}; readback failed. Reconcile; do not resubmit.") from exc
        self.verify_readback(proposal, frozen, receipt["proposal_id"])
        if receipt.get("status") != "pending-review":
            raise ValueError(f"Stored {receipt['proposal_id']}, but pending-review/readback checks failed.")
        return {"receipt": receipt, "proposal": proposal, "exact_text_verified": True}

    def verify_readback(self, proposal: Any, frozen: dict[str, Any], proposal_id: str | None) -> None:
        if (
            not isinstance(proposal, dict)
            or any(proposal.get(key) != frozen[key] for key in frozen)
            or proposal.get("team") != self.pack["team"]
            or proposal.get("status") != "pending-review"
            or not isinstance(proposal.get("proposal_id"), str)
            or not re.fullmatch(r"P-[A-Za-z0-9-]+", proposal["proposal_id"])
            or (proposal_id is not None and proposal.get("proposal_id") != proposal_id)
        ):
            raise ValueError(f"Stored {proposal_id or 'proposal'}, but complete pending-review/readback checks failed.")

    def reconcile(self, value: dict[str, Any]) -> dict[str, Any]:
        review_id = value.get("review_id")
        if not isinstance(review_id, str):
            raise TypeError("A review ID is required.")
        with self.lock:
            record = self.reviews.get(review_id)
            if record is None or record["state"] not in ("ambiguous", "stored"):
                raise ValueError("No completed/ambiguous attempt to reconcile.")
            frozen = copy.deepcopy(record["draft"])
        summaries = self.docs("/proposals")
        if not isinstance(summaries, list) or len(summaries) > 100:
            raise ValueError("Unexpected/oversized history. Reconcile with the organizer; do not retry.")
        matches = []
        for item in summaries:
            if item.get("system_id") != frozen["system_id"]:
                continue
            actual = self.read("proposal", item["proposal_id"])
            if actual.get("source") == frozen["source"] and actual.get("team") == self.pack["team"]:
                matches.append(actual)
        if len(matches) != 1:
            raise ValueError("Write remains unconfirmed. No retry is authorized; inspect with the organizer.")
        self.verify_readback(matches[0], frozen, record.get("receipt", {}).get("proposal_id"))
        with self.lock:
            record["state"] = "stored"
        return {"proposal": matches[0], "exact_text_verified": True}

    def cancel(self) -> dict[str, Any]:
        with self.lock:
            if any(r["state"] in ("submitting", "ambiguous") for r in self.reviews.values()):
                raise ValueError("A submitted/ambiguous write cannot be cancelled. Reconcile it.")
            self.reviews.clear()
            self.responses.clear()
            self.epoch += 1
        return {"cancelled": True, "message": "Consent cleared. An in-flight read may still finish."}

    def chat(self, value: dict[str, Any]) -> dict[str, Any]:
        previous = value.get("previous")
        if previous is not None and not isinstance(previous, str):
            raise ValueError("Previous response must be an actual response ID.")
        with self.lock:
            epoch = self.epoch
            if previous and previous not in self.responses:
                raise ValueError("Previous response is not from this local session.")
            if "approval_id" in value:
                if not previous:
                    raise ValueError("Tool approval requires its previous response ID.")
                prior = self.responses.get(previous, {})
                pending = [i for i in prior.get("output", [])
                           if i.get("type") == "mcp_approval_request" and i["id"] == value["approval_id"]]
                if len(pending) != 1 or type(value.get("approved")) is not bool:
                    raise ValueError("No unique pending approval and explicit decision.")
                if value["approved"] and pending[0]["name"] not in workshop.gate.READ_TOOLS:
                    raise ValueError("Chat writes cannot be approved here. Use exact-text document review.")
                self.responses.pop(previous)
                current: Any = [{"type": "mcp_approval_response", "approval_request_id": value["approval_id"],
                                 "approve": value["approved"]}]
            else:
                current = value.get("query")
                if not isinstance(current, str) or not 0 < len(current) <= 20000:
                    raise ValueError("Enter a nonempty question of at most 20000 characters.")
        with AIProjectClient(
            endpoint=self.pack["project_endpoint"], credential=self.identity,
            retry_total=0, connection_timeout=30, read_timeout=120,
        ) as project, project.get_openai_client(timeout=120, max_retries=0) as client:
            kwargs: dict[str, Any] = {
                "input": current, "max_output_tokens": 8192,
                "extra_body": {"agent_reference": {
                    "type": "agent_reference", "name": self.binding["agent_name"],
                    "version": self.binding["agent_version"],
                }},
            }
            if previous:
                kwargs["previous_response_id"] = previous
            response = client.responses.create(**kwargs)
            payload = response.model_dump(mode="json")
        with self.lock:
            if self.epoch != epoch:
                raise ValueError("Read finished after cancellation; its result was discarded.")
            self.responses[response.id] = payload
        items = payload.get("output", [])
        return {
            "id": response.id, "status": payload.get("status"), "error": payload.get("error"),
            "text": response.output_text,
            "tools": [i for i in items if i.get("type") in ("mcp_call", "mcp_approval_request")],
            "sources": [a for i in items for c in i.get("content", []) for a in c.get("annotations", [])],
        }


def handler_for(adapter: Adapter, nonce: str, origin: str) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:
            log.info(format, *args)

        def send_json(self, status: int, value: Any) -> None:
            self.send_body(status, json.dumps(value).encode("utf-8"), "application/json")

        def send_body(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy",
                             "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
                             "img-src 'self' data:; connect-src 'self'; object-src 'none'; "
                             "base-uri 'none'; frame-ancestors 'none'")
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                log.warning("Browser disconnected; no request is automatically retried.")

        def valid_host(self) -> bool:
            return self.headers.get("Host") == urlsplit(origin).netloc

        def do_GET(self) -> None:
            if not self.valid_host():
                self.send_json(403, {"error": "Unexpected Host."})
                return
            if self.path == "/api/context":
                self.send_json(200, adapter.context())
                return
            files = {"/": ("index.html", "text/html"), "/app.js": ("dist/app.js", "text/javascript"),
                     "/style.css": ("style.css", "text/css")}
            if self.path not in files:
                self.send_json(404, {"error": "Not found."})
                return
            name, content_type = files[self.path]
            body = (STATIC / name).read_bytes()
            if name == "index.html":
                body = body.replace(b"SESSION_NONCE", nonce.encode("ascii"))
            self.send_body(200, body, content_type)

        def do_POST(self) -> None:
            authorized = (
                self.valid_host() and self.headers.get("Origin") == origin
                and secrets.compare_digest(
                    self.headers.get("X-Lab-Session", "").encode("utf-8"), nonce.encode("ascii")
                )
                and self.headers.get("Content-Type") == "application/json"
            )
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 1200000:
                    raise ValueError("Invalid request size.")
                self.connection.settimeout(10)
                raw = self.rfile.read(length)
                # Consume the bounded body so closing a rejection does not reset
                # Windows clients before they receive the explicit HTTP error.
                if not authorized:
                    self.send_json(403, {"error": "Same-origin local session required."})
                    return
                body = json.loads(raw)
                if not isinstance(body, dict):
                    raise TypeError("Expected a JSON object.")
                routes = {
                    "/api/chat": adapter.chat, "/api/validate": adapter.validate,
                    "/api/approve": adapter.approve, "/api/submit": adapter.submit,
                    "/api/reconcile": adapter.reconcile,
                    "/api/read": lambda b: adapter.read(b["kind"], b.get("id", "")),
                    "/api/cancel": lambda _: adapter.cancel(),
                }
                if self.path not in routes:
                    self.send_json(404, {"error": "Not found; publication is not available."})
                    return
                self.send_json(200, routes[self.path](body))
            except (ValueError, KeyError, TypeError, URLError, TimeoutError, AzureError, OpenAIError, subprocess.SubprocessError) as exc:
                log.warning("Operation %s failed: %s", self.path, exc)
                self.send_json(400, {"error": str(exc), "operation": self.path})

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--binding", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Choose a valid nonzero TCP port.")
    if not (STATIC / "dist" / "app.js").is_file():
        parser.error("Build the reference frontend first: npm ci && npm run build.")
    pack = workshop.load_pack(args.pack)
    binding = workshop.binding_for(args.binding, pack)
    az = workshop.shutil.which("az")
    if az is None:
        raise ValueError("Azure CLI is required; sign in in your isolated participant context.")
    result = subprocess.run(
        [az, "account", "show", "--subscription", pack["subscription_id"], "-o", "json"],
        capture_output=True, text=True, timeout=30, check=True,
    )
    account = json.loads(result.stdout)
    if account["id"] != pack["subscription_id"] or account["tenantId"] != pack["tenant_id"]:
        raise ValueError("CLI target differs from the exported pack.")
    with AzureCliCredential(subscription=pack["subscription_id"], process_timeout=30) as identity:
        with AIProjectClient(endpoint=pack["project_endpoint"], credential=identity, retry_total=0) as client:
            actual = client.agents.get_version(
                agent_name=binding["agent_name"], agent_version=binding["agent_version"]
            ).as_dict()
            workshop.gate.validate_agent(actual, binding["agent_name"], binding["agent_version"])
            if actual["definition"] != binding["definition"]["definition"]:
                raise ValueError("Actual immutable definition differs from the binding.")
        adapter = Adapter(pack, binding, identity, account["user"]["name"])
        origin = f"http://127.0.0.1:{args.port}"
        server = ThreadingHTTPServer(("127.0.0.1", args.port),
                                    handler_for(adapter, secrets.token_urlsafe(32), origin))
        logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
        print(f"B9 local reference: {origin}; identity={adapter.user}; not release-qualified.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            log.info("Stopping local server.")
        finally:
            server.server_close()


if __name__ == "__main__":
    main()
