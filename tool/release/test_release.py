import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from feeds import generate, public_key, required_artifacts
from android_signing import configure
from macos_entitlements import validate as validate_macos_entitlements
from version import read_version


class ReleaseTests(unittest.TestCase):
    def test_macos_package_rejects_unexpanded_or_missing_sandbox_entitlements(self):
        info = {'CFBundleIdentifier': 'com.example.vela'}
        entitlements = {
            'com.apple.security.app-sandbox': True,
            'com.apple.security.temporary-exception.mach-lookup.global-name':
                ['com.example.vela-spks', 'com.example.vela-spki'],
        }
        validate_macos_entitlements(info, entitlements)
        for invalid in (
            entitlements | {'com.apple.security.app-sandbox': False},
            entitlements | {'com.apple.security.temporary-exception.mach-lookup.global-name':
                            ['$(PRODUCT_BUNDLE_IDENTIFIER)-spks', '$(PRODUCT_BUNDLE_IDENTIFIER)-spki']},
            entitlements | {'unexpanded': '$(OTHER_SETTING)'},
        ):
            with self.assertRaises(ValueError):
                validate_macos_entitlements(info, invalid)

    def test_draft_does_not_publish_or_change_live_feeds(self):
        commands = self.run_publication(publish=False)
        self.assertFalse(any(command[:2] == ['release', 'edit'] for command in commands))
        self.assertFalse(any('updates' in command for command in commands))

    def test_live_feeds_follow_completed_version_publication(self):
        commands = self.run_publication(publish=True)
        publish = next(i for i, command in enumerate(commands) if command[:2] == ['release', 'edit'])
        feeds = next(i for i, command in enumerate(commands) if command[:3] == ['release', 'upload', 'updates'])
        self.assertLess(publish, feeds)
        self.assertTrue(any(command[:3] == ['release', 'upload', 'v1.2.3'] for command in commands[:publish]))

    def run_publication(self, publish):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'tool' / 'release'
            scripts.mkdir(parents=True)
            for name in ('version.py', 'publish.sh'):
                shutil.copyfile(source / name, scripts / name)
            (root / 'pubspec.yaml').write_text('version: 1.2.3+42\n')
            for name in ('dist', 'feeds', 'bin'):
                (root / name).mkdir()
            (root / 'dist' / 'fixture.zip').write_text('installer')
            (root / 'feeds' / 'fixture.xml').write_text('feed')
            gh = root / 'bin' / 'gh'
            gh.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                          'with open(os.environ["COMMANDS"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
                          'sys.exit(1 if sys.argv[1:3] == ["release", "view"] else 0)\n')
            gh.chmod(0o755)
            git = root / 'bin' / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\n" "0123456789012345678901234567890123456789"\n')
            git.chmod(0o755)
            commands = root / 'commands.jsonl'
            environment = os.environ | {
                'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                'RUNNER_TEMP': str(root), 'GH_REPO': 'owner/Vela', 'TAG': 'v1.2.3',
                'PUBLISH': str(publish).lower(), 'COMMANDS': str(commands),
            }
            subprocess.run(['bash', str(scripts / 'publish.sh')], cwd=root, env=environment,
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return [json.loads(line) for line in commands.read_text().splitlines()]

    def test_android_release_signing_has_no_debug_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            android = Path(directory)
            with self.assertRaises(ValueError):
                configure({}, android)
            self.assertFalse((android / 'key.properties').exists())
            configure({
                'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'fixture-key').decode(),
                'ANDROID_KEYSTORE_PASSWORD': 'secret=one',
                'ANDROID_KEY_ALIAS': 'vela',
                'ANDROID_KEY_PASSWORD': 'secret:two',
            }, android)
            self.assertEqual((android / 'release.keystore').read_bytes(), b'fixture-key')
            properties = (android / 'key.properties').read_text()
            self.assertIn('storePassword=secret\\=one', properties)
            self.assertIn('keyPassword=secret\\:two', properties)

    def test_version_keeps_prerelease_and_validates_installer_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            spec = Path(directory) / "pubspec.yaml"
            spec.write_text("version: 1.2.3-beta.1+42\n")
            version = read_version(spec)
            self.assertEqual(version["tag"], "v1.2.3-beta.1")
            self.assertEqual(version["windows"], "1.2.3.42")
            self.assertTrue(version["prerelease"])
            for invalid in ("1.2.3", "1.2.3+0", "1.2.3+65536", "1.2.3+4;evil"):
                spec.write_text(f"version: {invalid}\n")
                with self.assertRaises(ValueError):
                    read_version(spec)

    def test_feeds_verify_real_signatures_and_require_complete_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "key.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "Ed25519", "-out", str(key)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            pub = root / "public.pem"
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(pub)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.assertEqual(len(base64.b64decode(public_key(key))), 32)
            artifacts, feeds = root / "dist", root / "feeds"
            artifacts.mkdir()
            version = {"version": "1.2.3", "build": 42, "tag": "v1.2.3"}
            with self.assertRaisesRegex(ValueError, "missing or empty"):
                generate(artifacts, feeds, key, "owner/Vela", version)
            for name in [*required_artifacts("1.2.3").values(),
                         "Vela-1.2.3-macos-arm64.dmg", "Vela-1.2.3-macos-x64.dmg"]:
                (artifacts / name).write_bytes(b"fixture-" + name.encode())
            generate(artifacts, feeds, key, "owner/Vela", version)
            for target in required_artifacts('1.2.3'):
                envelope = json.loads((feeds / f"{target}.json").read_text())
                payload = base64.b64decode(envelope["payload"])
                document = json.loads(payload)
                self.assertEqual(document["build"], 42)
                self.assertTrue(document["url"].startswith("https://github.com/owner/Vela/releases/download/v1.2.3/"))
                self.verify_signature(root, pub, payload, envelope["signature"])
                self.verify_signature(root, pub, payload + b"tampered", envelope["signature"], valid=False)
                if target.startswith('macos-'):
                    source = artifacts / required_artifacts('1.2.3')[target]
                    self.verify_signature(root, pub, source.read_bytes(), document['edSignature'])
            self.assertEqual(len((artifacts / "SHA256SUMS").read_text().splitlines()), 7)

    def verify_signature(self, root, public, payload, signature, valid=True):
        source, sig = root / "source", root / "signature"
        source.write_bytes(payload)
        sig.write_bytes(base64.b64decode(signature))
        result = subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey",
                                 str(public), "-in", str(source), "-sigfile", str(sig)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.assertEqual(result.returncode == 0, valid)


if __name__ == "__main__":
    unittest.main()
