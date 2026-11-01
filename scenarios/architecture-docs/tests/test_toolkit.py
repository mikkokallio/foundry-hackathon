import json
import logging
from pathlib import Path
from unittest.mock import Mock

import pytest
import server
import uvicorn
from docs_api.config import Settings
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]


def test_cli_uses_the_authenticated_app_factory(monkeypatch):
    transport_only = Mock()
    monkeypatch.setattr(server, "build_server", lambda: transport_only)
    monkeypatch.setattr(server, "get_inventory", lambda: None)
    run = Mock()
    monkeypatch.setattr(uvicorn, "run", run)
    assert server.main() == 0
    run.assert_called_once_with("app:create_app", factory=True, host="0.0.0.0", port=8080)
    transport_only.run.assert_not_called()


def test_toolkit_diagram_uses_actual_synthetic_inventory(monkeypatch):
    monkeypatch.setenv("INVENTORY_DIR", str(ROOT / "data" / "inventory"))
    server.get_inventory.cache_clear()
    try:
        diagram = server.generate_context_diagram("SYS-011")
        assert diagram.startswith("```mermaid\nflowchart LR")
        assert "SYS-011" in diagram
        assert "INT-" in diagram
    finally:
        server.get_inventory.cache_clear()


def test_missing_storage_configuration_never_selects_local(monkeypatch):
    monkeypatch.delenv("STORAGE_MODE", raising=False)
    monkeypatch.delenv("STORAGE_ACCOUNT_URL", raising=False)
    with pytest.raises(ValueError, match="requires STORAGE_ACCOUNT_URL"):
        Settings.from_env().check()


def test_empty_storage_mode_is_rejected():
    with pytest.raises(ValueError, match="STORAGE_MODE"):
        Settings.from_env({"STORAGE_MODE": ""})


@pytest.mark.parametrize("diagnostics", ("false", "true"))
def test_toolkit_factory_enforces_gateway_identity(monkeypatch, caplog, diagnostics):
    from app import create_app

    environment = {
        "ORGANIZATION_NAME": 'Northwind R&D "Test"',
        "STORAGE_MODE": "blob",
        "STORAGE_ACCOUNT_URL": "https://testonly.blob.core.windows.net",
        "AUTH_MODE": "entra",
        "AZURE_TENANT_ID": "00000000-0000-0000-0000-000000000001",
        "BACKEND_AUDIENCE": "test-only-audience",
        "GATEWAY_PRINCIPAL_ID": "00000000-0000-0000-0000-000000000002",
        "INVENTORY_DIR": str(ROOT / "data" / "inventory"),
        "MCP_PROTOCOL_DIAGNOSTICS": diagnostics,
    }
    for key, value in environment.items():
        monkeypatch.setenv(key, value)
    caplog.set_level(logging.INFO, logger="uvicorn.error.mcp_protocol")
    for _ in range(2):
        assert environment["ORGANIZATION_NAME"] in server.build_server().instructions
        with TestClient(create_app()) as client:
            assert client.get("/health").status_code == 200
            assert client.get("/mcp").status_code == 401
    records = [record for record in caplog.records if record.name == "uvicorn.error.mcp_protocol"]
    assert len(records) == (2 if diagnostics == "true" else 0)
    for record in records:
        assert json.loads(record.getMessage().split(" ", 1)[1])["http_status"] == 401


