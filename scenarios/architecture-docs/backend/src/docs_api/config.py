"""Configuration and small helpers for the Docs API that do not depend on FastAPI.

All settings come from environment variables (names are fixed by SPEC.md):

STORAGE_MODE           blob (default) | local (explicit development/test use)
LOCAL_STORE_DIR        folder for the local store (default .store)
STORAGE_ACCOUNT_URL    https://<account>.blob.core.windows.net (blob mode)
STORAGE_CONTAINER      blob container (default docs)
AZURE_CLIENT_ID        client id of the user-assigned managed identity (blob mode, optional)
INVENTORY_DIR          inventory JSON folder (default data/inventory)
SEED_DIR               published documents copied into an empty store on start (default data/docs)
STANDARD_DIR           documentation standard + template (default data/standard)
SEED_ON_START          true | false (default true)
REFERENCE_DATE         YYYY-MM-DD used for review-age checks (default: today)
REVIEW_MAX_AGE_DAYS    review age limit in days (default 365)
AUTH_MODE              entra (default) | local (explicit development/test use)
AZURE_TENANT_ID        permitted Entra tenant
BACKEND_AUDIENCE       backend API token audience
GATEWAY_PRINCIPAL_ID   permitted gateway managed identity
ORGANIZATION_NAME      required deployer-chosen real or fictional display name
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from archdocs.store import DocStore, LocalStore

LOGGER_NAME = "docs_api"
TRUE_VALUES = {"1", "true", "yes", "on"}
FALSE_VALUES = {"0", "false", "no", "off", ""}


def parse_bool(value: str | None, default: bool) -> bool:
    """Parse an environment flag such as 'true', '1', 'no'."""
    if value is None:
        return default
    v = value.strip().lower()
    if v in TRUE_VALUES:
        return True
    if v in FALSE_VALUES:
        return False
    raise ValueError(f"Expected a boolean (true/false), got {value!r}")


def parse_date(value: str | None) -> dt.date | None:
    """Parse REFERENCE_DATE (YYYY-MM-DD); empty means 'use today'."""
    if not value or not value.strip():
        return None
    try:
        return dt.date.fromisoformat(value.strip())
    except ValueError as exc:
        raise ValueError(f"REFERENCE_DATE must be YYYY-MM-DD, got {value!r}") from exc


@dataclass(frozen=True)
class Settings:
    storage_mode: str = "blob"
    local_store_dir: str = ".store"
    storage_account_url: str | None = None
    storage_container: str = "docs"
    azure_client_id: str | None = None
    inventory_dir: str = "data/inventory"
    seed_dir: str = "data/docs"
    standard_dir: str = "data/standard"
    seed_on_start: bool = True
    reference_date: dt.date | None = None
    review_max_age_days: int = 365
    auth_mode: str = "entra"
    tenant_id: str = ""
    gateway_audience: str = ""
    gateway_principal_id: str = ""
    organization_name: str = ""

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        e = os.environ if env is None else env
        mode = e.get("STORAGE_MODE", "blob").strip().lower()
        if mode not in ("local", "blob"):
            raise ValueError(f"STORAGE_MODE must be 'local' or 'blob', got {mode!r}")
        return cls(
            storage_mode=mode,
            local_store_dir=e.get("LOCAL_STORE_DIR") or ".store",
            storage_account_url=e.get("STORAGE_ACCOUNT_URL") or None,
            storage_container=e.get("STORAGE_CONTAINER") or "docs",
            azure_client_id=e.get("AZURE_CLIENT_ID") or None,
            inventory_dir=e.get("INVENTORY_DIR") or "data/inventory",
            seed_dir=e.get("SEED_DIR") or "data/docs",
            standard_dir=e.get("STANDARD_DIR") or "data/standard",
            seed_on_start=parse_bool(e.get("SEED_ON_START"), True),
            reference_date=parse_date(e.get("REFERENCE_DATE")),
            review_max_age_days=int(e.get("REVIEW_MAX_AGE_DAYS") or 365),
            auth_mode=e.get("AUTH_MODE", "entra"),
            tenant_id=e.get("AZURE_TENANT_ID", ""),
            gateway_audience=e.get("BACKEND_AUDIENCE", ""),
            gateway_principal_id=e.get("GATEWAY_PRINCIPAL_ID", ""),
            organization_name=e.get("ORGANIZATION_NAME", ""),
        )

    def check(self) -> None:
        """Fail fast on combinations that cannot work."""
        if self.storage_mode == "blob" and not self.storage_account_url:
            raise ValueError("STORAGE_MODE=blob requires STORAGE_ACCOUNT_URL")
        if self.storage_mode not in ("blob", "local"):
            raise ValueError("Unknown storage mode")
        if self.auth_mode not in ("entra", "local"):
            raise ValueError("AUTH_MODE must be entra or explicitly local")
        if self.storage_mode == "blob" and self.auth_mode != "entra":
            raise ValueError("Blob deployments require Entra authentication")
        if self.auth_mode == "entra" and not all(
            (self.tenant_id, self.gateway_audience, self.gateway_principal_id)
        ):
            raise ValueError(
                "Entra authentication requires AZURE_TENANT_ID, BACKEND_AUDIENCE "
                "and GATEWAY_PRINCIPAL_ID"
            )
        if self.review_max_age_days < 1:
            raise ValueError("REVIEW_MAX_AGE_DAYS must be a positive number of days")
        if (
            not self.organization_name
            or len(self.organization_name) > 120
            or self.organization_name != self.organization_name.strip()
            or any(ord(char) < 32 or ord(char) == 127 for char in self.organization_name)
        ):
            raise ValueError(
                "ORGANIZATION_NAME must be 1-120 characters, without surrounding "
                "whitespace or control characters"
            )


def build_store(settings: Settings) -> DocStore:
    """Local folder for development, Azure Blob Storage (Entra ID auth) in Azure."""
    if settings.storage_mode == "blob":
        from archdocs.store import BlobStore  # needs azure-identity + azure-storage-blob

        return BlobStore(
            settings.storage_account_url or "", settings.storage_container, settings.azure_client_id
        )
    if settings.storage_mode == "local":
        return LocalStore(settings.local_store_dir)
    raise ValueError(f"Unknown storage mode: {settings.storage_mode}")


def resolve_team(header_team: str | None, body_team: str | None) -> str:
    """Team for a proposal: X-Team-Id header (set by APIM) wins, then the body, then 'local'."""
    if header_team and header_team.strip():
        return header_team.strip()
    if body_team and body_team.strip():
        return body_team.strip()
    return "local"


def get_logger() -> logging.Logger:
    """Logger that writes one JSON object per line to stdout (picked up by Container Apps)."""
    logger = logging.getLogger(LOGGER_NAME)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)
        if logger.level == logging.NOTSET:
            logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
        logger.propagate = False
    return logger


def log_event(event: str, level: int = logging.INFO, **fields: Any) -> None:
    """Structured log line, e.g. log_event('proposal_submitted', team='team1', proposal_id=..., status=...)."""
    record = {
        "ts": dt.datetime.now(dt.UTC).isoformat(timespec="seconds"),
        "level": logging.getLevelName(level),
        "logger": LOGGER_NAME,
        "event": event,
        **fields,
    }
    get_logger().log(level, json.dumps(record, ensure_ascii=False, default=str))
