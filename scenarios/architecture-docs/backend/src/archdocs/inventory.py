"""Read-only access to the synthetic system inventory (data/inventory/*.json)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class Inventory:
    def __init__(self, inventory_dir: str | Path):
        d = Path(inventory_dir)
        self.systems: list[dict[str, Any]] = json.loads(
            (d / "systems.json").read_text(encoding="utf-8")
        )
        self.interfaces: list[dict[str, Any]] = json.loads(
            (d / "interfaces.json").read_text(encoding="utf-8")
        )
        self.data_products: list[dict[str, Any]] = json.loads(
            (d / "data_products.json").read_text(encoding="utf-8")
        )
        teams_file = d / "teams.json"
        self.teams: list[dict[str, Any]] = (
            json.loads(teams_file.read_text(encoding="utf-8")) if teams_file.exists() else []
        )
        self._sys = {s["system_id"]: s for s in self.systems}
        self._int = {i["interface_id"]: i for i in self.interfaces}
        self._dp = {p["data_product_id"]: p for p in self.data_products}

    # --- lookups -------------------------------------------------------
    def system(self, system_id: str) -> dict[str, Any] | None:
        return self._sys.get(system_id)

    def system_name(self, system_id: str | None) -> str | None:
        s = self._sys.get(system_id or "")
        return s["name"] if s else None

    def interface(self, interface_id: str) -> dict[str, Any] | None:
        return self._int.get(interface_id)

    def data_product(self, dp_id: str) -> dict[str, Any] | None:
        return self._dp.get(dp_id)

    def list_systems(
        self, domain: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        out = self.systems
        if domain:
            out = [s for s in out if s["domain"].lower() == domain.lower()]
        if status:
            out = [s for s in out if s["status"].lower() == status.lower()]
        return out

    def interfaces_for(
        self, system_id: str, status: str | None = None, include_via: bool = True
    ) -> list[dict[str, Any]]:
        out = []
        for i in self.interfaces:
            touches = (
                i["source"] == system_id
                or i["target"] == system_id
                or (include_via and i.get("via") == system_id)
            )
            if touches and (status is None or i["status"] == status):
                out.append(i)
        return out

    def list_interfaces(
        self, system_id: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        if system_id:
            return self.interfaces_for(system_id, status)
        return [i for i in self.interfaces if status is None or i["status"] == status]

    def list_data_products(self, domain: str | None = None) -> list[dict[str, Any]]:
        if not domain:
            return self.data_products
        return [p for p in self.data_products if p["domain"].lower() == domain.lower()]

    def data_products_for(self, system_id: str) -> list[dict[str, Any]]:
        out = []
        for p in self.data_products:
            role = None
            if system_id in p.get("source_systems", []):
                role = "produces"
            elif system_id in p.get("consumers", []):
                role = "consumes"
            if role:
                out.append({**p, "role": role})
        return out

    def expected_interface_ids(self, system_id: str) -> list[str]:
        """Active interfaces that must appear in the system's document (source, target or via)."""
        return sorted(i["interface_id"] for i in self.interfaces_for(system_id, status="active"))

    def decommissioned_interface_ids(self) -> set[str]:
        return {i["interface_id"] for i in self.interfaces if i["status"] == "decommissioned"}

    def enrich_interface(self, i: dict[str, Any]) -> dict[str, Any]:
        return {
            **i,
            "source_name": self.system_name(i["source"]),
            "target_name": self.system_name(i["target"]),
            "via_name": self.system_name(i.get("via")),
        }

    def system_detail(self, system_id: str) -> dict[str, Any] | None:
        s = self.system(system_id)
        if not s:
            return None
        team = next((t for t in self.teams if t["owner_team"] == s["owner_team"]), None)
        return {
            **s,
            "owner_contact": team.get("contact") if team else None,
            "interfaces": [self.enrich_interface(i) for i in self.interfaces_for(system_id)],
            "data_products": self.data_products_for(system_id),
        }
