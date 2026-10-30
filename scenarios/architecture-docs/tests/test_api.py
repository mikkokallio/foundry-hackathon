import datetime as dt
from html import escape
from pathlib import Path
from uuid import UUID

import pytest
from archdocs.store import make_store
from docs_api.auth import GatewayIdentity, GatewayVerifier
from docs_api.config import Settings
from docs_api.main import create_app
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]


def settings(tmp_path, **overrides):
    overrides.setdefault("storage_mode", "local")
    overrides.setdefault("organization_name", "Test Organization")
    return Settings(
        local_store_dir=str(tmp_path),
        inventory_dir=str(ROOT / "data" / "inventory"),
        seed_dir=str(ROOT / "data" / "docs"),
        standard_dir=str(ROOT / "data" / "standard"),
        reference_date=dt.date(2026, 11, 1),
        **overrides,
    )


def test_exact_gap_baseline(tmp_path):
    with TestClient(create_app(settings(tmp_path, auth_mode="local"))) as client:
        response = client.get("/gaps")
        assert response.status_code == 200
        assert len(response.json()) == 15


@pytest.mark.parametrize("organization", ["Northwind Manufacturing", 'R&D "North" <Works>'])
def test_deployer_branding_reaches_api_and_standard(tmp_path, organization):
    with TestClient(
        create_app(settings(tmp_path, auth_mode="local", organization_name=organization))
    ) as client:
        spec = client.get("/openapi.json").json()
        assert spec["info"]["title"] == f"{organization} Architecture Docs API"
        response = client.get("/standard")
        assert response.status_code == 200
        standard = response.json()["standard_markdown"]
        assert escape(organization, quote=False) in standard
        assert "{{organization_name}}" not in standard
        assert "Contoso" not in standard


@pytest.mark.parametrize("organization", ["", " ", "name\nheading", "name\x7f", "x" * 121])
def test_organization_name_must_be_explicit_and_single_line(tmp_path, organization):
    with pytest.raises(ValueError, match="ORGANIZATION_NAME"):
        create_app(settings(tmp_path, auth_mode="local", organization_name=organization))


def test_unknown_storage_does_not_fall_back(monkeypatch):
    monkeypatch.setenv("STORAGE_MODE", "typo")
    with pytest.raises(ValueError, match="Unknown STORAGE_MODE"):
        make_store()


def test_blob_requires_entra(tmp_path):
    with pytest.raises(ValueError, match="require Entra"):
        create_app(
            settings(
                tmp_path,
                storage_mode="blob",
                storage_account_url="https://test.blob.core.windows.net",
                auth_mode="local",
            )
        )


def test_entra_missing_config_fails_at_startup(tmp_path):
    with pytest.raises(ValueError, match="Entra authentication requires"):
        create_app(settings(tmp_path))


def test_spoofed_gateway_headers_do_not_authenticate(tmp_path):
    configured = settings(
        tmp_path,
        tenant_id=str(UUID(int=1)),
        gateway_audience="https://management.azure.com/",
        gateway_principal_id=str(UUID(int=2)),
    )
    with TestClient(create_app(configured)) as client:
        response = client.get(
            "/systems", headers={"X-Team-Id": "team1", "X-Publisher-Role": "librarian"}
        )
        assert response.status_code == 401
        assert client.get("/health").status_code == 200


def test_approved_shared_proposal_and_separate_publish(tmp_path, monkeypatch):
    monkeypatch.setattr(
        GatewayVerifier,
        "verify",
        lambda self, token: GatewayIdentity(str(UUID(int=2)), self.audience),
    )
    configured = settings(
        tmp_path,
        tenant_id=str(UUID(int=1)),
        gateway_audience="https://management.azure.com/",
        gateway_principal_id=str(UUID(int=2)),
    )
    headers = {"Authorization": "Bearer test-only", "X-Team-Id": "team1"}
    markdown = (ROOT / "tests" / "fixtures" / "generated" / "product-configurator.md").read_text(encoding="utf-8")
    with TestClient(create_app(configured)) as client:
        result = client.post(
            "/proposals",
            headers=headers,
            json={
                "system_id": "SYS-011",
                "markdown": markdown,
                "summary": "Human-approved proposal",
                "team": "forged-team",
            },
        )
        assert result.status_code == 200
        proposal = result.json()
        assert proposal["team"] == "team1"
        assert proposal["status"] == "pending-review"
        pid = proposal["proposal_id"]
        assert client.post(f"/proposals/{pid}/publish", headers=headers).status_code == 403
        published = client.post(
            f"/proposals/{pid}/publish",
            headers={**headers, "X-Publisher-Role": "librarian"},
        )
        assert published.status_code == 200
        assert client.get("/documents/ARCH-CFG", headers=headers).status_code == 200