@pytest.mark.parametrize(
    ("status", "body", "category", "code"),
    (
        (400, b'{"error":{"code":-32700,"message":"private-secret"}}', "parse-error", -32700),
        (400, b'{"error":{"code":-32602,"data":"private-secret"}}', "invalid-params", -32602),
        (406, b'{"error":{"code":"private-secret"}}', "accept-mismatch", None),
        (415, b'{"error":{"code":true}}', "content-type-mismatch", None),
        (400, b'{"error":{"code":2147483648}}', "bad-request", None),
        (400, b"private-secret", "bad-request", None),
        (200, b'{"result":{"document":"private-secret"}}', "http-response", None),
        (202, b"", "http-response", None),
        (400, b"[" * 1500 + b"]" * 1500, "bad-request", None),
        (400, b'{"secret":"' + b"x" * 17000 + b'"}', "bad-request", None),
    ),
)
def test_protocol_diagnostics_preserve_bytes_and_log_only_metadata(caplog, status, body, category, code):
    import asyncio

    from app import DIAGNOSTIC_BODY_LIMIT, _ProtocolDiagnostics

    messages = [
        {"type": "http.response.start", "status": status,
         "headers": [(b"content-type", b"application/json"), (b"secret", b"private-secret")]},
        {"type": "http.response.body", "body": body[:7], "more_body": True},
        {"type": "http.response.body", "body": body[7:]},
    ]
    sent = []

    async def receive():
        raise AssertionError("Diagnostics must not read request bodies.")

    async def send(message):
        sent.append(message)

    async def transport(scope, passed_receive, passed_send):
        assert passed_receive is receive
        assert scope["query_string"] == b"private-secret"
        for message in messages:
            await passed_send(message)

    caplog.set_level(logging.INFO, logger="uvicorn.error.mcp_protocol")
    asyncio.run(_ProtocolDiagnostics(transport)(
        {"type": "http", "path": "/mcp", "query_string": b"private-secret"}, receive, send
    ))
    assert sent == messages
    assert all(actual is original for actual, original in zip(sent, messages))
    record, = caplog.records
    assert "private-secret" not in record.getMessage()
    metadata = json.loads(record.getMessage().split(" ", 1)[1])
    assert set(metadata) <= {
        "response_started", "response_complete", "json_response", "body_truncated",
        "http_status", "json_valid", "jsonrpc_error_code", "category",
    }
    assert metadata["category"] == category
    assert metadata["http_status"] == status
    assert metadata.get("jsonrpc_error_code") == code
    assert metadata["body_truncated"] == (len(body) > DIAGNOSTIC_BODY_LIMIT)


def test_protocol_diagnostics_preserve_transport_failure(caplog):
    import asyncio

    from app import _ProtocolDiagnostics

    async def transport(scope, receive, send):
        raise RuntimeError("private-secret")

    async def unused():
        raise AssertionError("Unexpected request-body read.")

    caplog.set_level(logging.INFO, logger="uvicorn.error.mcp_protocol")
    with pytest.raises(RuntimeError, match="private-secret"):
        asyncio.run(_ProtocolDiagnostics(transport)({"type": "http", "path": "/mcp"}, unused, unused))
    record, = caplog.records
    assert "private-secret" not in record.getMessage()
    metadata = json.loads(record.getMessage().split(" ", 1)[1])
    assert metadata["category"] == "transport-incomplete"
    assert metadata["response_started"] is False


def test_invalid_protocol_diagnostic_setting_is_rejected(monkeypatch):
    from app import create_app

    monkeypatch.setenv("MCP_PROTOCOL_DIAGNOSTICS", "private-secret")
    monkeypatch.setenv("STORAGE_MODE", "local")
    monkeypatch.setenv("AUTH_MODE", "local")
    monkeypatch.setenv("ORGANIZATION_NAME", "Synthetic test")
    with pytest.raises(ValueError, match="MCP_PROTOCOL_DIAGNOSTICS must be true or false"):
        create_app()


@pytest.mark.parametrize(
    ("headers", "body", "status", "code"),
    (
        ({"accept": "application/json, text/event-stream", "content-type": "application/json"},
         b"{private-secret", 400, -32700),
        ({"accept": "application/json, text/event-stream", "content-type": "application/json"},
         b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"private-secret"}', 400, -32602),
        ({"accept": "application/json", "content-type": "application/json"},
         b'{"jsonrpc":"2.0","id":1,"method":"initialize"}', 406, -32600),
        ({"accept": "application/json, text/event-stream", "content-type": "text/plain"},
         b"private-secret", 400, None),
    ),
)
def test_real_mcp_protocol_errors_are_unchanged_by_diagnostics(monkeypatch, caplog, headers, body, status, code):
    from app import create_app

    for name, value in {
        "STORAGE_MODE": "local", "AUTH_MODE": "local", "ORGANIZATION_NAME": "Synthetic test",
        "INVENTORY_DIR": str(ROOT / "data" / "inventory"),
    }.items():
        monkeypatch.setenv(name, value)
    caplog.set_level(logging.INFO, logger="uvicorn.error.mcp_protocol")
    responses = []
    for enabled in ("false", "true"):
        monkeypatch.setenv("MCP_PROTOCOL_DIAGNOSTICS", enabled)
        with TestClient(create_app()) as client:
            response = client.post("/mcp", content=body, headers=headers)
            assert response.status_code == status
            if code is not None:
                assert response.json()["error"]["code"] == code
            responses.append(response.content)
    assert responses[0] == responses[1]
    record, = [record for record in caplog.records if record.name == "uvicorn.error.mcp_protocol"]
    assert "private-secret" not in record.getMessage()
    assert json.loads(record.getMessage().split(" ", 1)[1]).get("jsonrpc_error_code") == code
