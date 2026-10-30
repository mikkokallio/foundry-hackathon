"""Documentation standard v2.1: parsing and validation of architecture documents."""

from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass, field
from typing import Any

import yaml

REQUIRED_FIELDS = [
    "doc_id",
    "title",
    "system_id",
    "owner_team",
    "status",
    "version",
    "last_reviewed",
    "classification",
]
REQUIRED_SECTIONS = [
    "Purpose",
    "Context",
    "Components",
    "Interfaces",
    "Data",
    "Security and access",
    "Operations",
    "Known limitations",
    "Change log",
]
ALLOWED_STATUS = {"draft", "published", "archived"}
ALLOWED_CLASSIFICATION = {"Public", "Internal", "Confidential"}
DOC_ID_RE = re.compile(r"^ARCH-[A-Z]{2,6}$")
SYSTEM_ID_RE = re.compile(r"^SYS-\d{3}$")
VERSION_RE = re.compile(r"^\d+\.\d+$")
INTERFACE_ID_RE = re.compile(r"\bINT-\d{3}\b")

SECRET_PATTERNS = [
    re.compile(
        r"(?i)\b(api[_-]?key|apikey|secret|password|passwd|pwd|client[_-]?secret|access[_-]?key)\b\s*[:=]\s*['\"]?[A-Za-z0-9_\-\.\/+=]{8,}"
    ),
    re.compile(r"(?i)AccountKey=[A-Za-z0-9+/=]{20,}"),
    re.compile(r"(?i)SharedAccessSignature=|sig=[A-Za-z0-9%+/=]{20,}"),
    re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
    re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"(?i)Ocp-Apim-Subscription-Key\s*[:=]\s*[0-9a-f]{32}"),
]

FRONT_MATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?", re.DOTALL)
H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)


@dataclass
class ValidationResult:
    valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "valid": self.valid,
            "errors": self.errors,
            "warnings": self.warnings,
            "metadata": self.metadata,
        }


def _normalise(value: Any) -> Any:
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()[:10]
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    return value


def parse_document(markdown: str) -> tuple[dict[str, Any], str, dict[str, str]]:
    """Return (front_matter, body, sections). Sections map H2 title -> section text."""
    text = markdown.replace("\r\n", "\n").lstrip("\ufeff")
    meta: dict[str, Any] = {}
    body = text
    m = FRONT_MATTER_RE.match(text)
    if m:
        try:
            loaded = yaml.safe_load(m.group(1)) or {}
            if isinstance(loaded, dict):
                meta = {str(k): _normalise(v) for k, v in loaded.items()}
        except yaml.YAMLError:
            meta = {"__yaml_error__": True}
        body = text[m.end() :]
    sections: dict[str, str] = {}
    matches = list(H2_RE.finditer(body))
    for i, h in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        sections[h.group(1).strip()] = body[h.end() : end].strip()
    return meta, body, sections


def find_secrets(markdown: str) -> list[str]:
    """Return redacted descriptions of secret-like strings found in the text."""
    hits: list[str] = []
    for lineno, line in enumerate(markdown.splitlines(), start=1):
        for pat in SECRET_PATTERNS:
            if pat.search(line):
                hits.append(f"line {lineno}: looks like a credential ({pat.pattern[:28]}…)")
                break
    return hits


def interface_ids_in_table(section_text: str) -> list[str]:
    """Interface IDs from the first column of the markdown table in a section."""
    ids: list[str] = []
    for line in section_text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if cells and INTERFACE_ID_RE.fullmatch(cells[0] or ""):
            ids.append(cells[0])
    return ids


def interface_rows(section_text: str) -> list[dict[str, str]]:
    """Rows of the interfaces table as dicts keyed by header names (lower case)."""
    lines = [line.strip() for line in section_text.splitlines() if line.strip().startswith("|")]
    if len(lines) < 2:
        return []
    headers = [c.strip().lower() for c in lines[0].strip("|").split("|")]
    rows = []
    for line in lines[2:]:
        cells = [c.strip() for c in line.strip("|").split("|")]
        rows.append({headers[i]: cells[i] if i < len(cells) else "" for i in range(len(headers))})
    return rows


