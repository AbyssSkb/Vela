"""Materialize release signing only on the protected GitHub runner."""

import base64
import os
from pathlib import Path


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
    configure(os.environ, Path("android"))
