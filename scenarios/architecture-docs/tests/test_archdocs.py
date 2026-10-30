"""Unit tests for the shared docs logic. Run: python -m unittest discover -s tests"""

import datetime as dt
import tempfile
import unittest
from pathlib import Path

from archdocs import (
    DocsService,
    Forbidden,
    Inventory,
    LocalStore,
    ProposalRejected,
    validate_document,
)
from archdocs.store import seed_published

ROOT = Path(__file__).resolve().parents[1]
REF = dt.date(2026, 11, 1)


def make_service():
    store = LocalStore(tempfile.mkdtemp())
    seed_published(store, ROOT / "data" / "docs")
    return DocsService(
        store, Inventory(ROOT / "data" / "inventory"), ROOT / "data" / "standard", REF
    )


class StandardTests(unittest.TestCase):
    def test_reference_document_is_valid(self):
        md = (ROOT / "data" / "docs" / "ARCH-TEL.md").read_text(encoding="utf-8")
        self.assertTrue(validate_document(md, REF).valid)

    def test_template_has_all_sections(self):
        md = (ROOT / "data" / "standard" / "architecture-doc-template.md").read_text(
            encoding="utf-8"
        )
        r = validate_document(md, REF)
        self.assertFalse(any("Section" in e for e in r.errors), r.errors)

    def test_secret_is_an_error(self):
        md = (ROOT / "tests" / "fixtures" / "generated" / "remote-diagnostics-agent.md").read_text(
            encoding="utf-8"
        )
        r = validate_document(md, REF)
        self.assertTrue(any("credential" in e for e in r.errors))

    def test_missing_mermaid(self):
        md = (ROOT / "data" / "docs" / "ARCH-ASR.md").read_text(encoding="utf-8")
        self.assertTrue(any("Mermaid" in e for e in validate_document(md, REF).errors))


class GapTests(unittest.TestCase):
    def setUp(self):
        self.gaps = make_service().find_gaps()

    def has(self, gap_type, system_id, interface_id=None):
        return any(
            g["gap_type"] == gap_type
            and g["system_id"] == system_id
            and (interface_id is None or g.get("interface_id") == interface_id)
            for g in self.gaps
        )

    def test_planted_defects(self):
        self.assertTrue(self.has("missing_document", "SYS-008"))
        self.assertTrue(self.has("missing_document", "SYS-011"))
        self.assertTrue(self.has("missing_document", "SYS-012"))
        self.assertTrue(self.has("stale_review", "SYS-002"))
        self.assertTrue(self.has("stale_review", "SYS-010"))
        self.assertTrue(self.has("decommissioned_interface_in_doc", "SYS-002", "INT-007"))
        self.assertTrue(self.has("interface_missing_in_doc", "SYS-002", "INT-011"))
        self.assertTrue(self.has("interface_missing_in_doc", "SYS-002", "INT-018"))
        self.assertTrue(self.has("owner_mismatch", "SYS-004"))
        self.assertTrue(self.has("interface_missing_in_doc", "SYS-004", "INT-019"))
        self.assertTrue(self.has("template_noncompliance", "SYS-003"))
        self.assertTrue(self.has("template_noncompliance", "SYS-005"))
        self.assertTrue(self.has("decommissioned_system_documented", "SYS-013"))

    def test_clean_documents_have_no_gaps(self):
        for sid in ("SYS-001", "SYS-006", "SYS-007", "SYS-009"):
            self.assertFalse([g for g in self.gaps if g["system_id"] == sid], sid)


class ProposalTests(unittest.TestCase):
    def setUp(self):
        self.svc = make_service()

    def test_valid_proposal_is_pending_review(self):
        md = (ROOT / "tests" / "fixtures" / "generated" / "product-configurator.md").read_text(encoding="utf-8")
        r = self.svc.submit_proposal(
            system_id="SYS-011",
            markdown=md,
            summary="First version",
            team="team1",
            author_type="coding-agent",
            source="test",
        )
        self.assertEqual(r["status"], "pending-review")
        self.assertEqual(r["doc_id"], "ARCH-CFG")
        self.assertEqual(len(self.svc.list_proposals(team="team1")), 1)

    def test_secret_rejected_and_not_stored(self):
        md = (ROOT / "tests" / "fixtures" / "generated" / "remote-diagnostics-agent.md").read_text(
            encoding="utf-8"
        )
        with self.assertRaises(ProposalRejected):
            self.svc.submit_proposal(system_id="SYS-012", markdown=md, summary="x", team="team2")
        self.assertEqual(self.svc.list_proposals(team="team2"), [])

    def test_invalid_proposal_needs_changes(self):
        md = (ROOT / "tests" / "fixtures" / "generated" / "erp-core.md").read_text(encoding="utf-8")
        r = self.svc.submit_proposal(system_id="SYS-008", markdown=md, summary="x", team="team3")
        self.assertEqual(r["status"], "needs-changes")
        self.assertTrue(any("INT-020" in e for e in r["validation"]["errors"]))

    def test_publish_requires_librarian(self):
        md = (ROOT / "tests" / "fixtures" / "generated" / "product-configurator.md").read_text(encoding="utf-8")
        pid = self.svc.submit_proposal(system_id="SYS-011", markdown=md, summary="x", team="team1")[
            "proposal_id"
        ]
        with self.assertRaises(Forbidden):
            self.svc.publish_proposal(pid, publisher_role=None)
        r = self.svc.publish_proposal(pid, publisher_role="librarian", reviewer="test")
        self.assertEqual(r["status"], "published")
        doc = self.svc.get_document("ARCH-CFG")
        self.assertEqual(doc["status"], "published")
        self.assertFalse(
            [
                g
                for g in self.svc.find_gaps()
                if g["system_id"] == "SYS-011" and g["gap_type"] == "missing_document"
            ]
        )

    def test_bad_team_name(self):
        with self.assertRaises(ValueError):
            self.svc.submit_proposal(system_id="SYS-011", markdown="x", summary="x", team="../etc")


class InventoryTests(unittest.TestCase):
    def test_expected_interfaces_include_via(self):
        inv = Inventory(ROOT / "data" / "inventory")
        self.assertEqual(
            inv.expected_interface_ids("SYS-010"),
            ["INT-003", "INT-004", "INT-009", "INT-010", "INT-011", "INT-014"],
        )
        self.assertNotIn("INT-007", inv.expected_interface_ids("SYS-002"))


if __name__ == "__main__":
    unittest.main()
