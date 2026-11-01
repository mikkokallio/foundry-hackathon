"""Offline orchestration tests; fake native results never leave owned test directories."""
from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path, PureWindowsPath
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import run_workshop_load as load


class LoadTests(unittest.TestCase):
    def setUp(self):
        output = load.REPO / "out"
        output.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="unit-load-", dir=output)
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.configuration = self.directory / "configuration.json"
        self.configuration.write_text(json.dumps({"teams": {
            team: {"pack": f"{team}.json", "bindings": [f"{team}-{i}.json" for i in range(1, 5)]}
            for team in ("alpha", "beta", "gamma", "delta", "epsilon")
        }}), encoding="utf-8")
        self.inputs = load.gate.load_inputs(ROOT)
        self.native = self.directory / "scenario"
        self.native.mkdir()
        self.active = self.peak = 0
        self.lock = threading.Lock()

    def pack(self, path):
        team = path.stem
        return {
            "team": team, "subscription_id": "unit-subscription", "tenant_id": "unit-tenant",
            "foundry_resource_id": "/unit/foundry", "workspace_resource_id": "/unit/workspace",
            "workload_name": "unit-workload", "application_insights_resource_id": "/unit/insights",
            "project_endpoint": f"https://unit.services.ai.azure.com/api/projects/{team}",
            "model_variants": [{"model_alias": model, "instructions": f"prompts\\{prompt}.md",
                                "agent_model_id": f"unit-workload-{team}-models/{model}"}
                               for model in ("chat-small", "chat-medium")
                               for prompt in ("instructions", "instructions-concise")],
        }

    def binding(self, path, pack):
        index = int(path.stem.rsplit("-", 1)[1]) - 1
        variant = pack["model_variants"][index]
        return {"project_endpoint": pack["project_endpoint"], "agent_name": path.stem,
                "agent_version": "1", "model": variant["agent_model_id"],
                "model_alias": variant["model_alias"],
                "instructions": PureWindowsPath(variant["instructions"]).stem}

    def cells(self, count=16):
        teams = ["alpha", "beta", "gamma", "delta", "epsilon"][:count // 4]
        with patch.object(load.workshop, "load_pack", side_effect=self.pack), patch.object(
            load.workshop, "binding_for", side_effect=self.binding
        ):
            return load.cells_from_config(self.configuration, teams, count)

    def fake_native(self, command, **kwargs):
        def argument(name):
            return command[command.index(name) + 1]

        with self.lock:
            self.active += 1
            self.peak = max(self.peak, self.active)
        time.sleep(0.08)
        name = argument("--agent-name")
        team = argument("--environment")
        index = int(name.rsplit("-", 1)[1]) - 1
        variant = self.pack(Path(f"{team}.json"))["model_variants"][index]
        destination = Path(argument("--worker-results"))
        rows = []
        for ordinal, case in enumerate(self.inputs[0]["comparison_case_ids"]):
            start = dt.datetime(2026, 1, 1, 12, tzinfo=dt.UTC) + dt.timedelta(seconds=ordinal * 2)
            finish = start + dt.timedelta(seconds=2)
            response_id = f"resp_unit_{name}_{case}"
            rows.append({"id": case, "response_ids": [response_id], "latency_seconds": 2,
                         "input_tokens": 10, "output_tokens": 10, "reasoning_tokens": 0,
                         "provenance": {"verified": True}})
            load.gate.write_json(destination / "comparison" / f"{case}.json",
                                 {"status": "completed", "response_ids": [response_id],
                                  "started_at": start.isoformat(), "finished_at": finish.isoformat(),
                                  "response_create_retries": []})
        load.gate.write_json(destination / "agent-version.json", {
            "name": name, "version": "1", "definition": {
                "kind": "prompt", "model": variant["agent_model_id"],
                "instructions": variant["instructions"], "tools": [],
            }})
        load.gate.write_json(destination / "manifest.json", {
            "status": "completed", "input_sha256": self.inputs[3],
            "context": {"agent_name": name, "agent_version": "1",
                        "project_endpoint": argument("--project-endpoint")},
            "suites": [{"tier": "comparison", "status": "completed", "rows": rows,
                        "evaluation_id": "unit-eval", "evaluation_run_id": "unit-run",
                        "failure_clusters": {}, "checks": [{"metric": "task_adherence", "actual": 4}]}],
        })
        self.assertIn("--isolated-metadata", command)
        with self.lock:
            self.active -= 1
        return SimpleNamespace(returncode=0)

    def test_sixteen_and_twenty_actual_worker_slots_and_real_comparison_reuse(self):
        for count in (16, 20):
            with self.subTest(count=count), patch.object(load, "SCENARIO", self.native), patch.object(
                load.gate, "load_inputs", return_value=self.inputs
            ), patch.object(load.subprocess, "run", side_effect=self.fake_native) as process:
                report = load.execute(self.cells(count), self.directory / f"result-{count}",
                                      "00000000-0000-0000-0000-000000000001", 60)
                self.assertEqual(report["status"], "completed")
                self.assertEqual(process.call_count, count)
                self.assertEqual(len(report["comparisons"]), count // 4)
                self.assertEqual(report["case_latency_seconds"]["count"], count * 12)
                self.assertEqual(report["client_agent_turn_overlap_peak"], count)
                self.assertTrue(report["requested_concurrency_observed"])
                self.assertTrue(report["load_collection_verified"])
                self.assertFalse(report["human_ux_verified"])
                self.assertFalse(report["write_back_verified"])
                self.assertFalse(report["release_accepted"])
                self.assertGreater(self.peak, 1)

    def test_selects_only_complete_unique_team_matrices(self):
        for teams, count in ((["alpha"], 16), (["alpha"] * 4, 16), (["alpha"] * 5, 20)):
            with self.subTest(teams=teams), self.assertRaises(ValueError):
                load.cells_from_config(self.configuration, teams, count)
        original = self.binding

        def disconnected(path, pack):
            return {**original(path, pack), "model": "direct-unit-deployment"}

        with patch.object(load.workshop, "load_pack", side_effect=self.pack), patch.object(
            load.workshop, "binding_for", side_effect=disconnected
        ), self.assertRaisesRegex(ValueError, "connected model"):
            load.cells_from_config(self.configuration, ["alpha", "beta", "gamma", "delta"], 16)

    def test_quality_negative_controls_are_not_disguised_as_transport_or_quality_success(self):
        def negative(command, **kwargs):
            self.fake_native(command, **kwargs)
            path = Path(command[command.index("--worker-results") + 1]) / "manifest.json"
            manifest = json.loads(path.read_text())
            manifest["status"] = "failed"
            manifest["suites"][0]["status"] = "failed"
            manifest["suites"][0]["failure_clusters"] = {"thresholds": ["task_adherence"]}
            manifest["suites"][0]["checks"][0]["actual"] = 2
            load.gate.write_json(path, manifest)
            return SimpleNamespace(returncode=1)

        with patch.object(load, "SCENARIO", self.native), patch.object(
            load.gate, "load_inputs", return_value=self.inputs
        ), patch.object(load.subprocess, "run", side_effect=negative):
            report = load.execute(self.cells(), self.directory / "quality-negative",
                                  "00000000-0000-0000-0000-000000000001", 60)
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["quality_gates_passed"])
        self.assertTrue(report["load_collection_verified"])
        self.assertEqual(len(report["comparisons"]), 4)

    def test_deadline_is_failure_without_retry_or_claiming_writes(self):
        cells = self.cells()
        with patch.object(load, "SCENARIO", self.native), patch.object(
            load.gate, "load_inputs", return_value=self.inputs
        ), patch.object(load.subprocess, "run", side_effect=subprocess.TimeoutExpired("unit-only", 1)) as process:
            report = load.execute(cells, self.directory / "timeout",
                                  "00000000-0000-0000-0000-000000000001", 60)
        self.assertEqual(process.call_count, 16)
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["collection_complete"])
        self.assertEqual(report["comparisons"], [])
        self.assertTrue(all(session["status"] == "failed" for session in report["sessions"]))

    def test_missing_native_provenance_cannot_be_accepted(self):
        cell = self.cells()[0]
        command = [
            "--agent-name", cell.binding["agent_name"], "--environment", cell.team,
            "--worker-results", str(self.directory / "native"),
            "--project-endpoint", cell.pack["project_endpoint"], "--isolated-metadata",
        ]
        self.fake_native(command)
        path = self.directory / "native" / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["suites"][0]["rows"][0]["provenance"]["verified"] = False
        load.gate.write_json(path, manifest)
        result = load.collect_result(cell, {"manifest": str(path), "exit_code": 0},
                                     self.inputs[3], self.inputs[0]["comparison_case_ids"])
        self.assertFalse(result["collection_complete"])
        self.assertFalse(result["quality_gate_passed"])
        self.assertEqual(len(result["client_turn_intervals"]), 12)
        self.assertEqual(len(result["latencies_seconds"]), 12)
        self.assertFalse(result["quality_gate_passed"])

    def test_overlap_excludes_adjacent_intervals_and_rejects_naive_timestamps(self):
        self.assertEqual(load.overlap_peak([
            ("2026-01-01T00:00:00+00:00", "2026-01-01T00:00:01+00:00"),
            ("2026-01-01T00:00:01+00:00", "2026-01-01T00:00:02+00:00"),
        ]), 1)
        with self.assertRaises(ValueError):
            load.overlap_peak([("2026-01-01T00:00:00", "2026-01-01T00:00:01")])


if __name__ == "__main__":
    unittest.main()
