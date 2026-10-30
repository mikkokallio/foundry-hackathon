"""Bounded real Foundry smoke/regression collection, evaluation and provenance.

No offline mode or write approval exists. CLI configuration is explicit; run --help.
Native server spans, not runner-created telemetry, establish execution provenance.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import re
import subprocess
import sys
import time
import uuid
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import yaml

READ_TOOLS = {
    "getDocumentationStandard", "listDocuments", "getDocument", "listSystems",
    "getSystem", "listInterfaces", "listDataProducts", "findDocumentationGaps",
    "validateDocument", "listProposals", "getProposal",
    "generate_context_diagram", "lint_document", "compare_with_inventory",
}
WRITE_TOOLS = {"submitProposal", "publishProposal"}
TERMINAL = {"completed", "failed", "cancelled", "canceled", "incomplete", "expired"}
RESPONSE_CREATE_MAX_ATTEMPTS = 6
RESPONSE_CREATE_MAX_ELAPSED_SECONDS = 300
EVIDENCE_REPLACE_DELAYS = (0.05, 0.1, 0.2, 0.4, 0.8, 1.0)


class GateError(RuntimeError):
    pass


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_suffix(path.suffix + ".pending")
    staging.write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")
    for attempt in range(len(EVIDENCE_REPLACE_DELAYS) + 1):
        try:
            staging.replace(path)
            return
        except PermissionError as exc:
            if getattr(exc, "winerror", None) not in (5, 32, 33) or attempt == len(EVIDENCE_REPLACE_DELAYS):
                raise
            print(f"Retrying atomic evidence replacement after Windows file access error: {path}",
                  file=sys.stderr, flush=True)
            time.sleep(EVIDENCE_REPLACE_DELAYS[attempt])


def remaining(deadline: float, maximum: float = 120) -> float:
    value = min(maximum, deadline - time.monotonic())
    if value <= 0:
        raise GateError("Overall run deadline exceeded.")
    return value


def load_inputs(root: Path) -> tuple[dict, dict, list[dict], dict]:
    folder = root / "exercises" / "evaluation"
    plan = json.loads((folder / "plan.json").read_text(encoding="utf-8"))
    gate = yaml.safe_load((folder / "gate.yaml").read_text(encoding="utf-8"))
    cases = [json.loads(line) for line in (folder / "eval_set.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    ids = [row["id"] for row in cases]
    if len(cases) != 25 or len(set(ids)) != 25 or ids != plan["regression_case_ids"]:
        raise GateError("Frozen regression must contain all 25 unique cases in plan order.")
    if plan["smoke_case_ids"] != ["qa-01", "gap-01", "draft-01", "gr-01"]:
        raise GateError("Frozen smoke coverage differs.")
    if any(not isinstance(row.get("query"), str) or not row["query"].strip() for row in cases):
        raise GateError("Case query missing.")
    if gate != {"on_missing": "fail", "checks": {
        "task_adherence": {"min_mean": 3.0}, "template_compliance": {"min_mean": 0.5},
    }}:
        raise GateError("Unreviewed gate definition; thresholds were not changed.")
    hashes = {name: hashlib.sha256((folder / name).read_bytes()).hexdigest()
              for name in ("plan.json", "gate.yaml", "eval_set.jsonl")}
    return plan, gate, cases, hashes


class Evidence:
    def __init__(self, root: Path, destination: Path, environment: str, context: dict):
        self.root, self.destination, self.environment = root, destination, environment
        self.overlay = root / ".foundry" / "agent-metadata.rehearsal.yaml"
        self.manifest = {
            "startedAt": dt.datetime.now(dt.UTC).isoformat(),
            "status": "incomplete", "context": context, "suites": [],
            "failure_clusters": {}, "release_accepted": False,
        }
        self.save()

    def save(self) -> None:
        write_json(self.destination / "manifest.json", self.manifest)
        metadata = yaml.safe_load(self.overlay.read_text(encoding="utf-8")) if self.overlay.exists() else {}
        metadata = metadata or {}
        env = metadata.setdefault("environments", {}).setdefault(self.environment, {})
        env["lastEval"] = {
            "agentVersion": self.manifest["context"]["agent_version"],
            "startedAt": self.manifest["startedAt"],
            "resultFile": str(self.destination / "manifest.json"),
            "status": self.manifest["status"],
            "suites": [{
                key: suite.get(key)
                for key in ("tier", "evaluation_id", "evaluation_run_id", "status")
            } for suite in self.manifest["suites"]],
        }
        if self.manifest["suites"]:
            current = self.manifest["suites"][-1]
            env["lastEval"].update({
                "evalId": current.get("evaluation_id"),
                "evalRunId": current.get("evaluation_run_id"),
                "suiteName": current["tier"],
            })
        staging = self.overlay.with_suffix(".yaml.pending")
        staging.write_text(yaml.safe_dump(metadata, sort_keys=False), encoding="utf-8")
        staging.replace(self.overlay)


def validate_agent(agent: dict, name: str, version: str) -> None:
    if agent.get("name") != name or str(agent.get("version")) != version:
        raise GateError("Retrieved agent identity differs from explicit immutable target.")
    definition = agent.get("definition", {})
    if definition.get("kind") != "prompt":
        raise GateError("This runner requires a native PromptAgentDefinition.")
    if agent.get("status", "active") != "active":
        raise GateError("Agent version is not active.")
    tools = definition.get("tools") or []
    mcp = [tool for tool in tools if tool.get("type") == "mcp"]
    if not mcp:
        raise GateError("Native agent has no MCP tools.")
    for tool in tools:
        if tool.get("type") != "mcp":
            raise GateError("Unreviewed non-MCP tool; automated runner refuses unsafe execution.")
        if not tool.get("project_connection_id"):
            raise GateError("MCP project connection is missing.")
        approval = tool.get("require_approval")
        allowed = tool.get("allowed_tools")
        allowed = allowed.get("tool_names") if isinstance(allowed, dict) else allowed
        if not isinstance(allowed, list) or not set(allowed) <= READ_TOOLS | WRITE_TOOLS:
            raise GateError("MCP allowlist is missing or contains an unreviewed tool.")
        if approval == "always":
            continue
        if not isinstance(approval, dict):
            raise GateError("MCP approval policy can bypass human write approval.")
        always = approval.get("always", {}).get("tool_names", [])
        never = approval.get("never", {}).get("tool_names", [])
        if not WRITE_TOOLS.isdisjoint(never):
            raise GateError("Write tool is configured for automatic approval.")
        if not (set(allowed) & WRITE_TOOLS) <= set(always):
            raise GateError("Every writable MCP tool must require approval.")


def rate_limit_delay(error: Any, attempt: int) -> tuple[float, str] | None:
    """Retry only HTTP 429 or an explicit Foundry-wrapped model-gateway 429."""
    message = str(error)
    if error.status_code != 429 and not (
        re.search(r"Received 429 status code from model\b", message, re.IGNORECASE)
        or re.search(r"ModelGateway response:.*['\"]statusCode['\"]\s*:\s*429\b", message, re.IGNORECASE)
    ):
        return None
    header = error.response.headers.get("Retry-After")
    if header is not None:
        try:
            delay = float(header)
        except ValueError:
            try:
                date = parsedate_to_datetime(header)
                if date.tzinfo is None:
                    date = date.replace(tzinfo=dt.UTC)
                delay = max(0.0, (date - dt.datetime.now(dt.UTC)).total_seconds())
            except (TypeError, ValueError, OverflowError):
                delay = float("nan")
        if math.isfinite(delay) and delay >= 0:
            return delay, "Retry-After"
    wrapped = re.search(r"\bTry again in ([0-9]+(?:\.[0-9]+)?) seconds?\b", message, re.IGNORECASE)
    if wrapped:
        delay = float(wrapped[1])
        if math.isfinite(delay):
            return delay, "wrapped-model-gateway-message"
    return min(60.0, 2.0 ** (attempt - 1)), "bounded-exponential-backoff"


def create_response(client: Any, kwargs: dict, turn: dict, path: Path, deadline: float) -> Any:
    from openai import APIStatusError

    started = time.monotonic()
    stop = min(deadline, started + RESPONSE_CREATE_MAX_ELAPSED_SECONDS)
    for attempt in range(1, RESPONSE_CREATE_MAX_ATTEMPTS + 1):
        request = {**kwargs, "timeout": remaining(stop)}
        try:
            response = client.responses.create(**request)
            if time.monotonic() >= stop:
                turn.setdefault("late_response_create_results", []).append(response.model_dump(mode="json"))
                write_json(path, turn)
                raise GateError("Foundry response-create elapsed budget expired before completion.")
            return response
        except APIStatusError as exc:
            retry = rate_limit_delay(exc, attempt)
            if retry is None:
                raise
            delay, source = retry
            available = stop - time.monotonic()
            exhausted = attempt == RESPONSE_CREATE_MAX_ATTEMPTS or delay >= available
            diagnostic = {
                "response_create_index": len(turn["response_ids"]) + 1,
                "attempt": attempt, "max_attempts": RESPONSE_CREATE_MAX_ATTEMPTS,
                "max_elapsed_seconds": RESPONSE_CREATE_MAX_ELAPSED_SECONDS,
                "elapsed_seconds": time.monotonic() - started,
                "http_status": exc.status_code, "error_type": type(exc).__name__,
                "request_id": exc.response.headers.get("x-request-id")
                or exc.response.headers.get("x-ms-request-id"),
                "error": str(exc), "previous_response_id": kwargs.get("previous_response_id"),
                "retry_after_seconds": delay, "delay_source": source,
                "decision": "exhausted" if exhausted else "retry",
            }
            turn.setdefault("response_create_retries", []).append(diagnostic)
            write_json(path, turn)
            if exhausted:
                raise GateError("Foundry response-create 429 retry attempt/elapsed budget exhausted.") from exc
            time.sleep(delay)
    raise GateError("Foundry response-create retry bound exceeded.")


def invoke(client: Any, case: dict, name: str, version: str, path: Path, deadline: float) -> dict:
    started = time.monotonic()
    turn: dict = {"id": case["id"], "query": case["query"], "response_ids": [],
                  "responses": [], "tool_calls": [], "approvals": [], "status": "incomplete"}
    current: Any = case["query"]
    previous = None
    try:
        for _ in range(20):
            kwargs = {"input": current, "max_output_tokens": 8192,
                      "extra_body": {"agent_reference": {
                          "type": "agent_reference", "name": name, "version": version}},
                      "timeout": remaining(deadline)}
            if previous:
                kwargs["previous_response_id"] = previous
            response = create_response(client, kwargs, turn, path, deadline)
            payload = response.model_dump(mode="json")
            turn["responses"].append(payload)
            response_id = payload.get("id")
            if not isinstance(response_id, str) or not re.fullmatch(r"resp_[A-Za-z0-9_-]+", response_id) or response_id in turn["response_ids"]:
                raise GateError("Missing, repeated or invalid genuine Foundry response ID.")
            previous = response_id
            turn["response_ids"].append(response_id)
            write_json(path, turn)
            if payload.get("status") != "completed" or payload.get("error"):
                raise GateError(f"Foundry response failed or incomplete: {response_id}")
            approvals = []
            for item in payload.get("output", []):
                kind = item.get("type")
                if kind == "mcp_call":
                    turn["tool_calls"].append({**item, "response_id": response_id})
                    if item.get("name") not in READ_TOOLS or item.get("error"):
                        raise GateError("Unexpected write/unknown/failed tool execution.")
                elif kind == "mcp_approval_request":
                    approved = item.get("name") in READ_TOOLS
                    turn["approvals"].append({**item, "approved": approved})
                    approvals.append({"type": "mcp_approval_response",
                                      "approval_request_id": item["id"], "approve": approved})
                elif kind in ("function_call", "computer_call", "shell_call", "custom_tool_call"):
                    raise GateError("Unsupported tool call; no local execution is permitted.")
            write_json(path, turn)
            if approvals:
                current = approvals
                continue
            turn["response"] = response.output_text
            if not turn["response"].strip():
                raise GateError("Foundry response has no final answer.")
            turn["status"] = "completed"
            turn["latency_seconds"] = time.monotonic() - started
            return turn
        raise GateError("Approval continuation exceeded 20 turns.")
    except Exception as exc:
        turn["status"], turn["error"] = "failed", str(exc)
        raise
    finally:
        write_json(path, turn)


def dimensions(record: dict) -> dict:
    value = record.get("customDimensions")
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, dict):
        raise GateError("Malformed App Insights span dimensions.")
    return value


def span_success(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.strip().casefold() in ("true", "false"):
        return value.strip().casefold() == "true"
    raise GateError("App Insights span has missing or unrecognized success status.")


def native_identity(d: dict, name: str, version: str) -> bool:
    return (
        (d.get("gen_ai.agent.name") == name and str(d.get("gen_ai.agent.version")) == version)
        or d.get("gen_ai.agent.id") == f"{name}:{version}"
    )


def transport_cancellations(
    records: list[dict], exceptions: list[dict], turn: dict, mcp_servers: dict[str, str],
) -> list[dict]:
    """Classify only observed GET-200 client disconnects and proven forwarding children."""
    if turn.get("status") != "completed":
        return []
    declared_urls = {
        mcp_servers[call["server_label"]] for call in turn["tool_calls"]
        if call.get("server_label") in mcp_servers
    }
    partial = "200 [not sent in full (see exception telemetries)]"
    message = "Client connection was unexpectedly closed."
    by_id: dict[tuple[str, str], dict] = {}
    for record in records:
        key = (record.get("operation_Id"), record.get("id"))
        if not all(isinstance(value, str) and value for value in key):
            continue
        if key in by_id:
            raise GateError("App Insights contains ambiguous duplicate span identities.")
        by_id[key] = record
    approved: dict[tuple[str, str], dict] = {}
    for key, record in by_id.items():
        d = dimensions(record)
        url = record.get("url")
        if (
            url not in declared_urls
            or record.get("name") != f"GET {urlparse(url).path}"
            or record.get("resultCode") != partial
            or not str(record.get("telemetryTable", "")).endswith(".requests")
            or span_success(record.get("success"))
            or d.get("gen_ai.operation.name") or d.get("error.type")
            or d.get("Service Type") != "API Management" or not d.get("Service ID")
        ):
            continue
        matching = [(index, exc) for index, exc in enumerate(exceptions)
                    if (exc.get("operation_Id"), exc.get("operation_ParentId")) == key]
        if not matching:
            continue
        valid = True
        for _, exc in matching:
            if (exc.get("type") != "ClientConnectionFailure" or exc.get("outerMessage") != message
                    or exc.get("innermostMessage", "") not in ("", message)):
                valid = False
                break
            details = exc.get("details")
            if details is not None:
                try:
                    details = json.loads(details) if isinstance(details, str) else details
                except (TypeError, ValueError):
                    valid = False
                    break
                if not isinstance(details, list) or not details or any(
                    not isinstance(item, dict) or item.get("type") != "ClientConnectionFailure"
                    or item.get("message") != message for item in details
                ):
                    valid = False
                    break
        if valid:
            approved[key] = {
                "classification": "mcp_http200_client_stream_cancellation",
                "operation_id": key[0], "span_id": key[1], "request_span_id": key[1],
                "server_url": url, "exception_indices": [index for index, _ in matching],
                "ancestor_span_ids": [],
            }
    while True:
        additions = {}
        for key, record in by_id.items():
            if key in approved:
                continue
            parent_key = (key[0], record.get("operation_ParentId"))
            parent = approved.get(parent_key)
            if parent is None:
                continue
            root = by_id[key[0], parent["request_span_id"]]
            d = dimensions(record)
            if (
                record.get("name") != "forward-request" or record.get("target") != "forward-request"
                or record.get("type") != "HTTP" or record.get("data") != "REQUEST -"
                or record.get("url") not in ("", None) or record.get("resultCode") != ""
                or not str(record.get("telemetryTable", "")).endswith(".dependencies")
                or span_success(record.get("success")) or d.get("error.type")
                or d.get("gen_ai.operation.name") or d.get("Source") != "forward-request"
                or d.get("Service Type") != "API Management"
                or d.get("Service ID") != dimensions(root).get("Service ID")
            ):
                continue
            additions[key] = {
                **parent, "classification": "linked_forward_request_stream_cancellation",
                "span_id": key[1],
                "ancestor_span_ids": [parent_key[1], *parent["ancestor_span_ids"]],
            }
        if not additions:
            break
        approved.update(additions)
    return list(approved.values())


def match_trace(
    records: list[dict], turn: dict, name: str, version: str, expected: list[str],
    *, exceptions: list[dict] | None = None, mcp_servers: dict[str, str] | None = None,
) -> dict | None:
    """Match native response+version roots and tool spans within the SAME trace."""
    aliases: dict[tuple[str, str], str] = {}
    for call in turn["tool_calls"]:
        response_id, tool = call.get("response_id"), call.get("name")
        if response_id not in turn["response_ids"] or not isinstance(tool, str):
            raise GateError("Genuine response tool call has missing or invalid execution identity.")
        aliases[response_id, tool] = tool
        server = call.get("server_label")
        if isinstance(server, str) and server:
            aliases[response_id, f"mcp_{server}.{tool}"] = tool
    roots: dict[str, set[str]] = {}
    for record in records:
        d = dimensions(record)
        response_id = d.get("gen_ai.response.id") or d.get("azure.ai.agentserver.response_id")
        trace = record.get("operation_Id")
        if (native_identity(d, name, version) and d.get("gen_ai.operation.name") == "invoke_agent"
                and isinstance(response_id, str) and response_id in turn["response_ids"]
                and isinstance(trace, str) and re.fullmatch(r"[0-9a-f]{32}", trace)
                and trace != "0" * 32):
            roots.setdefault(trace, set()).add(response_id)
    exceptions = exceptions or []
    relevant = [record for record in records if record.get("operation_Id") in roots]
    relevant_exceptions = [exc for exc in exceptions if exc.get("operation_Id") in roots]
    cancellations = transport_cancellations(relevant, relevant_exceptions, turn, mcp_servers or {})
    classified = {(item["operation_id"], item["span_id"]) for item in cancellations}
    classified_exceptions = {
        index for item in cancellations for index in item["exception_indices"]
    }
    if any(index not in classified_exceptions for index in range(len(relevant_exceptions))):
        raise GateError("App Insights contains an unclassified execution exception.")
    matched_ids: set[str] = set()
    matched_tools: set[str] = set()
    for trace, response_ids in roots.items():
        matched_ids.update(response_ids)
        for record in records:
            if record.get("operation_Id") != trace:
                continue
            d = dimensions(record)
            if not span_success(record.get("success")) or d.get("error.type"):
                if (trace, record.get("id")) not in classified:
                    raise GateError(
                        f"App Insights contains a failed execution span: {record.get('name')}; "
                        f"id={record.get('id')}; resultCode={record.get('resultCode')}; "
                        f"error.type={d.get('error.type')}"
                    )
            if d.get("gen_ai.operation.name") == "execute_tool":
                tool = d.get("gen_ai.tool.name")
                response_id = d.get("gen_ai.response.id") or d.get("azure.ai.agentserver.response_id")
                if (native_identity(d, name, version) and isinstance(tool, str)
                        and isinstance(response_id, str) and response_id in response_ids):
                    genuine_name = aliases.get((response_id, tool))
                    if genuine_name is None:
                        return None
                    matched_tools.add(genuine_name)
    # Expected-tool omissions remain quality failures in run_worker, not missing telemetry.
    required = {call["name"] for call in turn["tool_calls"]}
    if set(turn["response_ids"]) <= matched_ids and required <= matched_tools:
        return {"verified": True, "operation_ids": sorted(roots),
                "response_ids": turn["response_ids"], "tool_names": sorted(matched_tools),
                "expected_tool_names": expected,
                "missing_expected_tool_names": sorted(set(expected) - matched_tools),
                "transport_cancellations": cancellations}
    return None


def verify_trace(logs: Any, args: argparse.Namespace, turn: dict, case: dict, path: Path, deadline: float) -> dict:
    from azure.monitor.query import LogsQueryStatus

    ids = json.dumps(turn["response_ids"])
    resource = json.dumps(args.app_insights_resource_id)
    query = f"""let spans = materialize(union withsource=telemetryTable app({resource}).requests, app({resource}).dependencies
| where timestamp >= datetime({args.started_at})
| where _ResourceId =~ {resource}
| project timestamp, name, operation_Id, operation_ParentId, id, success, customDimensions, telemetryTable, _ResourceId,
    evidence_kind="span",
    resultCode=column_ifexists("resultCode", ""), type=column_ifexists("type", ""),
    target=column_ifexists("target", ""), data=column_ifexists("data", ""), url=column_ifexists("url", ""));
