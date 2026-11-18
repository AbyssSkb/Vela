"""Prepare a release draft or publish the exact draft reviewed by the maintainer."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from feeds import required_artifacts
from version import parse_version, precedence, read_version


RELEASE_FIELDS = "assets,body,id,isDraft,isPrerelease,name,tagName,targetCommitish"


def gh(*args: str) -> str:
    return subprocess.check_output(["gh", *args], text=True).strip()


def release_exists(tag: str) -> bool:
    return subprocess.run(["gh", "release", "view", tag], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def tag_commit(repo: str, tag: str) -> str:
    return gh("api", f"repos/{repo}/commits/{tag}", "--jq", ".sha")


def check_version(repo: str, tag: str, version: dict) -> None:
    public_tags = gh("api", "--paginate", f"repos/{repo}/releases?per_page=100",
                     "--jq", ".[] | select(.draft == false) | .tag_name")
    for published_tag in public_tags.splitlines():
        if published_tag == tag or not re.fullmatch(r"v[0-9][0-9A-Za-z.-]*", published_tag):
            continue
        pubspec = gh("api", "--method", "GET", "-H", "Accept: application/vnd.github.raw+json",
                     f"repos/{repo}/contents/pubspec.yaml", "-f", f"ref={published_tag}")
        published = parse_version(pubspec)
        if published["tag"] != published_tag:
            raise ValueError(f"Published tag {published_tag} does not match its pubspec.yaml")
        if (version["build"] <= published["build"] or
                precedence(version["version"]) <= precedence(published["version"])):
            raise ValueError(f"Version and build must increase beyond {published_tag}+{published['build']}")


def draft_fingerprint(release: dict, commit: str) -> str:
    assets = sorted(
        ({field: asset[field] for field in ("name", "id", "size", "state", "digest")}
         for asset in release["assets"]), key=lambda asset: asset["name"],
    )
    draft = {field: release[field] for field in ("id", "body", "name", "tagName", "isPrerelease")}
    snapshot = json.dumps(dict(draft, commit=commit, assets=assets), sort_keys=True)
    return hashlib.sha256(snapshot.encode()).hexdigest()


def prepare(tag: str, version: dict) -> None:
    if release_exists(tag):
        if not json.loads(gh("release", "view", tag, "--json", "isDraft"))["isDraft"]:
            raise ValueError("Refusing to replace assets of an already published version")
    else:
        flags = ["--draft", "--verify-tag", "--title", f"Vela {version['version']}", "--generate-notes"]
        if version["prerelease"]:
            flags.append("--prerelease")
        gh("release", "create", tag, *flags)
    for directory in (Path("dist"), Path("feeds")):
        gh("release", "upload", tag, *map(str, sorted(directory.glob("*"))), "--clobber")


def publish(repo: str, tag: str, version: dict, commit: str) -> None:
    approved = os.environ.get("APPROVED_FINGERPRINT", "")
    if not re.fullmatch(r"[0-9a-f]{64}", approved):
        raise ValueError("Publication requires the approved release draft fingerprint")

    release = json.loads(gh("release", "view", tag, "--json", RELEASE_FIELDS))
    if draft_fingerprint(release, commit) != approved:
        raise ValueError("The release differs from the approved draft")
    if release["tagName"] != tag or release["isPrerelease"] != version["prerelease"]:
        raise ValueError("The release metadata does not match its version")

    targets = required_artifacts(version["version"])
    packages = [*targets.values(), *(f"Vela-{version['version']}-macos-{arch}.dmg"
                                     for arch in ("arm64", "x64"))]
    feeds = [f"{target}.json" for target in targets]
    assets = {asset["name"]: asset for asset in release["assets"]}
    for name in (*packages, *feeds, "SHA256SUMS"):
        asset = assets.get(name)
        if (not asset or asset["state"] != "uploaded" or not asset["size"] or
                not re.fullmatch(r"sha256:[0-9a-f]{64}", asset["digest"] or "")):
            raise ValueError(f"Missing or incomplete release asset: {name}")

    with tempfile.TemporaryDirectory(prefix="vela-publication-") as directory:
        gh("release", "download", tag, "--pattern", "*.json", "--pattern", "SHA256SUMS", "--dir", directory)
        paths = [Path(directory) / name for name in feeds]
        sums = Path(directory) / "SHA256SUMS"
        for path in (*paths, sums):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if f"sha256:{digest}" != assets[path.name]["digest"]:
                raise ValueError(f"Downloaded asset changed: {path.name}")
        checksums = dict(line.split(maxsplit=1)[::-1] for line in sums.read_text().splitlines())
        for name in packages:
            if assets[name]["digest"] != f"sha256:{checksums.get(name)}":
                raise ValueError(f"Package checksum mismatch: {name}")

        current = json.loads(gh("release", "view", tag, "--json", RELEASE_FIELDS))
        if draft_fingerprint(current, tag_commit(repo, tag)) != approved:
            raise ValueError("The release changed during verification")
        if current["isDraft"]:
            gh("release", "edit", tag, "--draft=false")
        if not release_exists("updates"):
            gh("release", "create", "updates", "--target", commit, "--prerelease", "--latest=false",
               "--title", "Vela update feeds", "--notes",
               "Machine-readable update feeds. Download installers from a versioned Vela release.")
        # Publish the installers before the rolling feeds advertise them.
        gh("release", "upload", "updates", *map(str, paths), "--clobber")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("check-version", "prepare", "publish", "fingerprint"))
    parser.add_argument("tag")
    args = parser.parse_args()
    repo, tag = os.environ["GH_REPO"], args.tag
    if not re.fullmatch(r"v[0-9][0-9A-Za-z.-]*", tag):
        parser.error("expected a Vela version tag")
    commit = tag_commit(repo, tag)
    if args.operation == "fingerprint":
        release = json.loads(gh("release", "view", tag, "--json", RELEASE_FIELDS))
        print(draft_fingerprint(release, commit))
        return

    version = read_version(Path("pubspec.yaml"))
    if version["tag"] != tag or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != commit:
        raise ValueError("The checkout and pubspec.yaml must match the release tag")
    check_version(repo, tag, version)
    if args.operation == "prepare":
        prepare(tag, version)
    elif args.operation == "publish":
        publish(repo, tag, version, commit)


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
