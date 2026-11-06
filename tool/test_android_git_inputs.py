from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import android_git_inputs as sources
from android_input_materials import MaterialError, compare_tree


class GitSourceTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.env = sources.git_environment(self.root)
        self.git('init', '-b', 'accepted')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.source / 'bin').mkdir()
        (self.source / 'bin/tool').write_bytes(b'accepted tool bytes; never execute')
        (self.source / 'bin/tool').chmod(0o755)
        (self.source / 'alias').symlink_to('bin/tool')
        self.git('add', '.')
        self.git('commit', '-m', 'Fixed source')
        self.commit = self.git('rev-parse', 'HEAD').strip().decode()

    def git(self, *arguments):
        return subprocess.run(['/usr/bin/git', '-C', str(self.source), *arguments],
                              env=self.env, check=True, capture_output=True).stdout

    def export(self):
        return sources.export_objects(self.source / '.git/objects',
                                      self.commit, self.root / 'export')

    def test_fixed_objects_and_exact_bytes_include_executable_and_symlink(self):
        repository = self.export()
        index = sources.source_index(repository, self.commit, self.root)
        self.assertEqual(index['bin/tool']['mode'], 0o755)
        self.assertEqual(index['alias']['target'], 'bin/tool')
        self.assertEqual(index['bin/tool']['size'], 34)
        compare_tree(self.source, index, complete=False)
        (self.source / 'bin/tool').write_bytes(b'replaced tool bytes; never execute')
        with self.assertRaises(MaterialError):
            compare_tree(self.source, index, complete=False)

    def test_export_does_not_import_source_config_or_unrelated_objects(self):
        (self.source / 'private').write_bytes(b'unrelated object')
        self.git('add', 'private')
        self.git('commit', '-m', 'Unselected source')
        excluded = self.git('rev-parse', 'HEAD:private').strip().decode()
        with (self.source / '.git/config').open('a') as stream:
            stream.write('\n[include]\n\tpath = /unselected/private/config\n')
        repository = self.export()
        index = sources.source_index(repository, self.commit, self.root)
        self.assertNotIn('private', index)
        self.assertNotIn('unselected', (repository / 'config').read_text())
        result = subprocess.run(['/usr/bin/git', '--git-dir', str(repository),
                                 'cat-file', '-e', excluded], env=self.env,
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_cached_object_alternates_and_symlinks_reject_before_export(self):
        objects = self.source / '.git/objects'
        (objects / 'info/alternates').write_text('/unselected/private/objects\n')
        with self.assertRaises(MaterialError):
            self.export()
        self.assertFalse((self.root / 'export').exists())
        (objects / 'info/alternates').unlink()
        (objects / 'outside').symlink_to(self.root / 'unselected')
        with self.assertRaises(MaterialError):
            self.export()

    def test_missing_object_and_bad_commit_are_not_accepted(self):
        with self.assertRaises(MaterialError):
            sources.export_objects(self.source / '.git/objects',
                                   '../commit', self.root / 'export')
        with self.assertRaises(subprocess.CalledProcessError):
            sources.export_objects(self.source / '.git/objects',
                                   '0' * 40, self.root / 'export')

    def test_native_archive_materialization_uses_blob_bytes_before_checkout_conversion(self):
        (self.source / '.gitattributes').write_text('*.bat text eol=crlf\n')
        (self.source / 'windows.bat').write_bytes(b'first\nsecond\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Native checkout conversion')
        self.commit = self.git('rev-parse', 'HEAD').strip().decode()
        repository = self.export()
        destination = self.root / 'materialized'
        result = sources.materialize_source(repository, self.commit, destination, self.root)
        self.assertTrue(result['source_blob_bytes_checked'])
        self.assertEqual((destination / 'windows.bat').read_bytes(), b'first\nsecond\n')
        self.assertTrue((destination / 'alias').is_symlink())
        identity = subprocess.run(['/usr/bin/git', '-C', str(destination), 'rev-parse', 'HEAD'],
                                  env=self.env, check=True, capture_output=True).stdout
        self.assertEqual(identity.strip().decode(), self.commit)

    def test_unexpected_git_config_is_rejected_before_git_can_read_includes(self):
        repository = self.export()
        with (repository / 'config').open('a') as stream:
            stream.write('\n[include]\n\tpath = /unselected/private/config\n')
        with patch.object(subprocess, 'run', side_effect=AssertionError('Git read unaccepted config')):
            with self.assertRaises(MaterialError):
                sources.source_index(repository, self.commit, self.root)


if __name__ == '__main__':
    unittest.main()
