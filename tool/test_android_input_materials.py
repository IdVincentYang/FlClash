import hashlib
import io
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import android_input_materials as materials


class MaterialTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.tree = self.root / 'tree'
        self.tree.mkdir()
        self.archive = self.root / 'payload.tar.gz'

    def spec(self, format='tar.gz'):
        data = self.archive.read_bytes()
        return {'prefix': 'pkg', 'format': format,
                'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

    def tar(self, entries):
        with tarfile.open(self.archive, 'w:gz') as archive:
            for name, kind, value in entries:
                item = tarfile.TarInfo(name)
                item.mode = 0o755 if name.endswith('tool') else 0o644
                if kind == 'file':
                    item.size = len(value)
                    archive.addfile(item, io.BytesIO(value))
                else:
                    item.type = {'symlink': tarfile.SYMTYPE,
                                 'hardlink': tarfile.LNKTYPE,
                                 'fifo': tarfile.FIFOTYPE}[kind]
                    item.linkname = value
                    archive.addfile(item)

    def basic(self):
        self.tar([('pkg/bin/tool', 'file', b'accepted code'),
                  ('pkg/bin/alias', 'symlink', 'tool'),
                  ('pkg/tool-copy', 'hardlink', 'pkg/bin/tool')])
        (self.tree / 'bin').mkdir()
        tool = self.tree / 'bin/tool'
        tool.write_bytes(b'accepted code')
        tool.chmod(0o755)
        (self.tree / 'bin/alias').symlink_to('tool')
        os.link(tool, self.tree / 'tool-copy')
        return materials.read_archive(self.archive, self.spec())

    def test_exact_payload_preserves_ordinary_symbolic_and_hard_links(self):
        index = self.basic()
        result = materials.compare_tree(self.tree, index)
        self.assertEqual(result['entries_checked'], 4)
        self.assertTrue(result['complete_tree'])
        self.assertEqual(result['generation_causality'], 'not_proven')

    def test_cached_payload_copy_preserves_links_and_has_independent_file_inodes(self):
        index = self.basic()
        destination = self.root / 'owned-copy'
        result = materials.materialize_tree(self.tree, index, destination)
        self.assertTrue(result['complete_tree'])
        self.assertNotEqual((self.tree / 'bin/tool').stat().st_ino,
                            (destination / 'bin/tool').stat().st_ino)
        self.assertEqual((destination / 'bin/tool').stat().st_ino,
                         (destination / 'tool-copy').stat().st_ino)
        (destination / 'bin/tool').write_bytes(b'owned mutation')
        self.assertEqual((self.tree / 'bin/tool').read_bytes(), b'accepted code')

    def test_cached_payload_never_opens_or_copies_extra_snapshot_or_external_alias(self):
        index = self.basic()
        private = self.root / 'unselected'
        private.write_bytes(b'not a selected archive member')
        (self.tree / 'old.snapshot').symlink_to(private)
        inode = private.stat().st_ino
        original = os.fdopen

        def guarded(fd, *args, **kwargs):
            self.assertNotEqual(os.fstat(fd).st_ino, inode)
            return original(fd, *args, **kwargs)

        with patch.object(os, 'fdopen', guarded):
            destination = self.root / 'selected-members-only'
            materials.materialize_tree(self.tree, index, destination)
        self.assertFalse((destination / 'old.snapshot').exists())
        self.assertFalse((destination / 'old.snapshot').is_symlink())

    def test_corrupt_cached_payload_fails_before_creating_a_copy(self):
        index = self.basic()
        source = self.tree / 'bin/tool'
        stat_before = source.stat()
        source.write_bytes(b'replaced code')
        os.utime(source, ns=(stat_before.st_atime_ns, stat_before.st_mtime_ns))
        destination = self.root / 'not-created'
        with self.assertRaises(materials.MaterialError):
            materials.materialize_tree(self.tree, index, destination)
        self.assertFalse(destination.exists())
        self.assertEqual(source.read_bytes(), b'replaced code')

    def test_same_size_and_mtime_replacement_fails(self):
        index = self.basic()
        path = self.tree / 'bin/tool'
        before = path.stat()
        path.write_bytes(b'replaced code')
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        self.assertEqual(path.stat().st_size, before.st_size)
        with self.assertRaises(materials.MaterialError):
            materials.compare_tree(self.tree, index)

    def test_archive_identity_is_checked_before_member_processing(self):
        self.basic()
        spec = self.spec()
        spec['sha256'] = '0' * 64
        with patch.object(tarfile, 'open', side_effect=AssertionError('parsed unaccepted archive')):
            with self.assertRaises(materials.MaterialError):
                materials.read_archive(self.archive, spec)

    def test_bad_archive_paths_links_and_special_members_are_rejected(self):
        for name, kind, value in [
                ('pkg/../outside', 'file', b'bad'),
                ('/absolute', 'file', b'bad'),
                ('pkg/link', 'symlink', '../../outside'),
                ('pkg/link', 'symlink', '/outside'),
                ('pkg/link', 'hardlink', 'other/root'),
                ('pkg/pipe', 'fifo', ''),
        ]:
            with self.subTest(name=name, kind=kind, value=value):
                self.tar([(name, kind, value)])
                with self.assertRaises(materials.MaterialError):
                    materials.read_archive(self.archive, self.spec())

    def test_virtual_directory_symlink_cycles_do_not_recurse_forever(self):
        self.tar([('pkg/regular', 'file', b'valid payload'),
                  ('pkg/a', 'symlink', 'b/file'),
                  ('pkg/b', 'symlink', 'a')])
        with self.assertRaisesRegex(materials.MaterialError, 'Cyclic'):
            materials.read_archive(self.archive, self.spec())

    def test_component_prefix_excludes_installer_but_bounds_all_members(self):
        self.tar([('installer', 'file', b'not part of installed component'),
                  ('pkg/bin/tool', 'file', b'accepted code')])
        index = materials.read_archive(self.archive, self.spec())
        self.assertEqual(set(index), {'bin', 'bin/tool'})
        with patch.object(materials, 'MAX_EXPANDED', len(b'accepted code')):
            with self.assertRaisesRegex(materials.MaterialError, 'expanded-size'):
                materials.read_archive(self.archive, self.spec())
        with patch.object(materials, 'MAX_ENTRIES', 1):
            with self.assertRaisesRegex(materials.MaterialError, 'excessive'):
                materials.read_archive(self.archive, self.spec())

    def test_framework_style_directory_link_resolves_to_accepted_payload(self):
        self.tar([('pkg/Versions/A/Resources/data', 'file', b'data'),
                  ('pkg/Versions/Current', 'symlink', 'A'),
                  ('pkg/Resources', 'symlink', 'Versions/Current/Resources')])
        index = materials.read_archive(self.archive, self.spec())
        self.assertEqual(materials.resolve_link('Resources', index), 'Versions/A/Resources')

    def test_no_read_through_local_file_or_parent_symlink(self):
        index = self.basic()
        private = self.root / 'private'
        private.write_bytes(b'private data')
        inode = private.stat().st_ino
        original = os.fdopen

        def no_private(fd, *args, **kwargs):
            self.assertNotEqual(os.fstat(fd).st_ino, inode)
            return original(fd, *args, **kwargs)

        (self.tree / 'bin/alias').unlink()
        (self.tree / 'bin/alias').symlink_to(private)
        with patch.object(os, 'fdopen', no_private):
            with self.assertRaises(materials.MaterialError):
                materials.compare_tree(self.tree, index)
        with materials.SelectedRoot(self.tree, directory=True) as root:
            with self.assertRaises(materials.MaterialError):
                with root.file('../private'):
                    self.fail('outside file opened')

    def test_extra_unaccepted_content_is_not_opened(self):
        index = self.basic()
        (self.tree / 'unaccepted').write_bytes(b'not inspected')
        with patch.object(os, 'fdopen', side_effect=AssertionError('opened before inventory rejection')):
            with self.assertRaises(materials.MaterialError):
                materials.compare_tree(self.tree, index)

    def test_duplicate_member_and_member_beneath_link_are_rejected(self):
        for entries in [
            [('pkg/a', 'file', b'a'), ('pkg/a', 'file', b'b')],
            [('pkg/a', 'symlink', 'target'), ('pkg/a/file', 'file', b'x')],
        ]:
            with self.subTest(entries=entries):
                self.tar(entries)
                with self.assertRaises(materials.MaterialError):
                    materials.read_archive(self.archive, self.spec())

    def test_archive_resource_bounds(self):
        self.basic()
        for field, value in [('MAX_ENTRIES', 1), ('MAX_EXPANDED', 2)]:
            with self.subTest(field=field), patch.object(materials, field, value):
                with self.assertRaises(materials.MaterialError):
                    materials.read_archive(self.archive, self.spec())

    def test_zip_symlink_is_data_not_a_file_to_execute(self):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            item = zipfile.ZipInfo('pkg/bin/tool')
            item.external_attr = (stat.S_IFREG | 0o755) << 16
            archive.writestr(item, b'never execute this file')
            link = zipfile.ZipInfo('pkg/bin/alias')
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, 'tool')
        index = materials.read_archive(self.archive, self.spec('zip'))
        self.assertEqual(index['bin/alias']['kind'], 'symlink')
        self.assertEqual(materials.resolve_link('bin/alias', index), 'bin/tool')

    def test_materialize_preserves_payload_and_links_without_installer(self):
        self.basic()
        target = self.root / 'new-component'
        result = materials.materialize_archive(self.archive, self.spec(), target)
        self.assertTrue(result['complete_tree'])
        self.assertEqual((target / 'bin/alias').read_bytes(), b'accepted code')
        self.assertEqual((target / 'bin/tool').stat().st_ino,
                         (target / 'tool-copy').stat().st_ino)

    def test_materialize_preserves_framework_directory_aliases(self):
        self.tar([('pkg/Versions/A/Resources/data', 'file', b'data'),
                  ('pkg/Versions/Current', 'symlink', 'A'),
                  ('pkg/Resources', 'symlink', 'Versions/Current/Resources')])
        target = self.root / 'framework'
        materials.materialize_archive(self.archive, self.spec(), target)
        self.assertEqual((target / 'Resources/data').read_bytes(), b'data')
        self.assertTrue((target / 'Resources').is_symlink())

    def test_materialize_rejects_existing_destination_without_reading_it(self):
        self.basic()
        with patch.object(materials.SelectedRoot, 'inventory',
                          side_effect=AssertionError('read existing destination')):
            with self.assertRaises(FileExistsError):
                materials.materialize_archive(self.archive, self.spec(), self.tree)
        target = self.root / 'existing-link'
        target.symlink_to(self.tree, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            materials.materialize_archive(self.archive, self.spec(), target)

    def test_materialize_checks_archive_before_creating_destination(self):
        self.basic()
        spec = self.spec()
        target = self.root / 'new-component'
        spec['sha256'] = '0' * 64
        with self.assertRaises(materials.MaterialError):
            materials.materialize_archive(self.archive, spec, target)
        self.assertFalse(target.exists())

    def test_materialize_ignores_archive_installer_and_checks_zip(self):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('installer', b'do not execute')
            archive.writestr('pkg/data', b'accepted data')
        target = self.root / 'zip-component'
        materials.materialize_archive(self.archive, self.spec('zip'), target)
        self.assertEqual((target / 'data').read_bytes(), b'accepted data')
        self.assertEqual({p.name for p in target.iterdir()}, {'data'})

    def test_standalone_binary_is_copied_exactly_with_accepted_executable_mode(self):
        self.archive.write_bytes(b'accepted executable bytes; never execute')
        spec = self.spec('file')
        spec.update(prefix='', payload='tool', mode=0o755)
        target = self.root / 'binary'
        materials.materialize_archive(self.archive, spec, target)
        self.assertEqual((target / 'tool').read_bytes(), self.archive.read_bytes())
        self.assertEqual((target / 'tool').stat().st_mode & 0o777, 0o755)

    def test_merge_maps_a_verified_component_without_overwriting_other_files(self):
        index = self.basic()
        target = self.root / 'combined'
        target.mkdir()
        (target / 'unrelated').write_bytes(b'preserve')
        mapped = materials.merge_materialized(self.tree, index, target, 'nested/component')
        self.assertEqual((target / 'nested/component/bin/alias').read_bytes(), b'accepted code')
        self.assertEqual((target / 'unrelated').read_bytes(), b'preserve')
        materials.compare_tree(target, mapped, complete=False)

    def test_merge_refuses_a_conflicting_file_and_an_external_parent_link(self):
        index = self.basic()
        target = self.root / 'combined'
        (target / 'component/bin').mkdir(parents=True)
        (target / 'component/bin/tool').write_bytes(b'keep existing data')
        with self.assertRaises(materials.MaterialError):
            materials.merge_materialized(self.tree, index, target, 'component')
        self.assertEqual((target / 'component/bin/tool').read_bytes(), b'keep existing data')
        (target / 'external').symlink_to(self.tree, target_is_directory=True)
        with self.assertRaises(OSError):
            materials.merge_materialized(self.tree, index, target, 'external')


if __name__ == '__main__':
    unittest.main()
