"""Configure and verify the Android release signer."""

import base64
import os
from pathlib import Path
import re
import sys


RELEASE_CERT_SHA256 = "e77c9a0b8c47ac70c4aee4b223c464e3b393cce438a9835542b2b489acb8210b"


def verify_release_signer(report: str) -> None:
    # Recent apksigner versions report the same certificate once per signature scheme.
    digests = {
        digest
        for label, digest in re.findall(r"^(.+?) certificate SHA-256 digest: (\S+)$", report, re.MULTILINE)
        if label.removesuffix(":") != "Source Stamp Signer"
    }
    if digests != {RELEASE_CERT_SHA256}:
        raise ValueError("APK signer must match the published Android signing certificate")


def configure(environment: dict, android: Path) -> None:
    names = ("ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
    if any(not environment.get(name) for name in names):
        raise ValueError("release requires all four ANDROID_KEYSTORE_* / ANDROID_KEY_* secrets")
    key = android / "release.keystore"
    key.write_bytes(base64.b64decode(environment[names[0]], validate=True))
    key.chmod(0o600)
    values = {
        "storeFile": str(key.resolve()),
        "storePassword": environment[names[1]],
        "keyAlias": environment[names[2]],
        "keyPassword": environment[names[3]],
    }
    def escape(value: str) -> str:
        return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("=", "\\=").replace(":", "\\:")
    properties = android / "key.properties"
    properties.write_text("".join(f"{name}={escape(value)}\n" for name, value in values.items()))
    properties.chmod(0o600)


if __name__ == "__main__":
    if sys.argv[1:] == ["verify-signer"]:
        try:
            verify_release_signer(sys.stdin.read())
        except ValueError as error:
            raise SystemExit(str(error)) from error
    elif len(sys.argv) == 1:
        configure(os.environ, Path("android"))
    else:
        raise SystemExit("Usage: android_signing.py [verify-signer]")
