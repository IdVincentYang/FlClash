import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from android_hook_environment import check_hook_outputs, configure_hook_pubspec, file_identity
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
                        'flclash_android_environment': str(self.root / 'hook-environment.json'),
                        'flclash_android_inputs_sha256': self.digest},
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
            if hook == 'setup':
                names = ['libclash/android/arm64-v8a/libclash.so',
                         'android/core/src/main/jniLibs/arm64-v8a/libclash.so',
                         'libclash/android/includes/arm64-v8a/libclash.h',
                         'android/core/src/main/cpp/includes/arm64-v8a/libclash.h']
            else:
                names = ['.dart_tool/hooks_runner/shared/rust_api/build/configuration/target/aarch64-linux-android/release/librust_api.so']
            generated = {}
            for name in names:
                path = self.root / 'source' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'actual producer fixture')
                generated[str(path)] = file_identity(path)
            output['assets_for_build'].append({'type': 'hooks/metadata', 'encoding': {
                'key': 'flclash_android_generated_outputs', 'value': json.dumps(generated)}})
            self.records[hook] = (directory, native_input, output)
        self.write()

    def write(self):
        for directory, native_input, output in self.records.values():
            (directory / 'input.json').write_text(json.dumps(native_input))
            (directory / 'output.json').write_text(json.dumps(output))

    def test_both_current_standard_outputs_are_required(self):
        self.assertEqual(set(check_hook_outputs(self.root, self.digest, self.digest)), {'setup', 'rust_api'})
        (self.records['setup'][0] / 'output.json').unlink()
        with self.assertRaises(OSError):
            check_hook_outputs(self.root, self.digest, self.digest)

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
                    check_hook_outputs(self.root, self.digest, self.digest)


    def test_changed_producer_bytes_and_cross_checkpoint_requalification_fail(self):
        expected = check_hook_outputs(self.root, self.digest, self.digest)
        path = next(iter(expected['rust_api']['generated']))
        Path(path).write_bytes(b'corrupt producer bytes!')
        with self.assertRaises(MaterialError):
            check_hook_outputs(self.root, self.digest, self.digest)
        record = self.records['rust_api'][2]['assets_for_build'][2]['encoding']
        record['value'] = json.dumps({path: file_identity(path)})
        self.write()
        with self.assertRaises(MaterialError):
            check_hook_outputs(self.root, self.digest, self.digest, expected)

    def test_pubspec_change_keeps_dependency_declarations_and_enabled_hooks(self):
        path = self.root / 'source/pubspec.yaml'
        path.write_text('name: example\nhooks:\n  user_defines:\n'
                        '    setup:\n      build_assets: true\n'
                        '    rust_api:\n      build_assets: true\n'
                        'dependencies:\n  existing: 1.2.3\n')
        configure_hook_pubspec(self.root, self.digest)
        actual = path.read_text()
        self.assertEqual(actual.count('flclash_android_environment:'), 2)
        self.assertEqual(actual.count('build_assets: true'), 2)
        self.assertTrue(actual.endswith('dependencies:\n  existing: 1.2.3\n'))
        with self.assertRaises(MaterialError):
            configure_hook_pubspec(self.root, self.digest)


if __name__ == '__main__':
    unittest.main()
