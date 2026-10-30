"""Local-only workflow and policy tests; no doubles are available to runtime paths."""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from workshop import practice
from workshop import workflow as flow


@pytest.mark.parametrize(
    "text",
    [
        "not json",
        "[]",
        '{"decision":"ready-for-human-review","findings":["unresolved"]}',
        '{"decision":"ready-for-human-review","findings":[{"message":"issue","source_ids":["SYS"],"correction":"fix"}]}',
        '{"decision":"revise","findings":[]}',
        '{"decision":"ready-for-human-review","findings":[],"approved":true}',
    ],
)
def test_reviewer_invalid_or_contradictory_output_never_becomes_approval(text):
    with pytest.raises((ValueError, json.JSONDecodeError)):
        flow.review_decision(text)


def workflow_case(tmp_path):
    pack = {"project_endpoint": "https://test.invalid"}
    for role in ("writer", "reviewer"):
        (tmp_path / f"{role}.json").write_text(
            json.dumps(
                {
                    "agent_name": f"test-{role}",
                    "agent_version": "1",
                    **pack,
                }
            )
        )
    args = SimpleNamespace(
        writer=tmp_path / "writer.json",
        reviewer=tmp_path / "reviewer.json",
        query="test-only user request",
        rounds=2,
        timeout_seconds=30,
    )
    agents = [
        {
            "name": f"test-{role}",
            "version": "1",
            "definition": {
                "kind": "prompt",
                "tools": [
                    {
                        "type": "mcp",
                        "project_connection_id": "test-connection",
                        "allowed_tools": ["validateDocument"],
                        "require_approval": {"never": {"tool_names": ["validateDocument"]}},
                    }
                ],
            },
        }
        for role in ("writer", "reviewer")
    ]
    draft = {
        "response": "COMPLETE TEST-ONLY DRAFT including all sections",
        "tool_calls": [{"name": "validateDocument", "output": '{"test_only":"validation"}'}],
        "response_ids": ["resp_test_writer"],
    }
    revise = {
        "response": json.dumps(
            {
                "decision": "revise",
                "findings": [
                    {
                        "message": "test-only missing detail",
                        "source_ids": ["TEST-STD"],
                        "correction": "test-only correction",
                    }
                ],
            }
        ),
        "tool_calls": [{"name": "validateDocument"}],
        "response_ids": ["resp_test_reviewer_revise"],
    }
    ready = {
        "response": '{"decision":"ready-for-human-review","findings":[]}',
        "tool_calls": [{"name": "validateDocument"}],
        "response_ids": ["resp_test_reviewer_ready"],
    }
    return pack, args, agents, draft, revise, ready


@pytest.mark.parametrize(
    "outcome",
    [
        "ready",
        "revise-then-ready",
        "unresolved",
        "invalid-review",
        "missing-writer-validation",
        "missing-reviewer-validation",
        "writable-agent",
    ],
)
def test_bounded_real_handoff_contract(tmp_path, monkeypatch, outcome):
    monkeypatch.setattr(flow, "SCENARIO", tmp_path)
    pack, args, agents, draft, revise, ready = workflow_case(tmp_path)
    turns = [draft, ready]
    if outcome == "revise-then-ready":
        turns = [draft, revise, draft, ready]
    elif outcome == "unresolved":
        turns = [draft, revise, draft, revise]
    elif outcome == "invalid-review":
        ready["response"] = "not valid JSON"
    elif outcome == "missing-writer-validation":
        draft["tool_calls"] = []
    elif outcome == "missing-reviewer-validation":
        ready["tool_calls"] = []
    elif outcome == "writable-agent":
        agents[0]["definition"]["tools"][0]["allowed_tools"].append("submitProposal")
        agents[0]["definition"]["tools"][0]["require_approval"] = "always"
    with (
        patch("azure.ai.projects.AIProjectClient") as project_type,
        patch.object(flow.gate, "invoke", side_effect=turns) as invoke,
    ):
        project = project_type.return_value.__enter__.return_value
        project.agents.get_version.return_value.as_dict.side_effect = agents
        if outcome in ("ready", "revise-then-ready"):
            flow.workflow(args, pack, None)
            assert invoke.call_args_list[1].args[1]["query"].find(draft["response"]) >= 0
            assert "validation" in invoke.call_args_list[1].args[1]["query"]
            if outcome == "revise-then-ready":
                assert "test-only correction" in invoke.call_args_list[2].args[1]["query"]
                assert draft["response"] in invoke.call_args_list[2].args[1]["query"]
        else:
            with pytest.raises(ValueError):
                flow.workflow(args, pack, None)
        if outcome == "writable-agent":
            invoke.assert_not_called()
        assert invoke.call_count <= 4
    manifest = json.loads(
        next((tmp_path / ".foundry" / "results").glob("*\\workflow.json")).read_text()
    )
    assert manifest["release_accepted"] is False
    assert manifest["provenance_verified"] is False
    assert manifest["proposal_saved"] is False
    assert manifest["status"] == (
        "ready-for-human-review" if outcome in ("ready", "revise-then-ready") else "failed"
    )


