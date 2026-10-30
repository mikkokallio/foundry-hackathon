"""Local adapter contracts. Mock service replies are not live acceptance evidence."""

import copy
import importlib.util
import json
import threading
from email.message import Message
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import Mock
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pytest

spec = importlib.util.spec_from_file_location(
    "frontend_reference", Path(__file__).parents[1] / "exercises" / "frontend" / "reference" / "app.py"
)
assert spec is not None and spec.loader is not None
frontend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frontend)


@pytest.fixture
def adapter():
    instance = frontend.Adapter(
        {"team": "alpha", "project_endpoint": "https://example.invalid", "reference_date": "2026-11-01"},
        {"agent_name": "alpha-p1-steward", "agent_version": "4"}, Mock(), "actual-cli-user"
    )
    instance.docs = Mock(return_value={
        "valid": True, "metadata": {"system_id": "SYS-001", "doc_id": "ARCH-TST"},
        "errors": [], "warnings": [],
    })
    return instance


@pytest.fixture
def draft():
    return {
        "system_id": "SYS-001", "doc_id": "ARCH-TST", "markdown": "exact reviewed text",
        "summary": "Reviewed change", "author_type": "human",
    }


def approved(adapter, draft):
    review = adapter.validate(draft)
    decision = {"review_id": review["review_id"], "draft": draft, "approved": True}
    approval = adapter.approve(decision)
    return {**decision, **approval}


def stored_reply(adapter, decision):
    frozen = copy.deepcopy(adapter.reviews[decision["review_id"]]["draft"])
    return {**frozen, "proposal_id": "P-test-alpha-0001", "team": "alpha", "status": "pending-review"}


def test_cancel_during_validation_cannot_recreate_consent(adapter, draft):
    def cancelled(*_args, **_kwargs):
        adapter.cancel()
        return {"valid": True, "metadata": {"system_id": "SYS-001", "doc_id": "ARCH-TST"}}

    adapter.docs.side_effect = cancelled
    with pytest.raises(ValueError, match="cancel|supersed"):
        adapter.validate(draft)
    assert adapter.reviews == {}


def test_failed_new_validation_revokes_old_approval(adapter, draft):
    decision = approved(adapter, draft)
    adapter.docs.side_effect = URLError("unavailable")
    with pytest.raises(URLError):
        adapter.validate({**draft, "summary": "new attempt"})
    assert decision["review_id"] not in adapter.reviews


@pytest.mark.parametrize("field,new", [
    ("markdown", "changed"), ("summary", "different summary"), ("author_type", "agent"),
    ("system_id", "SYS-002"), ("doc_id", "ARCH-OTHER"),
])
def test_edits_invalidate_exact_consent(adapter, draft, field, new):
    decision = approved(adapter, draft)
    with pytest.raises(ValueError, match="changed"):
        adapter.submit({**decision, "draft": {**draft, field: new}})
    assert adapter.docs.call_count == 1


def test_denial_and_expiry_do_not_write(adapter, draft, monkeypatch):
    review = adapter.validate(draft)
    assert adapter.approve({"review_id": review["review_id"], "draft": draft, "approved": False})["saved"] is False
    decision = approved(adapter, draft)
    monkeypatch.setattr(frontend.time, "monotonic", lambda: float("inf"))
    with pytest.raises(ValueError, match="expired"):
        adapter.submit(decision)
    assert adapter.docs.call_count == 2


def test_save_is_once_and_readback_is_exact(adapter, draft):
    decision = approved(adapter, draft)
    record = stored_reply(adapter, decision)
    adapter.docs.return_value = {"proposal_id": record["proposal_id"], "status": "pending-review"}
    adapter.read = Mock(return_value=record)
    assert adapter.submit(decision)["exact_text_verified"] is True
    with pytest.raises(ValueError):
        adapter.submit(decision)
    assert adapter.docs.call_count == 2


@pytest.mark.parametrize("field", ["markdown", "summary", "author_type", "source", "doc_id", "system_id", "team", "status", "proposal_id"])
def test_readback_checks_all_approved_fields(adapter, draft, field):
    decision = approved(adapter, draft)
    record = stored_reply(adapter, decision)
    adapter.docs.return_value = {"proposal_id": record["proposal_id"], "status": "pending-review"}
    record[field] = "changed"
    adapter.read = Mock(return_value=record)
    with pytest.raises(ValueError, match="readback"):
        adapter.submit(decision)
    assert adapter.reviews[decision["review_id"]]["state"] == "stored"


