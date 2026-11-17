"""Bundle original Rust dependency license material from a resolved Cargo graph."""

import argparse
import hashlib
import json
from pathlib import Path
import re


LICENSE_NAME = re.compile(r"^(licen[cs]es?|copying|notices?|copyright)(?:$|[._-])", re.I)


def crate_files(root: Path, declared: str | None) -> list[Path]:
    files = set()
    if declared:
        path = (root / declared).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError(f"declared license file is unavailable: {declared}")
        files.add(path)
    for path in root.iterdir():
        if LICENSE_NAME.match(path.name):
            if path.is_file():
                files.add(path.resolve())
            elif path.is_dir():
                files.update(child.resolve() for child in path.rglob("*") if child.is_file())
    return sorted(files)


def fallback_files(package: dict, root: Path, sources: dict, source_root: Path) -> tuple[list, bool]:
    name = f"{package['name']}@{package['version']}"
    fallback = sources.get(name)
    if not fallback:
        raise ValueError(f"{name}: no license text in crate; add exact upstream source to license_sources.json")
    vcs_path = root / ".cargo_vcs_info.json"
    revision = json.loads(vcs_path.read_text()).get("git", {}).get("sha1") if vcs_path.exists() else None
    if revision != fallback["revision"]:
        raise ValueError(f"{name}: upstream license revision does not match the published crate")
    if fallback.get("build_time_attribution_only"):
        kinds = {kind for target in package["targets"] for kind in target["kind"]}
        if "proc-macro" not in kinds or kinds & {"lib", "rlib", "dylib", "cdylib", "staticlib", "bin"}:
            raise ValueError(f"{name}: attribution-only exception is limited to a proc-macro-only crate")
        files = [root / "Cargo.toml.orig", root / "README.md"]
        if not all(path.is_file() for path in files):
            raise ValueError(f"{name}: original build-time attribution is unavailable")
        return [(path, f"crate:{path.name}") for path in files], True
    result = []
    for source in fallback["files"]:
        path = (source_root / source["file"]).resolve()
        if not path.is_relative_to(source_root.resolve()) or not path.is_file():
            raise ValueError(f"{name}: upstream license fallback is unavailable")
        if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError(f"{name}: upstream license checksum changed")
        result.append((path, source["url"]))
    if not result:
        raise ValueError(f"{name}: upstream license source is empty")
    return result, False


def generate(metadata: dict, output: Path, source_index: Path) -> None:
    sources = json.loads(source_index.read_text())["packages"]
    packages = sorted((p for p in metadata["packages"] if p["source"]), key=lambda p: (p["name"], p["version"]))
    material, index = [], []
    for package in packages:
        name = f"{package['name']}@{package['version']}"
        root = Path(package["manifest_path"]).parent
        try:
            files = [(path, f"crate:{path.relative_to(root.resolve())}")
                     for path in crate_files(root, package.get("license_file"))]
            upstream = sources.get(name, {}) if not files else {}
            attribution_only = False
            if not files:
                files, attribution_only = fallback_files(package, root, sources, source_index.parent)
            heading = f"{name}\nDeclared license: {package.get('license') or 'see license file'}\nRepository: {package.get('repository') or 'not specified'}\n"
            if upstream.get("selected_license"):
                heading += f"Selected license option: {upstream['selected_license']}\n"
            if attribution_only:
                heading += "Build-time procedural macro only. Upstream supplies a license declaration but no license text; original attribution follows. This is not runtime license coverage.\n"
            material.append("=" * 78 + "\n" + heading)
            copied = []
            for path, origin in files:
                content = path.read_bytes()
                reference = next((s for s in upstream.get("files", []) if s["url"] == origin), {})
                provenance = {key: reference[key] for key in ("kind", "referenced_by") if key in reference}
                details = "".join(f"{key}: {value}\n" for key, value in provenance.items())
                material.append(f"\nSource: {origin}\n{details}\n" + content.decode("utf-8") + "\n")
                copied.append({"source": origin, "sha256": hashlib.sha256(content).hexdigest(), **provenance})
            index.append({"name": package["name"], "version": package["version"],
                          "license": package.get("license"), "repository": package.get("repository"),
                          "build_time_attribution_only": attribution_only, "files": copied,
                          **{key: upstream[key] for key in ("revision", "selected_license") if key in upstream}})
        except (OSError, UnicodeError, ValueError) as error:
            raise ValueError(f"{name}: {error}") from error
    if not packages:
        raise ValueError("Cargo metadata contains no registry dependencies")
    output.mkdir(parents=True, exist_ok=True)
    (output / "RUST-NOTICES.txt").write_text(
        "Vela Rust dependency notices\nOriginal license material for the resolved target, including build dependencies.\n\n" + "".join(material))
    (output / "rust-notices-index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"Bundled license material for {len(packages)} Rust packages.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sources", type=Path, default=Path(__file__).with_name("license_sources.json"))
    args = parser.parse_args()
    try:
        generate(json.loads(args.metadata.read_text()), args.output, args.sources)
    except ValueError as error:
        raise SystemExit(f"Cannot package Rust notices: {error}") from error


if __name__ == "__main__":
    main()
