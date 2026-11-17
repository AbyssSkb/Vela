"""Check invalid packaging inputs without downloading tools or compiling an app."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PackageInputsTest(unittest.TestCase):
    def run_package(self, platform, version, arch, bundle):
        environment = os.environ | {"VERSION": version, "ARCH": arch}
        return subprocess.run(
            ["bash", str(ROOT / "packaging" / platform / "package.sh"), str(bundle)],
            env=environment,
            capture_output=True,
            text=True,
        )

    def test_version_cannot_be_a_path(self):
        for platform in ("linux", "macos"):
            result = self.run_package(platform, "../../escape", "x64", "/missing")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invalid VERSION", result.stderr)

    def test_wrong_architecture_is_rejected_before_tool_download(self):
        for platform in ("linux", "macos"):
            result = self.run_package(platform, "1.2.3-beta.1", "unsupported", "/missing")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unsupported", result.stderr)

    def test_empty_build_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for platform in ("linux", "macos"):
                result = self.run_package(platform, "1.2.3", "x64", directory)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Missing built", result.stderr)


if __name__ == "__main__":
    unittest.main()
