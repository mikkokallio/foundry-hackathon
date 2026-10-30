"""Document store: local folder for development, Azure Blob Storage in Azure.

Layout (same in both): published/<doc_id>.md, proposals/<team>/<proposal_id>.json, archive/<doc_id>/<version>.md
"""

from __future__ import annotations

import hashlib
import os
import tempfile
import threading
from collections.abc import Iterable
from pathlib import Path
from typing import Protocol


class StoreConflict(RuntimeError):
    """The document changed after the proposal was prepared."""


class DocStore(Protocol):
    def read(self, key: str) -> str | None: ...
    def write(self, key: str, content: str) -> None: ...
    def create(self, key: str, content: str) -> bool: ...
    def snapshot(self, key: str) -> tuple[str | None, str | None]: ...
    def replace_version(self, key: str, content: str, version: str | None) -> None: ...
    def delete(self, key: str) -> None: ...
    def list(self, prefix: str) -> list[str]: ...


class LocalStore:
    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._write_lock = threading.Lock()

    def _path(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root.resolve() not in p.parents and p != self.root.resolve():
            raise ValueError("invalid key")
        return p

    def read(self, key: str) -> str | None:
        p = self._path(key)
        return p.read_text(encoding="utf-8") if p.exists() else None

    def write(self, key: str, content: str) -> None:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=p.parent, delete=False
        ) as temporary:
            temporary.write(content)
        try:
            os.replace(temporary.name, p)
        finally:
            Path(temporary.name).unlink(missing_ok=True)

    def create(self, key: str, content: str) -> bool:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=p.parent, delete=False
        ) as temporary:
            temporary.write(content)
        try:
            os.link(temporary.name, p)
            return True
        except FileExistsError:
            return False
        finally:
            Path(temporary.name).unlink(missing_ok=True)

    def snapshot(self, key: str) -> tuple[str | None, str | None]:
        content = self.read(key)
        return content, hashlib.sha256(
            content.encode()
        ).hexdigest() if content is not None else None

    def replace_version(self, key: str, content: str, version: str | None) -> None:
        with self._write_lock:
            if self.snapshot(key)[1] != version:
                raise StoreConflict(
                    "Published content changed. Prepare and approve a new proposal."
                )
            if version is None:
                if not self.create(key, content):
                    raise StoreConflict("A document with this ID was published concurrently.")
            else:
                self.write(key, content)

    def delete(self, key: str) -> None:
        p = self._path(key)
        if p.exists():
            p.unlink()

    def list(self, prefix: str) -> list[str]:
        base = self._path(prefix) if prefix else self.root
        if not base.exists():
            return []
        return sorted(
            str(p.relative_to(self.root)).replace(os.sep, "/")
            for p in base.rglob("*")
            if p.is_file()
        )


class BlobStore:
    """Azure Blob Storage with Entra ID auth (managed identity in Azure, az login locally)."""

    def __init__(self, account_url: str, container: str, client_id: str | None = None):
        from azure.identity import DefaultAzureCredential  # lazy import
        from azure.storage.blob import BlobServiceClient

        cred = (
            DefaultAzureCredential(managed_identity_client_id=client_id)
            if client_id
            else DefaultAzureCredential()
        )
        self._container = BlobServiceClient(
            account_url=account_url, credential=cred
        ).get_container_client(container)

    def read(self, key: str) -> str | None:
        from azure.core.exceptions import ResourceNotFoundError

        try:
            return self._container.download_blob(key).readall().decode("utf-8")
        except ResourceNotFoundError:
            return None

    def write(self, key: str, content: str) -> None:
        from azure.storage.blob import ContentSettings

        ctype = "application/json" if key.endswith(".json") else "text/markdown; charset=utf-8"
        self._container.upload_blob(
            key,
            content.encode("utf-8"),
            overwrite=True,
            content_settings=ContentSettings(content_type=ctype),
        )

    def create(self, key: str, content: str) -> bool:
        from azure.core.exceptions import ResourceExistsError
        from azure.storage.blob import ContentSettings

        ctype = "application/json" if key.endswith(".json") else "text/markdown; charset=utf-8"
        try:
            self._container.upload_blob(
                key,
                content.encode("utf-8"),
                overwrite=False,
                content_settings=ContentSettings(content_type=ctype),
            )
            return True
        except ResourceExistsError:
            return False

    def snapshot(self, key: str) -> tuple[str | None, str | None]:
        from azure.core.exceptions import ResourceNotFoundError

        try:
            download = self._container.download_blob(key)
            return download.readall().decode("utf-8"), download.properties.etag
        except ResourceNotFoundError:
            return None, None

    def replace_version(self, key: str, content: str, version: str | None) -> None:
        from azure.core import MatchConditions
        from azure.core.exceptions import ResourceExistsError, ResourceModifiedError
        from azure.storage.blob import ContentSettings

        if version is None:
            if not self.create(key, content):
                raise StoreConflict("A document with this ID was published concurrently.")
            return
        try:
            self._container.upload_blob(
                key,
                content.encode("utf-8"),
                overwrite=True,
                etag=version,
                match_condition=MatchConditions.IfNotModified,
                content_settings=ContentSettings(content_type="text/markdown; charset=utf-8"),
            )
        except (ResourceModifiedError, ResourceExistsError) as exc:
            raise StoreConflict(
                "Published content changed. Prepare and approve a new proposal."
            ) from exc

    def delete(self, key: str) -> None:
        from azure.core.exceptions import ResourceNotFoundError

        try:
            self._container.delete_blob(key)
        except ResourceNotFoundError:
            pass

    def list(self, prefix: str) -> list[str]:
        return sorted(b.name for b in self._container.list_blobs(name_starts_with=prefix))


def make_store() -> DocStore:
    mode = os.getenv("STORAGE_MODE", "blob").lower()
    if mode == "blob":
        return BlobStore(
            account_url=os.environ["STORAGE_ACCOUNT_URL"],
            container=os.getenv("STORAGE_CONTAINER", "docs"),
            client_id=os.getenv("AZURE_CLIENT_ID") or None,
        )
    if mode == "local":
        return LocalStore(os.getenv("LOCAL_STORE_DIR", ".store"))
    raise ValueError(f"Unknown STORAGE_MODE: {mode!r}; expected local or blob")


def seed_published(store: DocStore, seed_dir: str | Path, only_if_empty: bool = True) -> int:
    seed = Path(seed_dir)
    if not seed.is_dir():
        raise FileNotFoundError(f"Configured seed directory does not exist: {seed}")
    if only_if_empty and store.list("published/"):
        return 0
    n = 0
    for f in sorted(seed.glob("*.md")):
        key, content = f"published/{f.stem}.md", f.read_text(encoding="utf-8")
        if only_if_empty:
            n += int(store.create(key, content))
        else:
            store.write(key, content)
            n += 1
    return n


def keys_with_suffix(keys: Iterable[str], suffix: str) -> list[str]:
    return [k for k in keys if k.endswith(suffix)]
