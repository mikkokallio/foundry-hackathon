"""Offline tests of exact-fixture consent and persistent synthetic attempt limits."""
from __future__ import annotations

import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import verify_proposal_save as save


class SaveTests(unittest.TestCase):
    def setUp(self):
        output = save.REPO / "out"
        output.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="unit-save-", dir=output)
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.ledger = self.directory / "session-attempts.json"
        self.turn = {"responses": [], "response_ids": [], "tool_calls": [], "approvals": []}
        self.binding = {"agent_name": "unit-only", "agent_version": "1"}
        self.arguments = {"markdown": "unit-only exact content", "source": "unit-only"}

    def response(self, identifier, output):
        response = Mock()
        response.model_dump.return_value = {"id": identifier, "status": "completed", "output": output}
        return response

    def approval(self, name="submitProposal", arguments=None, server="docs"):
        return {"type": "mcp_approval_request", "name": name, "server_label": server,
                "id": "unit-approval", "arguments": json.dumps(arguments or self.arguments)}

    def invoke(self, client, *, validated_at=None):
        with patch.object(save.sys.stdin, "isatty", return_value=True), patch(
            "builtins.input", side_effect=lambda prompt: prompt.split("type ", 1)[1][:-2]
        ), patch("builtins.print"):
            return save.invoke_exact(
                client, self.binding, "submitProposal", self.arguments, self.turn,
                self.directory / "turn.json", time.monotonic() + 30,
                ledger=self.ledger, authorization={"unit_only": True},
                validated_at=time.monotonic() if validated_at is None else validated_at,
            )

    def test_limit_is_persistent_and_the_101st_attempt_is_rejected(self):
        identifiers = {save.reserve_attempt(self.ledger, {"unit_only": True}) for _ in range(100)}
        self.assertEqual(len(identifiers), 100)
        with self.assertRaisesRegex(ValueError, "100"):
            save.reserve_attempt(self.ledger, {"unit_only": True})
        self.assertEqual(len(json.loads(self.ledger.read_text())["attempts"]), 100)
        self.assertFalse(self.ledger.with_suffix(".json.lock").exists())

    def test_invalid_or_locked_ledger_is_not_reset_or_retried(self):
        self.ledger.write_text('{"limit": 200, "attempts": []}')
        with self.assertRaises(ValueError):
            save.reserve_attempt(self.ledger, {})
        self.assertEqual(json.loads(self.ledger.read_text())["limit"], 200)
        lock = self.ledger.with_suffix(".json.lock")
        lock.write_text("another process")
        with self.assertRaises(FileExistsError):
            save.reserve_attempt(self.ledger, {})
        self.assertTrue(lock.exists())

    def test_exact_approval_is_reserved_before_the_only_write_continuation(self):
        client = Mock()
        result = {"proposal_id": "unit-only", "status": "pending-review", "team": "alpha"}
        client.responses.create.side_effect = [
            self.response("resp_unit_approval", [self.approval()]),
            self.response("resp_unit_saved", [{"type": "mcp_call", "name": "submitProposal",
                                              "server_label": "docs", "arguments": json.dumps(self.arguments),
                                              "output": json.dumps(result)}]),
        ]
        self.assertEqual(self.invoke(client), result)
        self.assertEqual(client.responses.create.call_count, 2)
        self.assertEqual(len(json.loads(self.ledger.read_text())["attempts"]), 1)
        self.assertTrue(client.responses.create.call_args_list[1].kwargs["input"][0]["approve"])
        self.assertTrue(self.turn["human_consent_verified"])

    def test_absent_noninteractive_or_inexact_human_consent_never_reserves_or_continues(self):
        for interactive, answer in ((False, ""), (True, ""), (True, "y"), (True, "approve wrong")):
            with self.subTest(interactive=interactive, answer=answer):
                client = Mock()
                client.responses.create.return_value = self.response("resp_unit_consent", [self.approval()])
                turn = {"responses": [], "response_ids": [], "tool_calls": [], "approvals": []}
                with patch.object(save.sys.stdin, "isatty", return_value=interactive), patch(
                    "builtins.input", return_value=answer
                ), patch("builtins.print"), self.assertRaises(ValueError):
                    save.invoke_exact(client, self.binding, "submitProposal", self.arguments, turn,
                                      self.directory / "consent.json", time.monotonic() + 30,
                                      ledger=self.ledger, authorization={"unit_only": True},
                                      validated_at=time.monotonic())
                self.assertEqual(client.responses.create.call_count, 1)
                self.assertFalse(self.ledger.exists())

    def test_readback_cannot_authorize_unrelated_reads_or_writes(self):
        for request in (self.approval(name="getDocument"), self.approval()):
            with self.subTest(name=request["name"]):
                client = Mock()
                client.responses.create.return_value = self.response("resp_unit_read", [request])
                turn = {"responses": [], "response_ids": [], "tool_calls": [], "approvals": []}
                with self.assertRaises(ValueError):
                    save.invoke_exact(client, self.binding, "getProposal", {"proposal_id": "unit-only"}, turn,
                                      self.directory / "read.json", time.monotonic() + 30,
                                      ledger=self.ledger, authorization={"unit_only": True})
                self.assertEqual(client.responses.create.call_count, 1)
                self.assertFalse(self.ledger.exists())

    def test_expiry_while_human_decides_never_reserves_or_continues(self):
        client = Mock()
        client.responses.create.return_value = self.response("resp_unit_expiry", [self.approval()])
        with patch.object(save.time, "monotonic", side_effect=[100, 100, 100, 100, 401]), self.assertRaisesRegex(
            ValueError, "expired while waiting"
        ):
            self.invoke(client, validated_at=100)
        self.assertEqual(client.responses.create.call_count, 1)
        self.assertFalse(self.ledger.exists())

    def test_verify_redacts_uncertain_write_errors_and_never_replays(self):
        pack = {"team": "alpha", "project_endpoint": "https://unit.invalid"}
        binding = {**self.binding, "definition": {"definition": {}}}
        project = Mock()
        project.agents.get_version.return_value.as_dict.return_value = {"definition": {}}
        project.__enter__ = Mock(return_value=project)
        project.__exit__ = Mock(return_value=False)
        client = Mock()
        client.__enter__ = Mock(return_value=client)
        client.__exit__ = Mock(return_value=False)
        project.get_openai_client.return_value = client

        def invoke(_client, _binding, operation, _arguments, turn, *_args, **_kwargs):
            if operation == "validateDocument":
                return {"valid": True}
            self.assertEqual(operation, "submitProposal")
            turn["write_attempt_id"] = "unit-reserved"
            raise TimeoutError("unit-private-text Bearer unit-secret")

        with patch("azure.ai.projects.AIProjectClient", return_value=project), patch.object(
            save.gate, "validate_agent"
        ), patch.object(save, "invoke_exact", side_effect=invoke) as calls, patch(
            "builtins.print"
        ) as output, self.assertRaises(ValueError) as raised:
            save.verify(pack, binding, Mock(), self.directory / "uncertain", self.ledger, 30)
        self.assertEqual(calls.call_count, 2)
        self.assertNotIn("unit-secret", str(raised.exception))
        self.assertNotIn("unit-private-text", str(output.call_args_list))
        evidence = json.loads((self.directory / "uncertain" / "save-verification.json").read_text())
        self.assertEqual(evidence["status"], "failed")
        self.assertTrue(evidence["uncertain_write_requires_read_only_reconciliation"])
        self.assertNotIn("saved", evidence)

    def test_ambiguous_write_failure_is_not_retried_and_reservation_survives(self):
        client = Mock()
        client.responses.create.side_effect = [
            self.response("resp_unit_approval", [self.approval()]), TimeoutError("unit-only uncertain write")]
        with self.assertRaises(TimeoutError):
            self.invoke(client)
        self.assertEqual(client.responses.create.call_count, 2)
        self.assertIn("write_attempt_id", self.turn)
        self.assertEqual(len(json.loads(self.ledger.read_text())["attempts"]), 1)

    def test_modified_expired_cross_server_or_publication_requests_never_get_approved(self):
        cases = [
            (self.approval(arguments={"markdown": "changed"}), time.monotonic()),
            (self.approval(server="other-server"), time.monotonic()),
            (self.approval(name="publishProposal"), time.monotonic()),
            (self.approval(), time.monotonic() - 301),
        ]
        for request, validated_at in cases:
            with self.subTest(request=request):
                client = Mock()
                client.responses.create.return_value = self.response("resp_unit_request", [request])
                self.turn = {"responses": [], "response_ids": [], "tool_calls": [], "approvals": []}
                with self.assertRaises(ValueError):
                    self.invoke(client, validated_at=validated_at)
                self.assertEqual(client.responses.create.call_count, 1)
                self.assertFalse(self.ledger.exists())

    def test_duplicate_write_requests_never_reserve_an_attempt(self):
        client = Mock()
        client.responses.create.return_value = self.response("resp_unit_duplicate", [self.approval(), self.approval()])
        with self.assertRaisesRegex(ValueError, "Multiple"):
            self.invoke(client)
        self.assertFalse(self.ledger.exists())

    def test_removing_only_the_final_newline_never_gets_approved(self):
        self.arguments["markdown"] += "\n"
        changed = {**self.arguments, "markdown": self.arguments["markdown"][:-1]}
        client = Mock()
        client.responses.create.return_value = self.response(
            "resp_unit_trimmed", [self.approval(arguments=changed)])
        with self.assertRaisesRegex(ValueError, "exact unexpired"):
            self.invoke(client)
        self.assertEqual(client.responses.create.call_count, 1)
        self.assertFalse(self.ledger.exists())

    def test_native_tool_result_must_be_real_json_and_not_an_mcp_error(self):
        self.assertEqual(save.tool_result({"name": "validateDocument", "output": json.dumps({
            "content": [{"type": "text", "text": '{"valid":true}'}], "isError": False})}), {"valid": True})
        for output in ("trust me, valid", '{"isError":true,"content":[]}'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                save.tool_result({"name": "validateDocument", "output": output})
        with self.assertRaises(ValueError) as raised:
            save.tool_result({"name": "submitProposal", "error": "Bearer unit-secret"})
        self.assertNotIn("unit-secret", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
