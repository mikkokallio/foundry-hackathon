"""Cache CLI tokens in memory and serialize access to the shared CLI cache."""
from __future__ import annotations

import errno
import os
import threading
import time
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Self

from azure.core.credentials import AccessToken
from azure.identity import AzureCliCredential


def _default_lock_path() -> Path:
    config = Path(os.environ.get("AZURE_CONFIG_DIR", str(Path.home() / ".azure")))
    return config / "workshop-token-acquisition.lock"


@contextmanager
def cli_cache_lock(path: Path | None = None, timeout: float = 120) -> Generator[None, None, None]:
    """Lock only CLI acquisition; the file contains no credentials."""
    if timeout <= 0:
        raise ValueError("CLI acquisition lock timeout must be positive.")
    path = path or _default_lock_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        if stream.seek(0, os.SEEK_END) == 0:
            stream.write(b"\0")
            stream.flush()
        stop = time.monotonic() + timeout
        while True:
            stream.seek(0)
            try:
                if os.name == "nt":
                    import msvcrt

                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl

                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as exc:
                if exc.errno not in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                    raise
                remaining = stop - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Timed out waiting for workshop CLI token acquisition.") from exc
                time.sleep(min(0.05, remaining))
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


class CachedAzureCliCredential:
    def __init__(
        self, *, tenant_id: str | None = None, process_timeout: int = 30,
        lock_timeout: float = 120, lock_path: Path | None = None,
    ) -> None:
        if lock_timeout <= 0:
            raise ValueError("CLI acquisition lock timeout must be positive.")
        self._credential = (
            AzureCliCredential(tenant_id=tenant_id, process_timeout=process_timeout)
            if tenant_id is not None else AzureCliCredential(process_timeout=process_timeout)
        )
        self._lock_path = lock_path or _default_lock_path()
        self._lock_timeout = lock_timeout
        self._mutex = threading.Lock()
        self._tokens: dict[tuple[tuple[str, ...], str | None, str | None, bool], AccessToken] = {}

    def get_token(
        self, *scopes: str, claims: str | None = None, tenant_id: str | None = None,
        enable_cae: bool = False, **kwargs: Any,
    ) -> AccessToken:
        key = (scopes, claims, tenant_id, enable_cae)
        with self._mutex:
            token = self._tokens.get(key)
            if not kwargs and token is not None and token.expires_on > time.time() + 300:
                return token
            with cli_cache_lock(self._lock_path, self._lock_timeout):
                token = self._credential.get_token(
                    *scopes, claims=claims, tenant_id=tenant_id, enable_cae=enable_cae, **kwargs,
                )
            if not kwargs:
                self._tokens[key] = token
            return token

    def close(self) -> None:
        with self._mutex:
            self._tokens.clear()
            self._credential.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
