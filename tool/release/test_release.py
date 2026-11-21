import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from textwrap import dedent
import unittest

from feeds import generate, public_key, required_artifacts
from android_signing import RELEASE_CERT_SHA256, configure, verify_release_signer
from macos_entitlements import validate as validate_macos_entitlements
from version import precedence, read_version


class ReleaseTests(unittest.TestCase):
    def test_android_release_requires_only_the_published_signer(self):
        report = f"Signer #1 certificate SHA-256 digest: {RELEASE_CERT_SHA256}\n"
        verify_release_signer(report)
        for invalid in ("", report.replace(RELEASE_CERT_SHA256, "0" * 64),
                        report + report.replace("#1", "#2")):
            with self.assertRaises(ValueError):
                verify_release_signer(invalid)

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
        result, commands = self.run_publication(publish=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(command[:3] == ['release', 'create', 'v1.2.3'] and '--draft' in command
                            for command in commands))
        self.assertTrue(any(command[:3] == ['release', 'upload', 'v1.2.3'] for command in commands))
        self.assertFalse(any(command[:2] == ['release', 'edit'] for command in commands))
        self.assertFalse(any('updates' in command for command in commands))

    def test_live_feeds_follow_completed_version_publication(self):
        result, commands = self.run_publication(publish=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        publish = next(i for i, command in enumerate(commands) if command[:2] == ['release', 'edit'])
        feeds, upload = next((i, command) for i, command in enumerate(commands)
                             if command[:3] == ['release', 'upload', 'updates'])
        self.assertLess(publish, feeds)
        self.assertFalse(any(command[:3] == ['release', 'upload', 'v1.2.3'] for command in commands))
        self.assertEqual({Path(argument).name for argument in upload[3:] if not argument.startswith('-')},
                         {f'{target}.json' for target in required_artifacts('1.2.3')})

    def test_publish_retry_keeps_the_versioned_release_intact(self):
        result, commands = self.run_publication(publish=True, change='already published')
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = [command[:3] for command in commands if command[1] in ('create', 'edit', 'upload')]
        self.assertEqual(mutations, [['release', 'upload', 'updates']])

    def test_publish_rejects_missing_approval_or_changes_to_reviewed_draft(self):
        for change in ('no approval', 'changed notes', 'missing asset', 'bad checksum',
                       'changed download', 'moved tag'):
            with self.subTest(change=change):
                result, commands = self.run_publication(publish=True, change=change)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(command[1] in ('create', 'edit', 'upload') for command in commands))

    def test_older_versions_or_reused_build_numbers_cannot_be_released(self):
        for publish in (False, True):
            for prior in ('1.2.2+42', '1.2.4+41'):
                with self.subTest(publish=publish, prior=prior):
                    result, commands = self.run_publication(publish=publish, prior=prior)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(command[1] in ('create', 'edit', 'upload') for command in commands))

    def run_publication(self, publish, *, change=None, prior='1.2.2+41'):
        source = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'tool' / 'release'
            scripts.mkdir(parents=True)
            for name in ('version.py', 'publish.sh', 'feeds.py', 'publication.py'):
                shutil.copyfile(source / name, scripts / name)
            (root / 'pubspec.yaml').write_text('version: 1.2.3+42\n')
            (root / 'bin').mkdir()
            targets = required_artifacts('1.2.3')
            packages = [*targets.values(), 'Vela-1.2.3-macos-arm64.dmg', 'Vela-1.2.3-macos-x64.dmg']
            manifests = [f'{target}.json' for target in targets]
            contents = {name: f'fixture {name}\n' for name in (*packages, *manifests)}
            checksums = {name: hashlib.sha256(contents[name].encode()).hexdigest() for name in packages}
            if change == 'bad checksum':
                checksums[packages[0]] = '0' * 64
            contents['SHA256SUMS'] = ''.join(f'{digest}  {name}\n' for name, digest in checksums.items())
            if change == 'missing asset':
                del contents['android-arm64.json']
            if not publish:
                for folder, names in (('dist', [*packages, 'SHA256SUMS']), ('feeds', manifests)):
                    (root / folder).mkdir()
                    for name in names:
                        (root / folder / name).write_text(contents[name])

            commit = 'a' * 40
            release = {
                'assets': [{'name': name, 'id': str(i), 'state': 'uploaded', 'size': len(data),
                            'digest': 'sha256:' + hashlib.sha256(data.encode()).hexdigest()}
                           for i, (name, data) in enumerate(contents.items())],
                'body': 'Reviewed release notes', 'id': 'release-id', 'isDraft': True,
                'isPrerelease': False, 'name': 'Vela 1.2.3', 'tagName': 'v1.2.3',
                'targetCommitish': commit,
            }
            fixture = {'commit': commit, 'prior': prior, 'release': release if publish else None,
                       'contents': contents}
            (root / 'release.json').write_text(json.dumps(fixture))
            gh = root / 'bin' / 'gh'
            gh.write_text('#!/usr/bin/env python3\n' + dedent(r'''
                import json, os, sys
                from pathlib import Path

                args = sys.argv[1:]
                tag = os.environ['TAG']
                fixture = json.loads(Path('release.json').read_text())
                with open(os.environ['COMMANDS'], 'a') as log:
                    log.write(json.dumps(args) + '\n')

                if args[:2] == ['api', '--paginate']:
                    print('v' + fixture['prior'].partition('+')[0])
                    print('updates')
                elif any('/contents/pubspec.yaml' in argument for argument in args):
                    print(f"version: {fixture['prior']}")
                elif any('/commits/' in argument for argument in args):
                    print(fixture['commit'])
                elif args[:3] == ['release', 'view', tag] and fixture['release']:
                    print(json.dumps(fixture['release']))
                elif args[:3] == ['release', 'view', 'updates'] and fixture.get('rolling_exists'):
                    print('Vela update feeds')
                elif args[:3] == ['release', 'download', tag]:
                    directory = Path(args[args.index('--dir') + 1])
                    for name, data in fixture['contents'].items():
                        if name.endswith('.json') or name == 'SHA256SUMS':
                            (directory / name).write_text(data)
                elif args[0] != 'release' or args[1] not in ('create', 'edit', 'upload'):
                    sys.exit(1)
            '''))
            gh.chmod(0o755)
            git = root / 'bin' / 'git'
            git.write_text(f'#!/bin/sh\nprintf "%s\\n" "{commit}"\n')
            git.chmod(0o755)
            commands = root / 'commands.jsonl'
            commands.touch()
            environment = os.environ | {
                'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                'RUNNER_TEMP': str(root), 'GH_REPO': 'owner/Vela', 'TAG': 'v1.2.3',
                'PUBLISH': str(publish).lower(), 'COMMANDS': str(commands),
                'APPROVED_FINGERPRINT': '',
            }
            if publish and change != 'no approval':
                reviewed = subprocess.run(['python3', str(scripts / 'publication.py'), 'fingerprint', 'v1.2.3'],
                                          cwd=root, env=environment, capture_output=True, text=True)
                self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
                environment['APPROVED_FINGERPRINT'] = reviewed.stdout.strip()
                commands.write_text('')
            if change == 'already published':
                release['isDraft'] = False
                fixture['rolling_exists'] = True
            elif change == 'changed notes':
                release['body'] = 'Unreviewed release notes'
            elif change == 'changed download':
                contents['android-arm64.json'] = 'unreviewed feed\n'
            elif change == 'moved tag':
                fixture['commit'] = 'b' * 40
            (root / 'release.json').write_text(json.dumps(fixture))
            result = subprocess.run(['bash', str(scripts / 'publish.sh')], cwd=root, env=environment,
                                    capture_output=True, text=True)
            return result, [json.loads(line) for line in commands.read_text().splitlines()]

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

    def test_version_precedence_compares_beta_numbers_numerically(self):
        versions = ['0.1.0-beta.9', '0.1.0-beta.10', '0.1.0', '0.2.0-beta.1']
        self.assertEqual(sorted(reversed(versions), key=precedence), versions)

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
