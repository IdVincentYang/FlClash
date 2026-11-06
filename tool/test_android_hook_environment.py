import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from android_hook_environment import check_hook_outputs, configure_hook_pubspec
from android_input_materials import MaterialError


class HookCompletionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.digest = 'a' * 64
        self.records = {}
        for hook in ('setup', 'rust_api'):
            directory = self.root / 'source/.dart_tool/hooks_runner' / hook / 'configuration'
            directory.mkdir(parents=True)
            native_input = {
                'package_name': hook,
                'package_root': str(self.root / 'source/plugins' / hook) + '/',
                'user_defines': {'workspace_pubspec': {
                    'base_path': str(self.root / 'source/pubspec.yaml'),
                    'defines': {'build_assets': True,
                        'flclash_android_environment': str(self.root / 'hook-environment.json')},
                }},
                'config': {'build_asset_types': ['code_assets/code']},
            }
            output = {
                'status': 'success', 'assets_for_build': [{'type': 'hooks/metadata',
                    'encoding': {'key': 'flclash_android_environment_sha256',
                                 'value': self.digest}},
                    {'type': 'hooks/metadata', 'encoding': {
                        'key': 'flclash_android_hook_input_sha256',
                        'value': hashlib.sha256(json.dumps(native_input).encode()).hexdigest()}}],
                'dependencies': [str(self.root / 'hook-environment.json'),
                                 str(self.root / 'source/tool/android_hook_binding.dart')],
            }
            self.records[hook] = (directory, native_input, output)
        self.write()

    def write(self):
        for directory, native_input, output in self.records.values():
            (directory / 'input.json').write_text(json.dumps(native_input))
            (directory / 'output.json').write_text(json.dumps(output))

    def test_both_current_standard_outputs_are_required(self):
        self.assertEqual(set(check_hook_outputs(self.root, self.digest)), {'setup', 'rust_api'})
        (self.records['setup'][0] / 'output.json').unlink()
        with self.assertRaises(OSError):
            check_hook_outputs(self.root, self.digest)

    def test_apk_with_legacy_stale_failed_or_skipped_hook_cannot_complete(self):
        saved = copy.deepcopy(self.records['rust_api'])
        for change in ('missing_metadata', 'old_digest', 'failed', 'skipped', 'missing_dependency',
                       'wrong_workspace', 'missing_define'):
            with self.subTest(change=change):
                self.records['rust_api'] = copy.deepcopy(saved)
                _, native_input, output = self.records['rust_api']
                if change == 'missing_metadata':
                    del output['assets_for_build']
                elif change == 'old_digest':
                    output['assets_for_build'][0]['encoding']['value'] = 'b' * 64
                elif change == 'failed':
                    output['status'] = 'failure'
                elif change == 'skipped':
                    native_input['config']['build_asset_types'] = []
                elif change == 'missing_dependency':
                    output['dependencies'] = []
                elif change == 'wrong_workspace':
                    native_input['package_root'] = '/other/source/plugins/rust_api/'
                else:
                    del native_input['user_defines']['workspace_pubspec']['defines']['flclash_android_environment']
                self.write()
                with self.assertRaises(MaterialError):
                    check_hook_outputs(self.root, self.digest)

    def test_pubspec_change_keeps_dependency_declarations_and_enabled_hooks(self):
        path = self.root / 'source/pubspec.yaml'
        path.write_text('name: example\nhooks:\n  user_defines:\n'
                        '    setup:\n      build_assets: true\n'
                        '    rust_api:\n      build_assets: true\n'
                        'dependencies:\n  existing: 1.2.3\n')
        configure_hook_pubspec(self.root)
        actual = path.read_text()
        self.assertEqual(actual.count('flclash_android_environment:'), 2)
        self.assertEqual(actual.count('build_assets: true'), 2)
        self.assertTrue(actual.endswith('dependencies:\n  existing: 1.2.3\n'))
        with self.assertRaises(MaterialError):
            configure_hook_pubspec(self.root)


if __name__ == '__main__':
    unittest.main()
