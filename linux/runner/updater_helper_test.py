"""Exercise the real replacement helper without launching Vela or an AppImage mount."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


HELPER = Path(sys.argv.pop(1)).resolve()


class UpdateHelperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="vela-updater-test-")
        self.directory = Path(self.temp.name)
        self.helper = self.directory / "helper"
        shutil.copy2(HELPER, self.helper)
        self.current = self.directory / "Vela.AppImage"
        self.staged = self.directory / "staged.AppImage"
        self.backup = self.directory / "previous.AppImage"
        self.marker = self.directory / "started"
        self.old = self.program("old")
        self.new = self.program("new")
        self.current.write_bytes(self.old)
        self.current.chmod(0o700)
        self.staged.write_bytes(self.new)
        self.staged.chmod(0o700)
        self.original = self.current.stat()
        parent = subprocess.Popen(["true"])
        parent.wait()
        self.exited_parent = parent.pid

    def tearDown(self):
        self.temp.cleanup()

    def program(self, name):
        return f"#!/bin/sh\nprintf {name} > '{self.marker}'\n".encode()

    def install(self, digest=None):
        checksum = digest or hashlib.sha256(self.staged.read_bytes()).hexdigest()
        result = subprocess.run(
            [str(self.helper), str(self.current), str(self.staged), str(self.backup),
             checksum, str(self.exited_parent), str(self.original.st_dev),
             str(self.original.st_ino)],
            check=False,
            timeout=5,
        )
        for _ in range(100):
            if self.marker.exists():
                break
            time.sleep(0.01)
        return result.returncode

    def test_replaces_and_relaunches(self):
        self.assertEqual(self.install(), 0)
        self.assertEqual(self.current.read_bytes(), self.new)
        self.assertEqual(self.marker.read_text(), "new")
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.staged.exists())
        self.assertFalse(self.helper.exists())

    def test_tampered_payload_keeps_old_version(self):
        self.assertEqual(self.install("0" * 64), 4)
        self.assertEqual(self.current.read_bytes(), self.old)
        self.assertEqual(self.marker.read_text(), "old")

    def test_changed_installation_is_not_overwritten(self):
        replacement = self.directory / "different.AppImage"
        replacement.write_bytes(self.program("other"))
        replacement.chmod(0o700)
        os.replace(replacement, self.current)
        self.assertEqual(self.install(), 4)
        self.assertEqual(self.marker.read_text(), "other")

    def test_existing_backup_is_not_overwritten(self):
        self.backup.write_text("user file")
        self.assertEqual(self.install(), 5)
        self.assertEqual(self.backup.read_text(), "user file")
        self.assertEqual(self.current.read_bytes(), self.old)

    def test_failed_launch_restores_old_version(self):
        self.staged.write_bytes(b"not an executable")
        self.assertEqual(self.install(), 7)
        self.assertEqual(self.current.read_bytes(), self.old)
        self.assertEqual(self.marker.read_text(), "old")

    def test_symlink_is_rejected_without_touching_its_target(self):
        payload = self.directory / "payload"
        payload.write_bytes(self.new)
        self.staged.unlink()
        self.staged.symlink_to(payload)
        self.assertEqual(self.install(), 4)
        self.assertEqual(payload.read_bytes(), self.new)
        self.assertEqual(self.current.read_bytes(), self.old)


if __name__ == "__main__":
    unittest.main()
