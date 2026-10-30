"""Business operations of the Docs API, independent of the web framework."""

from __future__ import annotations

import datetime as dt
import json
import re
import secrets
from html import escape
from pathlib import Path
from typing import Any

from .gaps import find_gaps
from .inventory import Inventory
from .standard import (
    REQUIRED_FIELDS,
    REQUIRED_SECTIONS,
    find_secrets,
    interface_ids_in_table,
    parse_document,
    validate_document,
)
from .store import DocStore, StoreConflict, keys_with_suffix

TEAM_RE = re.compile(r"^[a-z0-9][a-z0-9\-]{0,31}$")
AUTHOR_TYPES = {"agent", "human", "coding-agent"}


class NotFound(Exception):
    pass


class Forbidden(Exception):
    pass


class ProposalRejected(Exception):
    def __init__(self, message: str, findings: list[str]):
        super().__init__(message)
        self.findings = findings


class DocsService:
    def __init__(
        self,
        store: DocStore,
        inventory: Inventory,
        standard_dir: str | Path | None = None,
        reference_date: dt.date | None = None,
        review_max_age_days: int = 365,
        organization_name: str | None = None,
    ):
        self.store = store
        self.inventory = inventory
        self.standard_dir = Path(standard_dir) if standard_dir else None
        self._reference_date = reference_date
        self.review_max_age_days = review_max_age_days
        self.organization_name = organization_name

    @property
    def reference_date(self) -> dt.date:
        return self._reference_date or dt.date.today()

    # ----- documents -----------------------------------------------------
    def _published(self) -> dict[str, str]:
        out = {}
        for key in keys_with_suffix(self.store.list("published/"), ".md"):
            md = self.store.read(key)
            if md is not None:
                out[key.split("/")[-1][:-3]] = md
        return out

    @staticmethod
    def _summary(doc_id: str, meta: dict[str, Any]) -> dict[str, Any]:
        return {
            "doc_id": meta.get("doc_id", doc_id),
            "title": meta.get("title"),
            "system_id": meta.get("system_id"),
            "owner_team": meta.get("owner_team"),
            "status": meta.get("status"),
            "version": meta.get("version"),
            "last_reviewed": meta.get("last_reviewed"),
            "classification": meta.get("classification"),
        }

    def list_documents(
        self, system_id: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        out = []
        for doc_id, md in sorted(self._published().items()):
            meta, _, _ = parse_document(md)
            s = self._summary(doc_id, meta)
            if system_id and s["system_id"] != system_id:
                continue
            if status and s["status"] != status:
                continue
            out.append(s)
        return out

    def get_document(self, doc_id: str) -> dict[str, Any]:
        md = self.store.read(f"published/{doc_id}.md")
        if md is None:
            raise NotFound(f"Document {doc_id} not found")
        meta, _, sections = parse_document(md)
        return {**self._summary(doc_id, meta), "sections": list(sections.keys()), "markdown": md}

    # ----- inventory -----------------------------------------------------
    def list_systems(
        self, domain: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        docs = self._doc_ids_by_system()
        return [
            {**s, "doc_ids": docs.get(s["system_id"], [])}
            for s in self.inventory.list_systems(domain, status)
        ]

    def _doc_ids_by_system(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for doc_id, md in self._published().items():
            meta, _, _ = parse_document(md)
            out.setdefault(str(meta.get("system_id")), []).append(doc_id)
        return out

    def get_system(self, system_id: str) -> dict[str, Any]:
        d = self.inventory.system_detail(system_id)
        if not d:
            raise NotFound(f"System {system_id} not found")
        d["doc_ids"] = self._doc_ids_by_system().get(system_id, [])
        d["expected_interface_ids"] = self.inventory.expected_interface_ids(system_id)
        return d

    def list_interfaces(
        self, system_id: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        return [
            self.inventory.enrich_interface(i)
            for i in self.inventory.list_interfaces(system_id, status)
        ]

    def list_data_products(self, domain: str | None = None) -> list[dict[str, Any]]:
        return self.inventory.list_data_products(domain)

    def find_gaps(self, system_id: str | None = None) -> list[dict[str, Any]]:
        return find_gaps(
            self.inventory,
            self._published(),
            self.reference_date,
            self.review_max_age_days,
            system_id,
        )

    # ----- standard --------------------------------------------------------
    def get_standard(self) -> dict[str, Any]:
        std = tmpl = ""
        if self.standard_dir:
            p = self.standard_dir / "documentation-standard.md"
            t = self.standard_dir / "architecture-doc-template.md"
            std = p.read_text(encoding="utf-8") if p.exists() else ""
            tmpl = t.read_text(encoding="utf-8") if t.exists() else ""
        if "{{organization_name}}" in std or "{{organization_name}}" in tmpl:
            if not self.organization_name:
                raise ValueError("An organization name is required to render the documentation standard")
            name = re.sub(r"([\\`*_\[\]|])", r"\\\1", escape(self.organization_name, quote=False))
            std = std.replace("{{organization_name}}", name)
            tmpl = tmpl.replace("{{organization_name}}", name)
        return {
            "standard_markdown": std,
            "template_markdown": tmpl,
            "required_sections": REQUIRED_SECTIONS,
            "required_fields": REQUIRED_FIELDS,
        }

    def validate(self, markdown: str) -> dict[str, Any]:
        result = validate_document(markdown, self.reference_date, self.review_max_age_days)
        d = result.to_dict()
        sid = result.metadata.get("system_id")
        if sid and not self.inventory.system(str(sid)):
            d["errors"].append(f"system_id {sid} does not exist in the inventory.")
            d["valid"] = False
        elif sid:
            s = self.inventory.system(str(sid))
            owner = result.metadata.get("owner_team")
            if owner and owner != s["owner_team"]:
                d["warnings"].append(
                    f"owner_team '{owner}' differs from the inventory owner '{s['owner_team']}'."
                )
            if s["status"] != "decommissioned":
                _meta, _body, sections = parse_document(markdown)
                listed = set(interface_ids_in_table(sections.get("Interfaces", "")))
                missing = [
                    i for i in self.inventory.expected_interface_ids(str(sid)) if i not in listed
                ]
                if missing:
                    d["warnings"].append(
                        "Active interfaces missing from the Interfaces table: " + ", ".join(missing)
                    )
                stale = sorted(listed & self.inventory.decommissioned_interface_ids())
                if stale:
                    d["errors"].append(
                        "Decommissioned interfaces listed in the Interfaces table: "
                        + ", ".join(stale)
                        + ". Remove them and mention them in the change log."
                    )
                    d["valid"] = False
                unknown = sorted(i for i in listed if not self.inventory.interface(i))
                if unknown:
                    d["errors"].append("Unknown interface IDs: " + ", ".join(unknown))
                    d["valid"] = False
        return d

    # ----- proposals -------------------------------------------------------
    @staticmethod
    def _clean_team(team: str | None) -> str:
        t = (team or "local").strip().lower().replace(" ", "-")
        if not TEAM_RE.match(t):
            raise ValueError("team must be 1-32 characters: lower-case letters, digits and hyphens")
        return t

    def submit_proposal(
        self,
        *,
        system_id: str,
        markdown: str,
        summary: str,
        author_type: str = "agent",
        doc_id: str | None = None,
        source: str | None = None,
        team: str | None = None,
    ) -> dict[str, Any]:
        team = self._clean_team(team)
        if author_type not in AUTHOR_TYPES:
            raise ValueError(f"author_type must be one of {sorted(AUTHOR_TYPES)}")
        if not self.inventory.system(system_id):
            raise NotFound(f"System {system_id} not found")
        secrets_found = find_secrets(markdown)
        if secrets_found:
            raise ProposalRejected(
                "The document contains what looks like a credential. Remove it and submit again.",
                secrets_found,
            )
        validation = self.validate(markdown)
        meta_doc = validation["metadata"].get("doc_id")
        doc_id = doc_id or (str(meta_doc) if meta_doc else None)
        if doc_id and meta_doc and str(meta_doc) != doc_id:
            validation["errors"].append(
                f"doc_id in front matter ({meta_doc}) differs from the doc_id argument ({doc_id})."
            )
            validation["valid"] = False
        if (
            validation["metadata"].get("system_id")
            and validation["metadata"]["system_id"] != system_id
        ):
            validation["errors"].append(
                f"system_id in front matter ({validation['metadata']['system_id']}) differs from {system_id}."
            )
            validation["valid"] = False
        now = dt.datetime.now(dt.UTC)
        proposal_id = f"P-{now:%Y%m%d%H%M%S}-{team}-{secrets.token_hex(2)}"
        status = "pending-review" if validation["valid"] else "needs-changes"
        record = {
            "proposal_id": proposal_id,
            "team": team,
            "system_id": system_id,
            "doc_id": doc_id,
            "summary": summary,
            "author_type": author_type,
            "source": source,
            "status": status,
            "created_at": now.isoformat(timespec="seconds"),
            "validation": validation,
            "markdown": markdown,
            "base_version": self.store.snapshot(f"published/{doc_id}.md")[1],
        }
        key = f"proposals/{team}/{proposal_id}.json"
        for _ in range(20):
            if self.store.create(key, json.dumps(record, ensure_ascii=False, indent=2)):
                break
            proposal_id = f"P-{now:%Y%m%d%H%M%S}-{team}-{secrets.token_hex(2)}"
            record["proposal_id"] = proposal_id
            key = f"proposals/{team}/{proposal_id}.json"
        else:
            raise RuntimeError(
                "Could not allocate a unique proposal ID; no proposal was overwritten."
            )
        return {
            "proposal_id": proposal_id,
            "status": status,
            "doc_id": doc_id,
            "team": team,
            "validation": validation,
            "stored_at": key,
        }

    def _proposal_keys(self, team: str | None = None) -> list[str]:
        prefix = f"proposals/{self._clean_team(team)}/" if team else "proposals/"
        return keys_with_suffix(self.store.list(prefix), ".json")

    def list_proposals(
        self, team: str | None = None, status: str | None = None
    ) -> list[dict[str, Any]]:
        out = []
        for key in self._proposal_keys(team):
            raw = self.store.read(key)
            if not raw:
                continue
            r = json.loads(raw)
            if status and r.get("status") != status:
                continue
            out.append(
                {
                    k: r.get(k)
                    for k in (
                        "proposal_id",
                        "team",
                        "system_id",
                        "doc_id",
                        "summary",
                        "author_type",
                        "source",
                        "status",
                        "created_at",
                    )
                }
                | {"valid": r.get("validation", {}).get("valid")}
            )
        return sorted(out, key=lambda r: r["created_at"] or "", reverse=True)

    def _find_proposal_key(self, proposal_id: str) -> str:
        for key in self._proposal_keys():
            if key.endswith(f"/{proposal_id}.json"):
                return key
        raise NotFound(f"Proposal {proposal_id} not found")

    def get_proposal(self, proposal_id: str) -> dict[str, Any]:
        return json.loads(self.store.read(self._find_proposal_key(proposal_id)) or "{}")

    def publish_proposal(
        self, proposal_id: str, publisher_role: str | None, reviewer: str | None = None
    ) -> dict[str, Any]:
        if (publisher_role or "").lower() != "librarian":
            raise Forbidden(
                "Publishing requires the librarian role. Agents submit proposals; the librarian publishes them."
            )
        key = self._find_proposal_key(proposal_id)
        record = json.loads(self.store.read(key) or "{}")
        if record.get("status") != "pending-review":
            raise ValueError(
                f"Only pending-review proposals can be published (status is {record.get('status')})."
            )
        doc_id = record.get("doc_id")
        if not doc_id:
            raise ValueError("The proposal has no doc_id.")
        md = record["markdown"]
        meta, _, _ = parse_document(md)
        if meta.get("status") == "draft":
            md = md.replace("status: draft", "status: published", 1)
        previous, version = self.store.snapshot(f"published/{doc_id}.md")
        if previous != md:
            if "base_version" not in record or record["base_version"] != version:
                raise StoreConflict("The proposal is stale. Review and approve a new proposal.")
            if previous is not None:
                prev_meta, _, _ = parse_document(previous)
                archive_key = f"archive/{doc_id}/{prev_meta.get('version', 'unknown')}.md"
                if (
                    not self.store.create(archive_key, previous)
                    and self.store.read(archive_key) != previous
                ):
                    raise StoreConflict("Archive version already exists with different content.")
            self.store.replace_version(f"published/{doc_id}.md", md, version)
        record["status"] = "published"
        record["published_at"] = dt.datetime.now(dt.UTC).isoformat(timespec="seconds")
        record["reviewer"] = reviewer
        self.store.write(key, json.dumps(record, ensure_ascii=False, indent=2))
        return {
            "proposal_id": proposal_id,
            "status": "published",
            "doc_id": doc_id,
            "archived_previous": previous is not None,
        }
