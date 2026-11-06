import json
from pathlib import Path
import tempfile
import unittest

from android_build_profile import ManagedAndroidBuild, read_selections
from android_input_materials import MaterialError


class ProfileSelectionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / 'selections.json'
        self.policy = {'artifacts': {'go': {}, 'framework': {}}}
        self.selection = {'archives': {'go': '/explicit/go.tar.gz',
                                       'framework': '/explicit/framework.git'},
                          'pub_archives': {}, 'git_repositories': {},
                          'maven_root': '/explicit/raw-maven', 'maven_files': {}}

    def read(self):
        self.path.write_text(json.dumps(self.selection))
        return read_selections(self.path, self.policy)

    def test_paths_select_materials_without_accepting_them(self):
        result = self.read()
        self.assertEqual(result['archives']['go'], '/explicit/go.tar.gz')
        self.assertNotIn('profile_ready', result)

    def test_caller_cannot_supply_a_command_reference_hash_or_success_receipt(self):
        for name, value in [('command', ['/bin/echo', 'bypass']),
                            ('sha256', 'a' * 64), ('profile_ready', True),
                            ('verification_metadata', '/candidate/self-signed.xml')]:
            with self.subTest(name=name):
                self.selection[name] = value
                with self.assertRaises(MaterialError):
                    self.read()
                del self.selection[name]

    def test_missing_or_extra_tool_role_fails_before_materials_are_opened(self):
        del self.selection['archives']['framework']
        with self.assertRaises(MaterialError):
            self.read()
        self.selection['archives']['framework'] = '/explicit/framework.git'
        self.selection['archives']['unaccepted'] = '/candidate/executable'
        with self.assertRaises(MaterialError):
            self.read()

    def test_cached_tree_selection_cannot_replace_archive_identity_or_git_source(self):
        self.selection['trees'] = {'go': '/explicit/installed-go'}
        self.assertEqual(self.read()['trees']['go'], '/explicit/installed-go')
        self.selection['trees']['framework'] = '/unaccepted/sdk-state'
        with self.assertRaises(MaterialError):
            self.read()

    def test_duplicate_json_fields_and_symlink_selection_file_are_rejected(self):
        self.path.write_text('{"archives":{},"archives":{}}')
        with self.assertRaises(MaterialError):
            read_selections(self.path, self.policy)
        self.path.unlink()
        target = self.root / 'unselected'
        target.write_text('do not read')
        self.path.symlink_to(target)
        with self.assertRaises(MaterialError):
            read_selections(self.path, self.policy)


class WorkspacePathTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repository = Path(temporary.name) / 'repository'
        (self.repository / 'build').mkdir(parents=True)

    def construct(self, destination):
        return ManagedAndroidBuild(self.repository, {'artifacts': {}}, {}, destination)

    def test_unsupported_leaf_paths_fail_before_creating_a_workspace(self):
        for name in ('outside:owned', 'comma,path', 'escape\\path', 'line\npath',
                     'tab\tpath', 'control\x1fpath', 'delete\x7fpath', 'nonascii路径'):
            with self.subTest(name=name):
                destination = self.repository / 'build' / name
                with self.assertRaises(MaterialError):
                    self.construct(destination)
                self.assertFalse(destination.exists())

    def test_resolved_parent_path_is_checked_as_well_as_leaf(self):
        parent = self.repository / 'build/outside:parent'
        parent.mkdir()
        alias = self.repository / 'build/alias'
        alias.symlink_to(parent, target_is_directory=True)
        for destination in (parent / 'workspace', alias / 'workspace'):
            with self.subTest(destination=destination):
                with self.assertRaises(MaterialError):
                    self.construct(destination)
                self.assertFalse(destination.exists())

    def test_normal_and_space_locations_keep_the_same_canonical_owner(self):
        for name in ('normal', 'space position'):
            with self.subTest(name=name):
                destination = self.repository / 'build' / name
                builder = self.construct(destination)
                self.assertEqual(builder.root, destination.resolve(strict=True))
                self.assertFalse(builder.results['profile_ready'])


if __name__ == '__main__':
    unittest.main()
