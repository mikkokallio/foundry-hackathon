"""Local-only participant-tool tests; all doubles are confined to this file."""

from __future__ import annotations

import hashlib
import io
import json
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from urllib.error import HTTPError

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from workshop import __main__ as workshop
from workshop import practice


def example_pack():
    return {
        "subscription_id": "11111111-1111-1111-1111-111111111111",
        "tenant_id": "22222222-2222-2222-2222-222222222222",
        "team": "alpha",
        "workload_name": "example",
        "project_endpoint": "https://example.services.ai.azure.com/api/projects/alpha",
        "model_variants": [
            {
                "model_alias": model,
                "instructions": prompt,
                "agent_model_id": f"example-alpha-models/{model}",
            }
            for model in ("chat-small", "chat-medium")
            for prompt in ("instructions", "instructions-concise")
        ],
    }


def test_pack_verifies_receipt_and_does_not_accept_edited_prompt(tmp_path):
    pack = tmp_path / "workshop.json"
    pack.write_text(json.dumps(example_pack()), encoding="utf-8")
    prompt = tmp_path / "baseline.md"
    prompt.write_text("test-only prompt", encoding="utf-8")
    receipt = {
        "sha256": {
            name: hashlib.sha256((tmp_path / name).read_bytes()).hexdigest()
            for name in ("workshop.json", "baseline.md")
        }
    }
    (tmp_path / "assembly-receipt.json").write_text(json.dumps(receipt), encoding="utf-8")
    assert workshop.load_pack(pack)["team"] == "alpha"
    prompt.write_text("changed after export", encoding="utf-8")
    with pytest.raises(ValueError, match="hash mismatch"):
        workshop.load_pack(pack)


@pytest.mark.parametrize("prefix", ["beta-p1", "alpha", "alpha-p0", "alpha-p5", "../alpha-p1"])
def test_prefix_rejects_other_team_or_invalid_owner(prefix):
    with pytest.raises(ValueError, match="team-p1"):
        workshop.prefix_for(example_pack(), prefix)


