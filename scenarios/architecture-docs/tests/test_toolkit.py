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


def test_toolkit_factory_enforces_gateway_identity(monkeypatch):
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
    }
    for key, value in environment.items():
        monkeypatch.setenv(key, value)
    for _ in range(2):
        assert environment["ORGANIZATION_NAME"] in server.build_server().instructions
        with TestClient(create_app()) as client:
            assert client.get("/health").status_code == 200
            assert client.get("/mcp").status_code == 401
