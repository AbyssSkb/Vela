"""Verify the actual signed sandbox entitlements before packaging a Mac update."""

from pathlib import Path
import plistlib
import sys


def validate(info: dict, entitlements: dict) -> None:
    identifier = info.get("CFBundleIdentifier")
    if not identifier or entitlements.get("com.apple.security.app-sandbox") is not True:
        raise ValueError("the packaged app must retain its bundle identifier and sandbox")
    names = entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name", [])
    if not {identifier + "-spks", identifier + "-spki"}.issubset(set(names)):
        raise ValueError("the signed app is missing expanded Sparkle sandbox IPC entitlements")
    if "$(" in plistlib.dumps(entitlements).decode():
        raise ValueError("the signed entitlements contain unexpanded Xcode variables")


if __name__ == "__main__":
    try:
        validate(plistlib.loads(Path(sys.argv[1]).read_bytes()),
                 plistlib.loads(Path(sys.argv[2]).read_bytes()))
    except ValueError as error:
        raise SystemExit(str(error)) from error