let operations = spans
| where tostring(customDimensions["gen_ai.response.id"]) in (dynamic({ids}))
    or tostring(customDimensions["azure.ai.agentserver.response_id"]) in (dynamic({ids}))
| distinct operation_Id;
union (spans | where operation_Id in (operations)),
    (app({resource}).exceptions
    | where timestamp >= datetime({args.started_at})
    | where _ResourceId =~ {resource}
    | where operation_Id in (operations)
    | project timestamp, operation_Id, operation_ParentId, type, outerMessage, innermostMessage,
        details, customDimensions, _ResourceId, evidence_kind="exception")"""
    write_json(path, {"verified": False, "query": query, "records": [], "exceptions": []})
    stop = min(deadline, time.monotonic() + args.trace_timeout_seconds)
    while True:
        budget = remaining(stop, 60)
        print(f"Application Insights KQL ({case['id']}, workspace={args.workspace_id}):\n```kql\n{query}\n```", flush=True)
        result = logs.query_workspace(
            args.workspace_id, query, timespan=dt.timedelta(hours=24),
            server_timeout=max(1, math.ceil(budget)), retry_total=0,
            connection_timeout=budget, read_timeout=budget,
        )
        if result.status != LogsQueryStatus.SUCCESS:
            write_json(path, {"verified": False, "query": query, "error": str(result)})
            raise GateError("App Insights query failed or returned partial results.")
        rows = [dict(zip(table.columns, row, strict=True))
                for table in result.tables for row in table.rows]
        records = [row for row in rows if row.get("evidence_kind") == "span"]
        exceptions = [row for row in rows if row.get("evidence_kind") == "exception"]
        if len(records) + len(exceptions) != len(rows):
            raise GateError("App Insights returned unknown evidence row types.")
        servers = getattr(args, "declared_mcp_servers", {})
        cancellations = transport_cancellations(records, exceptions, turn, servers)
        write_json(path, {"verified": False, "query": query, "records": records,
                          "exceptions": exceptions, "transport_cancellations": cancellations})
        proof = match_trace(records, turn, args.agent_name, args.agent_version, case["expected_tools"],
                            exceptions=exceptions, mcp_servers=servers)
        if proof:
            remaining(stop)
            write_json(path, {**proof, "query": query, "records": records, "exceptions": exceptions})
            return proof
        time.sleep(min(5, remaining(stop)))


def task_scores(outputs: list[dict], rows: list[dict]) -> list[float]:
    by_response = {row["resp_id"]: row for row in rows}
    if len(outputs) != len(rows) or len(by_response) != len(rows):
        raise GateError("Incomplete or duplicated remote evaluation coverage.")
    seen = set()
    scores = []
    for output in outputs:
        source = output.get("datasource_item") or {}
        response_id = source.get("response_id") or source.get("resp_id")
        row = by_response.get(response_id)
        if row is None or response_id in seen or source.get("query") != row["query"]:
            raise GateError("Remote response identity/query differs from fresh collection.")
        if source.get("id", row["id"]) != row["id"]:
            raise GateError("Remote evaluation case identity differs.")
        seen.add(response_id)
        metrics = [item for item in output.get("results", [])
                   if (item.get("metric") or item.get("name")) == "task_adherence"]
        if len(metrics) != 1:
            raise GateError("Missing or repeated task_adherence result.")
        score = metrics[0].get("score")
        if (isinstance(score, bool) or not isinstance(score, (float, int))
                or not math.isfinite(score) or not 1 <= score <= 5
                or metrics[0].get("status", "completed") != "completed"
                or output.get("status", "completed") != "completed"):
            raise GateError("Invalid/non-numeric/incomplete inherited task_adherence score.")
        scores.append(float(score))
    return scores


def usage_totals(responses: list[dict]) -> dict[str, int | None]:
    result: dict[str, int | None] = {}
    for metric in ("input_tokens", "output_tokens", "reasoning_tokens"):
        values = []
        for response in responses:
            usage = response.get("usage") or {}
            value = ((usage.get("output_tokens_details") or {}).get("reasoning_tokens")
                     if metric == "reasoning_tokens" else usage.get(metric))
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                result[metric] = None
                break
            values.append(value)
        else:
            result[metric] = sum(values) if values else None
    return result


def remote_clusters(outputs: list[dict]) -> dict[str, list[dict]]:
    clusters: dict[str, list[dict]] = {}
    for output in outputs:
        for result in output.get("results", []):
            issue = ("failed" if result.get("passed") is False
                     else "unresolved" if result.get("passed") is None or result.get("reason") is None
                     else None)
            if issue:
                clusters.setdefault(f"remote_{issue}", []).append({
                    "datasource_item": output.get("datasource_item"),
                    "metric": result.get("metric") or result.get("name"),
                    "result": result,
                })
    return clusters


def evaluate(client: Any, args: argparse.Namespace, rows: list[dict], suite: dict, evidence: Evidence, deadline: float) -> list[dict]:
    from azure.ai.projects.models import (
        AzureAIDataSourceConfig, AzureAIResponsesEvalRunDataSource,
        ResponseRetrievalItemGenerationParams, TestingCriterionAzureAIEvaluator,
    )
    from openai.types.eval_create_response import EvalCreateResponse
    from openai.types.evals.run_create_response import RunCreateResponse

    criterion = TestingCriterionAzureAIEvaluator(
        type="azure_ai_evaluator", name="task_adherence",
        evaluator_name="builtin.task_adherence", evaluator_version="2",
        initialization_parameters={"model": args.judge_deployment},
        data_mapping={"query": "{{item.query}}", "response": "{{sample.output_items}}"},
    )
    body = {
        "name": f"{args.agent_name}-{suite['tier']}-{evidence.destination.name}",
        "data_source_config": AzureAIDataSourceConfig(type="azure_ai_source", scenario="responses"),
        "testing_criteria": [criterion],
    }
    write_json(evidence.destination / suite["tier"] / "evaluation-request.json", body)
    evaluation = client.post("/evals", cast_to=EvalCreateResponse, body=body,
                             options={"timeout": remaining(deadline)})
    suite["evaluation_id"] = evaluation.id
    evidence.save()
    source = AzureAIResponsesEvalRunDataSource(
        type="azure_ai_responses",
        item_generation_params=ResponseRetrievalItemGenerationParams(
            type="response_retrieval", data_mapping={"response_id": "{{item.resp_id}}"},
            source={"type": "file_content", "content": [{"item": row} for row in rows]},
        ),
    )
    run = client.post(f"/evals/{evaluation.id}/runs", cast_to=RunCreateResponse,
                      body={"name": f"{suite['tier']}-version-{args.agent_version}", "data_source": source},
                      options={"timeout": remaining(deadline)})
    suite["evaluation_run_id"], suite["status"] = run.id, "running-foundry-evaluators"
    evidence.save()
    stop = min(deadline, time.monotonic() + args.eval_timeout_seconds)
    while True:
        status = client.evals.runs.retrieve(run.id, eval_id=evaluation.id, timeout=remaining(stop))
        write_json(evidence.destination / suite["tier"] / "remote-run.json", status.model_dump(mode="json"))
        if status.status in TERMINAL:
            break
        time.sleep(min(10, remaining(stop)))
    outputs = []
    page = client.evals.runs.output_items.list(run.id, eval_id=evaluation.id, timeout=remaining(stop))
    while True:
        outputs.extend(item.model_dump(mode="json") for item in page.data)
        write_json(evidence.destination / suite["tier"] / "remote-output-items.json", outputs)
        if not page.has_next_page():
            break
        remaining(stop)
        page = page.get_next_page()
    remaining(stop)
    if status.status != "completed":
        raise GateError(f"Foundry evaluation ended with {status.status}.")
    return outputs


def run_worker(args: argparse.Namespace, evidence: Evidence) -> int:
    from azure.ai.projects import AIProjectClient
    from azure.identity import AzureCliCredential
    from azure.monitor.query import LogsQueryClient

    root = args.scenario_root.resolve()
    sys.path.insert(0, str(root / "backend" / "src"))
    from frozen_template import TemplateComplianceEvaluator

    deadline = time.monotonic() + args.timeout_seconds
    plan, gate, cases, hashes = load_inputs(root)
    evidence.manifest["input_sha256"] = hashes
    evidence.save()
    with AzureCliCredential(process_timeout=30) as credential, AIProjectClient(
        endpoint=args.project_endpoint, credential=credential, retry_total=0,
        connection_timeout=30, read_timeout=120,
    ) as project, project.get_openai_client(timeout=120, max_retries=0) as client, LogsQueryClient(credential) as logs:
        agent = project.agents.get_version(agent_name=args.agent_name, agent_version=args.agent_version)
        definition = agent.as_dict()
        write_json(evidence.destination / "agent-version.json", definition)
        validate_agent(definition, args.agent_name, args.agent_version)
        args.declared_mcp_servers = {
            tool["server_label"]: tool["server_url"] for tool in definition["definition"]["tools"]
            if tool.get("type") == "mcp" and tool.get("server_url")
        }
        evaluator = project.evaluators.get_version(name="builtin.task_adherence", version="2")
        contract = evaluator.as_dict()
        write_json(evidence.destination / "evaluator-contract.json", contract)
        metric = contract.get("definition", {}).get("metrics", {}).get("task_adherence", {})
        if (str(contract.get("version")) != "2" or metric.get("type") not in ("number", "integer", "ordinal")
                or metric.get("max_value", 5) < 3):
            raise GateError("Remote builtin.task_adherence v2 lacks the inherited numeric 1..5 contract.")
        tiers = ("comparison",) if getattr(args, "comparison", False) else ("smoke", "regression")
        for tier in tiers:
            selected = [case for case in cases if case["id"] in plan[f"{tier}_case_ids"]]
            suite: dict = {"tier": tier, "status": "incomplete", "expected_ids": [c["id"] for c in selected],
                           "rows": [], "failure_clusters": {}}
            evidence.manifest["suites"].append(suite)
            evidence.save()
            turns = []
            templates = []
            for case in selected:
                remaining(deadline)
                turn = invoke(client, case, args.agent_name, args.agent_version,
                              evidence.destination / tier / f"{case['id']}.json", deadline)
                turns.append((case, turn))
                names = {call["name"] for call in turn["tool_calls"]}
                missing = sorted(set(case["expected_tools"]) - names)
                forbidden = sorted(set(case["forbidden_tools"]) & names)
                for cluster, values in (
                    ("missing_tools", missing), ("forbidden_tools", forbidden),
                    ("missing_facts", [f for f in case["expected_facts"] if f.casefold() not in turn["response"].casefold()]),
                    ("forbidden_facts", [f for f in case["forbidden_facts"] if f.casefold() in turn["response"].casefold()]),
                ):
                    if values:
                        suite["failure_clusters"].setdefault(cluster, []).append({"case_id": case["id"], "values": values})
                template = TemplateComplianceEvaluator()(
                    response=turn["response"], tool_calls=turn["tool_calls"], category=case["category"])
                write_json(evidence.destination / tier / f"{case['id']}-template.json", template)
                value = template["template_compliance"]
                if case["category"] == "draft":
                    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                        raise GateError("Missing/invalid draft template compliance score.")
                    templates.append(value)
                suite["rows"].append({
                    "id": case["id"], "query": case["query"],
                    "resp_id": turn["response_ids"][-1], "response_ids": turn["response_ids"],
                    "latency_seconds": turn.get("latency_seconds"),
                    **usage_totals(turn["responses"]),
                })
                evidence.save()
            outputs = evaluate(client, args, suite["rows"], suite, evidence, deadline)
            suite["failure_clusters"].update(remote_clusters(outputs))
            evidence.save()
            scores = task_scores(outputs, suite["rows"])
            provenance_failures = []
            for case, turn in turns:
                try:
                    proof = verify_trace(logs, args, turn, case,
                                         evidence.destination / tier / f"{case['id']}-trace.json", deadline)
                    next(row for row in suite["rows"] if row["id"] == case["id"])["provenance"] = proof
                except Exception as exc:
                    provenance_failures.append({"case_id": case["id"], "error": str(exc)})
                evidence.save()
            if provenance_failures:
                suite["failure_clusters"]["provenance"] = provenance_failures
            actual = {"task_adherence": sum(scores) / len(scores),
                      "template_compliance": sum(templates) / len(templates)}
            suite["checks"] = [{"metric": name, "actual": actual[name], "minimum": check["min_mean"]}
                               for name, check in gate["checks"].items()]
            failed = [check["metric"] for check in suite["checks"] if check["actual"] < check["minimum"]]
            suite["failure_clusters"]["thresholds"] = failed
            suite["status"] = "failed" if any(suite["failure_clusters"].values()) else "completed"
            evidence.save()
            if suite["status"] != "completed":
                raise GateError(f"{tier} failed; evidence retained. Regression is not accepted/skipped-as-pass.")
    if load_inputs(root)[3] != hashes:
        raise GateError("Frozen input files changed during execution.")
    evidence.manifest["status"] = "completed"
    evidence.save()
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    for name in ("project-endpoint", "agent-name", "agent-version", "judge-deployment",
                 "app-insights-resource-id", "workspace-id", "environment"):
        result.add_argument(f"--{name}", required=True)
    result.add_argument("--scenario-root", type=Path, required=True)
    result.add_argument("--timeout-seconds", type=int, default=5400)
    result.add_argument("--eval-timeout-seconds", type=int, default=1200)
    result.add_argument("--trace-timeout-seconds", type=int, default=300)
    result.add_argument("--comparison", action="store_true",
                        help="Fresh twelve-case educational comparison only; never full release qualification.")
    result.add_argument("--worker-results", type=Path, help=argparse.SUPPRESS)
    result.add_argument("--started-at", help=argparse.SUPPRESS)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    parsed = urlparse(args.project_endpoint)
    if parsed.scheme != "https" or not parsed.hostname or not parsed.hostname.endswith(".services.ai.azure.com") or not re.fullmatch(r"/api/projects/[^/]+", parsed.path) or parsed.query or parsed.fragment:
        raise GateError("An explicit HTTPS Foundry project endpoint is required.")
    if not re.fullmatch(r"[1-9][0-9]*", args.agent_version):
        raise GateError("A numeric immutable agent version is required, never latest.")
    if not re.fullmatch(r"/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Insights/components/[^/]+", args.app_insights_resource_id, re.IGNORECASE):
        raise GateError("An actual Application Insights ARM resource ID is required.")
    uuid.UUID(args.workspace_id)
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.environment):
        raise GateError("Invalid environment name.")
    if not 1 <= args.timeout_seconds <= 14400 or not 1 <= args.eval_timeout_seconds <= 3600 or not 1 <= args.trace_timeout_seconds <= 900:
        raise GateError("Timeouts exceed bounded runner limits.")
    root = args.scenario_root.resolve()
    load_inputs(root)
    results = root / ".foundry" / "results"
    if args.worker_results:
        destination = args.worker_results.resolve()
        if destination.parent != results or not args.started_at:
            raise GateError("Invalid worker results path.")
        args.started_at = dt.datetime.fromisoformat(args.started_at).isoformat()
    else:
        destination = results / (dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex)
        args.started_at = dt.datetime.now(dt.UTC).isoformat()
    context = {key: str(getattr(args, key)) for key in (
        "project_endpoint", "agent_name", "agent_version", "judge_deployment",
        "app_insights_resource_id", "workspace_id", "environment", "scenario_root",
    )}
    evidence = Evidence(root, destination, args.environment, context)
    try:
        if args.worker_results:
            return run_worker(args, evidence)
        command = [sys.executable, str(Path(__file__).resolve()), *(argv if argv is not None else sys.argv[1:]),
                   "--worker-results", str(destination), "--started-at", args.started_at]
        process = subprocess.Popen(command)
        try:
            code = process.wait(timeout=args.timeout_seconds)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=30)
            evidence.manifest = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
            raise GateError("Hard overall deadline expired; worker terminated. Remote runs may still exist; IDs retained.")
        except KeyboardInterrupt:
            process.kill()
            process.wait(timeout=30)
            evidence.manifest = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
            raise GateError("Runner cancelled; worker terminated. Remote runs may still exist; IDs retained.") from None
        if code:
            return code
        manifest = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
        expected_tiers = ["comparison"] if args.comparison else ["smoke", "regression"]
        if (manifest["status"] != "completed"
                or [s["tier"] for s in manifest["suites"]] != expected_tiers
                or any(s["status"] != "completed" for s in manifest["suites"])):
            raise GateError("Worker exited without complete smoke and regression evidence.")
        label = "Educational comparison" if args.comparison else "Live smoke/regression"
        print(f"{label} completed; not write-back approval or release acceptance. Evidence: {destination}")
        return 0
    except Exception as exc:
        evidence.manifest["status"] = "failed"
        evidence.manifest["failure_clusters"]["runner"] = [str(exc)]
        for suite in evidence.manifest["suites"]:
            if suite["status"] != "completed":
                suite["status"] = "failed"
        evidence.save()
        print(f"FAILED: {exc}\nEvidence: {destination}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
