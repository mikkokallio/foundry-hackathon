"""Verify one human-authorized synthetic fixture save through real Foundry MCP.

Requires terminal consent to the exact write; does not establish participant UX.
No publication, arbitrary draft approval or write retry.
Use one persistent attempt ledger for the entire authorized test session.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))
import workshop.__main__ as workshop

gate = workshop.gate
FIXTURE = workshop.SCENARIO / "tests" / "fixtures" / "generated" / "product-configurator.md"
ATTEMPT_LIMIT = 100


def reserve_attempt(ledger: Path, metadata: dict[str, Any]) -> str:
    ledger.parent.mkdir(parents=True, exist_ok=True)
    lock = ledger.with_suffix(ledger.suffix + ".lock")
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        state = (json.loads(ledger.read_text(encoding="utf-8")) if ledger.exists()
                 else {"limit": ATTEMPT_LIMIT, "attempts": []})
        if state.get("limit") != ATTEMPT_LIMIT or not isinstance(state.get("attempts"), list):
            raise ValueError("Invalid persistent write-attempt ledger; refusing to reset it.")
        if len(state["attempts"]) >= ATTEMPT_LIMIT:
            raise ValueError("The authorized 100 synthetic write-attempt limit has been reached.")
        attempt = uuid.uuid4().hex
        state["attempts"].append({**metadata, "attempt_id": attempt,
                                  "reserved_at": dt.datetime.now(dt.UTC).isoformat(),
                                  "reservation_counts_as_attempt": True})
        gate.write_json(ledger, state)
        return attempt
    finally:
        os.close(descriptor)
        lock.unlink()


def tool_arguments(item: dict[str, Any]) -> dict[str, Any]:
    arguments = json.loads(item["arguments"])
    if isinstance(arguments, dict) and set(arguments) == {"body"}:
        arguments = arguments["body"]
    if not isinstance(arguments, dict):
        raise TypeError("Tool arguments are not a JSON object.")
    return arguments


def tool_result(item: dict[str, Any]) -> dict[str, Any]:
    if item.get("error"):
        raise ValueError("MCP tool failed; inspect private evidence without repeating the write.")
    result = json.loads(item["output"]) if isinstance(item["output"], str) else item["output"]
    if isinstance(result, dict) and "content" in result:
        if result.get("isError") or len(result["content"]) != 1 or result["content"][0].get("type") != "text":
            raise ValueError("MCP returned an error or noncanonical tool-result envelope.")
        result = json.loads(result["content"][0]["text"])
    if not isinstance(result, dict):
        raise TypeError("Expected the real backend's JSON object tool result.")
    return result


def invoke_exact(client: Any, binding: dict[str, Any], operation: str, arguments: dict[str, Any],
                 turn: dict[str, Any], evidence: Path, deadline: float, *,
                 ledger: Path, authorization: dict[str, Any], validated_at: float | None = None) -> dict[str, Any]:
    current: Any = (
        "Synthetic fixture verification; a human must authorize the exact write. "
        f"Call the docs MCP {operation} tool exactly once with the following exact JSON arguments. "
        "Do not change any value, summarize the markdown, publish, or call another write. "
        "Copy markdown character for character: preserve blank lines, bullet formatting and the final newline. "
        "JSON escapes such as \\n represent literal newline characters; do not strip or reformat the text. "
        "For submitProposal, request approval and wait; this test runner checks the exact fixture arguments. "
        "Stop after that tool result.\n" + json.dumps(arguments, ensure_ascii=False)
    )
    previous = None
    matched: list[dict[str, Any]] = []
    approved_id = None
    for _ in range(20):
        kwargs: dict[str, Any] = {
            "input": current, "max_output_tokens": 8192, "timeout": gate.remaining(deadline),
            "extra_body": {"agent_reference": {
                "type": "agent_reference", "name": binding["agent_name"], "version": binding["agent_version"]}},
        }
        if previous:
            kwargs["previous_response_id"] = previous
        # A continuation can execute the approved write: never use the read-only retry helper here.
        response = client.responses.create(**kwargs)
        payload = response.model_dump(mode="json")
        turn["responses"].append(payload)
        identifier = payload.get("id")
        if (not isinstance(identifier, str) or not re.fullmatch(r"resp_[A-Za-z0-9_-]+", identifier)
                or identifier in turn["response_ids"]):
            raise ValueError("Missing or repeated genuine Foundry response identity.")
        previous = identifier
        turn["response_ids"].append(identifier)
        gate.write_json(evidence, turn)
        if payload.get("status") != "completed" or payload.get("error"):
            raise ValueError("Foundry response failed/incomplete; inspect evidence, do not repeat the write.")
        approvals = []
        requests = [item for item in payload.get("output", [])
                    if item.get("type") == "mcp_approval_request" and item.get("name") == "submitProposal"]
        if len(requests) > 1:
            raise ValueError("Multiple proposed writes are not the one authorized fixture operation.")
        for item in payload.get("output", []):
            kind = item.get("type")
            if kind == "mcp_approval_request":
                name = item["name"]
                if name == "submitProposal":
                    if (operation != name or item.get("server_label") != "docs"
                            or tool_arguments(item) != arguments or approved_id is not None
                            or turn.get("write_attempt_id") is not None or validated_at is None
                            or time.monotonic() - validated_at > 300):
                        raise ValueError("Write request differs from the exact unexpired validated fixture authorization.")
                    if not sys.stdin.isatty():
                        raise ValueError("Exact write consent requires an interactive human terminal.")
                    consent = {"team": authorization.get("team"),
                               "project_endpoint": authorization.get("project_endpoint"),
                               "agent_name": binding["agent_name"], "agent_version": binding["agent_version"],
                               "operation": name, "arguments": arguments}
                    challenge = hashlib.sha256(json.dumps(consent, sort_keys=True).encode()).hexdigest()
                    print(json.dumps(consent, indent=2, ensure_ascii=True), flush=True)
                    if input(f"To approve only this exact write, type approve {challenge}: ") != f"approve {challenge}":
                        raise ValueError("Exact human write consent was not given.")
                    gate.remaining(deadline)
                    if time.monotonic() - validated_at > 300:
                        raise ValueError("Fixture validation expired while waiting for human consent.")
                    turn["human_consent_verified"] = True
                    turn["consent_sha256"] = challenge
                    turn["write_attempt_id"] = reserve_attempt(ledger, authorization)
                    approved_id = item["id"]
                    approve = True
                elif (name == operation and name in gate.READ_TOOLS
                      and item.get("server_label") == "docs" and tool_arguments(item) == arguments):
                    approve = True
                else:
                    raise ValueError("Unexpected tool approval; no unknown tool or publication is authorized.")
                approvals.append({"type": "mcp_approval_response", "approval_request_id": item["id"], "approve": approve})
                turn["approvals"].append({**item, "approved": approve})
            elif kind == "mcp_call":
                turn["tool_calls"].append({**item, "response_id": identifier})
                if item.get("server_label") != "docs" or item.get("name") != operation:
                    raise ValueError("Unexpected tool execution; publication and non-docs tools are prohibited.")
                if item["name"] == "submitProposal" and (operation != "submitProposal" or approved_id is None):
                    raise ValueError("Observed a write without this runner's exact fixture approval.")
                if item["name"] == operation:
                    if tool_arguments(item) != arguments:
                        raise ValueError("Executed tool arguments differ from the authorized exact arguments.")
                    matched.append(tool_result(item))
            elif kind in ("function_call", "computer_call", "shell_call", "custom_tool_call"):
                raise ValueError("No local execution or unsupported tool is permitted.")
        gate.write_json(evidence, turn)
        if approvals:
            current = approvals
            continue
        if len(matched) != 1:
            raise ValueError("Expected exactly one successful real MCP call for the requested operation.")
        return matched[0]
    raise ValueError("Bounded approval continuation exhausted; do not repeat an uncertain write.")


def verify(pack: dict[str, Any], binding: dict[str, Any], identity: Any, directory: Path,
           ledger: Path, timeout_seconds: int) -> dict[str, Any]:
    from azure.ai.projects import AIProjectClient
    from azure.monitor.query import LogsQueryClient

    directory = workshop.output_path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    markdown = FIXTURE.read_text(encoding="utf-8")
    fixture_sha = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
    flow = uuid.uuid4().hex
    payload = {
        "system_id": "SYS-011", "doc_id": "ARCH-CFG", "markdown": markdown,
        "summary": f"Synthetic fixture verification {flow}; exact human approval, no publication.",
        "author_type": "coding-agent", "source": f"authorized-synthetic-fixture/{flow}",
    }
    turn: dict[str, Any] = {
        "status": "incomplete", "started_at": dt.datetime.now(dt.UTC).isoformat(),
        "response_ids": [], "responses": [], "tool_calls": [], "approvals": [],
        "fixture_sha256": fixture_sha, "payload_sha256": hashlib.sha256(json.dumps(
            payload, sort_keys=True).encode()).hexdigest(),
        "human_consent_verified": False, "publication_performed": False,
    }
    evidence = directory / "save-verification.json"
    gate.write_json(evidence, turn)
    deadline = time.monotonic() + timeout_seconds
    try:
        with AIProjectClient(endpoint=pack["project_endpoint"], credential=identity, retry_total=0,
                             connection_timeout=30, read_timeout=120) as project, project.get_openai_client(
                                 timeout=120, max_retries=0) as client:
            actual = project.agents.get_version(agent_name=binding["agent_name"],
                                                agent_version=binding["agent_version"]).as_dict()
            gate.validate_agent(actual, binding["agent_name"], binding["agent_version"])
            if actual["definition"] != binding["definition"]["definition"]:
                raise ValueError("Actual immutable agent differs from the reviewed binding.")
            authorization = {"team": pack["team"], "project_endpoint": pack["project_endpoint"],
                             "agent_name": binding["agent_name"], "agent_version": binding["agent_version"],
                             "flow_id": flow, "fixture_sha256": fixture_sha, "payload_sha256": turn["payload_sha256"],
                             "evidence": str(evidence)}
            validation = invoke_exact(client, binding, "validateDocument", {"markdown": markdown}, turn,
                                      evidence, deadline, ledger=ledger, authorization=authorization)
            if validation.get("valid") is not True:
                raise ValueError("The real backend rejected the exact fixture; no write approved.")
            validated_at = time.monotonic()
            turn["validation"] = validation
            saved = invoke_exact(client, binding, "submitProposal", payload, turn, evidence, deadline,
                                 ledger=ledger, authorization=authorization, validated_at=validated_at)
            turn["saved"] = saved
            if saved.get("status") != "pending-review" or saved.get("team") != pack["team"]:
                raise ValueError("Saved proposal status/team does not match the authorized fixture operation.")
            proposal_id = saved["proposal_id"]
            readback = invoke_exact(client, binding, "getProposal", {"proposal_id": proposal_id}, turn,
                                    evidence, deadline, ledger=ledger, authorization=authorization)
            if (readback.get("team") != pack["team"] or readback.get("status") != "pending-review"
                    or readback.get("proposal_id") != proposal_id
                    or any(readback.get(key) != value for key, value in payload.items())):
                raise ValueError("Real proposal readback differs from the exact fixture/metadata; no repeat write.")
            turn["readback"] = readback
            turn["exact_readback_verified"] = True
            if hashlib.sha256(FIXTURE.read_bytes()).hexdigest() != fixture_sha:
                raise ValueError("Fixture changed during the authorization window.")
            turn["status"] = "completed"
            workspace = workshop.arm(pack, identity, pack["workspace_resource_id"], "2022-10-01")
            trace_args = argparse.Namespace(
                app_insights_resource_id=pack["application_insights_resource_id"],
                workspace_id=workspace["properties"]["customerId"], started_at=turn["started_at"],
                agent_name=binding["agent_name"], agent_version=binding["agent_version"],
                trace_timeout_seconds=min(300, timeout_seconds),
                declared_mcp_servers={tool["server_label"]: tool["server_url"]
                                      for tool in actual["definition"]["tools"] if tool.get("type") == "mcp"},
            )
            with LogsQueryClient(identity) as logs:
                turn["provenance"] = gate.verify_trace(
                    logs, trace_args, turn,
                    {"id": flow, "expected_tools": ["validateDocument", "submitProposal", "getProposal"]},
                    directory / "native-trace.json", deadline)
    except Exception as exc:  # noqa: BLE001 - Redact untrusted SDK errors at this evidence boundary.
        turn["status"] = "failed"
        turn["error"] = f"{type(exc).__name__}: verification failed; inspect private evidence without repeating the write."
        turn["uncertain_write_requires_read_only_reconciliation"] = (
            "write_attempt_id" in turn and "saved" not in turn)
        print(turn["error"], file=sys.stderr, flush=True)
        raise ValueError(turn["error"]) from None
    finally:
        turn["finished_at"] = dt.datetime.now(dt.UTC).isoformat()
        gate.write_json(evidence, turn)
    return turn


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--binding", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=1200)
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 3600:
        raise ValueError("Use a bounded save-verification timeout of 1..3600 seconds.")
    pack = workshop.load_pack(args.pack)
    binding = workshop.binding_for(args.binding, pack)
    from cli_credential import CachedAzureCliCredential

    with CachedAzureCliCredential(tenant_id=pack["tenant_id"], process_timeout=30) as identity:
        result = verify(pack, binding, identity, args.output, args.ledger.resolve(), args.timeout_seconds)
    print(json.dumps({"status": result["status"], "proposal_id": result["saved"]["proposal_id"],
                      "exact_readback_verified": result["exact_readback_verified"],
                      "human_consent_verified": result["human_consent_verified"], "publication_performed": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
