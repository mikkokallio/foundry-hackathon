"""Local-only runner tests. All SDK doubles live exclusively in this test module."""
from __future__ import annotations

import copy
import io
import json
import shutil
import sys
import time
import unittest
import uuid
from pathlib import Path
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import Mock, patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "backend" / "src"))
import run_foundry_gate as runner
from frozen_template import TemplateComplianceEvaluator, extract_markdown_document, find_document


class RunnerTests(unittest.TestCase):
    CLEANUP_DELAYS = (0.05, 0.1, 0.2, 0.4, 0.8, 1.0)

    def setUp(self):
        self.fixture_root = ROOT / "tests" / "__pycache__"
        self.fixture_root.mkdir(exist_ok=True)
        self.directory = self.fixture_root / ("gate-runner-fixture-" + uuid.uuid4().hex)
        self.directory.mkdir(exist_ok=False)
        self.addCleanup(self.cleanup_directory)
        self.case = runner.load_inputs(ROOT)[2][0]

    def cleanup_directory(self):
        if self.directory.parent != self.fixture_root or not self.directory.name.startswith("gate-runner-fixture-"):
            raise ValueError("Refusing to clean an unowned fixture directory.")
        for attempt in range(len(self.CLEANUP_DELAYS) + 1):
            try:
                shutil.rmtree(self.directory)
                return
            except OSError as exc:
                if getattr(exc, "winerror", None) not in (32, 33) or attempt == len(self.CLEANUP_DELAYS):
                    raise
                time.sleep(self.CLEANUP_DELAYS[attempt])

    def test_fixture_root_is_ignored_and_cleanup_retries_only_owned_directory(self):
        self.assertEqual(self.directory.parent, ROOT / "tests" / "__pycache__")
        sharing_error = PermissionError("test-scoped sharing lock")
        sharing_error.winerror = 32
        with patch.object(shutil, "rmtree", side_effect=[sharing_error, None]) as remove, patch.object(time, "sleep") as sleep:
            self.cleanup_directory()
        self.assertEqual(remove.call_args_list, [unittest.mock.call(self.directory)] * 2)
        sleep.assert_called_once_with(self.CLEANUP_DELAYS[0])

    def test_evidence_replacement_retries_a_transient_windows_lock(self):
        path = self.directory / "evidence.json"
        path.write_text('{"before": true}', encoding="utf-8")
        sharing_error = PermissionError("test-scoped Windows replacement lock")
        sharing_error.winerror = 5
        replace = Path.replace
        attempts = []

        def unlock_after_first_attempt(staging, destination):
            attempts.append((staging, destination))
            if len(attempts) == 1:
                raise sharing_error
            return replace(staging, destination)

        errors = io.StringIO()
        with patch.object(Path, "replace", unlock_after_first_attempt), patch.object(
            runner.time, "sleep"
        ) as sleep, patch.object(sys, "stderr", errors):
            runner.write_json(path, {"actual": "test-only receipt"})
        self.assertEqual(json.loads(path.read_text()), {"actual": "test-only receipt"})
        self.assertFalse(path.with_suffix(".json.pending").exists())
        self.assertEqual(len(attempts), 2)
        sleep.assert_called_once()
        self.assertIn("Windows", errors.getvalue())

    def test_evidence_replacement_exhaustion_preserves_original_and_raises(self):
        path = self.directory / "evidence.json"
        path.write_text('{"before": true}', encoding="utf-8")
        sharing_error = PermissionError("test-scoped persistent Windows replacement lock")
        sharing_error.winerror = 5
        with patch.object(Path, "replace", side_effect=sharing_error) as replace, patch.object(
            runner.time, "sleep"
        ) as sleep, patch.object(sys, "stderr", io.StringIO()):
            with self.assertRaises(PermissionError) as raised:
                runner.write_json(path, {"actual": "test-only receipt"})
        self.assertIs(raised.exception, sharing_error)
        self.assertEqual(json.loads(path.read_text()), {"before": True})
        self.assertGreater(replace.call_count, 1)
        self.assertLessEqual(replace.call_count, 7)
        self.assertEqual(sleep.call_count, replace.call_count - 1)

    def test_evidence_replacement_does_not_retry_other_permission_errors(self):
        permission_error = PermissionError("test-scoped unrelated permission denial")
        permission_error.winerror = 1314
        with patch.object(Path, "replace", side_effect=permission_error) as replace, patch.object(
            runner.time, "sleep"
        ) as sleep:
            with self.assertRaises(PermissionError):
                runner.write_json(self.directory / "evidence.json", {})
        replace.assert_called_once()
        sleep.assert_not_called()

    def test_cleanup_exhaustion_is_raised_not_ignored(self):
        sharing_error = PermissionError("test-scoped persistent sharing lock")
        sharing_error.winerror = 32
        with patch.object(shutil, "rmtree", side_effect=sharing_error) as remove, patch.object(time, "sleep") as sleep:
            with self.assertRaises(PermissionError) as raised:
                self.cleanup_directory()
        self.assertIs(raised.exception, sharing_error)
        self.assertEqual(remove.call_count, len(self.CLEANUP_DELAYS) + 1)
        self.assertEqual(sleep.call_count, len(self.CLEANUP_DELAYS))

    def test_cleanup_unrelated_os_error_is_not_retried(self):
        error = PermissionError("test-scoped access denial, not a sharing lock")
        error.winerror = 5
        with patch.object(shutil, "rmtree", side_effect=error) as remove, patch.object(time, "sleep") as sleep:
            with self.assertRaises(PermissionError) as raised:
                self.cleanup_directory()
        self.assertIs(raised.exception, error)
        remove.assert_called_once_with(self.directory)
        sleep.assert_not_called()

    def test_frozen_plan_and_gate_unchanged_coverage(self):
        plan, gate, cases, hashes = runner.load_inputs(ROOT)
        self.assertEqual(len(cases), 25)
        self.assertEqual(len(plan["smoke_case_ids"]), 4)
        self.assertEqual(gate["checks"]["task_adherence"]["min_mean"], 3.0)
        self.assertEqual(gate["checks"]["template_compliance"]["min_mean"], 0.5)
        self.assertEqual(len(hashes), 3)

    def test_isolated_concurrent_evidence_never_updates_shared_metadata(self):
        context = {"agent_version": "1"}
        first = runner.Evidence(self.directory, self.directory / "first", "alpha", context, True)
        second = runner.Evidence(self.directory, self.directory / "second", "alpha", context, True)
        first.manifest["status"] = "completed"
        first.save()
        self.assertNotEqual(first.overlay, second.overlay)
        self.assertFalse((self.directory / ".foundry" / "agent-metadata.rehearsal.yaml").exists())
        self.assertEqual(yaml.safe_load(first.overlay.read_text())["environments"]["alpha"]["lastEval"]["status"],
                         "completed")
        self.assertEqual(yaml.safe_load(second.overlay.read_text())["environments"]["alpha"]["lastEval"]["status"],
                         "incomplete")

    def test_no_dataset_reduction_or_threshold_change(self):
        target = self.directory / "exercises" / "evaluation"
        shutil.copytree(ROOT / "exercises" / "evaluation", target)
        data = (target / "eval_set.jsonl").read_text(encoding="utf-8").splitlines()
        (target / "eval_set.jsonl").write_text("\n".join(data[:-1]), encoding="utf-8")
        with self.assertRaisesRegex(runner.GateError, "25"):
            runner.load_inputs(self.directory)
        (target / "eval_set.jsonl").write_text("\n".join(data), encoding="utf-8")
        (target / "gate.yaml").write_text("on_missing: ignore\n", encoding="utf-8")
        with self.assertRaisesRegex(runner.GateError, "gate definition"):
            runner.load_inputs(self.directory)

    def agent(self):
        return {"name": "agent", "version": "7", "definition": {"kind": "prompt", "tools": [{
            "type": "mcp", "project_connection_id": "connection",
            "allowed_tools": ["getSystem", "submitProposal"],
            "require_approval": {"always": {"tool_names": ["submitProposal"]},
                                 "never": {"tool_names": ["getSystem"]}},
        }]}}

    def test_native_agent_requires_safe_immutable_write_policy(self):
        runner.validate_agent(self.agent(), "agent", "7")
        for policy in ("never", None, {"never": {"tool_names": ["submitProposal"]}}):
            agent = self.agent()
            agent["definition"]["tools"][0]["require_approval"] = policy
            with self.assertRaises(runner.GateError):
                runner.validate_agent(agent, "agent", "7")
        with self.assertRaises(runner.GateError):
            runner.validate_agent(self.agent(), "agent", "8")
        agent = self.agent()
        agent["definition"]["tools"][0].update(require_approval="always", allowed_tools=["unknown"])
        with self.assertRaises(runner.GateError):
            runner.validate_agent(agent, "agent", "7")

    def response(self, response_id, output, text="Real SDK-shaped answer", status="completed"):
        payload = {"id": response_id, "status": status, "output": output}
        return SimpleNamespace(model_dump=lambda **_: payload, output_text=text)

    def test_every_save_is_denied_and_query_is_unchanged(self):
        client = Mock()
        client.responses.create.side_effect = [
            self.response("resp_first", [
                {"type": "mcp_approval_request", "id": "request-save", "name": "submitProposal",
                 "arguments": '{"markdown":"exact text"}'},
                {"type": "mcp_approval_request", "id": "request-read", "name": "getSystem", "arguments": "{}"},
            ]),
            self.response("resp_second", [{"type": "mcp_call", "name": "getSystem", "arguments": "{}", "output": "{}"}]),
        ]
        result = runner.invoke(client, self.case, "agent", "7", self.directory / "turn.json", time.monotonic() + 10)
        self.assertEqual(client.responses.create.call_args_list[0].kwargs["input"], self.case["query"])
        self.assertEqual(client.responses.create.call_args_list[0].kwargs["extra_body"]["agent_reference"]["version"], "7")
        continuation = client.responses.create.call_args_list[1].kwargs
        self.assertEqual(continuation["input"], [
            {"type": "mcp_approval_response", "approval_request_id": "request-save", "approve": False},
            {"type": "mcp_approval_response", "approval_request_id": "request-read", "approve": True},
        ])
        self.assertEqual(continuation["previous_response_id"], "resp_first")
        self.assertEqual(result["response_ids"], ["resp_first", "resp_second"])
        self.assertEqual(result["status"], "completed")

    def test_bad_response_or_actual_write_fails_and_persists(self):
        for response in (
            self.response("resp_error", [], status="incomplete"),
            self.response("fabricated", []),
            self.response("resp_write", [{"type": "mcp_call", "name": "submitProposal"}]),
            self.response("resp_error", [{"type": "mcp_call", "name": "getSystem", "error": "failed"}]),
            self.response("resp_empty", [], text=""),
        ):
            client = Mock()
            client.responses.create.return_value = response
            path = self.directory / "failed.json"
            with self.assertRaises(runner.GateError):
                runner.invoke(client, self.case, "agent", "7", path, time.monotonic() + 10)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["status"], "failed")

    def test_approval_loop_and_total_time_are_bounded(self):
        client = Mock()
        client.responses.create.side_effect = [
            self.response(f"resp_{index}", [{"type": "mcp_approval_request", "id": str(index), "name": "submitProposal"}])
            for index in range(20)
        ]
        with self.assertRaisesRegex(runner.GateError, "20 turns"):
            runner.invoke(client, self.case, "agent", "7", self.directory / "loop.json", time.monotonic() + 10)
        with self.assertRaisesRegex(runner.GateError, "deadline"):
            runner.remaining(time.monotonic() - 1)

    def http_error(self, status=429, message="Rate limit exceeded.", headers=None):
        import httpx
        from openai import APIStatusError

        response = httpx.Response(status, headers=headers,
                                  request=httpx.Request("POST", "https://unit-test.invalid/responses"))
        return APIStatusError(message, response=response, body={"error": {"message": message}})

    def test_429_retry_after_success_preserves_approval_continuation_and_persists(self):
        client = Mock()
        client.responses.create.side_effect = [
            self.response("resp_approval", [{"type": "mcp_approval_request", "id": "save", "name": "submitProposal"}]),
            self.http_error(headers={"Retry-After": "8", "x-request-id": "request-throttled"}),
            self.response("resp_completed", []),
        ]
        path = self.directory / "retry-success.json"
        with patch.object(runner.time, "sleep") as sleep:
            turn = runner.invoke(client, self.case, "agent", "7", path, time.monotonic() + 100)
        sleep.assert_called_once_with(8.0)
        failed_request = client.responses.create.call_args_list[1].kwargs
        retried_request = client.responses.create.call_args_list[2].kwargs
        for key in ("input", "previous_response_id", "extra_body", "max_output_tokens"):
            self.assertEqual(failed_request[key], retried_request[key])
        self.assertEqual(retried_request["previous_response_id"], "resp_approval")
        self.assertFalse(retried_request["input"][0]["approve"])
        self.assertEqual(turn["response_ids"], ["resp_approval", "resp_completed"])
        diagnostic = json.loads(path.read_text())["response_create_retries"][0]
        self.assertEqual(diagnostic["delay_source"], "Retry-After")
        self.assertEqual(diagnostic["previous_response_id"], "resp_approval")
        self.assertEqual(diagnostic["request_id"], "request-throttled")
        self.assertEqual(diagnostic["decision"], "retry")

    def test_wrapped_model_429_retries_explicit_delay_but_not_ordinary_400(self):
        client = Mock()
        client.responses.create.side_effect = [
            self.http_error(400, "Model could not be accessed - Received 429 status code from model. "
                            "ModelGateway response: {'statusCode': 429, 'message': "
                            "'Token limit is exceeded. Try again in 8 seconds.'}"),
            self.response("resp_completed", []),
        ]
        with patch.object(runner.time, "sleep") as sleep:
            turn = runner.invoke(client, self.case, "agent", "7",
                                 self.directory / "wrapped-retry.json", time.monotonic() + 100)
        sleep.assert_called_once_with(8.0)
        self.assertEqual(turn["response_create_retries"][0]["delay_source"], "wrapped-model-gateway-message")
        self.assertEqual(turn["response_create_retries"][0]["http_status"], 400)

    def test_429_attempt_exhaustion_fails_with_persisted_diagnostics(self):
        client = Mock()
        client.responses.create.side_effect = self.http_error(headers={"Retry-After": "0"})
        path = self.directory / "retry-exhausted.json"
        with patch.object(runner.time, "sleep"), self.assertRaisesRegex(runner.GateError, "budget exhausted"):
            runner.invoke(client, self.case, "agent", "7", path, time.monotonic() + 100)
        self.assertEqual(client.responses.create.call_count, runner.RESPONSE_CREATE_MAX_ATTEMPTS)
        saved = json.loads(path.read_text())
        self.assertEqual(saved["status"], "failed")
        self.assertEqual(saved["response_ids"], [])
        self.assertEqual(len(saved["response_create_retries"]), runner.RESPONSE_CREATE_MAX_ATTEMPTS)
        self.assertEqual(saved["response_create_retries"][-1]["decision"], "exhausted")

    def test_429_elapsed_budget_does_not_shorten_retry_after_or_issue_extra_call(self):
        for header, deadline in (("301", time.monotonic() + 1000), ("8", time.monotonic() + 1)):
            client = Mock()
            client.responses.create.side_effect = self.http_error(headers={"Retry-After": header})
            with patch.object(runner, "write_json") as evidence_write, patch.object(
                runner.time, "sleep"
            ) as sleep, self.assertRaisesRegex(runner.GateError, "budget exhausted"):
                runner.invoke(client, self.case, "agent", "7", self.directory / "retry-timeout.json", deadline)
            sleep.assert_not_called()
            self.assertEqual(client.responses.create.call_count, 1)
            saved = evidence_write.call_args.args[1]
            self.assertEqual(saved["response_create_retries"][0]["retry_after_seconds"], float(header))

    def test_unrelated_errors_are_reraised_without_retry(self):
        for error in (
            self.http_error(400, "Invalid arguments. Try again in 8 seconds."),
            self.http_error(401, "Unauthorized"),
            self.http_error(500, "Internal server error"),
            RuntimeError("429 text alone is not an SDK rate-limit response"),
        ):
            client = Mock()
            client.responses.create.side_effect = error
            with patch.object(runner.time, "sleep") as sleep, self.assertRaises(type(error)) as raised:
                runner.invoke(client, self.case, "agent", "7", self.directory / "unrelated.json", time.monotonic() + 100)
            self.assertIs(raised.exception, error)
            sleep.assert_not_called()
            self.assertEqual(client.responses.create.call_count, 1)
            self.assertNotIn("response_create_retries", json.loads((self.directory / "unrelated.json").read_text()))

    def test_429_http_date_header_and_header_precedence(self):
        from email.utils import format_datetime
        import datetime as dt

        retry_at = format_datetime(dt.datetime.now(dt.UTC) + dt.timedelta(seconds=60), usegmt=True)
        delay, source = runner.rate_limit_delay(self.http_error(headers={"Retry-After": retry_at}), 1)
        self.assertTrue(58 <= delay <= 60)
        self.assertEqual(source, "Retry-After")
        self.assertEqual(
            runner.rate_limit_delay(self.http_error(message="Try again in 8 seconds.", headers={"Retry-After": "12"}), 1),
            (12.0, "Retry-After"),
        )
        self.assertEqual(
            runner.rate_limit_delay(self.http_error(headers={"Retry-After": "invalid"}), 3),
            (4.0, "bounded-exponential-backoff"),
        )

    def test_late_response_cannot_escape_elapsed_bound(self):
        client = Mock()
        now = [0.0]

        def late_response(**kwargs):
            now[0] = runner.RESPONSE_CREATE_MAX_ELAPSED_SECONDS + 1
            return self.response("resp_late", [])

        client.responses.create.side_effect = late_response
        path = self.directory / "late.json"
        with patch.object(runner.time, "monotonic", side_effect=lambda: now[0]):
            with self.assertRaisesRegex(runner.GateError, "elapsed budget expired"):
                runner.invoke(client, self.case, "agent", "7", path, 1000)
        saved = json.loads(path.read_text())
        self.assertEqual(saved["status"], "failed")
        self.assertEqual(saved["late_response_create_results"][0]["id"], "resp_late")
        self.assertEqual(saved["response_ids"], [])

    def records(self):
        trace = "a" * 32
        return [
            {"operation_Id": trace, "success": True, "customDimensions": {
                "gen_ai.agent.name": "agent", "gen_ai.agent.version": "7", "gen_ai.response.id": "resp_real",
                "gen_ai.operation.name": "invoke_agent"}},
            {"operation_Id": trace, "success": True, "customDimensions": {
                "gen_ai.operation.name": "execute_tool", "gen_ai.tool.name": "getSystem",
                "gen_ai.agent.name": "agent", "gen_ai.agent.version": "7", "gen_ai.response.id": "resp_real"}},
        ]

    def test_native_provenance_requires_response_version_and_same_trace_tool(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{"name": "getSystem", "response_id": "resp_real"}]}
        records = self.records()
        self.assertTrue(runner.match_trace(records, turn, "agent", "7", ["getSystem"])["verified"])
        self.assertIsNone(runner.match_trace(records, turn, "agent", "8", ["getSystem"]))
        self.assertIsNone(runner.match_trace(records[:1], turn, "agent", "7", ["getSystem"]))
        records[1]["operation_Id"] = "b" * 32
        self.assertIsNone(runner.match_trace(records, turn, "agent", "7", ["getSystem"]))
        records = self.records()
        records[0]["customDimensions"]["gen_ai.response.id"] = "resp_stale"
        self.assertIsNone(runner.match_trace(records, turn, "agent", "7", []))
        records = self.records()
        records[1]["success"] = False
        with self.assertRaises(runner.GateError):
            runner.match_trace(records, turn, "agent", "7", [])

    def test_denied_save_is_not_forged_as_executed_provenance(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{"name": "getSystem", "response_id": "resp_real"}]}
        proof = runner.match_trace(self.records(), turn, "agent", "7", ["getSystem", "submitProposal"])
        self.assertNotIn("submitProposal", proof["tool_names"])
        self.assertIn("submitProposal", proof["expected_tool_names"])

    def test_quality_missing_tool_is_not_mislabeled_as_missing_execution_provenance(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [
            {"name": "getSystem", "response_id": "resp_real"},
        ]}
        proof = runner.match_trace(
            self.records(), turn, "agent", "7", ["getSystem", "listInterfaces"],
        )
        self.assertTrue(proof["verified"])
        self.assertEqual(proof["tool_names"], ["getSystem"])
        self.assertEqual(proof["expected_tool_names"], ["getSystem", "listInterfaces"])
        self.assertEqual(proof["missing_expected_tool_names"], ["listInterfaces"])

    def test_exact_native_mcp_prefix_uses_genuine_server_label_and_tool_name(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{
            "name": "findDocumentationGaps", "server_label": "documentation", "response_id": "resp_real",
        }]}
        records = self.records()
        records[1]["customDimensions"]["gen_ai.tool.name"] = "mcp_documentation.findDocumentationGaps"
        proof = runner.match_trace(records, turn, "agent", "7", ["findDocumentationGaps"])
        self.assertTrue(proof["verified"])
        self.assertEqual(proof["tool_names"], ["findDocumentationGaps"])
        self.assertEqual(records[1]["customDimensions"]["gen_ai.tool.name"], "mcp_documentation.findDocumentationGaps")
        for bad_name in ("mcp_untrusted.findDocumentationGaps", "documentation.findDocumentationGaps",
                         "findDocumentationGaps.extra", "mcp_documentation.findDocumentationGaps.extra"):
            records[1]["customDimensions"]["gen_ai.tool.name"] = bad_name
            self.assertIsNone(runner.match_trace(records, turn, "agent", "7", ["findDocumentationGaps"]))
        turn["tool_calls"][0].pop("server_label")
        records[1]["customDimensions"]["gen_ai.tool.name"] = "mcp_documentation.findDocumentationGaps"
        self.assertIsNone(runner.match_trace(records, turn, "agent", "7", ["findDocumentationGaps"]))

    def test_native_tool_requires_matching_response_version_and_execute_tool_operation(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{
            "name": "getSystem", "server_label": "documentation", "response_id": "resp_real",
        }]}
        for key, value in (
            ("gen_ai.response.id", "resp_other"),
            ("gen_ai.agent.version", "8"),
            ("gen_ai.agent.name", "another-agent"),
            ("gen_ai.operation.name", "tools/call"),
        ):
            records = self.records()
            records[1]["customDimensions"]["gen_ai.tool.name"] = "mcp_documentation.getSystem"
            records[1]["customDimensions"][key] = value
            self.assertIsNone(runner.match_trace(records, turn, "agent", "7", ["getSystem"]))
        turn["tool_calls"][0]["response_id"] = "resp_other"
        with self.assertRaisesRegex(runner.GateError, "execution identity"):
            runner.match_trace(self.records(), turn, "agent", "7", ["getSystem"])

    def test_actual_success_strings_are_normalized_without_changing_raw_receipts(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{"name": "getSystem", "response_id": "resp_real"}]}
        records = self.records()
        for record in records:
            record["success"] = "True"
        self.assertTrue(runner.match_trace(records, turn, "agent", "7", ["getSystem"])["verified"])
        self.assertEqual(records[0]["success"], "True")
        for failed in (False, "False", "false", "FALSE"):
            for index in (0, 1):
                bad = copy.deepcopy(records)
                bad[index]["success"] = failed
                with self.assertRaisesRegex(runner.GateError, "failed execution span"):
                    runner.match_trace(bad, turn, "agent", "7", ["getSystem"])
        for unknown in (None, 0, 1, "unknown"):
            records[1]["success"] = unknown
            with self.assertRaisesRegex(runner.GateError, "success status"):
                runner.match_trace(records, turn, "agent", "7", ["getSystem"])

    def test_failed_native_tool_and_transport_errors_remain_rejected(self):
        turn = {"response_ids": ["resp_real"], "tool_calls": [{
            "name": "getSystem", "server_label": "documentation", "response_id": "resp_real",
        }]}
        for operation, tool in (("execute_tool", "mcp_documentation.getSystem"), ("tools/call", "getSystem")):
            records = self.records()
            records[1]["success"] = "True"
            records[1]["customDimensions"].update({
                "gen_ai.operation.name": operation, "gen_ai.tool.name": tool,
                "error.type": "Unprocessable Entity", "error.message": "Tool invocation failed with status code 422",
            })
            with self.assertRaisesRegex(runner.GateError, "failed execution span"):
                runner.match_trace(records, turn, "agent", "7", ["getSystem"])
        records = self.records()
        records.append({"operation_Id": "a" * 32, "name": "GET /mcp", "success": "False",
                        "resultCode": "405", "customDimensions": {}})
        with self.assertRaisesRegex(runner.GateError, "failed execution span"):
            runner.match_trace(records, turn, "agent", "7", ["getSystem"])

    def discovery_records(self, api_type="mcp-backend"):
        records = self.records()
        url = "https://gateway.invalid/docs-mcp/mcp"
        dimensions = {
            "api.type": api_type, "network.protocol.name": "MCP",
            "gen_ai.operation.name": "server/discover",
            "Service Type": "API Management", "Service ID": "test-gateway",
            "error.type": "Bad Request", "error.message": "Method server/discover is not supported.",
        }
        records.append({
            "operation_Id": "a" * 32, "id": "b" * 16, "name": "POST /docs-mcp/mcp",
            "url": url, "success": "False", "resultCode": "400",
            "telemetryTable": "app('test').requests", "customDimensions": dimensions,
        })
        for span, operation in (("c", "initialize"), ("d", "tools/list")):
            record = copy.deepcopy(records[2])
            record.update(id=span * 16, success="True", resultCode="200")
            record["customDimensions"]["gen_ai.operation.name"] = operation
            record["customDimensions"].pop("error.type")
            record["customDimensions"].pop("error.message")
            records.append(record)
        child = {
            "operation_Id": "a" * 32, "id": "e" * 16, "operation_ParentId": "b" * 16,
            "name": "forward-request", "target": "forward-request", "type": "HTTP",
            "data": "REQUEST -", "resultCode": "", "success": "False",
            "telemetryTable": "app('test').dependencies", "customDimensions": {
                "Source": "forward-request", "Service Type": "API Management",
                "Service ID": "test-gateway",
            },
        }
        if api_type == "pass-through-mcp":
            dimensions.pop("error.type")
            dimensions.pop("error.message")
            child.update(name="POST /mcp", target="https://backend.invalid",
                         data="POST - https://backend.invalid/mcp", resultCode="400")
        records.append(child)
        turn = {
            "status": "completed", "response_ids": ["resp_real"],
            "tool_calls": [{"name": "getSystem", "server_label": "docs", "response_id": "resp_real"}],
            "responses": [{"output": [{
                "type": "mcp_list_tools", "server_label": "docs", "tools": [{"name": "getSystem"}],
            }]}],
        }
        return records, turn, {"docs": url}

    def test_recovered_discovery_probe_remains_visible_without_forging_tool_provenance(self):
        for api_type in ("mcp-backend", "pass-through-mcp"):
            with self.subTest(api_type=api_type):
                records, turn, servers = self.discovery_records(api_type)
                before = copy.deepcopy(records)
                proof = runner.match_trace(records, turn, "agent", "7", ["getSystem", "getDocument"],
                                           mcp_servers=servers)
                self.assertTrue(proof["verified"])
                self.assertEqual(proof["missing_expected_tool_names"], ["getDocument"])
                self.assertEqual(len(proof["mcp_discovery_negotiations"]), 2)
                self.assertEqual(proof["mcp_discovery_negotiations"][0]["http_status"], "400")
                self.assertEqual(proof["mcp_discovery_negotiations"][0]["recovery_phases"],
                                 ["initialize", "tools/list"])
                self.assertEqual(records, before)

    def test_discovery_probe_requires_successful_same_endpoint_and_trace_recovery(self):
        mutations = [
            (2, "resultCode", "401"), (2, "resultCode", "403"), (2, "resultCode", "429"),
            (2, "resultCode", "500"), (2, "url", "https://untrusted.invalid/docs-mcp/mcp"),
            (3, "operation_Id", "f" * 32), (3, "success", "False"),
            (4, "operation_Id", "f" * 32), (4, "url", "https://untrusted.invalid/docs-mcp/mcp"),
        ]
        for index, key, value in mutations:
            with self.subTest(index=index, key=key, value=value):
                records, turn, servers = self.discovery_records()
                records[index][key] = value
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
        for key, value in (
            ("gen_ai.operation.name", "tools/call"), ("gen_ai.tool.name", "getSystem"),
            ("error.type", "BackendConnectionFailure"), ("error.message", "Invalid arguments"),
            ("api.type", "http"), ("network.protocol.name", "HTTP"),
        ):
            with self.subTest(dimension=key):
                records, turn, servers = self.discovery_records()
                records[2]["customDimensions"][key] = value
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
        for index in (3, 4):
            records, turn, servers = self.discovery_records()
            records.pop(index)
            with self.assertRaises(runner.GateError):
                runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
        for key, value in (("Service ID", "other-service"), ("api.type", "http"),
                           ("gen_ai.tool.name", "getSystem")):
            records, turn, servers = self.discovery_records()
            records[3]["customDimensions"][key] = value
            with self.assertRaises(runner.GateError):
                runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
        for change in ("incomplete", "no-tools", "wrong-label", "failed-listing"):
            with self.subTest(change=change):
                records, turn, servers = self.discovery_records()
                if change == "incomplete":
                    turn["status"] = "failed"
                else:
                    listing = turn["responses"][0]["output"][0]
                    listing.update({"no-tools": {"tools": []}, "wrong-label": {"server_label": "other"},
                                    "failed-listing": {"error": "failed"}}[change])
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)

    def test_discovery_forwarding_children_require_exact_parent_service_and_http_shape(self):
        for api_type in ("mcp-backend", "pass-through-mcp"):
            for key, value in (
                ("operation_ParentId", "f" * 16), ("resultCode", "500"), ("type", "SQL"),
                ("data", "unrelated request"), ("telemetryTable", "app('test').requests"),
            ):
                with self.subTest(api_type=api_type, key=key):
                    records, turn, servers = self.discovery_records(api_type)
                    records[-1][key] = value
                    with self.assertRaises(runner.GateError):
                        runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
            for key, value in (
                ("Service ID", "other-service"), ("Source", "other-policy"),
                ("error.type", "BackendConnectionFailure"),
            ):
                records, turn, servers = self.discovery_records(api_type)
                records[-1]["customDimensions"][key] = value
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)

    def test_discovery_probe_does_not_hide_real_execution_errors_or_exceptions(self):
        records, turn, servers = self.discovery_records()
        records[1]["success"] = False
        with self.assertRaises(runner.GateError):
            runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)
        records, turn, servers = self.discovery_records()
        exceptions = [{"operation_Id": "a" * 32, "operation_ParentId": "b" * 16,
                       "type": "BackendConnectionFailure"}]
        with self.assertRaisesRegex(runner.GateError, "unclassified execution exception"):
            runner.match_trace(records, turn, "agent", "7", [], exceptions=exceptions, mcp_servers=servers)
        records, turn, servers = self.discovery_records()
        records[1]["customDimensions"]["gen_ai.response.id"] = "other-response"
        self.assertIsNone(runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers))
        records, turn, servers = self.discovery_records()
        records.pop(1)
        self.assertIsNone(runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers))
        records, turn, servers = self.discovery_records()
        failed_call = copy.deepcopy(records[2])
        failed_call["id"] = "f" * 16
        failed_call["customDimensions"]["gen_ai.operation.name"] = "tools/call"
        failed_call["customDimensions"]["gen_ai.tool.name"] = "getSystem"
        records.append(failed_call)
        with self.assertRaises(runner.GateError):
            runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)

    def test_discovery_diagnostics_and_raw_records_survive_success_and_later_failure(self):
        from azure.monitor.query import LogsQueryStatus

        for failed in (False, True):
            with self.subTest(failed=failed):
                records, turn, servers = self.discovery_records()
                if failed:
                    records[1]["success"] = False
                rows = [{**record, "evidence_kind": "span"} for record in records]
                columns = list(dict.fromkeys(key for row in rows for key in row))
                table = SimpleNamespace(columns=columns, rows=[[row.get(key) for key in columns] for row in rows])
                logs = Mock()
                logs.query_workspace.return_value = SimpleNamespace(status=LogsQueryStatus.SUCCESS, tables=[table])
                args = SimpleNamespace(
                    app_insights_resource_id="/subscriptions/s/resourceGroups/g/providers/Microsoft.Insights/components/a",
                    workspace_id=str(uuid.uuid4()), started_at="2026-10-29T00:00:00Z",
                    trace_timeout_seconds=1, agent_name="agent", agent_version="7",
                    declared_mcp_servers=servers,
                )
                path = self.directory / f"discovery-{failed}.json"
                with redirect_stdout(io.StringIO()):
                    if failed:
                        with self.assertRaises(runner.GateError):
                            runner.verify_trace(logs, args, turn, self.case, path, time.monotonic() + 5)
                    else:
                        runner.verify_trace(logs, args, turn, self.case, path, time.monotonic() + 5)
                saved = json.loads(path.read_text())
                self.assertEqual(saved["verified"], not failed)
                self.assertEqual(len(saved["mcp_discovery_negotiations"]), 2)
                self.assertEqual(saved["records"], [
                    {key: row.get(key) for key in columns} for row in rows
                ])

    def test_discovery_session_url_must_match_declared_endpoint_and_uuid_only(self):
        session = "?sessionId=00000000-0000-0000-0000-000000000001"
        records, turn, servers = self.discovery_records()
        records[2]["url"] += session
        self.assertTrue(runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)["verified"])
        for suffix in ("?sessionId=unknown", session + "&extra=1", session + "#other"):
            records, turn, servers = self.discovery_records()
            records[2]["url"] += suffix
            with self.assertRaises(runner.GateError):
                runner.match_trace(records, turn, "agent", "7", [], mcp_servers=servers)

    def mcp_phase_records(self, operation="initialize"):
        records = self.records()
        url = "https://gateway.invalid/docs-mcp/mcp"
        records.extend([
            {"operation_Id": "a" * 32, "id": "b" * 16, "name": "POST /docs-mcp/mcp",
             "url": url, "success": "True", "resultCode": "200",
             "telemetryTable": "app('test').requests", "customDimensions": {
                 "api.type": "mcp-backend", "network.protocol.name": "MCP",
                 "gen_ai.operation.name": operation, "gen_ai.tool.name": "getSystem",
                 "Service Type": "API Management", "Service ID": "test-gateway"}},
            {"operation_Id": "a" * 32, "id": "c" * 16, "operation_ParentId": "b" * 16,
             "name": "forward-request", "target": "forward-request", "type": "HTTP",
             "data": "REQUEST -", "resultCode": "", "success": "False",
             "telemetryTable": "app('test').dependencies", "customDimensions": {
                 "Source": "forward-request", "Service Type": "API Management",
                 "Service ID": "test-gateway"}},
        ])
        turn = {"status": "completed", "response_ids": ["resp_real"], "tool_calls": [{
            "name": "getSystem", "server_label": "docs", "response_id": "resp_real",
        }]}
        return records, turn, {"docs": url}

    def test_proven_native_mcp_policy_phase_is_not_a_failed_backend_execution(self):
        for operation, status in (
            ("initialize", "200"), ("tools/list", "200"),
            ("tools/call", "200"), ("notifications/initialized", "202"),
        ):
            with self.subTest(operation=operation):
                records, turn, servers = self.mcp_phase_records(operation)
                records[-2]["resultCode"] = status
                before = copy.deepcopy(records)
                proof = runner.match_trace(records, turn, "agent", "7", ["getSystem"], mcp_servers=servers)
                self.assertTrue(proof["verified"])
                self.assertEqual(proof["native_mcp_forwarding_markers"][0]["span_id"], "c" * 16)
                self.assertEqual(proof["native_mcp_forwarding_markers"][0]["mcp_operation"], operation)
                self.assertEqual(records, before)

    def test_mcp_marker_cannot_hide_failed_unknown_or_unrelated_backend_spans(self):
        mutations = [
            (0, "success", "False"), (0, "resultCode", "422"),
            (0, "url", "https://untrusted.invalid/mcp"),
            (1, "target", "https://backend.invalid"), (1, "resultCode", "500"),
            (1, "data", "REQUEST - GET https://backend.invalid"), (1, "type", "SQL"),
            (1, "operation_ParentId", "d" * 16),
        ]
        for index, key, value in mutations:
            with self.subTest(key=key, value=value):
                records, turn, servers = self.mcp_phase_records()
                records[-2 + index][key] = value
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", ["getSystem"], mcp_servers=servers)
        for index, key, value in (
            (0, "api.type", "http"), (0, "network.protocol.name", "HTTP"),
            (0, "gen_ai.operation.name", "unknown"), (0, "Service ID", "another-gateway"),
            (1, "Source", "other-policy"), (1, "error.type", "BackendConnectionFailure"),
        ):
            with self.subTest(dimension=key, value=value):
                records, turn, servers = self.mcp_phase_records()
                records[-2 + index]["customDimensions"][key] = value
                with self.assertRaises(runner.GateError):
                    runner.match_trace(records, turn, "agent", "7", ["getSystem"], mcp_servers=servers)

    def test_mcp_marker_keeps_real_tool_failures_exceptions_and_omissions_visible(self):
        records, turn, servers = self.mcp_phase_records("tools/call")
        records[-2]["customDimensions"]["gen_ai.tool.name"] = "unobservedTool"
        with self.assertRaises(runner.GateError):
            runner.match_trace(records, turn, "agent", "7", ["getSystem"], mcp_servers=servers)
        records, turn, servers = self.mcp_phase_records()
        records[1]["success"] = False
        with self.assertRaises(runner.GateError):
            runner.match_trace(records, turn, "agent", "7", ["getSystem"], mcp_servers=servers)
        records, turn, servers = self.mcp_phase_records()
        exceptions = [{"operation_Id": "a" * 32, "operation_ParentId": "c" * 16,
                       "type": "BackendConnectionFailure"}]
        with self.assertRaisesRegex(runner.GateError, "unclassified execution exception"):
            runner.match_trace(records, turn, "agent", "7", ["getSystem"],
                               exceptions=exceptions, mcp_servers=servers)
        records, turn, servers = self.mcp_phase_records()
        proof = runner.match_trace(records, turn, "agent", "7", ["getSystem", "getDocument"],
                                   mcp_servers=servers)
        self.assertEqual(proof["missing_expected_tool_names"], ["getDocument"])

    def test_repeated_legacy_http_ids_do_not_alias_native_span_ids_or_hide_failures(self):
        turn = {"status": "completed", "response_ids": ["resp_real"],
                "tool_calls": [{"name": "getSystem", "response_id": "resp_real"}]}
        records = self.records()
        legacy = {"operation_Id": "a" * 32, "id": "c" * 32, "success": True,
                  "customDimensions": {}, "type": "HTTP"}
        records.extend(({**legacy, "name": "GET identity-configuration"}, {**legacy, "name": "POST token"}))
        proof = runner.match_trace(records, turn, "agent", "7", ["getSystem"])
        self.assertTrue(proof["verified"])
        self.assertEqual(len(records), 4)
        records[-1]["success"] = False
        with self.assertRaisesRegex(runner.GateError, "failed execution span"):
            runner.match_trace(records, turn, "agent", "7", ["getSystem"])

    def test_ambiguous_native_spans_are_preserved_before_classification_fails(self):
        from azure.monitor.query import LogsQueryStatus

        record = {"operation_Id": "a" * 32, "id": "b" * 16,
                  "success": True, "customDimensions": {}, "evidence_kind": "span"}
        records = [record, dict(record)]
        columns = list(record)
        table = SimpleNamespace(columns=columns, rows=[[row[key] for key in columns] for row in records])
        logs = Mock()
        logs.query_workspace.return_value = SimpleNamespace(status=LogsQueryStatus.SUCCESS, tables=[table])
        args = SimpleNamespace(
            app_insights_resource_id="/subscriptions/s/resourceGroups/g/providers/Microsoft.Insights/components/a",
            workspace_id=str(uuid.uuid4()), started_at="2026-10-29T00:00:00Z",
            trace_timeout_seconds=1, agent_name="agent", agent_version="7",
        )
        path = self.directory / "ambiguous-trace.json"
        with redirect_stdout(io.StringIO()), self.assertRaisesRegex(runner.GateError, "ambiguous duplicate"):
            runner.verify_trace(logs, args, {"status": "completed", "response_ids": ["resp_real"],
                                          "tool_calls": []}, self.case, path, time.monotonic() + 5)
        saved = json.loads(path.read_text())
        self.assertFalse(saved["verified"])
        self.assertEqual(saved["records"], records)

    def test_partial_log_query_never_passes(self):
        from azure.monitor.query import LogsQueryStatus
        logs = Mock()
        logs.query_workspace.return_value = SimpleNamespace(status=LogsQueryStatus.PARTIAL)
        args = SimpleNamespace(
            app_insights_resource_id="/subscriptions/s/resourceGroups/g/providers/Microsoft.Insights/components/a",
            workspace_id=str(uuid.uuid4()), started_at="2026-10-29T00:00:00Z",
            trace_timeout_seconds=1, agent_name="agent", agent_version="7",
        )
        with self.assertRaisesRegex(runner.GateError, "partial"):
            runner.verify_trace(logs, args, {"response_ids": ["resp_real"]}, self.case,
                                self.directory / "trace.json", time.monotonic() + 5)
        self.assertFalse(json.loads((self.directory / "trace.json").read_text())["verified"])

    def test_actual_kql_is_emitted_and_flushed_before_query_execution(self):
        from azure.monitor.query import LogsQueryStatus

        output = io.StringIO()
        args = SimpleNamespace(
            app_insights_resource_id="/subscriptions/s/resourceGroups/g/providers/Microsoft.Insights/components/a",
            workspace_id=str(uuid.uuid4()), started_at="2026-10-29T00:00:00Z",
            trace_timeout_seconds=1, agent_name="agent", agent_version="7",
        )
        logs = Mock()

        def query_workspace(workspace, query, **kwargs):
            self.assertEqual(workspace, args.workspace_id)
            self.assertIn(f"```kql\n{query}\n```", output.getvalue())
            output.flush.assert_called()
            return SimpleNamespace(status=LogsQueryStatus.PARTIAL)

        logs.query_workspace.side_effect = query_workspace
        with patch.object(output, "flush", wraps=output.flush), redirect_stdout(output), patch.object(runner, "write_json") as persist:
            with self.assertRaisesRegex(runner.GateError, "partial"):
                runner.verify_trace(logs, args, {"response_ids": ["resp_real"]}, self.case,
                                    self.directory / "emitted-trace.json", time.monotonic() + 5)
        persisted = persist.call_args.args[1]
        self.assertIn(persisted["query"], output.getvalue())

    def test_workspace_query_qualifies_application_tables_and_preserves_predicates(self):
        from azure.monitor.query import LogsQueryStatus

        resource = "/subscriptions/s/resourceGroups/g/providers/Microsoft.Insights/components/a"
        args = SimpleNamespace(
            app_insights_resource_id=resource, workspace_id=str(uuid.uuid4()),
            started_at="2026-10-29T00:00:00Z", trace_timeout_seconds=1,
            agent_name="agent", agent_version="7",
        )
        logs = Mock()
        logs.query_workspace.return_value = SimpleNamespace(status=LogsQueryStatus.PARTIAL)
        with patch.object(runner, "write_json"), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(runner.GateError, "partial"):
                runner.verify_trace(logs, args, {"response_ids": ["resp_real"]}, self.case,
                                    self.directory / "qualified-trace.json", time.monotonic() + 5)
        workspace, query = logs.query_workspace.call_args.args
        self.assertEqual(workspace, args.workspace_id)
        encoded = json.dumps(resource)
        self.assertEqual(query, f"""let spans = materialize(union withsource=telemetryTable app({encoded}).requests, app({encoded}).dependencies
| where timestamp >= datetime(2026-10-29T00:00:00Z)
| where _ResourceId =~ {encoded}
| project timestamp, name, operation_Id, operation_ParentId, id, success, customDimensions, telemetryTable, _ResourceId,
    evidence_kind="span",
    resultCode=column_ifexists("resultCode", ""), type=column_ifexists("type", ""),
    target=column_ifexists("target", ""), data=column_ifexists("data", ""), url=column_ifexists("url", ""));
let operations = spans
| where tostring(customDimensions["gen_ai.response.id"]) in (dynamic(["resp_real"]))
    or tostring(customDimensions["azure.ai.agentserver.response_id"]) in (dynamic(["resp_real"]))
| distinct operation_Id;
union (spans | where operation_Id in (operations)),
    (app({encoded}).exceptions
    | where timestamp >= datetime(2026-10-29T00:00:00Z)
    | where _ResourceId =~ {encoded}
    | where operation_Id in (operations)
    | project timestamp, operation_Id, operation_ParentId, type, outerMessage, innermostMessage,
        details, customDimensions, _ResourceId, evidence_kind="exception")""")

    def outputs(self):
        row = {"id": "qa-01", "query": "query", "resp_id": "resp_real"}
        output = {"datasource_item": row.copy(), "results": [{
            "name": "task_adherence", "score": 4, "passed": True, "reason": "supported",
        }]}
        return row, output

    def test_remote_scores_reject_missing_duplicate_boolean_nan_or_other_identity(self):
        row, output = self.outputs()
        self.assertEqual(runner.task_scores([output], [row]), [4.0])
        for score in (None, True, float("nan"), 0, 6):
            bad = copy.deepcopy(output)
            bad["results"][0]["score"] = score
            with self.assertRaises(runner.GateError):
                runner.task_scores([bad], [row])
        with self.assertRaises(runner.GateError):
            runner.task_scores([output, output], [row, row])
        bad = copy.deepcopy(output)
        bad["datasource_item"]["resp_id"] = "resp_cached"
        with self.assertRaises(runner.GateError):
            runner.task_scores([bad], [row])
        self.assertEqual(runner.remote_clusters([{"results": [{"passed": None, "reason": None}]}]).keys(), {"remote_unresolved"})

    def test_ids_are_persisted_before_run_creation_failure(self):
        evidence = runner.Evidence(self.directory, self.directory / ".foundry" / "results" / "run", "local-test",
                                   {"agent_version": "7"})
        suite = {"tier": "smoke", "status": "incomplete"}
        evidence.manifest["suites"].append(suite)
        client = Mock()
        client.post.side_effect = [SimpleNamespace(id="eval_genuine"), RuntimeError("run creation failed")]
        args = SimpleNamespace(agent_name="agent", agent_version="7", judge_deployment="actual-judge")
        with self.assertRaisesRegex(RuntimeError, "creation failed"):
            runner.evaluate(client, args, [{"id": "qa-01", "query": "q", "resp_id": "resp_real"}],
                            suite, evidence, time.monotonic() + 10)
        manifest = json.loads((evidence.destination / "manifest.json").read_text(encoding="utf-8"))
        metadata = yaml.safe_load(evidence.overlay.read_text(encoding="utf-8"))
        self.assertEqual(manifest["suites"][0]["evaluation_id"], "eval_genuine")
        self.assertEqual(metadata["environments"]["local-test"]["lastEval"]["evalId"], "eval_genuine")
        criterion = client.post.call_args_list[0].kwargs["body"]["testing_criteria"][0]
        self.assertEqual(criterion["evaluator_name"], "builtin.task_adherence")
        self.assertEqual(criterion["evaluator_version"], "2")
        self.assertEqual(criterion["data_mapping"], {"query": "{{item.query}}", "response": "{{sample.output_items}}"})

    def test_remote_outputs_and_ids_survive_failed_terminal_state(self):
        evidence = runner.Evidence(self.directory, self.directory / ".foundry" / "results" / "run", "local-test",
                                   {"agent_version": "7"})
        suite = {"tier": "regression", "status": "incomplete"}
        evidence.manifest["suites"].append(suite)
        client = Mock()
        client.post.side_effect = [SimpleNamespace(id="eval_real"), SimpleNamespace(id="run_real")]
        client.evals.runs.retrieve.return_value = SimpleNamespace(
            status="cancelled", model_dump=lambda **_: {"status": "cancelled"})
        client.evals.runs.output_items.list.return_value = SimpleNamespace(
            data=[], has_next_page=lambda: False)
        args = SimpleNamespace(agent_name="agent", agent_version="7", judge_deployment="actual-judge", eval_timeout_seconds=10)
        with patch.object(runner.time, "monotonic", return_value=100), self.assertRaisesRegex(
            runner.GateError, "cancelled"
        ):
            runner.evaluate(client, args, [], suite, evidence, 110)
        metadata = yaml.safe_load(evidence.overlay.read_text(encoding="utf-8"))
        self.assertEqual(metadata["environments"]["local-test"]["lastEval"]["evalRunId"], "run_real")
        self.assertTrue((evidence.destination / "regression" / "remote-run.json").exists())
        self.assertTrue((evidence.destination / "regression" / "remote-output-items.json").exists())

    def test_completed_remote_run_downloads_all_pages_and_preserves_input_mapping(self):
        evidence = runner.Evidence(self.directory, self.directory / ".foundry" / "results" / "run", "local-test",
                                   {"agent_version": "7"})
        suite = {"tier": "smoke", "status": "incomplete"}
        evidence.manifest["suites"].append(suite)
        client = Mock()
        client.post.side_effect = [SimpleNamespace(id="eval_real"), SimpleNamespace(id="run_real")]
        client.evals.runs.retrieve.return_value = SimpleNamespace(
            status="completed", model_dump=lambda **_: {"status": "completed"})
        row, output = self.outputs()
        item = SimpleNamespace(model_dump=lambda **_: output)
        last_page = SimpleNamespace(data=[item], has_next_page=lambda: False)
        first_page = SimpleNamespace(data=[], has_next_page=lambda: True, get_next_page=lambda: last_page)
        client.evals.runs.output_items.list.return_value = first_page
        args = SimpleNamespace(agent_name="agent", agent_version="7", judge_deployment="actual-judge", eval_timeout_seconds=10)
        with patch.object(runner.time, "monotonic", return_value=100):
            outputs = runner.evaluate(client, args, [row], suite, evidence, 110)
        self.assertEqual(outputs, [output])
        request = client.post.call_args_list[1].kwargs["body"]["data_source"]
        params = request["item_generation_params"]
        self.assertEqual(params["type"], "response_retrieval")
        self.assertEqual(params["data_mapping"], {"response_id": "{{item.resp_id}}"})
        self.assertEqual(params["source"]["content"], [{"item": row}])
        self.assertEqual(json.loads((evidence.destination / "smoke" / "remote-output-items.json").read_text()), [output])

    def cli(self):
        shutil.copytree(ROOT / "exercises" / "evaluation", self.directory / "exercises" / "evaluation")
        return [
            "--project-endpoint", "https://aif-ai-lab-r1029a.services.ai.azure.com/api/projects/alpha",
            "--agent-name", "agent", "--agent-version", "7", "--judge-deployment", "actual-judge",
            "--app-insights-resource-id", "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Insights/components/app",
            "--workspace-id", str(uuid.uuid4()), "--scenario-root", str(self.directory),
            "--environment", "local-test", "--timeout-seconds", "1",
        ]

    def test_hard_timeout_terminates_only_worker_and_marks_failed(self):
        import subprocess
        process = Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired("worker", 1), -1]
        with patch.object(runner.subprocess, "Popen", return_value=process):
            self.assertEqual(runner.main(self.cli()), 1)
        process.kill.assert_called_once_with()
        manifests = list((self.directory / ".foundry" / "results").glob("*\\manifest.json"))
        manifest = json.loads(manifests[0].read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertFalse(manifest["release_accepted"])
        self.assertIn("Hard overall deadline", manifest["failure_clusters"]["runner"][0])

    def test_successful_process_exit_is_not_acceptance_without_both_suites(self):
        process = Mock()
        process.wait.return_value = 0
        with patch.object(runner.subprocess, "Popen", return_value=process):
            self.assertEqual(runner.main(self.cli()), 1)
        manifest = json.loads(next((self.directory / ".foundry" / "results").glob("*\\manifest.json")).read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertFalse(manifest["release_accepted"])

    def test_operator_cancellation_terminates_worker_and_never_accepts(self):
        process = Mock()
        process.wait.side_effect = [KeyboardInterrupt(), -1]
        with patch.object(runner.subprocess, "Popen", return_value=process):
            self.assertEqual(runner.main(self.cli()), 1)
        process.kill.assert_called_once_with()
        manifest = json.loads(next((self.directory / ".foundry" / "results").glob("*\\manifest.json")).read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertIn("cancelled", manifest["failure_clusters"]["runner"][0])

    def test_original_template_rubric_and_precedence(self):
        evaluator = TemplateComplianceEvaluator()
        self.assertIsNone(evaluator(category="qa", response="answer")["template_compliance"])
        self.assertEqual(evaluator(category="draft", response="no document")["template_compliance"], 0.0)
        markdown = (ROOT / "data" / "docs" / "ARCH-TEL.md").read_text(encoding="utf-8")
        self.assertEqual(evaluator(category="draft", response=markdown)["template_compliance"], 1.0)
        calls = [{"name": "docs__validateDocument", "arguments": json.dumps({"markdown": markdown})}]
        self.assertEqual(find_document("answer", calls), (markdown, "validateDocument"))
        calls.append({"name": "submitProposal", "arguments": json.dumps({"markdown": "invalid"})})
        self.assertEqual(find_document(markdown, calls), ("invalid", "submitProposal"))
        wrapped = "````markdown\n" + markdown + "\n````\nignored commentary"
        self.assertEqual(extract_markdown_document(wrapped).strip(), markdown.strip())


if __name__ == "__main__":
    unittest.main()
