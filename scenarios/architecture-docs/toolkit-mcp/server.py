"""Existing MCP toolkit for M2; participants add their own separate server in B2.

Three read-only helper tools that complement the Docs API tools:

- generate_context_diagram(system_id)  Mermaid context diagram from the inventory
- lint_document(markdown)              check a draft against the documentation standard
- compare_with_inventory(markdown)     what a document gets wrong compared with the inventory

Transport: streamable HTTP on port 8080, path /mcp (stateless, so it scales and sits behind APIM).

Run from this directory after installing the backend and requirements.txt:
               python server.py                       -> http://localhost:8080/mcp
Environment:   INVENTORY_DIR (default data/inventory in the repo), REFERENCE_DATE (YYYY-MM-DD,
               default today), REVIEW_MAX_AGE_DAYS (default 365), HOST (0.0.0.0), PORT (8080).

The tool logic is plain Python (importable and testable without the mcp package); the
FastMCP server is built only in build_server().
"""

import datetime as dt
import os
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

from archdocs import DocsService, Inventory, find_gaps, interface_ids_in_table, parse_document
from docs_api.config import Settings, build_store

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent

SERVER_NAME = "architecture-doc-tools"
SERVER_INSTRUCTIONS = (
    "Helper tools for {organization_name} architecture documents. All lab business data is synthetic. "
    "Use generate_context_diagram for the Context "
    "section, lint_document to check a draft against the documentation standard and compare_with_inventory "
    "to find interfaces, owners and lifecycle facts that disagree with the system inventory. "
    "These tools never store or publish anything."
)
HIGHLIGHT_CLASS = "classDef this fill:#0078D4,color:#ffffff"


# ----- configuration --------------------------------------------------------------------
def inventory_dir() -> Path:
    """INVENTORY_DIR if set (absolute, relative to the working directory or to the repo root), else data/inventory."""
    value = os.getenv("INVENTORY_DIR")
    if not value:
        return REPO_ROOT / "data" / "inventory"
    path = Path(value)
    if not path.is_absolute() and not path.exists() and (REPO_ROOT / path).exists():
        return REPO_ROOT / path
    return path


def reference_date() -> dt.date | None:
    value = os.getenv("REFERENCE_DATE", "").strip()
    return dt.date.fromisoformat(value) if value else None


def review_max_age_days() -> int:
    return int(os.getenv("REVIEW_MAX_AGE_DAYS") or 365)


@lru_cache(maxsize=1)
def get_inventory() -> Inventory:
    return Inventory(inventory_dir())


def get_service() -> DocsService:
    settings = Settings.from_env()
    settings.check()
    return DocsService(
        build_store(settings),
        get_inventory(),
        settings.standard_dir,
        reference_date(),
        review_max_age_days(),
        organization_name=settings.organization_name,
    )


# ----- diagram ------------------------------------------------------------------------------
def _node_id(system_id: str) -> str:
    return system_id.replace("-", "")


def _node(inv: Inventory, system_id: str) -> str:
    name = (inv.system_name(system_id) or "Unknown system").replace('"', "#quot;")
    return f'{_node_id(system_id)}["{name} ({system_id})"]'


def _edge(source: str, target: str, label: str, planned: bool) -> str:
    a, b = _node_id(source), _node_id(target)
    if planned:
        return f'    {a} -. "{label}" .-> {b}'
    return f'    {a} -- "{label}" --> {b}'


def context_diagram(inv: Inventory, system_id: str) -> str:
    """Mermaid 'flowchart LR' source for one system, following section 3 of the documentation standard.

    Active interfaces are solid arrows, planned ones dashed, decommissioned ones are left out.
    Edges are labelled with the interface ID ("via <platform>" when routed through an integration
    platform). When the system itself is the integration route, the interface is drawn through it.
    """
    system = inv.system(system_id)
    if not system:
        raise ValueError(f"System {system_id} not found in the inventory. Use an ID like SYS-002.")
    lines = ["flowchart LR", f"    {_node(inv, system_id)}:::this"]
    if system["status"] == "decommissioned":
        lines.append(f"    %% {system_id} is decommissioned; its interfaces are not shown")
    declared = {system_id}
    edges: list[str] = []
    for i in inv.interfaces_for(system_id):
        if i["status"] not in ("active", "planned"):
            continue
        planned = i["status"] == "planned"
        label = i["interface_id"] + (" (planned)" if planned else "")
        via = i.get("via")
        for sid in (i["source"], i["target"]):
            if sid not in declared:
                lines.append(f"    {_node(inv, sid)}")
                declared.add(sid)
        if via == system_id:
            edges.append(_edge(i["source"], system_id, label, planned))
            edges.append(_edge(system_id, i["target"], label, planned))
        else:
            if via:
                label += f" via {inv.system_name(via) or via}"
            edges.append(_edge(i["source"], i["target"], label, planned))
    lines.extend(edges)
    lines.append(f"    {HIGHLIGHT_CLASS}")
    return "\n".join(lines)


