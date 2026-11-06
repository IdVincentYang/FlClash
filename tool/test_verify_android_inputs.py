import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from android_input_materials import MaterialError
import verify_android_inputs as verifier


class InputVerifierTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        (self.root / 'tool').mkdir()
        self.archive = self.root / 'accepted-tool'
        self.archive.write_bytes(b'#!/bin/sh\necho executed > marker\n')
        self.tree = self.root / 'installed'
        self.tree.mkdir()
        (self.tree / 'tool').write_bytes(self.archive.read_bytes())
        (self.tree / 'tool').chmod(0o755)
        self.artifact = {
            'version': '1.0.0', 'selector': 'accepted_bootstrap', 'host': 'macos-arm64',
            'url': 'https://example.invalid/fixed/tool',
            'reference': 'https://example.invalid/fixed/tool.sha256',
            'acceptance': 'Test-only fixed reference',
            'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(),
            'size': self.archive.stat().st_size, 'format': 'file', 'prefix': '',
            'payload': 'tool', 'mode': 0o755, 'complete_tree': True,
        }
        self.policy = {'profiles': {verifier.PROFILE: {
            'host': 'macos-arm64', 'target': 'android-arm64-dev', 'roles': ['fixture'],
        }}, 'artifacts': {'fixture': self.artifact}}

    def write_policy(self, policy=None):
        policy = policy or self.policy
        lines = []
        for group, tables in policy.items():
            for name, table in tables.items():
                lines.append(f'[{group}.{name}]')
                for key, value in table.items():
                    lines.append(f'{key} = {json.dumps(value)}')
        (self.root / 'tool/android_artifacts.toml').write_text('\n'.join(lines) + '\n')

    def invoke(self, *arguments):
        output = io.StringIO()
        with patch.object(verifier, 'REPOSITORY', self.root), \
                patch.object(sys, 'argv', ['verify_android_inputs.py', *arguments]), \
                patch.object(sys, 'platform', 'darwin'), \
                patch.object(verifier.platform, 'machine', return_value='arm64'), \
                contextlib.redirect_stdout(output):
            code = verifier.main()
        return code, json.loads(output.getvalue())

    def test_material_cli_checks_exact_binary_without_executing_it(self):
        self.write_policy()
        code, result = self.invoke('--check-material', 'fixture', '--archive',
                                   f'fixture={self.archive}', '--tree', f'fixture={self.tree}')
        self.assertEqual(code, 0)
        self.assertFalse(result['profile_ready'])
        self.assertEqual(result['status'], 'selected_material_reference_match')
        self.assertFalse((self.root / 'marker').exists())
        self.assertFalse((self.tree / 'marker').exists())

    def test_complete_material_selection_does_not_claim_execution_binding(self):
        self.write_policy()
        code, result = self.invoke('--archive', f'fixture={self.archive}',
                                   '--tree', f'fixture={self.tree}')
        self.assertEqual(code, 1)
        self.assertFalse(result['profile_ready'])
        self.assertEqual(result['status'], 'published_materials_checked_not_execution_binding')

    def test_missing_required_role_prevents_any_material_consumer(self):
        self.policy['profiles'][verifier.PROFILE]['roles'].append('pub_app')
        self.write_policy()
        with patch.object(verifier, 'inspect_material', side_effect=AssertionError('partial profile used')):
            code, result = self.invoke('--archive', 'fixture=/unselected/archive',
                                       '--tree', 'fixture=/unselected/tree')
        self.assertEqual(code, 1)
        self.assertEqual(result['missing_roles'], ['pub_app'])

    def test_noncanonical_version_rejects_before_archive_read(self):
        workflow = self.root / '.github/workflows'
        workflow.mkdir(parents=True)
        (workflow / 'build.yaml').write_text("  GO_VERSION: '2.0.0'\n")
        self.artifact['selector'] = 'workflow.GO_VERSION'
        self.write_policy()
        with patch.object(verifier, 'read_archive', side_effect=AssertionError('opened wrong version')):
            code, result = self.invoke('--check-material', 'fixture', '--archive',
                                       f'fixture={self.archive}', '--tree', f'fixture={self.tree}')
        self.assertEqual(code, 2)
        self.assertIn('canonical tool version', result['reason'])

    def test_bad_policy_representations_reject_without_opening_payload(self):
        for field, value in [('sha256', '0' * 63), ('size', True), ('prefix', '../outside'),
                             ('payload', '/outside'), ('url', 'http://example.invalid/tool'),
                             ('mode', 0o4755), ('host', 'linux-x64'), ('extra', 'unknown')]:
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                policy['artifacts']['fixture'][field] = value
                self.write_policy(policy)
                with self.assertRaises(MaterialError):
                    verifier.policy_from_repository(self.root)

    def test_duplicate_roles_and_selections_are_rejected(self):
        self.policy['profiles'][verifier.PROFILE]['roles'].append('fixture')
        self.write_policy()
        with self.assertRaises(MaterialError):
            verifier.policy_from_repository(self.root)
        with self.assertRaises(MaterialError):
            verifier.selections(['fixture=/a', 'fixture=/b'])

    def test_unsupported_host_rejects_before_reading_policy(self):
        with patch.object(sys, 'argv', ['verify_android_inputs.py']), \
                patch.object(sys, 'platform', 'linux'), \
                patch.object(verifier, 'policy_from_repository',
                             side_effect=AssertionError('read unsupported profile')), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(verifier.main(), 2)

    def test_malformed_accepted_zip_produces_rejection_json(self):
        self.artifact.update(format='zip')
        del self.artifact['payload']
        del self.artifact['mode']
        self.write_policy()
        code, result = self.invoke('--check-material', 'fixture', '--archive',
                                   f'fixture={self.archive}', '--tree', f'fixture={self.tree}')
        self.assertEqual(code, 2)
        self.assertEqual(result['status'], 'rejected_input')

    def test_project_policy_has_no_implicit_material_or_pub_success(self):
        policy = verifier.policy_from_repository(verifier.REPOSITORY)
        result = verifier.inspect_profile(verifier.REPOSITORY, policy, {}, {})
        self.assertFalse(result['profile_ready'])
        self.assertEqual(result['exit_code'], 1)
        self.assertIn('pub_app', result['missing_roles'])


if __name__ == '__main__':
    unittest.main()
