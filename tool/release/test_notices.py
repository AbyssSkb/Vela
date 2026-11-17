import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from notices import generate


class NoticeTests(unittest.TestCase):
    def test_unicode_license_is_utf8_under_non_utf8_process_locale(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = self.fixture(root)
            crate = Path(package['manifest_path']).parent
            (crate / 'LICENSE').write_text('Copyright Michał\n', encoding='utf-8')
            metadata, sources = root / 'metadata.json', root / 'sources.json'
            metadata.write_text(json.dumps({'packages': [package]}), encoding='utf-8')
            sources.write_text('{"packages":{}}', encoding='utf-8')
            output = root / 'output'
            environment = os.environ | {'LC_ALL': 'C', 'PYTHONCOERCECLOCALE': '0', 'PYTHONIOENCODING': 'ascii'}
            subprocess.run([sys.executable, '-X', 'utf8=0', str(Path(__file__).with_name('notices.py')),
                            '--metadata', str(metadata), '--sources', str(sources), '--output', str(output)],
                           env=environment, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.assertIn('Copyright Michał\n'.encode('utf-8'), (output / 'RUST-NOTICES.txt').read_bytes())

    def test_windows_checkout_preserves_upstream_license_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, checkout, hooks = root / 'source', root / 'checkout', root / 'hooks'
            source.mkdir()
            hooks.mkdir()
            git = ['git', '-c', f'core.hooksPath={hooks}', '-c', 'commit.gpgsign=false']
            def run(*args, cwd=source):
                subprocess.run(git + list(args), cwd=cwd, check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            run('init', '--quiet')
            attributes = Path(__file__).resolve().parents[2] / '.gitattributes'
            shutil.copyfile(attributes, source / '.gitattributes')
            name = Path('tool/release/licenses/fixture-LICENSE.md')
            (source / name).parent.mkdir(parents=True)
            original = b'Original upstream license\nCopyright fixture author\n'
            (source / name).write_bytes(original)
            run('-c', 'core.autocrlf=false', 'add', '.')
            run('-c', 'user.name=Vela tests', '-c', 'user.email=tests@example.invalid',
                'commit', '--quiet', '-m', 'Fixture')
            run('clone', '--quiet', '--no-checkout', str(source), str(checkout), cwd=root)
            run('-c', 'core.autocrlf=true', 'checkout', '--quiet', 'HEAD', cwd=checkout)
            self.assertEqual((checkout / name).read_bytes(), original)

    def fixture(self, root, name='fixture', targets=None):
        crate = root / name
        crate.mkdir()
        (crate / 'Cargo.toml').write_text('[package]\n')
        return {'name': name, 'version': '1.2.3', 'source': 'registry+fixture',
                'license': 'MIT OR Apache-2.0', 'license_file': None,
                'repository': 'https://github.com/example/fixture',
                'manifest_path': str(crate / 'Cargo.toml'),
                'targets': targets or [{'kind': ['lib']}]}

    def test_dual_license_and_notice_text_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = self.fixture(root)
            crate = Path(package['manifest_path']).parent
            for name in ('LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE'):
                (crate / name).write_text('Original ' + name)
            sources = root / 'sources.json'
            sources.write_text('{"packages":{}}')
            output = root / 'output'
            generate({'packages': [package]}, output, sources)
            text = (output / 'RUST-NOTICES.txt').read_text()
            for name in ('LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE'):
                self.assertIn('Original ' + name, text)
            self.assertNotIn(str(root), text)

    def test_missing_runtime_license_fails_and_does_not_create_a_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = self.fixture(root)
            sources = root / 'sources.json'
            sources.write_text('{"packages":{}}')
            with self.assertRaisesRegex(ValueError, 'no license text'):
                generate({'packages': [package]}, root / 'output', sources)
            self.assertFalse((root / 'output').exists())

    def test_exact_upstream_revision_and_content_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = self.fixture(root)
            crate = Path(package['manifest_path']).parent
            (crate / '.cargo_vcs_info.json').write_text('{"git":{"sha1":"abc"}}')
            license_file = root / 'LICENSE'
            license_file.write_text('Actual upstream license text')
            entry = {'revision': 'abc', 'files': [{'file': 'LICENSE', 'url': 'https://github.com/example/fixture/blob/abc/LICENSE',
                      'sha256': hashlib.sha256(license_file.read_bytes()).hexdigest()}]}
            sources = root / 'sources.json'
            sources.write_text(json.dumps({'packages': {'fixture@1.2.3': entry}}))
            generate({'packages': [package]}, root / 'output', sources)
            license_file.write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'checksum changed'):
                generate({'packages': [package]}, root / 'output', sources)
            entry['revision'] = 'wrong'
            sources.write_text(json.dumps({'packages': {'fixture@1.2.3': entry}}))
            with self.assertRaisesRegex(ValueError, 'revision does not match'):
                generate({'packages': [package]}, root / 'output', sources)

    def test_only_declared_proc_macro_can_use_build_time_attribution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = self.fixture(root, targets=[{'kind': ['proc-macro']}, {'kind': ['test']}])
            crate = Path(package['manifest_path']).parent
            (crate / '.cargo_vcs_info.json').write_text('{"git":{"sha1":"abc"}}')
            (crate / 'Cargo.toml.orig').write_text('license = "MIT OR Apache-2.0"')
            (crate / 'README.md').write_text('Original author attribution')
            sources = root / 'sources.json'
            sources.write_text(json.dumps({'packages': {'fixture@1.2.3': {
                'revision': 'abc', 'files': [], 'build_time_attribution_only': True}}}))
            output = root / 'output'
            generate({'packages': [package]}, output, sources)
            self.assertIn('This is not runtime license coverage', (output / 'RUST-NOTICES.txt').read_text())
            package['targets'] = [{'kind': ['lib']}]
            with self.assertRaisesRegex(ValueError, 'proc-macro-only'):
                generate({'packages': [package]}, output, sources)


if __name__ == '__main__':
    unittest.main()