@pytest.mark.parametrize("failure", [URLError("lost connection"), HTTPError("https://example.invalid", 503, "failed", Message(), None)])
def test_uncertain_write_blocks_retry_and_new_save(adapter, draft, failure):
    decision = approved(adapter, draft)
    adapter.docs.side_effect = failure
    with pytest.raises(ValueError, match="unconfirmed"):
        adapter.submit(decision)
    assert adapter.reviews[decision["review_id"]]["state"] == "ambiguous"
    with pytest.raises(ValueError):
        adapter.submit(decision)
    with pytest.raises(ValueError, match="Reconcile"):
        adapter.validate(draft)
    with pytest.raises(ValueError, match="Reconcile"):
        adapter.cancel()
    assert adapter.docs.call_count == 2


def test_explicit_credential_rejection_is_not_reported_as_stored_or_unknown(adapter, draft):
    decision = approved(adapter, draft)
    adapter.docs.side_effect = HTTPError("https://example.invalid", 422, "rejected", Message(), None)
    with pytest.raises(ValueError, match="422"):
        adapter.submit(decision)
    assert adapter.reviews[decision["review_id"]]["state"] == "rejected"


def test_missing_write_receipt_is_ambiguous(adapter, draft):
    decision = approved(adapter, draft)
    adapter.docs.return_value = {}
    with pytest.raises(ValueError, match="unconfirmed"):
        adapter.submit(decision)
    assert adapter.reviews[decision["review_id"]]["state"] == "ambiguous"


def test_readback_failure_exposes_known_id_and_can_reconcile(adapter, draft):
    decision = approved(adapter, draft)
    record = stored_reply(adapter, decision)
    adapter.docs.return_value = {"proposal_id": record["proposal_id"], "status": "pending-review"}
    adapter.read = Mock(side_effect=URLError("readback unavailable"))
    with pytest.raises(ValueError, match=record["proposal_id"]):
        adapter.submit(decision)
    adapter.docs.return_value = [record]
    adapter.read = Mock(return_value=record)
    assert adapter.reconcile(decision)["exact_text_verified"] is True


@pytest.mark.parametrize("field", ["summary", "author_type", "status", "doc_id"])
def test_reconciliation_checks_metadata_too(adapter, draft, field):
    decision = approved(adapter, draft)
    record = stored_reply(adapter, decision)
    adapter.reviews[decision["review_id"]]["state"] = "ambiguous"
    record[field] = "changed"
    adapter.docs.return_value = [record]
    adapter.read = Mock(return_value=record)
    with pytest.raises(ValueError, match="readback"):
        adapter.reconcile(decision)


def test_inferred_document_id_is_in_exact_review(adapter, draft):
    result = adapter.validate({**draft, "doc_id": None})
    assert result["draft"]["doc_id"] == "ARCH-TST"


def test_context_names_actual_server_identity(adapter):
    assert adapter.context()["identity"] == "actual-cli-user"
    assert adapter.context()["release_accepted"] is False


def test_http_host_origin_nonce_and_no_publication(adapter):
    server = ThreadingHTTPServer(("127.0.0.1", 0), frontend.handler_for(adapter, "test-nonce", "unused"))
    origin = f"http://127.0.0.1:{server.server_port}"
    server.RequestHandlerClass = frontend.handler_for(adapter, "test-nonce", origin)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        with urlopen(origin + "/api/context", timeout=5) as response:
            assert json.load(response)["identity"] == "actual-cli-user"
        for path, headers, expected in [
            ("/api/cancel", {}, 403),
            ("/api/cancel", {"Origin": origin}, 403),
            ("/api/cancel", {"Origin": "https://evil.invalid", "X-Lab-Session": "test-nonce"}, 403),
            ("/api/cancel", {"Origin": origin, "X-Lab-Session": "test-nonce", "Host": "evil.invalid"}, 403),
            ("/api/publish", {"Origin": origin, "X-Lab-Session": "test-nonce"}, 404),
        ]:
            request = Request(origin + path, data=b"{}", headers={"Content-Type": "application/json", **headers})
            with pytest.raises(HTTPError) as error:
                urlopen(request, timeout=5)
            assert error.value.code == expected
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