# ----- MCP tools (plain functions; registered in build_server) --------------------------
def generate_context_diagram(system_id: str) -> str:
    """Generate the Mermaid context diagram for one system from the system inventory.

    Use it when drafting or fixing the Context section of an architecture document.
    Returns a fenced ```mermaid block (flowchart LR) ready to paste: the system is highlighted
    (class "this"), neighbours are nodes "Name (SYS-NNN)", active interfaces are solid arrows
    and planned interfaces dashed arrows, each labelled with its INT-NNN ID. Decommissioned
    interfaces are omitted.

    Args:
        system_id: System ID in the format SYS-NNN, e.g. SYS-011.
    """
    return "```mermaid\n" + context_diagram(get_inventory(), system_id.strip().upper()) + "\n```"


def lint_document(markdown: str) -> dict[str, Any]:
    """Check an architecture document draft against the documentation standard and the inventory.

    Use it on every draft before proposing it. Checks front matter (doc_id ARCH-XXX, system_id
    SYS-NNN, owner_team, status, version, last_reviewed, classification), required sections and
    their order, the Mermaid diagram in Context, the Interfaces table (INT-NNN IDs, missing active,
    decommissioned or unknown interfaces), owner team and credentials. Stores nothing.
    Returns {valid, errors[], warnings[], metadata}; fix every error.

    Args:
        markdown: The complete document, starting with the YAML front matter block (--- ... ---).
    """
    return get_service().validate(markdown)


def compare_with_inventory(markdown: str) -> dict[str, Any]:
    """Compare an architecture document with the system inventory and list what disagrees.

    Use it to check whether a published or drafted document is still true. Returns the system
    from the front matter (system_id SYS-NNN) and: missing_active_interfaces (INT-NNN active in
    the inventory but not in the Interfaces table), decommissioned_interfaces_listed,
    unknown_interfaces_listed, planned_interfaces_not_listed (optional to document),
    owner_mismatch, stale_review, lifecycle problems, the full list of gaps and up_to_date.

    Args:
        markdown: The complete document, starting with the YAML front matter block (--- ... ---).
    """
    inv = get_inventory()
    meta, _body, sections = parse_document(markdown)
    system_id = str(meta.get("system_id") or "").strip()
    if not system_id:
        raise ValueError(
            "The front matter has no system_id (format SYS-NNN), so the document cannot be compared."
        )
    system = inv.system(system_id)
    if not system:
        raise ValueError(
            f"system_id {system_id} from the front matter does not exist in the inventory."
        )
    doc_id = str(meta.get("doc_id") or "DRAFT")
    ref = reference_date() or dt.date.today()
    gaps = find_gaps(inv, {doc_id: markdown}, ref, review_max_age_days(), system_id)
    gaps = [g for g in gaps if g["gap_type"] != "missing_document"]

    listed = interface_ids_in_table(sections.get("Interfaces", ""))
    unknown = sorted({i for i in listed if not inv.interface(i)})
    planned_ids = {i["interface_id"] for i in inv.interfaces_for(system_id, status="planned")}

    def describe(interface_id: str) -> dict[str, Any]:
        i = inv.enrich_interface(inv.interface(interface_id) or {})
        return {
            k: i.get(k)
            for k in (
                "interface_id",
                "name",
                "source",
                "source_name",
                "target",
                "target_name",
                "via",
                "via_name",
                "pattern",
                "status",
            )
        }

    missing = [
        describe(g["interface_id"]) for g in gaps if g["gap_type"] == "interface_missing_in_doc"
    ]
    decommissioned = [
        describe(g["interface_id"])
        for g in gaps
        if g["gap_type"] == "decommissioned_interface_in_doc"
    ]
    owner_doc = meta.get("owner_team")
    lifecycle = [g["detail"] for g in gaps if g["gap_type"] == "decommissioned_system_documented"]
    return {
        "system_id": system_id,
        "system_name": system["name"],
        "system_status": system["status"],
        "doc_id": meta.get("doc_id"),
        "owner_team_inventory": system["owner_team"],
        "owner_team_document": owner_doc,
        "owner_mismatch": bool(owner_doc) and owner_doc != system["owner_team"],
        "missing_active_interfaces": missing,
        "decommissioned_interfaces_listed": decommissioned,
        "unknown_interfaces_listed": unknown,
        "planned_interfaces_not_listed": sorted(planned_ids - set(listed)),
        "stale_review": any(g["gap_type"] == "stale_review" for g in gaps),
        "lifecycle_problems": lifecycle,
        "gaps": gaps,
        "up_to_date": not gaps and not unknown,
    }


TOOLS = (generate_context_diagram, lint_document, compare_with_inventory)


# ----- server ---------------------------------------------------------------------------------
def build_server() -> Any:
    """Create the FastMCP server (needs the 'mcp' package) and register the tools."""
    from mcp.server.fastmcp import FastMCP

    settings = Settings.from_env()
    settings.check()
    server = FastMCP(
        SERVER_NAME,
        instructions=SERVER_INSTRUCTIONS.format(organization_name=settings.organization_name),
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8080")),
        stateless_http=True,
    )
    for tool in TOOLS:
        server.tool()(tool)
    return server


def main() -> int:
    import uvicorn

    uvicorn.run(
        "app:create_app",
        factory=True,
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8080")),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
