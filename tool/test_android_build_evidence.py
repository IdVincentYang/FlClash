import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

import android_build_evidence as parser
import inspect_android_build_sources as audit
from test_inspect_android_build_sources import elf
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


class CompilerRecordTest(unittest.TestCase):
    def test_continuation_separates_inputs_for_lf_and_crlf(self):
        for newline in [b'\n', b'\r\n']:
            for before, after in [(b'', b''), (b' \t', b' \t')]:
                data = b'out: a' + before + b'\\' + newline + after + b'b' + newline + b'a b ab:' + newline
                with self.subTest(newline=newline, before=before):
                    self.assertEqual(parser.depfile(data)['inputs'], ['a', 'b'])

    def test_continuation_whitespace_preserves_make_escape_boundary(self):
        self.assertEqual(parser.depfile(b'out: a\\ \\\nb\na\\ b:\n')['inputs'], ['a b'])
        self.assertEqual(parser.depfile(b'out: a\\\n\\ b\n')['inputs'], [' b', 'a'])
        for data in [b'out: a\\\\\nb\n', b'out: a\\\\\\\nb\n',
                     b'.POSIX:\nout: a\\\nb\n', b'out: a\rb\n']:
            with self.subTest(data=data), self.assertRaises(ValueError):
                parser.depfile(data)

    def test_make_escaping_continuation_and_phony_rules(self):
        value = parser.depfile(b'out\\ name: src\\ name.c src\\:id.h \\\n  hash\\#name.h dollar$$.h\nsrc\\ name.c:\n')
        self.assertEqual(value['inputs'], ['dollar$.h', 'hash#name.h', 'src name.c', 'src:id.h'])
        self.assertIn('out name', value['outputs'])

    def test_variables_incomplete_escapes_and_missing_rules_are_unsupported(self):
        for data in [b'x: $(SECRET)', b'x: incomplete\\', b'not a rule', b'']:
            with self.subTest(data=data), self.assertRaises(ValueError):
                parser.depfile(data)

    def test_compiler_arguments_are_declarations_only(self):
        data = b'[{"directory":"/source","file":"a.c","arguments":["cc","a.c",";","touch","marker"]}]'
        self.assertEqual(parser.compile_commands(data)[0]['arguments'][-1], 'marker')
        for data in [b'[{"directory":"/a","directory":"/b"}]', b'{}',
                     b'[{"directory":"/a","file":"a","arguments":[1]}]']:
            with self.subTest(data=data), self.assertRaises(ValueError):
                parser.compile_commands(data)


class BuildEvidenceTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.build = self.root / 'build'
        self.build.mkdir()
        self.source = self.root / 'source space'
        self.source.mkdir()
        self.file = self.source / 'example name.dart'
        self.file.write_text('source bytes')
        self.dep = self.build / '.dart_tool/flutter_build/abc/kernel_snapshot_program.d'
        self.dep.parent.mkdir(parents=True)
        escaped = str(self.file).replace(' ', '\\ ')
        self.dep.write_text(f'output: {escaped}\n')
        self.apk = self.root / 'app.apk'
        with zipfile.ZipFile(self.apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'synthetic')
            archive.writestr('lib/arm64-v8a/libexample.so', elf())
        self.record = self.root / 'record.json'
        self.context = self.root / 'run.json'

    def inspect(self, record=None, selections=None, root='build'):
        if record is not None:
            self.record.write_text(json.dumps(record))
        if selections is None:
            selections = [f'build={self.build}', f'source={self.source}']
            if self.context.exists():
                selections.append(f'run={self.context}')
        return audit.inspect(self.apk, self.record if record is not None else None,
                             selections, 'arm64-v8a', root)

    def bound_record(self, **changes):
        context = {'workspace': str(self.root), 'source_commit': 'a' * 40,
                   'apks': [{'sha256': sha(self.apk.read_bytes())}]}
        context.update(changes)
        self.context.write_text(json.dumps(context))
        return {'apk_sha256': sha(self.apk.read_bytes()), 'objects': [],
                'build_evidence': {'input': 'build', 'source_commit': 'a' * 40,
                                   'context': {'input': 'run', 'sha256': sha(self.context.read_bytes())}}}

    def test_current_source_hash_does_not_establish_generation(self):
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        evidence = result['build_evidence']
        self.assertEqual(evidence['inputs'][0]['sha256'], sha(self.file.read_bytes()))
        self.assertEqual(evidence['binding']['status'], 'unknown')
        self.assertEqual(evidence['generation_causality'], 'not_proven')
        self.assertEqual(result['proof_limits']['source_generation'], 'not_proven')

    def test_unselected_absolute_and_parent_paths_never_grant_access(self):
        secret = self.root / 'secret'
        secret.write_text('private data')
        self.dep.write_text(f'output: {secret}\n')
        result = self.inspect()
        self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'unselected')
        self.assertNotIn('sha256', result['build_evidence']['inputs'][0])
        self.dep.write_text('output: ../secret\n')
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'unresolved_relative_path')

    def test_symlink_parent_cannot_be_lexically_reassigned(self):
        external = self.root / 'external'
        (external / 'child').mkdir(parents=True)
        (external / self.file.name).write_text('outside bytes')
        (self.source / 'link').symlink_to(external / 'child')
        for relative in [False, True]:
            record = self.bound_record()
            record['build_evidence']['working_directories'] = {'flutter_depfile': str(self.source)}
            path = 'link/../' + self.file.name
            if not relative:
                path = str(self.source) + '/' + path
            self.dep.write_text('output: ' + path.replace(' ', '\\ ') + '\n')
            result = self.inspect(record)
            self.assertEqual(result['exit_code'], 2)
            self.assertFalse(result['build_evidence']['inputs'])
            self.assertEqual(result['build_evidence']['records'][0]['commands'][0]['declared_inputs'],
                             [path])

    def test_path_declaration_and_mapping_basis_are_preserved(self):
        (self.source / 'plain').mkdir()
        record = self.bound_record()
        record['build_evidence']['working_directories'] = {'flutter_depfile': str(self.source)}
        self.dep.write_text('output: ./example\\ name.dart\n')
        result = self.inspect(record)
        row = result['build_evidence']['inputs'][0]
        self.assertEqual(row['status'], 'current_identity')
        self.assertEqual(row['declared_path'], './example name.dart')
        self.assertEqual(row['mapped_path'], str(self.file))
        self.assertEqual(row['mapping_basis'], 'declared_working_directory')
        self.assertEqual(result['build_evidence']['records'][0]['commands'][0]['declared_inputs'],
                         ['./example name.dart'])
        self.dep.write_text('output: plain/../example\\ name.dart\n')
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        row = result['build_evidence']['inputs'][0]
        self.assertEqual(row['sha256'], sha(self.file.read_bytes()))
        self.assertEqual(row['declared_path'], 'plain/../example name.dart')
        self.assertEqual(row['mapped_path'], str(self.file))
        for name in ['../secret', 'missing/../example\\ name.dart']:
            self.dep.write_text(f'output: {name}\n')
            result = self.inspect(record)
            if name.startswith('../'):
                self.assertEqual(result['exit_code'], 2)
            else:
                self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'unavailable')

    def test_continuation_cli_checks_both_actual_inputs(self):
        a, b, ab = [self.source / name for name in ['a', 'b', 'ab']]
        for file, data in [(a, 'first'), (b, 'second'), (ab, 'unrelated')]:
            file.write_text(data)
        record = self.bound_record()
        record['build_evidence']['working_directories'] = {'flutter_depfile': str(self.source)}
        for newline in [b'\n', b'\r\n']:
            self.dep.write_bytes(b'out: a\\' + newline + b'b' + newline + b'a b ab:' + newline)
            result = self.inspect(record)
            self.assertEqual(result['exit_code'], 0)
            self.assertEqual({row['mapped_path']: row['sha256']
                              for row in result['build_evidence']['inputs']},
                             {str(a): sha(a.read_bytes()), str(b): sha(b.read_bytes())})

    def test_directory_suffix_does_not_reassign_a_regular_file(self):
        record = self.bound_record()
        record['build_evidence']['working_directories'] = {'flutter_depfile': str(self.source)}
        for suffix in ['/', '/.']:
            self.dep.write_text('output: example\\ name.dart' + suffix + '\n')
            self.assertEqual(self.inspect(record)['exit_code'], 2)
        (self.source / 'directory').mkdir()
        self.dep.write_text('output: directory/.\n')
        result = self.inspect(record)
        self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'directory_declaration')

    def test_missing_selected_source_is_reported_as_unavailable(self):
        self.file.unlink()
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['coverage']['unavailable_inputs'], 1)

    def test_directory_dependencies_do_not_claim_content_identity(self):
        directory = str(self.source).replace(' ', '\\ ')
        self.dep.write_text(f'output: {directory}\n')
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['coverage']['directory_declarations'], 1)
        self.assertNotIn('sha256', result['build_evidence']['inputs'][0])

    def test_flutter_empty_dependency_rule_adds_no_source_claims(self):
        self.dep.write_text(': ')
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['coverage']['declared_inputs'], 0)
        self.assertEqual(result['build_evidence']['generation_causality'], 'not_proven')

    def test_metadata_and_source_symlinks_are_rejected(self):
        original = self.root / 'original'
        original.write_bytes(self.dep.read_bytes())
        self.dep.unlink()
        self.dep.symlink_to(original)
        self.assertEqual(self.inspect()['exit_code'], 2)
        self.dep.unlink()
        self.dep.write_bytes(original.read_bytes())
        self.file.unlink()
        self.file.symlink_to(original)
        self.assertEqual(self.inspect()['exit_code'], 2)

    def test_selected_context_is_not_a_build_attestation(self):
        result = self.inspect(self.bound_record())
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['binding']['status'], 'matched_declarations')
        self.assertEqual(result['build_evidence']['generation_causality'], 'not_proven')

    def test_cross_run_source_and_apk_context_contradictions(self):
        for changes in [{'workspace': '/different-run'}, {'source_commit': 'b' * 40},
                        {'apks': [{'sha256': 'b' * 64}]}]:
            with self.subTest(changes=changes):
                result = self.inspect(self.bound_record(**changes))
                self.assertEqual(result['exit_code'], 1)
                self.assertEqual(result['build_evidence']['binding']['status'], 'contradiction')

    def test_same_size_context_replacement_is_not_accepted(self):
        record = self.bound_record()
        before = self.context.stat()
        self.context.write_text(self.context.read_text().replace('a' * 40, 'b' * 40))
        os.utime(self.context, ns=(before.st_atime_ns, before.st_mtime_ns))
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 1)
        self.assertIn('build_context_hash_mismatch', result['contradictions'])

    def test_source_reference_mismatch_does_not_become_same_run_proof(self):
        record = self.bound_record()
        record['source_inputs'] = [{'input': 'source', 'path': self.file.name,
                                    'sha256': sha(self.file.read_bytes())}]
        self.file.write_text('changed after original build')
        self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_relative_source_requires_an_explicit_working_directory(self):
        self.dep.write_text('output: example\\ name.dart\n')
        result = self.inspect()
        self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'unresolved_relative_path')
        record = self.bound_record()
        record['build_evidence']['working_directories'] = {'flutter_depfile': str(self.source)}
        result = self.inspect(record)
        self.assertEqual(result['build_evidence']['inputs'][0]['status'], 'current_identity')
        record['build_evidence']['working_directories']['flutter_depfile'] = '../unselected'
        self.assertEqual(self.inspect(record)['exit_code'], 2)

    def test_context_does_not_silently_ignore_relation_or_cmake_directory_overrides(self):
        record = self.bound_record()
        record['build_evidence']['context']['relation'] = 'same_bytes'
        self.assertEqual(self.inspect(record)['exit_code'], 2)
        record = self.bound_record()
        record['build_evidence']['working_directories'] = {'cmake_compile_commands': str(self.source)}
        self.assertEqual(self.inspect(record)['exit_code'], 2)

    def test_compiler_shell_text_is_not_executed(self):
        commands = self.build / 'android/core/.cxx/Release/id/arm64-v8a/compile_commands.json'
        commands.parent.mkdir(parents=True)
        marker = self.root / 'marker'
        commands.write_text(json.dumps([{'directory': str(self.source),
                                         'file': self.file.name,
                                         'command': f'cc -c "{self.file}"; touch {marker}'}]))
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['build_evidence']['coverage']['metadata_files'], 2)
        self.assertFalse(marker.exists())

    def test_invalid_metadata_and_unselected_or_file_root_are_rejected(self):
        self.dep.write_text('malformed')
        self.assertEqual(self.inspect()['exit_code'], 2)
        self.assertEqual(self.inspect(root='missing')['exit_code'], 2)
        self.assertEqual(self.inspect(selections=[f'build={self.file}'])['exit_code'], 2)


if __name__ == '__main__':
    unittest.main()
