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


@pytest.mark.parametrize("role", ["instructions", "writer", "reviewer"])
def test_agent_can_reuse_one_team_practice_mcp_without_changing_ownership(
    tmp_path, monkeypatch, role
):
    monkeypatch.setattr(workshop, "ROOT", tmp_path)
    pack = example_pack() | {
        "docs_mcp": "https://example.invalid/example/docs-mcp/mcp",
        "foundry_resource_id": "/test-resource",
        "toolkit_mcp": "https://example.invalid/example/toolkit/mcp",
    }
    args = workshop.parser().parse_args(
        [
            "--pack",
            str(tmp_path / "workshop.json"),
            "--prefix",
            "alpha-p2",
            "agent",
            "--name",
            "alpha-p2-comparison",
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
    ):
        project = project_type.return_value.__enter__.return_value
        project.agents.create_version.return_value = SimpleNamespace(
            name=args.name,
            version="1",
            as_dict=lambda: {"test_only": True},
        )
        workshop.create_agent(args, pack, None)
    call = project.agents.create_version.call_args
    assert call.kwargs["agent_name"] == "alpha-p2-comparison"
    tool = call.kwargs["definition"].as_dict()["tools"][0]
    assert tool["server_url"] == "https://example.invalid/alpha-p1/docs-mcp/mcp"
    assert tool["project_connection_id"].endswith("/connections/alpha-p1-docs")
    definition = call.kwargs["definition"].as_dict()
    workshop.gate.validate_agent(
        {"name": args.name, "version": "1", "definition": definition},
        args.name,
        "1",
    )
    if role in ("writer", "reviewer"):
        assert "submitProposal" not in tool["allowed_tools"]


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
        assert "## Understand" in text, guide
        assert re.search(r"^## Build", text, re.MULTILINE), guide
        assert "## Validate" in text, guide
        articles = re.findall(r"\]\((https://[^)]+)\)", text)
        assert 1 <= len(articles) <= 2, guide
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
