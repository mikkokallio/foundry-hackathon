"""Concurrent real Foundry comparisons using existing operator/project identities.

Each selected team supplies the genuine two-model by two-instruction teaching
matrix. No synthetic users, write approval or release acceptance.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Any

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))
import workshop.__main__ as workshop

gate = workshop.gate
SCENARIO = workshop.SCENARIO


@dataclass(frozen=True)
class Cell:
    team: str
    index: int
    pack: dict[str, Any]
    binding: dict[str, Any]

    @property
    def label(self) -> str:
        return f"{self.team}-{self.index}"


def cells_from_config(path: Path, teams: list[str], sessions: int) -> list[Cell]:
    if sessions not in (16, 20) or len(teams) * 4 != sessions or len(set(teams)) != len(teams):
        raise ValueError("Select exactly four or five distinct teams for sixteen or twenty virtual sessions.")
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    plan = gate.load_inputs(SCENARIO)[0]
    expected_signatures = {(model, PureWindowsPath(prompt).stem)
                           for model in plan["model_aliases"] for prompt in plan["instruction_files"]}
    if len(expected_signatures) != 4:
        raise ValueError("The frozen teaching plan must declare exactly four comparison cells.")
    cells: list[Cell] = []
    targets = set()
    identities = set()
    for team in teams:
        entry = config["teams"][team]
        pack = workshop.load_pack((path.parent / entry["pack"]).resolve())
        if pack["team"] != team or team == "facilitator":
            raise ValueError("Selected pack must belong to its declared non-facilitator team.")
        targets.add((pack["subscription_id"], pack["tenant_id"], pack["foundry_resource_id"],
                     pack["workspace_resource_id"], pack["workload_name"]))
        signatures = set()
        if len(entry["bindings"]) != 4:
            raise ValueError("Every team requires exactly four genuine immutable candidate bindings.")
        for index, name in enumerate(entry["bindings"], 1):
            binding = workshop.binding_for((path.parent / name).resolve(), pack)
            signature = (binding["model_alias"], binding["instructions"])
            variants = [v for v in pack["model_variants"]
                        if (v["model_alias"], PureWindowsPath(v["instructions"]).stem) == signature]
            if len(variants) != 1 or binding["model"] != variants[0]["agent_model_id"]:
                raise ValueError("Load candidates must use their real matching connected model variant.")
            identity = (pack["project_endpoint"], binding["agent_name"], binding["agent_version"])
            if identity in identities:
                raise ValueError("Each virtual session needs a distinct immutable candidate binding.")
            identities.add(identity)
            signatures.add(signature)
            cells.append(Cell(team, index, pack, binding))
        if signatures != expected_signatures:
            raise ValueError("The complete two-model by two-instruction matrix is required for each team.")
    if len(targets) != 1:
        raise ValueError("All sessions must use the same actual lab/workload and telemetry resources.")
    return cells


def run_cell(cell: Cell, directory: Path, run_id: str, workspace_id: str,
             barrier: threading.Barrier, deadline: float, timeout_seconds: int) -> dict[str, Any]:
    destination = SCENARIO / ".foundry" / "results" / f"{run_id}-{cell.label}"
    if destination.exists():
        raise ValueError("A native evidence destination already exists; choose a fresh run.")
    started_at = dt.datetime.now(dt.UTC).isoformat()
    command = [
        sys.executable, str(SCENARIO / "scripts" / "run_foundry_gate.py"),
        "--scenario-root", str(SCENARIO), "--project-endpoint", cell.pack["project_endpoint"],
        "--agent-name", cell.binding["agent_name"], "--agent-version", cell.binding["agent_version"],
        "--judge-deployment", cell.pack["workload_name"] + "-judge",
        "--app-insights-resource-id", cell.pack["application_insights_resource_id"],
        "--workspace-id", workspace_id, "--environment", cell.team,
        "--comparison", "--isolated-metadata", "--timeout-seconds", str(timeout_seconds),
        "--worker-results", str(destination), "--started-at", started_at,
    ]
    barrier.wait(timeout=max(0.001, min(60, deadline - time.monotonic())))
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("Load deadline expired before this session could start.")
    receipt: dict[str, Any] = {
        "team": cell.team, "cell": cell.label, "agent_name": cell.binding["agent_name"],
        "agent_version": cell.binding["agent_version"],
        "started_at": dt.datetime.now(dt.UTC).isoformat(),
        "manifest": str(destination / "manifest.json"), "status": "incomplete",
    }
    with (directory / f"{cell.label}.log").open("x", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=remaining, check=False)
            receipt["exit_code"] = result.returncode
            receipt["status"] = "completed" if result.returncode == 0 else "failed"
        except subprocess.TimeoutExpired:
            receipt["status"] = "failed"
            receipt["error"] = "Hard session deadline expired; worker killed. Inspect retained remote IDs before further calls."
    receipt["finished_at"] = dt.datetime.now(dt.UTC).isoformat()
    gate.write_json(directory / f"{cell.label}.json", receipt)
    return receipt


def overlap_peak(intervals: list[tuple[str, str]]) -> int:
    events = []
    for start, finish in intervals:
        left, right = dt.datetime.fromisoformat(start), dt.datetime.fromisoformat(finish)
        if left.tzinfo is None or right.tzinfo is None or right < left:
            raise ValueError("Missing timezone or invalid measured interval.")
        events.extend(((left, 1), (right, -1)))
    current = peak = 0
    for _, delta in sorted(events):
        current += delta
        peak = max(peak, current)
    return peak


def collect_result(cell: Cell, receipt: dict[str, Any], frozen: dict[str, str],
                   expected_ids: list[str]) -> dict[str, Any]:
    path = Path(receipt["manifest"])
    result: dict[str, Any] = {"cell": cell.label, "collection_complete": False,
                              "quality_gate_passed": False, "client_turn_intervals": [],
                              "latencies_seconds": [], "response_create_retries": []}
    if not path.is_file():
        result["error"] = "Native manifest missing; no collection or provenance acceptance."
        return result
    manifest = json.loads(path.read_text(encoding="utf-8"))
    context = manifest["context"]
    if (context["agent_name"] != cell.binding["agent_name"]
            or context["agent_version"] != cell.binding["agent_version"]
            or context["project_endpoint"] != cell.pack["project_endpoint"]
            or manifest.get("input_sha256") != frozen):
        raise ValueError("Native immutable target or frozen inputs differ from the selected cell.")
    suites = manifest["suites"]
    if len(suites) != 1 or suites[0]["tier"] != "comparison":
        result["error"] = "Expected exactly one genuine twelve-case comparison."
        return result
    suite = suites[0]
    rows = suite["rows"]
    if ([row["id"] for row in rows] != expected_ids
            or not suite.get("evaluation_id") or not suite.get("evaluation_run_id")):
        result["error"] = "Incomplete cases, genuine remote evaluation IDs or native execution provenance."
        return result
    result["evaluation_id"] = suite["evaluation_id"]
    result["evaluation_run_id"] = suite["evaluation_run_id"]
    result["failure_clusters"] = suite["failure_clusters"]
    for row in rows:
        latency = row.get("latency_seconds")
        if isinstance(latency, bool) or not isinstance(latency, (int, float)) or not math.isfinite(latency) or latency < 0:
            raise ValueError("A completed case has no valid measured latency.")
        turn = json.loads((path.parent / "comparison" / f"{row['id']}.json").read_text(encoding="utf-8"))
        if turn["status"] != "completed" or turn["response_ids"] != row["response_ids"]:
            raise ValueError("Measured turn differs from the native evaluated response IDs.")
        result["client_turn_intervals"].append((turn["started_at"], turn["finished_at"]))
        result["latencies_seconds"].append(latency)
        result["response_create_retries"].extend(turn.get("response_create_retries", []))
    if any(row.get("provenance", {}).get("verified") is not True for row in rows):
        result["error"] = "Incomplete cases, genuine remote evaluation IDs or native execution provenance."
        return result
    result["collection_complete"] = suite["status"] in ("completed", "failed")
    result["quality_gate_passed"] = (receipt.get("exit_code") == 0 and manifest["status"] == "completed"
                                      and suite["status"] == "completed")
    return result


def execute(cells: list[Cell], directory: Path, workspace_id: str, timeout_seconds: int) -> dict[str, Any]:
    directory = workshop.output_path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    uuid.UUID(workspace_id)
    plan, _, _, frozen = gate.load_inputs(SCENARIO)
    run_id = "load-" + uuid.uuid4().hex
    report: dict[str, Any] = {
        "run_id": run_id, "status": "incomplete", "virtual_sessions": len(cells),
        "started_at": dt.datetime.now(dt.UTC).isoformat(), "input_sha256": frozen,
        "identity_approach": "Existing operator invokes actual project agents; existing project managed identities authenticate downstream.",
        "human_ux_verified": False, "write_back_verified": False, "release_accepted": False,
        "publication_performed": False, "sessions": [], "results": [], "errors": [],
    }
    gate.write_json(directory / "manifest.json", report)
    barrier = threading.Barrier(len(cells))
    deadline = time.monotonic() + timeout_seconds
    with ThreadPoolExecutor(max_workers=len(cells)) as pool:
        futures = {pool.submit(run_cell, cell, directory, run_id, workspace_id, barrier,
                               deadline, timeout_seconds): cell for cell in cells}
        for future in as_completed(futures):
            cell = futures[future]
            try:
                receipt = future.result()
                report["sessions"].append(receipt)
                report["results"].append(collect_result(cell, receipt, frozen, plan["comparison_case_ids"]))
            except (OSError, ValueError, KeyError, threading.BrokenBarrierError) as exc:
                error = {"cell": cell.label, "error_type": type(exc).__name__, "error": str(exc)}
                report["errors"].append(error)
                print(json.dumps(error), file=sys.stderr, flush=True)
            gate.write_json(directory / "manifest.json", report)
    report["collection_complete"] = (not report["errors"] and len(report["results"]) == len(cells)
                                      and all(r["collection_complete"] for r in report["results"]))
    intervals = [interval for result in report["results"] for interval in result["client_turn_intervals"]]
    report["client_agent_turn_overlap_peak"] = overlap_peak(intervals)
    report["requested_concurrency_observed"] = report["client_agent_turn_overlap_peak"] >= len(cells)
    report["quality_gates_passed"] = (report["collection_complete"]
                                      and all(r["quality_gate_passed"] for r in report["results"]))
    report["comparisons"] = []
    if report["collection_complete"]:
        for team in sorted({cell.team for cell in cells}):
            paths = [Path(s["manifest"]) for s in report["sessions"] if s["team"] == team]
            try:
                target = directory / "comparisons" / team
                workshop.compare(paths, target)
                report["comparisons"].append({"team": team, "directory": str(target)})
            except (OSError, ValueError, KeyError) as exc:
                report["errors"].append({"team": team, "error": str(exc)})
                print(f"Comparison failed for {team}: {exc}", file=sys.stderr, flush=True)
    latencies = sorted(value for result in report["results"] for value in result["latencies_seconds"])
    report["case_latency_seconds"] = {
        "count": len(latencies),
        **({f"p{p}": latencies[math.ceil(len(latencies) * p / 100) - 1] for p in (50, 95, 99)}
           if latencies else {}),
    }
    report["load_collection_verified"] = (
        report["collection_complete"] and report["requested_concurrency_observed"] and not report["errors"]
        and len(report["comparisons"]) == len({cell.team for cell in cells})
    )
    report["response_create_retry_count"] = sum(len(r["response_create_retries"]) for r in report["results"])
    report["status"] = ("completed" if report["collection_complete"] and report["quality_gates_passed"]
                         and report["requested_concurrency_observed"] and not report["errors"] else "failed")
    report["finished_at"] = dt.datetime.now(dt.UTC).isoformat()
    if gate.load_inputs(SCENARIO)[3] != frozen:
        report["status"] = "failed"
        report["load_collection_verified"] = False
        report["errors"].append({"error": "Frozen evaluation inputs changed during this run."})
    gate.write_json(directory / "manifest.json", report)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", type=Path, required=True,
                        help="Private JSON: teams maps team to pack path and four binding paths, relative to this JSON.")
    parser.add_argument("--teams", nargs="+", required=True)
    parser.add_argument("--sessions", type=int, choices=(16, 20), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=5400)
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 14400:
        raise ValueError("Use an explicit bounded timeout of 1..14400 seconds.")
    cells = cells_from_config(args.configuration.resolve(), args.teams, args.sessions)
    from cli_credential import CachedAzureCliCredential

    with CachedAzureCliCredential(tenant_id=cells[0].pack["tenant_id"], process_timeout=30) as identity:
        workspace = workshop.arm(cells[0].pack, identity, cells[0].pack["workspace_resource_id"], "2022-10-01")
    report = execute(cells, args.output, workspace["properties"]["customerId"], args.timeout_seconds)
    print(json.dumps({"status": report["status"], "collection_complete": report["collection_complete"],
                      "load_collection_verified": report["load_collection_verified"],
                      "quality_gates_passed": report["quality_gates_passed"],
                      "client_agent_turn_overlap_peak": report["client_agent_turn_overlap_peak"],
                      "manifest": str(args.output.resolve() / "manifest.json")}, indent=2))
    return 0 if report["status"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
