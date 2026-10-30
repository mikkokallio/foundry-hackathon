"""Compare published documents with the inventory and report documentation gaps."""

from __future__ import annotations

import datetime as dt
from typing import Any

from .inventory import Inventory
from .standard import interface_ids_in_table, parse_document, validate_document


def find_gaps(
    inventory: Inventory,
    published: dict[str, str],
    reference_date: dt.date,
    review_max_age_days: int = 365,
    system_id: str | None = None,
) -> list[dict[str, Any]]:
    """published maps doc_id -> markdown of currently published documents."""
    gaps: list[dict[str, Any]] = []
    docs_by_system: dict[str, list[tuple[str, dict[str, Any], dict[str, str], str]]] = {}
    for doc_id, md in published.items():
        meta, _body, sections = parse_document(md)
        sid = str(meta.get("system_id", ""))
        docs_by_system.setdefault(sid, []).append((doc_id, meta, sections, md))

    decommissioned = inventory.decommissioned_interface_ids()
    for s in inventory.systems:
        sid = s["system_id"]
        if system_id and sid != system_id:
            continue
        docs = docs_by_system.get(sid, [])
        if not docs:
            if s["status"] in ("active", "pilot"):
                gaps.append(
                    {
                        "gap_type": "missing_document",
                        "system_id": sid,
                        "system_name": s["name"],
                        "doc_id": None,
                        "severity": "high" if s["status"] == "active" else "medium",
                        "detail": f"{s['name']} ({s['status']}) has no published architecture document.",
                    }
                )
            continue
        for doc_id, meta, sections, md in docs:
            if s["status"] == "decommissioned":
                if meta.get("status") != "archived":
                    gaps.append(
                        {
                            "gap_type": "decommissioned_system_documented",
                            "system_id": sid,
                            "system_name": s["name"],
                            "doc_id": doc_id,
                            "severity": "medium",
                            "detail": f"{doc_id} is '{meta.get('status')}' but {s['name']} was decommissioned"
                            f"{' on ' + s['decommissioned_on'] if s.get('decommissioned_on') else ''}. Archive the document.",
                        }
                    )
                continue
            result = validate_document(md, reference_date, review_max_age_days)
            if result.errors:
                gaps.append(
                    {
                        "gap_type": "template_noncompliance",
                        "system_id": sid,
                        "system_name": s["name"],
                        "doc_id": doc_id,
                        "severity": "medium",
                        "detail": "; ".join(result.errors),
                    }
                )
            reviewed = meta.get("last_reviewed")
            if reviewed:
                try:
                    age = (reference_date - dt.date.fromisoformat(str(reviewed))).days
                    if age > review_max_age_days:
                        gaps.append(
                            {
                                "gap_type": "stale_review",
                                "system_id": sid,
                                "system_name": s["name"],
                                "doc_id": doc_id,
                                "severity": "medium",
                                "detail": f"{doc_id} was last reviewed {reviewed} ({age} days ago; limit {review_max_age_days}).",
                            }
                        )
                except ValueError:
                    pass
            if meta.get("owner_team") and meta["owner_team"] != s["owner_team"]:
                gaps.append(
                    {
                        "gap_type": "owner_mismatch",
                        "system_id": sid,
                        "system_name": s["name"],
                        "doc_id": doc_id,
                        "severity": "low",
                        "detail": f"{doc_id} names owner '{meta['owner_team']}' but the inventory owner is '{s['owner_team']}'.",
                    }
                )
            documented = set(interface_ids_in_table(sections.get("Interfaces", "")))
            for iid in inventory.expected_interface_ids(sid):
                if iid not in documented:
                    i = inventory.interface(iid)
                    gaps.append(
                        {
                            "gap_type": "interface_missing_in_doc",
                            "system_id": sid,
                            "system_name": s["name"],
                            "doc_id": doc_id,
                            "severity": "medium",
                            "interface_id": iid,
                            "detail": f"Active interface {iid} '{i['name']}' is not in the Interfaces table of {doc_id}.",
                        }
                    )
            for iid in sorted(documented & decommissioned):
                gaps.append(
                    {
                        "gap_type": "decommissioned_interface_in_doc",
                        "system_id": sid,
                        "system_name": s["name"],
                        "doc_id": doc_id,
                        "severity": "medium",
                        "interface_id": iid,
                        "detail": f"{doc_id} lists {iid}, which is decommissioned. Remove it and note it in the change log.",
                    }
                )
    return gaps
