import json
from pathlib import Path

from docs_api.main import create_app
from test_api import settings

ROOT = Path(__file__).resolve().parents[1]


def test_imported_operations_match_real_routes(tmp_path):
    imported = json.loads((ROOT / "openapi.json").read_text(encoding="utf-8"))
    actual = create_app(settings(tmp_path, auth_mode="local")).openapi()

    def operations(spec):
        return {
            (path, method, operation["operationId"])
            for path, methods in spec["paths"].items()
            for method, operation in methods.items()
            if method in ("get", "post")
        }

    assert operations(imported) == operations(actual)


def test_contract_describes_current_auth_and_publication_conflicts():
    text = (ROOT / "openapi.json").read_text(encoding="utf-8")
    spec = json.loads(text)
    assert "subscription key" not in text
    assert "gateway secret" not in text
    assert spec["security"] == [{"EntraBearer": []}]
    assert spec["paths"]["/health"]["get"]["security"] == []
    assert "409" in spec["paths"]["/proposals/{proposal_id}/publish"]["post"]["responses"]
