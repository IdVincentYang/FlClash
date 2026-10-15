import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'tool' / 'restore_l1_t03_core.py'


def git(root, *args, data=None, check=True):
    result = subprocess.run(['git', '-C', str(root), *args], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise AssertionError(result.stderr.decode())
    return result


def value(root, *args, **kwargs):
    return git(root, *args, **kwargs).stdout.decode().strip()


class RestoreCoreTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='core-carrier-test-')
        self.directory = Path(self.temporary.name)
        source = self.directory / 'source'
        source.mkdir()
        git(source, 'init', '--quiet')
        git(source, 'config', 'user.name', 'Synthetic fixture')
        git(source, 'config', 'user.email', 'synthetic@example.invalid')
        git(source, 'config', 'commit.gpgsign', 'false')
        (source / 'fixture.txt').write_text('public base\n')
        git(source, 'add', '.')
        git(source, 'commit', '--quiet', '-m', 'synthetic base')
        base = value(source, 'rev-parse', 'HEAD')
        self.public = self.directory / 'public-base.git'
        self.public.mkdir()
        git(self.public, 'init', '--bare', '--quiet')
        git(self.public, 'fetch', '--quiet', '--depth=1', str(source), base)
        (source / 'fixture.txt').write_text('candidate\n')
        (source / 'binary.bin').write_bytes(bytes(range(256)))
        git(source, 'add', '.')
        tree = value(source, 'write-tree')
        commit = value(source, 'commit-tree', tree, '-p', base, '-m', 'synthetic change')
        raw = git(source, 'cat-file', 'commit', commit).stdout
        patch = git(source, 'diff', '--binary', base, commit).stdout
        self.root = self.directory / 'parent'
        self.root.mkdir()
        git(self.root, 'init', '--quiet')
        (self.root / '.gitmodules').write_text(
            '[submodule "core/Clash.Meta"]\n\tpath = core/Clash.Meta\n\turl = ' + self.public.as_uri() + '\n')
        git(self.root, 'add', '.gitmodules')
        git(self.root, 'update-index', '--add', '--cacheinfo', '160000,' + commit + ',core/Clash.Meta')
        material = self.root / 'core/patches/l1_t03'
        material.mkdir(parents=True)
        (material / 'source.patch').write_bytes(patch)
        (material / 'commit.txt').write_bytes(raw)
        self.manifest = {
            'repository': self.public.as_uri(), 'base_commit': base,
            'base_tree': value(source, 'rev-parse', base + '^{tree}'),
            'tree': tree, 'commit': commit,
            'patch_sha256': hashlib.sha256(patch).hexdigest(),
            'commit_sha256': hashlib.sha256(raw).hexdigest(),
            'changed_blobs': {path: value(source, 'rev-parse', tree + ':' + path)
                              for path in ('fixture.txt', 'binary.bin')},
        }
        self.manifest_path = material / 'manifest.json'
        self.manifest_path.write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.temporary.cleanup()

    def restore(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), '--root', str(self.root),
                               '--base-repository', str(self.public), *args],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_reconstructs_binary_tree_and_commit_from_only_public_base(self):
        commit = self.manifest['commit']
        self.assertNotEqual(git(self.public, 'cat-file', '-e', commit, check=False).returncode, 0)
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        core = self.root / 'core/Clash.Meta'
        self.assertEqual(value(core, 'rev-parse', 'HEAD'), commit)
        self.assertEqual((core / 'binary.bin').read_bytes(), bytes(range(256)))
        self.assertEqual((core / 'fixture.txt').read_text(), 'candidate\n')
        self.assertNotEqual(git(self.public, 'cat-file', '-e', commit, check=False).returncode, 0)
        check = self.restore('--check')
        self.assertEqual(check.returncode, 0, check.stderr.decode())
        inputs = json.loads(check.stdout)['inputs']
        self.assertIn(str(self.manifest_path.resolve()), inputs)
        self.assertIn(str((self.manifest_path.parent / 'source.patch').resolve()), inputs)
        self.assertIn(str((self.manifest_path.parent / 'commit.txt').resolve()), inputs)
        self.assertIn(str((self.root / '.gitmodules').resolve()), inputs)

    def test_check_does_not_initialize_or_download(self):
        result = self.restore('--check')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'core/Clash.Meta/.git').exists())

    def test_preserves_unrelated_local_changes(self):
        self.assertEqual(self.restore().returncode, 0)
        local = self.root / 'core/Clash.Meta/local-only.txt'
        local.write_text('keep local data')
        for args in [(), ('--check',)]:
            result = self.restore(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(local.read_text(), 'keep local data')

    def test_exact_working_candidate_is_checkable_before_branch_commit(self):
        self.assertEqual(self.restore().returncode, 0)
        core = self.root / 'core/Clash.Meta'
        git(core, 'reset', '--mixed', self.manifest['base_commit'])
        result = self.restore('--check')
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(value(core, 'rev-parse', 'HEAD'), self.manifest['base_commit'])

    def test_corrupt_material_fails_before_install(self):
        patch = self.manifest_path.parent / 'source.patch'
        patch.write_bytes(patch.read_bytes() + b'corruption')
        result = self.restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'core/Clash.Meta/.git').exists())

    def test_missing_material_and_wrong_gitlink_fail_even_with_candidate_present(self):
        self.assertEqual(self.restore().returncode, 0)
        commit = self.manifest_path.parent / 'commit.txt'
        raw = commit.read_bytes()
        commit.unlink()
        self.assertNotEqual(self.restore('--check').returncode, 0)
        commit.write_bytes(raw)
        git(self.root, 'update-index', '--cacheinfo', '160000,' + self.manifest['base_commit'] + ',core/Clash.Meta')
        self.assertNotEqual(self.restore('--check').returncode, 0)

    def test_ignored_compiler_source_is_rejected(self):
        self.assertEqual(self.restore().returncode, 0)
        core = self.root / 'core/Clash.Meta'
        exclude = Path(value(core, 'rev-parse', '--git-path', 'info/exclude'))
        if not exclude.is_absolute():
            exclude = core / exclude
        exclude.write_text('hidden.go\n')
        (core / 'hidden.go').write_text('package hidden\n')
        result = self.restore('--check')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Ignored build source', result.stderr.decode())

    def test_rejects_a_commit_with_another_unpublished_parent(self):
        commit = self.manifest_path.parent / 'commit.txt'
        raw = commit.read_bytes().replace(b'\n\n', b'\nparent ' + b'1' * 40 + b'\n\n', 1)
        commit.write_bytes(raw)
        self.manifest['commit_sha256'] = hashlib.sha256(raw).hexdigest()
        self.manifest_path.write_text(json.dumps(self.manifest))
        result = self.restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('sole parent', result.stderr.decode())


if __name__ == '__main__':
    unittest.main()
