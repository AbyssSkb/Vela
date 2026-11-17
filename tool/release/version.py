"""Read the app version once for installers, update feeds, and release tags."""

import argparse
import json
from pathlib import Path
import re


def read_version(pubspec: Path) -> dict:
    match = re.search(r"^version:\s*['\"]?([^\s'\"]+)", pubspec.read_text(), re.M)
    if not match:
        raise ValueError("pubspec.yaml has no version")
    parsed = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?\+(\d+)", match[1])
    if not parsed:
        raise ValueError("version must be major.minor.patch[-prerelease]+build")
    major, minor, patch, prerelease, build = parsed.groups()
    numbers = [int(major), int(minor), int(patch), int(build)]
    if any(n > 65535 for n in numbers) or numbers[-1] == 0:
        raise ValueError("installer version components must fit 16 bits; build must be positive")
    base = f"{major}.{minor}.{patch}"
    version = base + (prerelease or "")
    return {
        "version": version,
        "build": int(build),
        "base": base,
        "windows": f"{base}.{build}",
        "tag": f"v{version}",
        "prerelease": bool(prerelease),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    parser.add_argument("--tag")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    version = read_version(args.pubspec)
    if args.tag and args.tag != version["tag"]:
        raise SystemExit(f"tag {args.tag!r} does not match {version['tag']!r}")
    if args.github_output:
        with args.github_output.open("a") as output:
            for key, value in version.items():
                output.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")
    print(json.dumps(version))


if __name__ == "__main__":
    main()
