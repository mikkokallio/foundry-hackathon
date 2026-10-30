"""Real participant operations. Shared infrastructure and reference resources are never modified."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from azure.core.exceptions import AzureError
from openai import OpenAIError

ROOT = Path(__file__).resolve().parents[1]
SCENARIO = ROOT / "scenarios" / "architecture-docs"
sys.path.insert(0, str(SCENARIO / "scripts"))
import run_foundry_gate as gate

TOOLKIT_TOOLS = ["generate_context_diagram", "lint_document", "compare_with_inventory"]


def load_pack(path: Path) -> dict[str, Any]:
    pack = json.loads(path.read_text(encoding="utf-8-sig"))
    for key in ("subscription_id", "tenant_id"):
        uuid.UUID(pack[key])
    endpoint = urlparse(pack["project_endpoint"])
    if (
        endpoint.scheme != "https"
        or not endpoint.hostname
        or not endpoint.hostname.endswith(".services.ai.azure.com")
        or endpoint.path != f"/api/projects/{pack['team']}"
        or endpoint.query
        or endpoint.fragment
        or endpoint.username
    ):
        raise ValueError("Invalid team project endpoint.")
    variants = pack["model_variants"]
    if len(variants) != 4 or len({(v["model_alias"], v["instructions"]) for v in variants}) != 4:
        raise ValueError("Pack must contain four distinct model/instruction variants.")
    for variant in variants:
        if variant["agent_model_id"] != (
            f"{pack['workload_name']}-{pack['team']}-models/{variant['model_alias']}"
        ):
            raise ValueError("Connected model identifier differs from the selected workload/team.")
    receipt = json.loads((path.parent / "assembly-receipt.json").read_text(encoding="utf-8-sig"))
    for name, expected in receipt["sha256"].items():
        target = (path.parent / name.replace("\\", "/")).resolve()
        if not target.is_relative_to(path.parent.resolve()):
            raise ValueError("Pack receipt contains an escaping path.")
        if hashlib.sha256(target.read_bytes()).hexdigest().lower() != expected.lower():
            raise ValueError(
                f"Pack hash mismatch: {name}. Export a fresh pack; do not edit the receipt."
            )
    return pack


def prefix_for(pack: dict[str, Any], value: str) -> str:
    if not re.fullmatch(re.escape(pack["team"]) + r"-p[1-4](?:-[a-z0-9]+)*", value):
        raise ValueError("Use your assigned team-p1 through team-p4 prefix (optional suffix).")
    return value


def output_path(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT / "out"):
        raise ValueError("Participant output must be under this workspace's ignored out directory.")
    return resolved


def save_new(path: Path, value: Any) -> None:
    path = output_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def request_json(
    url: str,
    token: str,
    *,
    method: str = "GET",
    body: Any = None,
    headers: dict[str, str] | None = None,
) -> Any:
    request = Request(
        url,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            **(headers or {}),
        },
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urlopen(request, timeout=120) as response:
        content = response.read()
        return json.loads(content) if content else {}


def arm(
    pack: dict[str, Any],
    identity: Any,
    resource: str,
    version: str,
    *,
    method: str = "GET",
    body: Any = None,
) -> Any:
    if not resource.lower().startswith(f"/subscriptions/{pack['subscription_id']}/".lower()):
        raise ValueError("ARM target is outside the pack subscription.")
    return request_json(
        f"https://management.azure.com{resource}?api-version={version}",
        identity.get_token("https://management.azure.com/.default").token,
        method=method,
        body=body,
        headers={"If-None-Match": "*"} if method == "PUT" else None,
    )


def project_id(pack: dict[str, Any]) -> str:
    return f"{pack['foundry_resource_id']}/projects/{pack['team']}"


def connection(pack: dict[str, Any], suffix: str) -> str:
    return f"{project_id(pack)}/connections/{pack['workload_name']}-{pack['team']}-{suffix}"


def create_agent(args: argparse.Namespace, pack: dict[str, Any], identity: Any) -> None:
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import (
        MCPTool,
        MCPToolFilter,
        MCPToolRequireApproval,
        PromptAgentDefinition,
        Reasoning,
    )

    prefix = prefix_for(pack, args.prefix)
    if not re.fullmatch(re.escape(prefix) + r"-[a-z0-9-]+", args.name):
        raise ValueError("Agent name must start with your participant prefix followed by '-'.")
    variant = next(v for v in pack["model_variants"] if v["model_alias"] == args.model)
    instructions = (args.pack.parent / "prompts" / f"{args.prompt}.md").read_text("utf-8-sig")
    if "{{" in instructions:
        raise ValueError("Unrendered instructions; use an exported pack.")
    if args.prompt == "baseline" and (args.docs or args.toolkit):
        raise ValueError("The negative-control baseline must have no tools.")
    if args.prompt != "baseline" and not args.docs:
        raise ValueError("The steward requires an explicit documentation MCP choice.")
    if args.docs_owner and args.docs != "practice":
        raise ValueError("--docs-owner requires --docs practice.")
    tools = []
    if args.docs:
        endpoint = pack["docs_mcp"]
        connection_id = connection(pack, "docs")
        if args.docs == "practice":
            owner = prefix_for(pack, args.docs_owner) if args.docs_owner else prefix
            endpoint = pack["docs_mcp"].split("/" + pack["workload_name"] + "/")[0]
            endpoint += f"/{owner}/docs-mcp/mcp"
            connection_id = f"{project_id(pack)}/connections/{owner}-docs"
        tools.append(
            MCPTool(
                server_label="docs",
                server_url=endpoint,
                project_connection_id=connection_id,
                allowed_tools=sorted(gate.READ_TOOLS - set(TOOLKIT_TOOLS))
                + ([] if args.prompt in ("writer", "reviewer") else ["submitProposal"]),
                require_approval=MCPToolRequireApproval(
                    always=MCPToolFilter(tool_names=["submitProposal"]),
                    never=MCPToolFilter(tool_names=sorted(gate.READ_TOOLS - set(TOOLKIT_TOOLS))),
                ),
            )
        )
    if args.toolkit:
        tools.append(
            MCPTool(
                server_label="toolkit",
                server_url=pack["toolkit_mcp"],
                project_connection_id=connection(pack, "toolkit"),
                allowed_tools=TOOLKIT_TOOLS,
                require_approval=MCPToolRequireApproval(
                    never=MCPToolFilter(tool_names=TOOLKIT_TOOLS),
                ),
            )
        )
    definition = PromptAgentDefinition(
        model=variant["deployment"] if args.direct else variant["agent_model_id"],
        instructions=instructions,
        tools=tools,
        reasoning=Reasoning(effort=args.reasoning) if args.reasoning else None,
    )
    destination = output_path(args.output)
    if destination.exists():
        raise ValueError("Binding already exists. Choose a new output file; no agent was changed.")
    with AIProjectClient(
        endpoint=pack["project_endpoint"],
        credential=identity,
        retry_total=0,
        connection_timeout=30,
        read_timeout=60,
    ) as client:
        candidate = client.agents.create_version(
            agent_name=args.name,
            definition=definition,
            metadata={"workshop_prefix": prefix},
        )
    save_new(
        destination,
        {
            "agent_name": candidate.name,
            "agent_version": str(candidate.version),
            "project_endpoint": pack["project_endpoint"],
            "model_alias": args.model,
            "instructions": args.prompt,
            "model": definition.model,
            "definition": candidate.as_dict(),
            "release_accepted": False,
        },
    )
    print(
        f"Created {candidate.name}:{candidate.version}. Binding: {destination}. Not release-qualified."
    )


def binding_for(path: Path, pack: dict[str, Any]) -> dict[str, Any]:
    binding = json.loads(path.read_text("utf-8-sig"))
    if binding["project_endpoint"] != pack["project_endpoint"] or not re.fullmatch(
        r"[1-9][0-9]*", binding["agent_version"]
    ):
        raise ValueError("Binding must name an immutable version in this exact project.")
    return binding


def chat(args: argparse.Namespace, pack: dict[str, Any], identity: Any) -> None:
    from azure.ai.projects import AIProjectClient

    binding = binding_for(args.binding, pack)
    destination = (
        SCENARIO
        / ".foundry"
        / "results"
        / ("chat-" + dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex)
    )
    turn: dict[str, Any] = {
        "agent_name": binding["agent_name"],
        "agent_version": binding["agent_version"],
        "project_endpoint": pack["project_endpoint"],
        "query": args.query,
        "response_ids": [],
        "responses": [],
        "approvals": [],
        "status": "incomplete",
    }
    gate.write_json(destination / "turn.json", turn)
    with (
        AIProjectClient(
            endpoint=pack["project_endpoint"],
            credential=identity,
            retry_total=0,
            connection_timeout=30,
            read_timeout=60,
        ) as project,
        project.get_openai_client(timeout=120, max_retries=0) as client,
    ):
        current: Any = args.query
        previous = args.previous
        for _ in range(20):
            kwargs: dict[str, Any] = {
                "input": current,
                "max_output_tokens": 8192,
                "extra_body": {
                    "agent_reference": {
                        "type": "agent_reference",
                        "name": binding["agent_name"],
                        "version": binding["agent_version"],
                    }
                },
            }
            if previous:
                kwargs["previous_response_id"] = previous
            response = client.responses.create(**kwargs)
            payload = response.model_dump(mode="json")
            turn["responses"].append(payload)
            turn["response_ids"].append(response.id)
            previous = response.id
            gate.write_json(destination / "turn.json", turn)
            if payload.get("status") != "completed" or payload.get("error"):
                raise ValueError(f"Incomplete/failed Foundry response; evidence: {destination}")
            decisions = []
            for item in payload.get("output", []):
                if item["type"] == "mcp_call" and item.get("error"):
                    raise ValueError(f"MCP call failed; evidence: {destination}")
                if item["type"] != "mcp_approval_request":
                    continue
                print(f"\nApproval request: {item['name']}\n{item['arguments']}")
                if item["name"] == "publishProposal":
                    raise ValueError("Publication is never an agent operation.")
                known = item["name"] in gate.READ_TOOLS | {"submitProposal"}
                approved = (
                    known
                    and input("Approve this exact tool and arguments? [y/N] ").strip().lower()
                    == "y"
                )
                turn["approvals"].append({**item, "approved": approved})
                decisions.append(
                    {
                        "type": "mcp_approval_response",
                        "approval_request_id": item["id"],
                        "approve": approved,
                    }
                )
            gate.write_json(destination / "turn.json", turn)
            if decisions:
                current = decisions
                continue
            print(response.output_text)
            turn.update(status="completed", response=response.output_text)
            gate.write_json(destination / "turn.json", turn)
            print(f"\nResponse: {response.id}\nEvidence: {destination}")
            print(
                "Inspect matching native traces; response collection alone is not provenance acceptance."
            )
            return
    raise ValueError(f"Approval continuation exceeded 20 turns; evidence: {destination}")


def gateway(args: argparse.Namespace, pack: dict[str, Any], identity: Any) -> None:
    if args.route in ("models", "models-tight"):
        url = pack["gateway_models"][args.route]
    else:
        prefix = prefix_for(pack, args.prefix)
        base = pack["docs_url"].split("/" + pack["workload_name"] + "/")[0]
        url = f"{base}/{prefix}/models-{args.route}/chat/completions?api-version=2024-10-21"
    token = identity.get_token(pack["gateway_scope"]).token
    for _ in range(6 if args.burst else 1):
        try:
            result = request_json(
                url,
                token,
                method="POST",
                body={
                    "model": args.model,
                    "messages": [{"role": "user", "content": args.query}],
                    "max_completion_tokens": 64,
                },
            )
        except HTTPError as exc:
            if exc.code != 429:
                raise
            retry = exc.headers.get("Retry-After")
            print(json.dumps({"status": 429, "retry_after": retry, "endpoint": url}))
            if not retry:
                raise ValueError("429 has no Retry-After; record the source and inspect policy.")
            return
        if not result.get("usage"):
            raise ValueError("Real model response has no usage; the exercise has not passed.")
        print(json.dumps(result, indent=2))
    if args.burst:
        raise ValueError("Bounded burst did not observe a 429; do not claim the throttle passed.")


def evaluate(args: argparse.Namespace, pack: dict[str, Any], identity: Any) -> None:
    binding = binding_for(args.binding, pack)
    workspace = arm(pack, identity, pack["workspace_resource_id"], "2022-10-01")
    workspace_id = workspace["properties"]["customerId"]
    arguments = [
        "--scenario-root",
        str(SCENARIO),
        "--project-endpoint",
        pack["project_endpoint"],
        "--agent-name",
        binding["agent_name"],
        "--agent-version",
        binding["agent_version"],
        "--judge-deployment",
        pack["workload_name"] + "-judge",
        "--app-insights-resource-id",
        pack["application_insights_resource_id"],
        "--workspace-id",
        workspace_id,
        "--environment",
        pack["team"],
    ]
    if args.comparison:
        arguments.append("--comparison")
    result = subprocess.run(
        [sys.executable, str(SCENARIO / "scripts" / "run_foundry_gate.py"), *arguments],
        check=False,
    )
    if result.returncode:
        raise ValueError(f"Live evaluation/provenance failed (exit {result.returncode}).")


def compare(paths: list[Path], destination: Path) -> None:
    if len(paths) != 4:
        raise ValueError("Supply the four actual comparison manifest files.")
    reports = []
    signatures = set()
    coverage = None
    hashes = None
    controls = set()
    projects = set()
    for path in paths:
        manifest = json.loads(path.read_text("utf-8"))
        suites = manifest["suites"]
        if (
            len(suites) != 1
            or suites[0]["tier"] != "comparison"
            or suites[0]["status"] not in ("completed", "failed")
            or manifest["status"] != suites[0]["status"]
        ):
            raise ValueError(
                "Only completed comparison collection (passed or failed) can be compared."
            )
        suite = suites[0]
        rows = suite["rows"]
        if len(rows) != 12 or not all(
            row.get("provenance", {}).get("verified") is True for row in rows
        ):
            raise ValueError("Incomplete comparison coverage/provenance.")
        if not suite.get("evaluation_id") or not suite.get("evaluation_run_id"):
            raise ValueError("Missing real remote evaluation identities.")
        ids = [row["id"] for row in rows]
        if len(set(ids)) != 12:
            raise ValueError("Comparison requires twelve distinct cases, not duplicate rows.")
        current_hashes = manifest["input_sha256"]
        if coverage is not None and (ids != coverage or hashes != current_hashes):
            raise ValueError("Comparisons must use identical cases and frozen input hashes.")
        coverage, hashes = ids, current_hashes
        agent = json.loads((path.parent / "agent-version.json").read_text("utf-8"))
        definition = agent["definition"]
        if (
            agent["name"] != manifest["context"]["agent_name"]
            or str(agent["version"]) != manifest["context"]["agent_version"]
        ):
            raise ValueError(
                "Saved agent definition does not match the evaluated immutable version."
            )
        projects.add(manifest["context"]["project_endpoint"])
        controls.add(
            json.dumps(
                {
                    key: value
                    for key, value in definition.items()
                    if key not in ("model", "instructions")
                },
                sort_keys=True,
            )
        )
        signatures.add((definition["model"], definition["instructions"]))
        reports.append(
            {
                "agent": manifest["context"]["agent_name"],
                "version": manifest["context"]["agent_version"],
                "model": definition["model"],
                "result": suite["status"],
                "failure_clusters": ", ".join(
                    key for key, values in suite["failure_clusters"].items() if values
                )
                or "none",
                "reasoning": json.dumps(definition.get("reasoning"), sort_keys=True),
                "task_adherence": next(
                    c["actual"] for c in suite["checks"] if c["metric"] == "task_adherence"
                ),
                "mean_latency_seconds": mean_measure(rows, "latency_seconds"),
                "mean_input_tokens": mean_measure(rows, "input_tokens"),
                "mean_output_tokens": mean_measure(rows, "output_tokens"),
                "mean_reasoning_tokens": mean_measure(rows, "reasoning_tokens"),
                "estimated_cost": "unavailable: verify all matching token prices before pricing",
                "evaluation_id": suite["evaluation_id"],
                "evidence": str(path),
            }
        )
    models = {item[0] for item in signatures}
    prompts = {item[1] for item in signatures}
    if len(signatures) != 4 or len(models) != 2 or len(prompts) != 2:
        raise ValueError("Need the complete two-model by two-instruction matrix.")
    if len(controls) != 1 or len(projects) != 1:
        raise ValueError(
            "Use the same project, actual tool connections and reasoning/settings for all four candidates."
        )
    destination = output_path(destination)
    if destination.exists():
        raise ValueError("Comparison destination exists; choose a fresh directory.")
    destination.mkdir(parents=True)
    with (destination / "comparison.csv").open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(reports[0]))
        writer.writeheader()
        writer.writerows(reports)
    headings = list(reports[0])
    table = ["| " + " | ".join(headings) + " |", "| " + " | ".join(["---"] * len(headings)) + " |"]
    table.extend("| " + " | ".join(str(row[key]) for key in headings) + " |" for row in reports)
    (destination / "comparison.md").write_text(
        "# Fresh educational comparison (not full release qualification)\n\n"
        + "\n".join(table)
        + "\n",
        encoding="utf-8",
    )
    print(destination)


def mean_measure(rows: list[dict[str, Any]], name: str) -> float | str:
    values: list[int | float] = []
    for row in rows:
        value = row.get(name)
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or value < 0
        ):
            return "unavailable"
        values.append(value)
    if not values:
        return "unavailable"
    return sum(values) / len(values)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--pack", type=Path, required=True, help="Exported workshop.json")
    result.add_argument("--prefix", help="Assigned team-p1 through team-p4")
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    agent = commands.add_parser("agent")
    agent.add_argument("--name", required=True)
    agent.add_argument("--model", choices=["chat-small", "chat-medium"], default="chat-small")
    agent.add_argument(
        "--prompt",
        choices=["baseline", "instructions", "instructions-concise", "writer", "reviewer"],
        default="baseline",
    )
    agent.add_argument("--direct", action="store_true")
    agent.add_argument("--docs", choices=["practice", "reference"])
    agent.add_argument(
        "--docs-owner", help="Team participant prefix owning the common practice MCP"
    )
    agent.add_argument("--toolkit", action="store_true")
    agent.add_argument("--reasoning", choices=["minimal", "low", "medium", "high"])
    agent.add_argument("--output", type=Path, required=True)
    chat_command = commands.add_parser("chat")
    chat_command.add_argument("--binding", type=Path, required=True)
    chat_command.add_argument(
        "--previous", help="Explicit prior genuine response ID in this conversation"
    )
    chat_command.add_argument("query")
    gateway_command = commands.add_parser("gateway")
    gateway_command.add_argument(
        "--route", choices=["models", "models-tight", "requests", "tokens"], default="models"
    )
    gateway_command.add_argument(
        "--model", choices=["chat-small", "chat-medium"], default="chat-small"
    )
    gateway_command.add_argument("--query", default="Reply in one sentence about architecture.")
    gateway_command.add_argument("--burst", action="store_true")
    practice = commands.add_parser("practice")
    practice.add_argument("kind", choices=["docs", "models", "status"])
    registry = commands.add_parser("catalog")
    registry.add_argument("action", choices=["list", "register", "export"])
    registry.add_argument("--output", type=Path)
    evaluation = commands.add_parser("eval")
    evaluation.add_argument("--binding", type=Path, required=True)
    evaluation.add_argument("--comparison", action="store_true")
    comparison = commands.add_parser("compare")
    comparison.add_argument("manifests", type=Path, nargs=4)
    comparison.add_argument("--output", type=Path, required=True)
    workflow = commands.add_parser("workflow")
    workflow.add_argument("--writer", type=Path, required=True)
    workflow.add_argument("--reviewer", type=Path, required=True)
    workflow.add_argument("--rounds", type=int, choices=range(1, 4), default=2)
    workflow.add_argument("--timeout-seconds", type=int, default=600, metavar="1..1800")
    workflow.add_argument("query")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        pack = load_pack(args.pack)
        if args.command == "compare":
            compare(args.manifests, args.output)
            return 0
        from azure.identity import AzureCliCredential

        from workshop.practice import catalog, practice

        with AzureCliCredential(tenant_id=pack["tenant_id"], process_timeout=30) as identity:
            if args.command == "check":
                from azure.ai.projects import AIProjectClient

                with AIProjectClient(
                    endpoint=pack["project_endpoint"],
                    credential=identity,
                    retry_total=0,
                    connection_timeout=30,
                    read_timeout=60,
                ) as client:
                    next(iter(client.agents.list(limit=1)), None)
                systems = request_json(
                    pack["docs_url"] + "/systems",
                    identity.get_token(pack["gateway_scope"]).token,
                )
                print(
                    f"Foundry list and authenticated systems read succeeded ({type(systems).__name__})."
                )
                print("This is not authoring-permission verification or release acceptance.")
            elif args.command == "agent":
                create_agent(args, pack, identity)
            elif args.command == "chat":
                chat(args, pack, identity)
            elif args.command == "gateway":
                gateway(args, pack, identity)
            elif args.command == "eval":
                evaluate(args, pack, identity)
            elif args.command == "practice":
                practice(args, pack, identity)
            elif args.command == "catalog":
                catalog(args, pack, identity)
            elif args.command == "workflow":
                from workshop.workflow import workflow

                workflow(args, pack, identity)
        return 0
    except (ValueError, KeyError, OSError, URLError, gate.GateError) as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    except (AzureError, OpenAIError) as exc:
        print(f"Azure/Foundry operation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