def test_output_refuses_source_file_and_does_not_overwrite(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    with pytest.raises(ValueError, match="ignored out"):
        workshop.save_new(tmp_path / "source.py", {})
    target = tmp_path / "out" / "binding.json"
    workshop.save_new(target, {"version": "1"})
    with pytest.raises(FileExistsError):
        workshop.save_new(target, {"version": "2"})
    assert json.loads(target.read_text()) == {"version": "1"}


def test_idempotent_creation_never_puts_existing_or_different_object():
    pack = example_pack()
    with patch.object(
        practice, "arm", return_value={"properties": {"path": "alpha-p1/docs"}}
    ) as arm:
        practice.add(pack, None, "/owned", "version", {"path": "alpha-p1/docs"})
        arm.assert_called_once()
    with patch.object(practice, "arm", return_value={"properties": {"path": "reference"}}) as arm:
        with pytest.raises(ValueError, match="rather than overwrite"):
            practice.add(pack, None, "/owned", "version", {"path": "alpha-p1/docs"})
        arm.assert_called_once()
    missing = HTTPError("https://example.invalid", 404, "test-only missing", {}, None)
    with patch.object(practice, "arm", side_effect=[missing, {}]) as arm:
        practice.add(pack, None, "/owned", "version", {"path": "alpha-p1/docs"})
        assert arm.call_args_list[1].kwargs["method"] == "PUT"


def test_practice_mcp_can_resume_with_actual_apim_readback_shape(tmp_path):
    pack = {
        **example_pack(),
        "docs_url": "https://example.azure-api.net/example/docs-api",
        "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
        "gateway_exercises": {
            "model_backend_ids": {"chat-small": "/service/backends/chat-small"}
        },
    }
    (tmp_path / "openapi.json").write_text('{"paths": {}}', encoding="utf-8")
    args = SimpleNamespace(prefix="alpha-p1", kind="docs", pack=tmp_path / "workshop.json")
    with (
        patch.object(
            practice,
            "arm",
            return_value={"properties": {"serviceUrl": "https://backend.example"}},
        ),
        patch.object(practice, "copy_policy"),
        patch.object(practice, "project_id", return_value="/project"),
        patch.object(practice, "add") as add,
    ):
        practice.practice(args, pack, None)
    mcp = next(
        call for call in add.call_args_list if call.args[2].endswith("/alpha-p1-docs-mcp")
    )
    desired = mcp.args[4]
    assert "mcpProperties" not in desired
    actual = {
        **desired,
        "mcpProperties": {"endpoints": None, "federation": None, "isFederationRouter": False},
    }
    with patch.object(practice, "arm", return_value={"properties": actual}) as arm:
        practice.add(pack, None, mcp.args[2], mcp.args[3], desired)
    arm.assert_called_once()


def test_practice_docs_creates_tools_inline_like_the_working_reference(tmp_path):
    pack = {
        **example_pack(),
        "docs_url": "https://example.azure-api.net/example/docs-api",
        "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
        "gateway_exercises": {
            "model_backend_ids": {"chat-small": "/service/backends/chat-small"}
        },
    }
    spec = {
        "paths": {
            "/systems": {
                "get": {"operationId": "listSystems", "description": "List systems"}
            },
            "/validate": {
                "post": {"operationId": "validateDocument", "description": "Validate"}
            },
            "/health": {"get": {"operationId": "health"}},
            "/publish": {"post": {"operationId": "publishProposal"}},
        }
    }
    (tmp_path / "openapi.json").write_text(json.dumps(spec), encoding="utf-8")
    args = SimpleNamespace(prefix="alpha-p1", kind="docs", pack=tmp_path / "workshop.json")
    with (
        patch.object(
            practice,
            "arm",
            return_value={"properties": {"serviceUrl": "https://backend.example"}},
        ),
        patch.object(practice, "copy_policy"),
        patch.object(practice, "project_id", return_value="/project"),
        patch.object(practice, "add") as add,
    ):
        practice.practice(args, pack, None)
    mcp = next(
        call for call in add.call_args_list if call.args[2].endswith("/alpha-p1-docs-mcp")
    )
    assert mcp.args[4]["mcpTools"] == [
        {
            "name": "listSystems",
            "description": "List systems",
            "operationId": "/service/apis/alpha-p1-docs-api/operations/listSystems",
        },
        {
            "name": "validateDocument",
            "description": "Validate",
            "operationId": "/service/apis/alpha-p1-docs-api/operations/validateDocument",
        },
    ]
    assert not any("/tools/" in call.args[2] for call in add.call_args_list)
    with patch.object(practice, "arm", return_value={"properties": mcp.args[4]}) as arm:
        practice.add(pack, None, mcp.args[2], mcp.args[3], mcp.args[4])
    arm.assert_called_once()


def test_arm_refuses_different_subscription_before_request():
    identity = Mock()
    with pytest.raises(ValueError, match="outside"):
        workshop.arm(example_pack(), identity, "/subscriptions/other/resourceGroups/no", "version")
    identity.get_token.assert_not_called()


def test_json_requests_explicitly_negotiate_json_for_arm_policy_reads():
    def policy_response(request, timeout):
        assert timeout == 120
        if request.get_header("Accept") == "application/json":
            return io.BytesIO(b'{"properties":{"value":"<policies />"}}')
        return io.BytesIO(b"\xef\xbb\xbf<policies />")

    with patch.object(workshop, "urlopen", side_effect=policy_response):
        result = workshop.request_json(
            "https://management.azure.com/test-only/policies/policy",
            "test-only-token",
        )
    assert result == {"properties": {"value": "<policies />"}}


def test_policy_copy_requests_rawxml_instead_of_display_encoded_expressions():
    with (
        patch.object(
            practice, "arm", return_value={"properties": {"value": "<policies />"}}
        ) as read,
        patch.object(practice, "add"),
    ):
        practice.copy_policy({}, None, "/service", "reference", "alpha-p1-owned")
    assert read.call_args.kwargs == {"query": {"format": "rawxml"}}


def test_gateway_token_requests_the_exact_delegated_scope_without_resource_conversion():
    scope = "api://33333333-3333-3333-3333-333333333333/Lab.Access"
    pack = {**example_pack(), "gateway_scope": scope}
    with (
        patch("shutil.which", return_value="test-only-az"),
        patch.object(
            workshop.subprocess,
            "run",
            return_value=SimpleNamespace(returncode=0, stdout="test-only-token\n", stderr=""),
        ) as run,
    ):
        assert workshop.gateway_token(pack) == "test-only-token"
    command = run.call_args.args[0]
    assert command[command.index("--scope") + 1] == scope
    assert command[command.index("--subscription") + 1] == pack["subscription_id"]
    assert "--resource" not in command
    assert run.call_args.kwargs["timeout"] == 30
    assert run.call_args.kwargs["capture_output"] is True
    assert run.call_args.kwargs["shell"] is False


@pytest.mark.parametrize(
    "scope",
    [
        "api://33333333-3333-3333-3333-333333333333/.default",
        "api://not-a-guid/Lab.Access",
        "api://33333333-3333-3333-3333-333333333333/Lab.Access;unexpected",
    ],
)
def test_gateway_token_rejects_noncanonical_workload_scopes(scope):
    with patch.object(workshop.subprocess, "run") as run, pytest.raises(ValueError):
        workshop.gateway_token({**example_pack(), "gateway_scope": scope})
    run.assert_not_called()


@pytest.mark.parametrize(
    "result",
    [
        SimpleNamespace(returncode=1, stdout="test-only-do-not-log", stderr="auth rejected"),
        SimpleNamespace(returncode=0, stdout=" \n", stderr=""),
    ],
)
def test_gateway_token_failures_never_substitute_a_token_or_expose_stdout(result):
    with (
        patch("shutil.which", return_value="test-only-az"),
        patch.object(workshop.subprocess, "run", return_value=result),
        pytest.raises(ValueError, match="token") as error,
    ):
        workshop.gateway_token(
            {
                **example_pack(),
                "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
            }
        )
    assert "test-only-do-not-log" not in str(error.value)


def test_gateway_uses_delegated_token_instead_of_identity_resource_conversion():
    pack = {
        **example_pack(),
        "gateway_models": {"models": "https://example.invalid/models"},
        "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
    }
    identity = Mock()
    args = SimpleNamespace(route="models", burst=False, model="chat-small", query="test-only")
    with (
        patch.object(workshop, "gateway_token", create=True, return_value="test-only-token") as token,
        patch.object(workshop, "request_json", return_value={"usage": {"total_tokens": 1}}) as send,
    ):
        workshop.gateway(args, pack, identity)
    token.assert_called_once_with(pack)
    identity.get_token.assert_not_called()
    assert send.call_args.args[1] == "test-only-token"


def test_usage_preserves_unknown_and_sums_all_genuine_response_usage():
    assert workshop.gate.usage_totals([{"usage": {"input_tokens": 2, "output_tokens": 3}}]) == {
        "input_tokens": 2,
        "output_tokens": 3,
        "reasoning_tokens": None,
    }
    assert (
        workshop.gate.usage_totals([{"usage": {}}, {"usage": {"input_tokens": 8}}])["input_tokens"]
        is None
    )
    with_reasoning = {
        "usage": {
            "input_tokens": 2,
            "output_tokens": 4,
            "output_tokens_details": {"reasoning_tokens": 1},
        }
    }
    assert workshop.gate.usage_totals([with_reasoning, with_reasoning]) == {
        "input_tokens": 4,
        "output_tokens": 8,
        "reasoning_tokens": 2,
    }
    assert workshop.mean_measure([{"tokens": 1}, {"tokens": None}], "tokens") == "unavailable"
    for value in (float("nan"), float("inf"), True, -1):
        assert workshop.mean_measure([{"tokens": value}], "tokens") == "unavailable"
    assert workshop.mean_measure([], "tokens") == "unavailable"
    assert workshop.mean_measure([{"tokens": 2}, {"tokens": 4}], "tokens") == 3


@pytest.mark.parametrize(
    "cluster",
    [
        "missing_tools",
        "forbidden_tools",
        "missing_facts",
        "forbidden_facts",
        "remote_failed",
        None,
    ],
)
def test_custom_case_failure_cannot_pass_with_good_means_and_provenance(tmp_path, cluster):
    runner = workshop.gate
    plan, gate, cases, hashes = runner.load_inputs(workshop.SCENARIO)
    case = dict(next(case for case in cases if case["category"] == "draft"))
    plan = {**plan, "comparison_case_ids": [case["id"]]}
    turn = {
        "response": "Isolated test-only response",
        "tool_calls": [],
        "response_ids": ["resp_test_only"],
        "responses": [],
    }
    if cluster == "missing_tools":
        case["expected_tools"] = ["getSystem"]
    else:
        case["expected_tools"] = []
    case["forbidden_tools"] = []
    case["expected_facts"] = ["absent test fact"] if cluster == "missing_facts" else []
    case["forbidden_facts"] = ["test-only"] if cluster == "forbidden_facts" else []
    if cluster == "forbidden_tools":
        case["forbidden_tools"] = ["forbidden_test_tool"]
        turn["tool_calls"] = [{"name": "forbidden_test_tool"}]
    agent = {"name": "test-agent", "version": "1", "definition": {"tools": []}}
    args = SimpleNamespace(
        scenario_root=tmp_path,
        timeout_seconds=30,
        project_endpoint="https://test.invalid",
        agent_name="test-agent",
        agent_version="1",
        comparison=True,
    )
    evidence = runner.Evidence(
        tmp_path, tmp_path / ".foundry" / "results" / "test", "test", {"agent_version": "1"}
    )
    with (
        patch("azure.ai.projects.AIProjectClient") as project_type,
        patch("azure.identity.AzureCliCredential"),
        patch("azure.monitor.query.LogsQueryClient"),
        patch("frozen_template.TemplateComplianceEvaluator") as template,
        patch.object(runner, "load_inputs", return_value=(plan, gate, [case], hashes)),
        patch.object(runner, "validate_agent"),
        patch.object(runner, "invoke", return_value=turn),
        patch.object(runner, "evaluate", return_value=[]),
        patch.object(runner, "task_scores", return_value=[5.0]),
        patch.object(
            runner,
            "remote_clusters",
            return_value={cluster: [{"test_only": True}]} if cluster == "remote_failed" else {},
        ),
        patch.object(runner, "verify_trace", return_value={"verified": True}),
    ):
        project = project_type.return_value.__enter__.return_value
        project.agents.get_version.return_value.as_dict.return_value = agent
        project.evaluators.get_version.return_value.as_dict.return_value = {
            "version": "2",
            "definition": {"metrics": {"task_adherence": {"type": "number"}}},
        }
        template.return_value.return_value = {"template_compliance": 1.0}
        if cluster:
            with pytest.raises(runner.GateError, match="failed"):
                runner.run_worker(args, evidence)
        else:
            assert runner.run_worker(args, evidence) == 0
    suite = evidence.manifest["suites"][0]
    if cluster:
        assert suite["failure_clusters"][cluster]
        assert suite["status"] == "failed"
    else:
        assert suite["status"] == "completed"


def test_no_tools_baseline_cannot_silently_acquire_mcp():
    args = SimpleNamespace(
        prefix="alpha-p1",
        name="alpha-p1-baseline",
        model="chat-small",
        pack=Path("unused"),
        prompt="baseline",
        docs="reference",
        toolkit=False,
    )
    with (
        patch.object(Path, "read_text", return_value="Test-only baseline"),
        pytest.raises(ValueError, match="must have no tools"),
    ):
        workshop.create_agent(args, example_pack(), None)


def test_comparison_rejects_missing_incomplete_or_duplicate_matrix(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    with pytest.raises(ValueError, match="four actual"):
        workshop.compare([], tmp_path / "out" / "report")
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps({"status": "incomplete", "suites": []}))
    with pytest.raises(ValueError, match="completed"):
        workshop.compare([path] * 4, tmp_path / "out" / "report")
    assert not (tmp_path / "out" / "report").exists()


def comparison_files(tmp_path):
    paths = []
    for model in ("test-small", "test-medium"):
        for prompt in ("test-prompt-one", "test-prompt-two"):
            directory = tmp_path / f"cell-{len(paths)}"
            directory.mkdir()
            status = "failed" if not paths else "completed"
            (directory / "agent-version.json").write_text(
                json.dumps(
                    {
                        "name": f"test-agent-{len(paths)}",
                        "version": "1",
                        "definition": {"model": model, "instructions": prompt, "tools": []},
                    }
                )
            )
            manifest = {
                "status": status,
                "input_sha256": {"test-only": "test-hash"},
                "context": {
                    "agent_name": f"test-agent-{len(paths)}",
                    "agent_version": "1",
                    "project_endpoint": "https://test.invalid",
                },
                "suites": [
                    {
                        "tier": "comparison",
                        "status": status,
                        "evaluation_id": "test-eval",
                        "evaluation_run_id": "test-run",
                        "checks": [
                            {"metric": "task_adherence", "actual": 2 if status == "failed" else 4},
                        ],
                        "failure_clusters": {"missing_facts": ["test-case"]}
                        if status == "failed"
                        else {},
                        "rows": [
                            {
                                "id": f"test-case-{i}",
                                "provenance": {"verified": True},
                                "input_tokens": 2,
                                "output_tokens": 3,
                                "latency_seconds": 1,
                            }
                            for i in range(12)
                        ],
                    }
                ],
            }
            path = directory / "manifest.json"
            path.write_text(json.dumps(manifest))
            paths.append(path)
    return paths


def test_complete_failed_candidate_is_reported_as_failed_not_hidden(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    paths = comparison_files(tmp_path)
    destination = tmp_path / "out" / "comparison"
    workshop.compare(paths, destination)
    import csv

    with (destination / "comparison.csv").open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 4
    assert rows[0]["result"] == "failed"
    assert rows[0]["failure_clusters"] == "missing_facts"
    assert rows[0]["task_adherence"] == "2"
    assert rows[0]["mean_reasoning_tokens"] == "unavailable"
    assert "unavailable" in rows[0]["estimated_cost"]


@pytest.mark.parametrize("difference", ["tools", "reasoning", "project", "duplicate-coverage"])
def test_comparison_refuses_uncontrolled_matrix(tmp_path, monkeypatch, difference):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    paths = comparison_files(tmp_path)
    if difference in ("tools", "reasoning"):
        path = paths[1].parent / "agent-version.json"
        agent = json.loads(path.read_text())
        agent["definition"][difference] = (
            [{"different": True}] if difference == "tools" else {"effort": "high"}
        )
        path.write_text(json.dumps(agent))
    else:
        path = paths[1]
        manifest = json.loads(path.read_text())
        if difference == "project":
            manifest["context"]["project_endpoint"] = "https://different.invalid"
        else:
            manifest["suites"][0]["rows"][1]["id"] = "test-case-0"
        path.write_text(json.dumps(manifest))
    with pytest.raises(ValueError):
        workshop.compare(paths, tmp_path / "out" / "comparison")
    assert not (tmp_path / "out" / "comparison").exists()


def test_one_remaining_participant_can_supply_four_distinct_matrix_cells(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    paths = comparison_files(tmp_path)
    for cell, path in enumerate(paths):
        name = f"alpha-p1-comparison-{cell}"
        manifest = json.loads(path.read_text())
        manifest["context"]["agent_name"] = name
        path.write_text(json.dumps(manifest))
        agent_path = path.parent / "agent-version.json"
        agent = json.loads(agent_path.read_text())
        agent["name"] = name
        agent_path.write_text(json.dumps(agent))
    destination = tmp_path / "out" / "comparison"
    workshop.compare(paths, destination)
    import csv

    with (destination / "comparison.csv").open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 4
    assert {row["agent"] for row in rows} == {
        f"alpha-p1-comparison-{cell}" for cell in range(4)
    }
    assert rows[0]["result"] == "failed"


@pytest.mark.parametrize("agent_suffix", ["comparison", "comparison-small", "comparison-medium"])
@pytest.mark.parametrize("role", ["instructions", "writer", "reviewer"])
@pytest.mark.parametrize(
    "endpoint",
    [
        "https://example.invalid/alpha-p1/docs-mcp/mcp",
        "https://example.invalid/alpha-p1-docs-mcp/mcp",
    ],
)
def test_agent_can_reuse_one_team_practice_mcp_without_changing_ownership(
    tmp_path, monkeypatch, role, endpoint, agent_suffix
):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    pack = example_pack() | {
        "docs_mcp": "https://example.invalid/example/docs-mcp/mcp",
        "foundry_resource_id": "/test-resource",
        "toolkit_mcp": "https://example.invalid/example/toolkit/mcp",
        "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
    }
    args = workshop.parser().parse_args(
        [
            "--pack",
            str(tmp_path / "workshop.json"),
            "--prefix",
            "alpha-p2",
            "agent",
            "--name",
            f"alpha-p2-{agent_suffix}",
            "--prompt",
            role,
            "--docs",
            "practice",
            "--docs-owner",
            "alpha-p1",
            "--toolkit",
            "--output",
            str(tmp_path / "out" / "binding.json"),
        ]
    )
    with (
        patch.object(Path, "read_text", return_value="Test-only instructions"),
        patch("azure.ai.projects.AIProjectClient") as project_type,
        patch.object(
            workshop,
            "arm",
            return_value={
                "properties": {
                    "category": "RemoteTool",
                    "authType": "ProjectManagedIdentity",
                    "audience": "33333333-3333-3333-3333-333333333333",
                    "target": endpoint,
                }
            },
        ) as connection_read,
    ):
        project = project_type.return_value.__enter__.return_value
        project.agents.create_version.return_value = SimpleNamespace(
            name=args.name,
            version="1",
            as_dict=lambda: {"test_only": True},
        )
        workshop.create_agent(args, pack, None)
    assert connection_read.call_args.args[2].endswith("/connections/alpha-p1-docs")
    call = project.agents.create_version.call_args
    assert call.kwargs["agent_name"] == f"alpha-p2-{agent_suffix}"
    tool = call.kwargs["definition"].as_dict()["tools"][0]
    assert tool["server_url"] == endpoint
    assert tool["project_connection_id"].endswith("/connections/alpha-p1-docs")
    definition = call.kwargs["definition"].as_dict()
    workshop.gate.validate_agent(
        {"name": args.name, "version": "1", "definition": definition},
        args.name,
        "1",
    )
    if role in ("writer", "reviewer"):
        assert "submitProposal" not in tool["allowed_tools"]


@pytest.mark.parametrize(
    "target",
    [
        "https://other.invalid/alpha-p1-docs-mcp/mcp",
        "https://example.invalid/alpha-p2-docs-mcp/mcp",
        "http://example.invalid/alpha-p1-docs-mcp/mcp",
        "https://example.invalid/alpha-p1-docs-mcp/mcp?unexpected=true",
    ],
)
def test_practice_connection_rejects_foreign_or_unexpected_endpoints(target):
    pack = {
        **example_pack(),
        "foundry_resource_id": "/test-resource",
        "docs_mcp": "https://example.invalid/example/docs-mcp/mcp",
        "gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access",
    }
    with patch.object(
        workshop,
        "arm",
        return_value={
            "properties": {
                "category": "RemoteTool",
                "authType": "ProjectManagedIdentity",
                "audience": "33333333-3333-3333-3333-333333333333",
                "target": target,
            }
        },
    ), pytest.raises(ValueError, match="owned MCP"):
        workshop.practice_docs_endpoint(pack, None, "alpha-p1")


def test_catalog_registers_the_actual_connection_endpoint(tmp_path):
    (tmp_path / "openapi.json").write_text('{"openapi":"3.0.3"}', encoding="utf-8")
    endpoint = "https://example.invalid/alpha-p1-docs-mcp/mcp"
    pack = {
        **example_pack(),
        "catalog_resource_id": "/test-catalog",
        "docs_url": "https://example.invalid/example/docs-api",
    }
    args = SimpleNamespace(action="register", prefix="alpha-p1", pack=tmp_path / "workshop.json")
    with (
        patch.object(practice, "practice_docs_endpoint", create=True, return_value=endpoint),
        patch.object(practice, "add") as add,
        patch.object(practice, "arm"),
    ):
        practice.catalog(args, pack, None)
    assert add.call_args_list[0].args[4]["externalDocumentation"][0]["url"] == endpoint


def test_manual_approval_defaults_to_denial_and_preserves_response_ids(tmp_path, monkeypatch):
    monkeypatch.setattr(workshop, "SCENARIO", tmp_path)
    pack = example_pack()
    binding = tmp_path / "binding.json"
    binding.write_text(
        json.dumps(
            {
                "project_endpoint": pack["project_endpoint"],
                "agent_name": "alpha-p1-test",
                "agent_version": "1",
            }
        )
    )
    args = SimpleNamespace(binding=binding, query="test-only request", previous=None)
    approval = {
        "id": "test-approval",
        "type": "mcp_approval_request",
        "name": "submitProposal",
        "arguments": '{"test_only":true}',
    }
    payloads = [
        {"id": "resp_test_one", "status": "completed", "output": [approval]},
        {"id": "resp_test_two", "status": "completed", "output": []},
    ]
    with (
        patch("azure.ai.projects.AIProjectClient") as project_type,
        patch("builtins.input", return_value=""),
    ):
        client = project_type.return_value.__enter__.return_value.get_openai_client.return_value.__enter__.return_value
        client.responses.create.side_effect = [
            SimpleNamespace(
                id=p["id"], model_dump=lambda p=p, **_: p, output_text="Test-only response"
            )
            for p in payloads
        ]
        workshop.chat(args, pack, None)
    continuation = client.responses.create.call_args_list[1].kwargs
    assert continuation["previous_response_id"] == "resp_test_one"
    assert continuation["input"][0]["approve"] is False
    turn = json.loads(next((tmp_path / ".foundry" / "results").glob("*\\turn.json")).read_text())
    assert turn["response_ids"] == ["resp_test_one", "resp_test_two"]
    assert turn["approvals"][0]["approved"] is False


def test_all_guides_have_learning_structure_and_valid_local_links():
    import re

    guides = list((ROOT / "docs" / "modules").glob("*.md"))
    bonuses = list((ROOT / "docs" / "bonus").glob("*.md"))
    assert len(guides) == 6 and len(bonuses) == 9
    for guide in [*guides, *bonuses]:
        text = guide.read_text("utf-8")
        assert re.search(
            r"^## (?:Understand|What you will do)\b", text, re.MULTILINE
        ), guide
        assert re.search(r"^## (?:Build\b|1\. )", text, re.MULTILINE), guide
        assert re.search(
            r"^## (?:Validate|You are done when)\b", text, re.MULTILINE
        ), guide
        assert text.count("<details>") == text.count("</details>"), guide
        articles = re.findall(r"\]\((https://learn\.microsoft\.com/[^)]+)\)", text)
        assert 1 <= len(articles) <= (4 if guide.name == "m2-tools.md" else 2), guide
    for guide in [
        *guides,
        *bonuses,
        ROOT / "PARTICIPANT-START.md",
        ROOT / "docs" / "coach-guide.md",
        *(ROOT / "scenarios" / "architecture-docs" / "exercises" / "frontend").glob("*.md"),
    ]:
        for target in re.findall(r"\]\(([^)]+)\)", guide.read_text("utf-8")):
            if target.startswith(("https://", "#")):
                continue
            assert (guide.parent / target.split("#")[0]).resolve().exists(), (guide, target)


def test_core_guides_use_examples_and_explore_import_before_configuration():
    guides = list((ROOT / "docs" / "modules").glob("m[1-5]-*.md"))
    assert len(guides) == 5
    for guide in guides:
        text = guide.read_text("utf-8")
        assert "alpha-p2" in text, guide
        assert "<details>" in text, guide
    tools = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    assert tools.index("### 2. Explore") < tools.index("### 3. Configure")
    assert "**Tab** and press **Enter**" in tools
    assert "**reference REST API from Step 1**" in tools
    assert "Confirm **API URL suffix** is `alpha-p2/docs-api`" in tools
    assert 'Write-Output "Testing your API: $systemsUrl"' in tools
    assert "**404 / Resource not found:**" in tools
    start = (ROOT / "PARTICIPANT-START.md").read_text("utf-8")
    assert "## PowerShell helper setup" in start
    for guide in guides:
        assert "PARTICIPANT-START.md#optional-python" not in guide.read_text("utf-8")


def test_required_command_guides_cover_both_shells_and_scoped_sign_in():
    start = (ROOT / "PARTICIPANT-START.md").read_text("utf-8")
    starter = (ROOT / "workshop" / "Start-Lab.ps1").read_text("utf-8")
    assert "Cloud Shell PowerShell" in start and "PowerShell 7.5+" in start
    assert "supply only" in (ROOT / "docs" / "modules" / "m3-governance.md").read_text("utf-8")
    assert "only the coach-supplied **`workshop.json`**" in start
    assert ". ./workshop/Start-Lab.ps1 -Configuration" in start
    assert "az login --tenant $context.tenant_id --scope $context.gateway_scope" in starter
    assert "bin\\python" in starter and "Scripts\\python.exe" in starter
    assert "function global:lab" in starter
    for name in ("m2-tools.md", "m3-governance.md", "m5-evaluation.md"):
        text = (ROOT / "docs" / "modules" / name).read_text("utf-8")
        assert "Cloud Shell PowerShell" in text
        assert "local PowerShell" in text or "Local PowerShell" in text
    tools = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    assert "existing **Rehearsal Architecture Docs API**" in tools
    assert "az login --tenant $context.tenant_id --scope $context.gateway_scope" in tools
    assert "finally" in tools and "$token = $null" in tools


def test_m2_authenticated_request_has_small_blocks_with_adjacent_guidance():
    import re

    text = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    walkthrough = text.split("**A. Load your team pack and prefix**", 1)[1].split(
        "In your API's **Settings -> Diagnostics", 1
    )[0]
    blocks = re.findall(r"```powershell\n(.*?)```", walkthrough, re.DOTALL)
    assert len(blocks) == 4
    assert "$context = Get-Content" in blocks[0] and "az login" not in blocks[0]
    assert "az login --tenant" in blocks[1] and "Invoke-RestMethod" not in blocks[1]
    assert "$systemsUrl =" in blocks[2] and "get-access-token" not in blocks[2]
    assert "get-access-token" in blocks[3] and "Invoke-RestMethod" in blocks[3]
    assert "finally" in blocks[3] and "$token = $null" in blocks[3]
    assert all(len(block.strip().splitlines()) <= 10 for block in blocks)
    assert "Skip this block if you already completed" in walkthrough
    assert "device code appears" in walkthrough
    assert "rerun Block D" in walkthrough


def test_m2_policy_copy_has_exact_editor_target_and_post_connection_checks():
    text = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    assert "https://learn.microsoft.com/en-us/azure/api-management/set-edit-policies" in text
    assert "This is the MCP server's policy editor" in text
    assert '"/architecture-docs/docs-api" + path;' in text
    assert '"/alpha-p2/docs-api" + path;' in text
    assert "Do not save changes on the reference." in text
    checks = text.index("**Check the connection before trying the larger tasks:**")
    assert checks > text.index("### 5. Connect the tools")
    assert 'domain "Parts & Logistics"' in text[checks:]
    assert 'markdown exactly "# Validation test"' in text[checks:]
    assert "validation stores nothing" in text[checks:]


def test_m2_audience_is_locatable_in_the_team_pack():
    text = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    connection = text.split("### 5. Connect the tools", 1)[1]
    assert "open your team pack's `workshop.json`" in connection
    assert "search for **`gateway_scope`**" in connection
    assert '"gateway_scope": "api://33333333-3333-3333-3333-333333333333/Lab.Access"' in connection
    assert "paste only `33333333-3333-3333-3333-333333333333` into **Audience**" in connection
    assert "copy the actual ID from **your pack**" in connection
    assert "You do not need to locate the reference connection in the portal." in connection


def test_cloud_evaluation_guidance_requires_verified_result_preservation():
    start = (ROOT / "PARTICIPANT-START.md").read_text("utf-8")
    evaluation = (ROOT / "docs" / "modules" / "m5-evaluation.md").read_text("utf-8")
    assert "verify that a small file can" in start
    assert "actually be downloaded and opened locally" in start
    assert "do not create storage" in start
    assert "local PowerShell remains an alternative" in evaluation
    assert "download $archive" in evaluation
    assert "Click the archive filename in the **Download file** notification" in evaluation
    assert "Get-FileHash $archive -Algorithm SHA256" in evaluation
    assert "compare the SHA256" in evaluation
    assert "do not treat archive creation as a successful backup" in evaluation


def test_m2_tool_filter_uses_exact_comma_separated_operation_names():
    text = (ROOT / "docs" / "modules" / "m2-tools.md").read_text("utf-8")
    connection = text.split("### 5. Connect the tools", 1)[1]
    names = connection.split("```text\n", 1)[1].split("\n```", 1)[0].split(",")
    expected = (workshop.gate.READ_TOOLS - set(workshop.TOOLKIT_TOOLS)) | {
        "submitProposal"
    }
    assert len(names) == 12 and set(names) == expected
    assert "**comma-separated**" in connection
    assert "Do not use semicolons." in connection
    assert "Leaving this field blank can expose all tools" in connection
    assert "Tool availability and approval are separate settings." in connection
    assert "https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice" in connection
    assert "[M3 - See the traffic and test gateway limits](m3-governance.md)" in text


def test_cloud_setup_is_self_service_without_coach_source_upload():
    text = (ROOT / "PARTICIPANT-START.md").read_text("utf-8")
    cloud = text.split("### 1. Clone the public tools", 1)[1].split(
        "### 4. Check access", 1
    )[0]
    assert "git clone --depth 1 https://github.com/mikkokallio/foundry-hackathon.git" in cloud
    assert "No GitHub sign-in or coach-prepared shell" in cloud
    assert "not a ZIP, prompts," in cloud
    assert "Path of your workshop.json in this shell" in cloud
    assert "-Team $team -Prefix $prefix" in cloud
    assert "Expand-Archive" not in cloud
    assert "The repository is private" not in text
    assert "the coach must make" not in cloud
