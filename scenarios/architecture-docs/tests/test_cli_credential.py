"""CLI-cache coordination tests; no live credentials or network calls."""
from __future__ import annotations

import errno
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import Mock, patch

from azure.core.credentials import AccessToken

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import cli_credential as auth


class CredentialTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.lock = self.root / "acquisition.lock"
        self.cli = Mock()
        self.cli.get_token.return_value = AccessToken("test-only-token", int(time.time()) + 3600)
        replacement = patch.object(auth, "AzureCliCredential", return_value=self.cli)
        replacement.start()
        self.addCleanup(replacement.stop)

    def credential(self, **kwargs):
        return auth.CachedAzureCliCredential(lock_path=self.lock, **kwargs)

    def test_caches_only_in_memory_and_separates_scope_tenant_claims_and_cae(self):
        with self.credential() as identity:
            first = identity.get_token("scope-a")
            self.assertIs(identity.get_token("scope-a"), first)
            identity.get_token("scope-b")
            identity.get_token("scope-a", tenant_id="test-tenant")
            identity.get_token("scope-a", claims="test-claim")
            identity.get_token("scope-a", enable_cae=True)
        self.assertEqual(self.cli.get_token.call_count, 5)
        self.cli.close.assert_called_once()
        self.assertEqual(self.lock.read_bytes(), b"\0")
        self.assertEqual(list(self.root.iterdir()), [self.lock])

    def test_refreshes_near_expiry_and_propagates_failure_without_caching(self):
        self.cli.get_token.side_effect = [
            AccessToken("test-only-expiring", int(time.time()) + 10),
            PermissionError(errno.EACCES, "test-only shared cache contention"),
            AccessToken("test-only-refreshed", int(time.time()) + 3600),
        ]
        with self.credential() as identity:
            identity.get_token("scope-a")
            with self.assertRaises(PermissionError):
                identity.get_token("scope-a")
            token = identity.get_token("scope-a")
            self.assertEqual(token.token, "test-only-refreshed")
        self.assertEqual(self.cli.get_token.call_count, 3)
        with auth.cli_cache_lock(self.lock, 0.1):
            pass

    def test_omits_default_tenant_and_preserves_explicit_tenant(self):
        with patch.object(auth, "AzureCliCredential", return_value=self.cli) as factory:
            with self.credential():
                pass
            factory.assert_called_once_with(process_timeout=30)
            factory.reset_mock()
            with self.credential(tenant_id="test-tenant"):
                pass
            factory.assert_called_once_with(tenant_id="test-tenant", process_timeout=30)

    def test_forwards_additional_sdk_options_without_reusing_or_replacing_cached_tokens(self):
        self.cli.get_token.side_effect = [
            AccessToken("test-only-cached", int(time.time()) + 3600),
            AccessToken("test-only-option-one", int(time.time()) + 3600),
            AccessToken("test-only-option-two", int(time.time()) + 3600),
        ]
        option = {"value": "test-only"}
        with self.credential() as identity:
            cached = identity.get_token("scope-a")
            first = identity.get_token("scope-a", sdk_option=option)
            second = identity.get_token("scope-a", sdk_option=option)
            self.assertNotEqual(first, second)
            self.assertIs(identity.get_token("scope-a"), cached)
        self.assertEqual(self.cli.get_token.call_count, 3)
        self.cli.get_token.assert_called_with(
            "scope-a", claims=None, tenant_id=None, enable_cae=False, sdk_option=option,
        )

    def test_serializes_distinct_credentials_but_not_work_after_acquisition(self):
        active = 0
        peak = 0
        state = threading.Lock()

        def acquire(*_, **__):
            nonlocal active, peak
            with state:
                active += 1
                peak = max(peak, active)
            try:
                if active > 1:
                    raise PermissionError(errno.EACCES, "test-only MSAL cache collision")
                time.sleep(0.05)
                return AccessToken("test-only-token", int(time.time()) + 3600)
            finally:
                with state:
                    active -= 1

        self.cli.get_token.side_effect = acquire
        barrier = threading.Barrier(2)
        cloud_barrier = threading.Barrier(2)

        def worker():
            with self.credential() as identity:
                barrier.wait(timeout=5)
                identity.get_token("scope-a")
                cloud_barrier.wait(timeout=5)
                identity.get_token("scope-a")

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(worker) for _ in range(2)]
            for future in futures:
                future.result(timeout=10)
        self.assertEqual(peak, 1)
        self.assertEqual(self.cli.get_token.call_count, 2)

    def test_cross_process_lock_times_out_and_releases_without_deleting_shared_file(self):
        ready = self.root / "ready"
        release = self.root / "release"
        code = (
            "import sys,time; from pathlib import Path; "
            "sys.path.insert(0,sys.argv[1]); from cli_credential import cli_cache_lock\n"
            "with cli_cache_lock(Path(sys.argv[2]),2):\n"
            " Path(sys.argv[3]).write_text('ready')\n"
            " stop=time.monotonic()+10\n"
            " while not Path(sys.argv[4]).exists():\n"
            "  if time.monotonic()>stop: raise TimeoutError('test holder deadline')\n"
            "  time.sleep(.01)\n"
        )
        process = subprocess.Popen(
            [sys.executable, "-c", code, str(SCRIPTS), str(self.lock), str(ready), str(release)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            stop = time.monotonic() + 5
            while not ready.exists():
                if process.poll() is not None or time.monotonic() > stop:
                    self.fail("Cross-process test lock holder did not become ready.")
                time.sleep(0.01)
            with (
                self.assertRaisesRegex(TimeoutError, "token acquisition"),
                auth.cli_cache_lock(self.lock, 0.05),
            ):
                self.fail("Acquired another process's CLI lock.")
        finally:
            release.write_text("release")
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise
        self.assertEqual(process.returncode, 0, stderr.decode())
        self.assertEqual(stdout, b"")
        with auth.cli_cache_lock(self.lock, 0.1):
            pass
        self.assertEqual(self.lock.read_bytes(), b"\0")

    def test_rejects_nonpositive_lock_timeout(self):
        with self.assertRaisesRegex(ValueError, "positive"):
            self.credential(lock_timeout=0)


if __name__ == "__main__":
    unittest.main()