@pytest.mark.parametrize("limiter", ["requests", "tokens"])
def test_model_limiters_remain_separate_and_metrics_follow_validated_model(limiter):
    xml = """<policies><inbound><base/><validate-jwt header-name="Authorization"/>
    <rate-limit-by-key calls="60" counter-key="keep-request-counter"/>
    <azure-openai-token-limit tokens-per-minute="10000" counter-key="keep-token-counter"/>
    <azure-openai-emit-token-metric><dimension name="Team" value="team"/>
    <dimension name="API" value="api"/></azure-openai-emit-token-metric>
    <set-variable name="modelDeployment" value="validated-model"/>
    <choose/><authentication-managed-identity resource="keep-auth-audience"/>
    </inbound></policies>"""
    with (
        patch.object(practice, "arm", return_value={"properties": {"value": xml}}),
        patch.object(practice, "add") as add,
    ):
        practice.copy_policy(
            {"team": "alpha"}, None, "/service", "reference", "alpha-p1-owned", limiter=limiter
        )
    properties = add.call_args.args[-1]
    policy = ET.fromstring(properties["value"])
    inbound = policy.find("inbound")
    metric = inbound.find("azure-openai-emit-token-metric")
    assert list(inbound).index(metric) > list(inbound).index(inbound.find("set-variable"))
    assert inbound.find("rate-limit-by-key").get("calls") == (
        "2" if limiter == "requests" else "30"
    )
    assert inbound.find("azure-openai-token-limit").get("tokens-per-minute") == (
        "50000" if limiter == "requests" else "256"
    )
    assert {node.get("name") for node in metric} == {"Team", "API", "Model", "Project"}
    assert inbound.find("authentication-managed-identity").get("resource") == "keep-auth-audience"
    assert inbound.find("validate-jwt").get("header-name") == "Authorization"
    assert inbound.find("rate-limit-by-key").get("counter-key") == "keep-request-counter"
    assert "/apis/alpha-p1-owned/" in add.call_args.args[2]


def test_post_adapter_rewrites_owned_path_and_does_not_guess_missing_adapter():
    xml = "<policies><inbound><set-url>https://gateway.invalid/reference/docs-api/validate</set-url></inbound></policies>"
    with (
        patch.object(practice, "arm", return_value={"properties": {"value": xml}}),
        patch.object(practice, "add") as add,
    ):
        practice.copy_policy(
            {},
            None,
            "/service",
            "reference",
            "alpha-p1-owned",
            replace_path=("/reference/docs-api", "/alpha-p1/docs-api"),
        )
        assert "/alpha-p1/docs-api/validate" in add.call_args.args[-1]["value"]
        with pytest.raises(ValueError, match="missing"):
            practice.copy_policy(
                {},
                None,
                "/service",
                "reference",
                "alpha-p1-owned",
                replace_path=("/not-present/docs-api", "/alpha-p1/docs-api"),
            )