def validate_document(
    markdown: str, reference_date: dt.date | None = None, review_max_age_days: int = 365
) -> ValidationResult:
    errors: list[str] = []
    warnings: list[str] = []
    meta, _body, sections = parse_document(markdown)

    if not meta:
        errors.append("Missing YAML front matter block (--- ... ---) at the top of the document.")
    elif meta.get("__yaml_error__"):
        errors.append("Front matter is not valid YAML.")
        meta = {}

    for f in REQUIRED_FIELDS:
        if f not in meta or meta.get(f) in (None, ""):
            errors.append(f"Front matter field '{f}' is missing.")
    if meta.get("doc_id") and not DOC_ID_RE.match(str(meta["doc_id"])):
        errors.append(f"doc_id '{meta['doc_id']}' must look like ARCH-XXX (2–6 capital letters).")
    if meta.get("system_id") and not SYSTEM_ID_RE.match(str(meta["system_id"])):
        errors.append(f"system_id '{meta['system_id']}' must look like SYS-NNN.")
    if meta.get("status") and meta["status"] not in ALLOWED_STATUS:
        errors.append(f"status '{meta['status']}' must be one of {sorted(ALLOWED_STATUS)}.")
    if meta.get("classification") and meta["classification"] not in ALLOWED_CLASSIFICATION:
        errors.append(
            f"classification '{meta['classification']}' must be one of {sorted(ALLOWED_CLASSIFICATION)}."
        )
    if meta.get("version") and not VERSION_RE.match(str(meta["version"])):
        errors.append(f"version '{meta['version']}' must be major.minor, e.g. 1.4.")
    if meta.get("last_reviewed"):
        try:
            reviewed = dt.date.fromisoformat(str(meta["last_reviewed"]))
            ref = reference_date or dt.date.today()
            age = (ref - reviewed).days
            if age > review_max_age_days:
                warnings.append(
                    f"last_reviewed {reviewed.isoformat()} is {age} days old (limit {review_max_age_days})."
                )
            if age < -1:
                warnings.append(f"last_reviewed {reviewed.isoformat()} is in the future.")
        except ValueError:
            errors.append(f"last_reviewed '{meta['last_reviewed']}' must be YYYY-MM-DD.")

    present = list(sections.keys())
    for s in REQUIRED_SECTIONS:
        if s not in sections:
            errors.append(f"Section '## {s}' is missing.")
    order = [s for s in present if s in REQUIRED_SECTIONS]
    expected_order = [s for s in REQUIRED_SECTIONS if s in order]
    if order != expected_order:
        warnings.append("Sections are not in the standard order: " + ", ".join(REQUIRED_SECTIONS))

    if "Context" in sections and "```mermaid" not in sections["Context"]:
        errors.append("The Context section must contain a Mermaid diagram (```mermaid block).")
    if "Interfaces" in sections:
        rows = interface_rows(sections["Interfaces"])
        if not rows:
            errors.append(
                "The Interfaces section must contain a table with columns ID | Counterpart | Direction | Pattern | Status."
            )
        elif "id" not in rows[0]:
            errors.append("The first column of the Interfaces table must be 'ID'.")
        elif not interface_ids_in_table(sections["Interfaces"]):
            warnings.append("The Interfaces table has no INT-NNN identifiers.")

    for hit in find_secrets(markdown):
        errors.append(
            f"Possible credential in the document ({hit}). Remove it; secrets never belong in documentation."
        )

    clean_meta = {k: v for k, v in meta.items() if not k.startswith("__")}
    return ValidationResult(valid=not errors, errors=errors, warnings=warnings, metadata=clean_meta)
