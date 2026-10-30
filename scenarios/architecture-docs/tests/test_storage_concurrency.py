import datetime as dt
from pathlib import Path
from unittest.mock import patch

import pytest
from archdocs import DocsService, Inventory
from archdocs.store import LocalStore, StoreConflict

ROOT = Path(__file__).resolve().parents[1]


def service(tmp_path):
    return DocsService(
        LocalStore(tmp_path),
        Inventory(ROOT / "data" / "inventory"),
        ROOT / "data" / "standard",
        dt.date(2026, 11, 1),
    )


def test_exclusive_create_never_overwrites(tmp_path):
    store = LocalStore(tmp_path)
    assert store.create("proposals/team1/one.json", "first")
    assert not store.create("proposals/team1/one.json", "second")
    assert store.read("proposals/team1/one.json") == "first"


def test_stale_compare_and_swap_rejected(tmp_path):
    store = LocalStore(tmp_path)
    store.write("published/ARCH-CFG.md", "old")
    _, version = store.snapshot("published/ARCH-CFG.md")
    store.replace_version("published/ARCH-CFG.md", "new", version)
    with pytest.raises(StoreConflict):
        store.replace_version("published/ARCH-CFG.md", "lost update", version)
    assert store.read("published/ARCH-CFG.md") == "new"


def test_colliding_proposal_ids_do_not_replace_content(tmp_path):
    svc = service(tmp_path)
    markdown = (ROOT / "tests" / "fixtures" / "generated" / "product-configurator.md").read_text(encoding="utf-8")
    with (
        patch("archdocs.service.secrets.token_hex", return_value="aaaa"),
        patch("archdocs.service.dt") as clock,
    ):
        clock.UTC = dt.UTC
        clock.datetime.now.return_value = dt.datetime(2026, 11, 1, tzinfo=dt.UTC)
        first = svc.submit_proposal(
            system_id="SYS-011", markdown=markdown, summary="first", team="team1"
        )
        with pytest.raises(RuntimeError, match="unique proposal"):
            svc.submit_proposal(
                system_id="SYS-011", markdown=markdown, summary="second", team="team1"
            )
    assert svc.get_proposal(first["proposal_id"])["summary"] == "first"


def test_stale_approved_proposal_cannot_replace_new_content(tmp_path):
    svc = service(tmp_path)
    markdown = (ROOT / "tests" / "fixtures" / "generated" / "product-configurator.md").read_text(encoding="utf-8")
    first = svc.submit_proposal(
        system_id="SYS-011", markdown=markdown, summary="first", team="team1"
    )
    second = svc.submit_proposal(
        system_id="SYS-011",
        markdown=markdown + "\nDifferent approved content.\n",
        summary="second",
        team="team2",
    )
    svc.publish_proposal(first["proposal_id"], publisher_role="librarian")
    with pytest.raises(StoreConflict, match="stale"):
        svc.publish_proposal(second["proposal_id"], publisher_role="librarian")
    assert "Different approved content" not in svc.get_document("ARCH-CFG")["markdown"]
    assert svc.get_proposal(second["proposal_id"])["status"] == "pending-review"
