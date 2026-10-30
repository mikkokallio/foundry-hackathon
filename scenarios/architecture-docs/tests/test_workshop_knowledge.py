"""Local-only B1 candidate and approval contracts; no service calls."""

import copy
import json
from types import SimpleNamespace
from unittest.mock import Mock, patch

import pytest
from azure.core.exceptions import ResourceNotFoundError

from workshop import __main__ as workshop


@pytest.fixture
def candidate(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    pack = {
        "subscription_id": "11111111-1111-1111-1111-111111111111",
        "foundry_resource_id": "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test",
        "project_endpoint": "https://test.services.ai.azure.com/api/projects/alpha",
        "team": "alpha",
        "workload_name": "example",
    }
    base = {
        "name": "alpha-p1-steward",
        "version": "7",
        "definition": {
            "kind": "prompt",
            "model": "unchanged-model",
            "instructions": "Unchanged steward instructions.",
            "tools": [{
                "type": "mcp",
                "server_label": "docs",
                "project_connection_id": "owned-docs",
                "allowed_tools": {"tool_names": ["listSystems", "submitProposal"]},
                "require_approval": {"always": {"tool_names": ["submitProposal"]}},
            }],
        },
    }
    binding = tmp_path / "base.json"
    binding.write_text(json.dumps({
        "agent_name": base["name"],
        "agent_version": base["version"],
        "project_endpoint": pack["project_endpoint"],
        "definition": base,
    }), encoding="utf-8")
    args = SimpleNamespace(
        prefix="alpha-p1", name="alpha-p1-knowledge-new",
        binding=binding, output=tmp_path / "out" / "new.json",
    )
    properties = {
        "category": "RemoteTool", "authType": "ProjectManagedIdentity",
        "audience": "https://search.azure.com", "isSharedToAll": False,
        "target": "https://test.search.windows.net/knowledgebases/example-architecture/mcp?api-version=2026-05-01-preview",
    }
    return args, pack, base, properties


def expected_candidate(args, pack, base):
    definition = copy.deepcopy(base["definition"])
    definition["tools"].append({
        "type": "mcp", "server_label": "example-alpha-knowledge",
        "server_url": "https://test.search.windows.net/knowledgebases/example-architecture/mcp?api-version=2026-05-01-preview",
        "project_connection_id": workshop.connection(pack, "knowledge"),
        "allowed_tools": {"tool_names": ["knowledge_base_retrieve"]},
        "require_approval": "always",
    })
    return {"name": args.name, "version": "1", "definition": definition}


def configure_client(factory, args, pack, base):
    client = factory.return_value.__enter__.return_value
    expected = expected_candidate(args, pack, base)
    client.agents.get.side_effect = ResourceNotFoundError("test-only missing")
    client.agents.get_version.side_effect = [
        Mock(as_dict=lambda: base), Mock(as_dict=lambda: expected),
    ]
    client.agents.create_version.return_value = SimpleNamespace(name=args.name, version="1")
    return client, expected


def test_candidate_preserves_actual_base_and_reads_back_fresh_version(candidate):
    args, pack, base, properties = candidate
    original = copy.deepcopy(base)
    with patch.object(workshop, "arm", return_value={"properties": properties}), patch(
        "azure.ai.projects.AIProjectClient"
    ) as factory:
        client, expected = configure_client(factory, args, pack, base)
        workshop.knowledge_candidate(args, pack, Mock())
    saved = json.loads(args.output.read_text(encoding="utf-8"))
    assert saved["definition"] == expected
    assert saved["release_accepted"] is False
    assert saved["base_agent"] == {"name": base["name"], "version": "7"}
    assert base == original
    assert expected["definition"]["tools"][:-1] == base["definition"]["tools"]
    assert expected["definition"]["instructions"] == base["definition"]["instructions"]
    assert client.agents.get_version.call_count == 2
    assert client.agents.create_version.call_args.kwargs["body"]["definition"] == expected["definition"]


@pytest.mark.parametrize("key,value", [
    ("authType", "ApiKey"), ("audience", "https://wrong.invalid"),
    ("isSharedToAll", True), ("category", "ApiManagement"),
    ("target", "http://test.search.windows.net/knowledgebases/example-architecture/mcp?api-version=2026-05-01-preview"),
    ("target", "https://test.search.windows.net/knowledgebases/foreign-architecture/mcp?api-version=2026-05-01-preview"),
    ("target", "https://test.search.windows.net/knowledgebases/example-architecture/mcp?api-version=2026-05-01-preview&extra=true"),
])
def test_candidate_rejects_unexpected_connection_before_agent_creation(candidate, key, value):
    args, pack, _, properties = candidate
    properties[key] = value
    with patch.object(workshop, "arm", return_value={"properties": properties}), patch(
        "azure.ai.projects.AIProjectClient"
    ) as factory, pytest.raises(ValueError, match="unexpected"):
        workshop.knowledge_candidate(args, pack, Mock())
    factory.assert_not_called()
    assert not args.output.exists()


def test_candidate_refuses_existing_name(candidate):
    args, pack, base, properties = candidate
    with patch.object(workshop, "arm", return_value={"properties": properties}), patch(
        "azure.ai.projects.AIProjectClient"
    ) as factory:
        client, _ = configure_client(factory, args, pack, base)
        client.agents.get.side_effect = None
        with pytest.raises(ValueError, match="name already exists"):
            workshop.knowledge_candidate(args, pack, Mock())
        client.agents.create_version.assert_not_called()


def test_candidate_refuses_existing_output_before_any_service_call(candidate):
    args, pack, _, _ = candidate
    args.output.parent.mkdir()
    args.output.write_text("preserve", encoding="utf-8")
    with patch.object(workshop, "arm") as arm, pytest.raises(ValueError, match="Binding already"):
        workshop.knowledge_candidate(args, pack, Mock())
    arm.assert_not_called()
    assert args.output.read_text() == "preserve"


def test_candidate_rejects_stale_base_binding(candidate):
    args, pack, base, properties = candidate
    with patch.object(workshop, "arm", return_value={"properties": properties}), patch(
        "azure.ai.projects.AIProjectClient"
    ) as factory:
        client, _ = configure_client(factory, args, pack, base)
        base["definition"]["instructions"] = "Different actual instructions"
        with pytest.raises(ValueError, match="differs"):
            workshop.knowledge_candidate(args, pack, Mock())
        client.agents.create_version.assert_not_called()


@pytest.mark.parametrize("arguments", [
    "null", "[]", "false", '"text"', "not json", '{"queries":[]}',
    '{"queries":["one","two"]}', '{"queries":[17]}',
    '{"queries":[""]}', json.dumps({"queries": ["a" * 151]}),
    json.dumps({"queries": ["word " * 12]}),
    '{"queries":["standard"],"unexpected":true}',
])
def test_knowledge_approval_denies_malformed_or_out_of_policy_arguments(candidate, arguments):
    args, pack, base, _ = candidate
    actual = expected_candidate(args, pack, base)
    binding = {"definition": actual, "knowledge_connection_id": workshop.connection(pack, "knowledge")}
    item = {
        "name": "knowledge_base_retrieve", "server_label": "example-alpha-knowledge",
        "arguments": arguments,
    }
    assert workshop.knowledge_approval_allowed(binding, item) is False


def test_knowledge_approval_is_specific_to_candidate_server_and_still_requires_human(candidate):
    args, pack, base, _ = candidate
    actual = expected_candidate(args, pack, base)
    binding = {"definition": actual, "knowledge_connection_id": workshop.connection(pack, "knowledge")}
    item = {
        "name": "knowledge_base_retrieve", "server_label": "example-alpha-knowledge",
        "arguments": '{"queries":["documentation interfaces"]}',
    }
    assert workshop.knowledge_approval_allowed(binding, item) is True
    assert workshop.knowledge_approval_allowed({}, item) is False
    assert workshop.knowledge_approval_allowed(binding, {**item, "server_label": "foreign"}) is False
    actual["definition"]["tools"][-1]["require_approval"] = "never"
    assert workshop.knowledge_approval_allowed(binding, item) is False
