"""Generate signed update manifests from complete, versioned release artifacts."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from version import read_version

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def public_key(key: Path) -> str:
    der = subprocess.check_output(
        ["openssl", "pkey", "-in", str(key), "-pubout", "-outform", "DER"],
        stderr=subprocess.DEVNULL,
    )
    prefix = bytes.fromhex("302a300506032b6570032100")
    if len(der) != 44 or not der.startswith(prefix):
        raise ValueError("UPDATE_PRIVATE_KEY_PEM must be an Ed25519 PKCS8 PEM key")
    return base64.b64encode(der[len(prefix):]).decode("ascii")


def sign_file(key: Path, source: Path) -> str:
    signature = subprocess.check_output(
        ["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key), "-in", str(source)],
        stderr=subprocess.DEVNULL,
    )
    if len(signature) != 64:
        raise ValueError("unexpected Ed25519 signature length")
    return base64.b64encode(signature).decode("ascii")


def signed_json(key: Path, payload: dict) -> dict:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    with tempfile.TemporaryDirectory(prefix="vela-sign-") as directory:
        path = Path(directory) / "payload.json"
        path.write_bytes(encoded)
        signature = sign_file(key, path)
    return {"payload": base64.b64encode(encoded).decode("ascii"), "signature": signature}


def required_artifacts(version: str) -> dict:
    prefix = f"Vela-{version}"
    return {
        "macos-arm64": f"{prefix}-macos-arm64.zip",
        "macos-x64": f"{prefix}-macos-x64.zip",
        "windows-x64": f"{prefix}-windows-x64-setup.exe",
        "linux-x64": f"{prefix}-linux-x64.AppImage",
        "android-arm64": f"{prefix}-android-arm64.apk",
    }


def generate(artifacts: Path, output: Path, key: Path, repository: str, version: dict) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("invalid GitHub repository")
    public_key(key)
    assets = required_artifacts(version["version"])
    installation = [f"Vela-{version['version']}-macos-{arch}.dmg" for arch in ("arm64", "x64")]
    for name in [*assets.values(), *installation]:
        path = artifacts / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing or empty release artifact: {name}")
    output.mkdir(parents=True, exist_ok=True)
    base_url = f"https://github.com/{repository}/releases/download/{version['tag']}"
    for target, name in assets.items():
        platform, arch = target.split("-")
        path = artifacts / name
        url = f"{base_url}/{name}"
        if platform == "macos":
            rss = ET.Element("rss", version="2.0")
            channel = ET.SubElement(rss, "channel")
            ET.SubElement(channel, "title").text = f"Vela {target}"
            item = ET.SubElement(channel, "item")
            ET.SubElement(item, "title").text = f"Vela {version['version']}"
            ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(version["build"])
            ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version["version"]
            ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = "12.0.0"
            ET.SubElement(item, "enclosure", {
                "url": url,
                "length": str(path.stat().st_size),
                "type": "application/octet-stream",
                f"{{{SPARKLE}}}edSignature": sign_file(key, path),
            })
            ET.indent(rss)
            ET.ElementTree(rss).write(output / f"{target}.xml", encoding="utf-8", xml_declaration=True)
        else:
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            envelope = signed_json(key, {
                "version": version["version"], "build": version["build"],
                "platform": platform, "arch": arch, "url": url,
                "sha256": digest, "size": path.stat().st_size,
            })
            (output / f"{target}.json").write_text(json.dumps(envelope, separators=(",", ":")) + "\n")
    with (artifacts / "SHA256SUMS").open("w") as checksums:
        for path in sorted(artifacts.iterdir()):
            if path.is_file() and path.name != "SHA256SUMS":
                with path.open("rb") as stream:
                    digest = hashlib.file_digest(stream, "sha256").hexdigest()
                checksums.write(f"{digest}  {path.name}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--print-public-key", action="store_true")
    parser.add_argument("--artifacts", type=Path, default=Path("dist"))
    parser.add_argument("--output", type=Path, default=Path("feeds"))
    parser.add_argument("--repository")
    parser.add_argument("--tag")
    args = parser.parse_args()
    if args.print_public_key:
        print(public_key(args.key))
        return
    version = read_version(Path("pubspec.yaml"))
    if args.tag != version["tag"]:
        raise SystemExit("release tag must exactly match pubspec.yaml version")
    if not args.repository:
        parser.error("--repository is required when generating feeds")
    generate(args.artifacts, args.output, args.key, args.repository, version)


if __name__ == "__main__":
    main()
