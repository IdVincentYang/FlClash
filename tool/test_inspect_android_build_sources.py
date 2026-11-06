import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import inspect_android_build_sources as audit


NATIVE = 'lib/arm64-v8a/libexample.so'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def elf(machine=183, bits=64):
    data = bytearray(64)
    data[:7] = b'\x7fELF' + bytes([2 if bits == 64 else 1, 1, 1])
    struct.pack_into('<H', data, 18, machine)
    return bytes(data)


def dex():
    data = bytearray(160)
    data[:8] = b'dex\n039\0'
    struct.pack_into('<III', data, 32, 160, 112, 0x12345678)
    struct.pack_into('<II', data, 56, 1, 112)
    struct.pack_into('<II', data, 64, 1, 116)
    struct.pack_into('<II', data, 96, 1, 120)
    struct.pack_into('<I', data, 112, 152)
    data[152:157] = b'\x03La;\0'
    return bytes(data)


class BuildSourcesTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.allowed = self.root / 'allowed'
        self.allowed.mkdir()
        self.apk = self.root / 'app.apk'
        self.record_path = self.root / 'record.json'
        self.entries = {'AndroidManifest.xml': b'synthetic manifest',
                        NATIVE: elf(), 'classes.dex': dex(),
                        'assets/example.txt': b'asset'}
        self.write_apk()

    def write_apk(self):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)

    def record(self):
        return {'apk_sha256': sha(self.apk.read_bytes()),
                'objects': [{'entry': name, 'sha256': sha(data)}
                            for name, data in self.entries.items()]}

    def inspect(self, record=None, inputs=None, abi='arm64-v8a'):
        self.record_path.write_text(json.dumps(record or self.record()))
        return audit.inspect(self.apk, self.record_path,
                             inputs or [f'allowed={self.allowed}'], abi)

    def native_record(self, record):
        return next(x for x in record['objects'] if x['entry'] == NATIVE)

    def native_result(self, result):
        return next(x for x in result['objects'] if x['entry'] == NATIVE)

    def link(self, path='material.so', relation='same_bytes', data=None):
        data = self.entries[NATIVE] if data is None else data
        (self.allowed / path).write_bytes(data)
        return {'input': 'allowed', 'path': path, 'sha256': sha(data),
                'relation': relation}

    def test_inventory_comes_from_apk_without_a_record(self):
        result = audit.inspect(self.apk)
        self.assertEqual(result['coverage']['apk_entries'], 4)
        self.assertEqual(result['coverage']['entries_without_reference'], 4)
        self.assertFalse(result['coverage']['entry_reference_coverage_complete'])
        self.assertEqual(result['status'], 'partial_inventory')
        self.assertEqual(result['proof_limits']['source_generation'], 'not_proven')

    def test_matching_bytes_are_not_publisher_or_generation_proof(self):
        record = self.record()
        self.native_record(record)['links'] = [self.link()]
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertTrue(result['coverage']['entry_reference_coverage_complete'])
        self.assertEqual(self.native_result(result)['links'][0]['status'], 'matched')
        self.assertEqual(result['proof_limits']['publisher_authentication'], 'not_assessed')
        self.assertEqual(result['proof_limits']['runtime_loading'], 'not_observed')
        self.assertEqual(result['coverage']['entries_without_checked_material_links'], 3)

    def test_empty_deleted_and_new_unrecorded_entries_remain_visible(self):
        for mode in ['empty', 'deleted', 'new']:
            with self.subTest(mode=mode):
                record = self.record()
                if mode == 'empty':
                    record['objects'] = []
                elif mode == 'deleted':
                    record['objects'].pop()
                else:
                    self.entries['assets/new.txt'] = b'new'
                    self.write_apk()
                    record['apk_sha256'] = sha(self.apk.read_bytes())
                result = self.inspect(record)
                self.assertEqual(result['exit_code'], 0)
                self.assertEqual(result['coverage']['apk_entries'], len(self.entries))
                self.assertFalse(result['coverage']['entry_reference_coverage_complete'])
                self.assertGreater(result['coverage']['entries_without_reference'], 0)

    def test_expected_entry_missing_from_apk_is_a_contradiction(self):
        record = self.record()
        record['objects'].append({'entry': 'assets/missing', 'sha256': 'a' * 64})
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 1)
        self.assertEqual(result['records_not_in_apk'], ['assets/missing'])

    def test_wrong_apk_hash_and_object_hash_are_contradictions(self):
        for mode in ['apk', 'object']:
            with self.subTest(mode=mode):
                record = self.record()
                if mode == 'apk':
                    record['apk_sha256'] = 'a' * 64
                else:
                    self.native_record(record)['sha256'] = 'b' * 64
                self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_same_name_does_not_accept_different_material_bytes(self):
        record = self.record()
        link = self.link(data=b'a different file')
        self.native_record(record)['links'] = [link]
        self.assertEqual(self.inspect(record)['exit_code'], 1)
        link['sha256'] = 'a' * 64
        self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_transform_input_only_checks_its_own_hash(self):
        record = self.record()
        self.native_record(record)['links'] = [self.link(relation='transform_input', data=b'not stripped')]
        result = self.inspect(record)
        link = self.native_result(result)['links'][0]
        self.assertEqual(result['exit_code'], 0)
        self.assertIn('not proven', link['limitation'])

    def test_wrong_elf_abi_and_expected_target_are_rejected(self):
        self.entries[NATIVE] = elf(machine=3, bits=32)
        self.write_apk()
        result = self.inspect()
        self.assertIn('elf_abi_mismatch', self.native_result(result)['contradictions'])
        self.assertEqual(result['exit_code'], 1)
        result = audit.inspect(self.apk)
        self.assertEqual(result['coverage']['entries_with_reference'], 0)
        self.assertFalse(result['coverage']['entry_reference_coverage_complete'])
        self.entries.pop(NATIVE)
        self.entries['lib/x86/libexample.so'] = elf(machine=3, bits=32)
        self.write_apk()
        self.assertEqual(self.inspect()['exit_code'], 1)

    def test_wasm_candidate_is_not_hidden_by_an_omitted_material_record(self):
        payload = audit.WASM_MAGIC + b'\x00\x01\x00'
        self.entries[NATIVE] += b'prefix' + payload + b'suffix'
        self.write_apk()
        record = self.record()
        ref = self.link(path='module.wasm', relation='embedded_bytes', data=payload)
        self.native_record(record)['links'] = [ref]
        result = self.inspect(record)
        self.assertEqual(self.native_result(result)['links'][0]['offset'], 70)
        self.assertEqual(result['coverage']['wasm_magic_candidates'], 1)
        self.native_record(record).pop('links')
        result = self.inspect(record)
        self.assertEqual(result['coverage']['wasm_magic_candidates'], 1)
        self.assertIn('not exhaustive', result['proof_limits']['embedded_code_scan'])

    def test_embedded_payload_not_in_parent_is_a_contradiction(self):
        record = self.record()
        self.native_record(record)['links'] = [self.link(relation='embedded_bytes', data=b'missing')]
        self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_source_file_is_read_not_executed_and_no_network_is_used(self):
        marker = self.root / 'executed'
        program = f"from pathlib import Path\nPath({str(marker)!r}).touch()\n".encode()
        record = self.record()
        record['source_inputs'] = [self.link('generator.py', 'source_file', program)]
        with patch.object(socket, 'socket', side_effect=AssertionError('network used')):
            result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertFalse(marker.exists())

    def test_unavailable_material_is_unknown_not_a_wrong_hash(self):
        record = self.record()
        self.native_record(record)['links'] = [{'input': 'allowed', 'path': 'missing',
                                               'sha256': 'a' * 64, 'relation': 'same_bytes'}]
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['status'], 'partial_inventory')
        self.assertEqual(result['coverage']['unavailable_inputs'], 1)
        self.assertEqual(result['coverage']['contradictory_apk_entries'], 0)

    def assert_scope_rejected_without_reading_private(self, ref):
        private = self.root / 'private.txt'
        private.write_bytes(b'private material must not be opened')
        private_inode = private.stat().st_ino
        original = os.fdopen

        def checked(fd, *args, **kwargs):
            self.assertNotEqual(os.fstat(fd).st_ino, private_inode)
            return original(fd, *args, **kwargs)

        record = self.record()
        self.native_record(record)['links'] = [dict(ref, relation='same_bytes', sha256='a' * 64)]
        with patch.object(os, 'fdopen', checked):
            result = self.inspect(record)
        self.assertEqual(result['exit_code'], 2)
        self.assertEqual(result['status'], 'rejected_input')

    def test_unselected_absolute_parent_and_windows_paths_do_not_expand_scope(self):
        for ref in [{'input': 'unselected'},
                    {'input': 'allowed', 'path': '../private.txt'},
                    {'input': 'allowed', 'path': str(self.root / 'private.txt')},
                    {'input': 'allowed', 'path': 'C:\\private.txt'},
                    {'input': 'allowed', 'path': 'sub/../../private.txt'}]:
            with self.subTest(ref=ref):
                self.assert_scope_rejected_without_reading_private(ref)

    def test_file_and_directory_symlinks_do_not_escape_a_selected_root(self):
        (self.root / 'private.txt').write_bytes(b'private')
        (self.allowed / 'link').symlink_to(self.root / 'private.txt')
        (self.allowed / 'linked-dir').symlink_to(self.root, target_is_directory=True)
        for name in ['link', 'linked-dir/private.txt']:
            with self.subTest(name=name):
                self.assert_scope_rejected_without_reading_private({'input': 'allowed', 'path': name})

    def test_explicit_file_selection_does_not_grant_sibling_access(self):
        file = self.allowed / 'selected'
        file.write_bytes(self.entries[NATIVE])
        record = self.record()
        self.native_record(record)['links'] = [{'input': 'one', 'path': 'sibling',
                                               'sha256': 'a' * 64, 'relation': 'same_bytes'}]
        self.assertEqual(self.inspect(record, [f'one={file}'])['exit_code'], 2)

    def test_archive_member_exact_bytes_and_traversal(self):
        aar = self.allowed / 'library.aar'
        with zipfile.ZipFile(aar, 'w') as archive:
            archive.writestr('jni/arm64-v8a/libexample.so', self.entries[NATIVE])
        ref = {'input': 'aar', 'member': 'jni/arm64-v8a/libexample.so',
               'sha256': sha(self.entries[NATIVE]), 'relation': 'same_bytes'}
        record = self.record()
        self.native_record(record)['links'] = [ref]
        self.assertEqual(self.inspect(record, [f'aar={aar}'])['exit_code'], 0)
        ref['member'] = 'jni/arm64-v8a/missing.so'
        missing = self.inspect(record, [f'aar={aar}'])
        self.assertEqual(missing['exit_code'], 1)
        self.assertEqual(self.native_result(missing)['links'][0]['reason'], 'expected_archive_member_missing')
        ref['member'] = '../outside'
        self.assertEqual(self.inspect(record, [f'aar={aar}'])['exit_code'], 2)

    def test_unsafe_or_duplicate_zip_members_are_rejected_without_extraction(self):
        for mode in ['parent', 'absolute', 'duplicate', 'symlink']:
            with self.subTest(mode=mode), warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                self.write_apk()
                with zipfile.ZipFile(self.apk, 'a') as archive:
                    if mode == 'symlink':
                        info = zipfile.ZipInfo('assets/link')
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                        archive.writestr(info, '../private')
                    else:
                        archive.writestr({'parent': '../outside', 'absolute': '/outside',
                                          'duplicate': NATIVE}[mode], b'bad')
                self.assertEqual(audit.inspect(self.apk)['exit_code'], 2)

    def test_bad_zip_dex_and_bounded_input_fail_honestly(self):
        self.apk.write_bytes(b'not zip')
        self.assertEqual(audit.inspect(self.apk)['exit_code'], 2)
        self.write_apk()
        with patch.object(audit, 'MAX_ENTRIES', 2):
            self.assertEqual(audit.inspect(self.apk)['exit_code'], 2)
        self.entries['classes.dex'] = b'dex\n039\0'
        self.write_apk()
        self.assertEqual(self.inspect()['exit_code'], 1)

    def test_duplicate_record_fields_and_duplicate_objects_fail(self):
        record = self.record()
        record['objects'].append(copy.deepcopy(record['objects'][0]))
        self.assertEqual(self.inspect(record)['exit_code'], 2)
        self.record_path.write_text('{"objects":[],"objects":[]}')
        self.assertEqual(audit.inspect(self.apk, self.record_path)['exit_code'], 2)

    def test_dex_metadata_and_r8_names_do_not_prove_generation(self):
        mapping = self.allowed / 'mapping.txt'
        mapping.write_text('example.Original -> a:\nexample.Inlined -> z:\n')
        record = self.record()
        next(x for x in record['objects'] if x['entry'] == 'classes.dex')['expect'] = {'dex_class_count': 1}
        record['r8'] = {'input': 'allowed', 'path': 'mapping.txt', 'sha256': sha(mapping.read_bytes())}
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['r8']['original_names_mapping_to_defined_classes'], ['example.Original'])
        self.assertIn('zero is not absence', result['r8']['limitation'])
        record['objects'][2]['expect']['dex_class_count'] = True
        self.assertEqual(self.inspect(record)['exit_code'], 2)

    def test_go_declarations_and_wrong_expected_version(self):
        module = (b'path\texample/core\nbuild\tGOOS=android\nbuild\tGOARCH=arm64\n'
                  b'build\tvcs.revision=' + b'a' * 40 + b'\nbuild\t-tags=with_gvisor,no_zerotier\n')
        module = bytes.fromhex('3077af0c9274080241e1c107e6d618e6') + module + bytes.fromhex('f932433186182072008242104116d8f2')
        self.assertLess(len(module), 256)
        length = bytes([len(module) & 127 | 128, len(module) >> 7]) if len(module) > 127 else bytes([len(module)])
        blob = audit.GO_MAGIC + b'\x08\x02' + bytes(16) + b'\x08go1.26.4' + length + module
        self.entries[NATIVE] = elf() + blob
        self.write_apk()
        record = self.record()
        self.native_record(record)['expect'] = {'go_version': 'go1.26.4', 'go_revision': 'a' * 40,
                                               'go_tags': 'with_gvisor,no_zerotier'}
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertIn('not build attestation', self.native_result(result)['go']['proof'])
        self.native_record(record)['expect']['go_version'] = 'go1.25.0'
        self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_source_mismatch_and_read_only_inputs(self):
        record = self.record()
        ref = self.link('source.dart', 'source_file', b'const value = 1;')
        record['source_inputs'] = [ref]
        self.record_path.write_text(json.dumps(record))
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns)
                  for p in self.root.rglob('*') if p.is_file()}
        result = audit.inspect(self.apk, self.record_path, [f'allowed={self.allowed}'])
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns)
                                  for p in self.root.rglob('*') if p.is_file()})
        ref['sha256'] = '0' * 64
        self.assertEqual(self.inspect(record)['exit_code'], 1)

    def test_undecoded_metadata_is_unknown_not_an_observed_mismatch(self):
        record = self.record()
        self.native_record(record)['expect'] = {'go_version': 'go1.17.0'}
        result = self.inspect(record)
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['status'], 'partial_inventory')
        self.assertGreater(result['coverage']['unavailable_metadata_fields'], 0)
        future = bytearray(self.entries['classes.dex'])
        future[4:7] = b'999'
        self.entries['classes.dex'] = bytes(future)
        self.write_apk()
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['status'], 'partial_inventory')
        self.assertEqual(result['coverage']['contradictory_apk_entries'], 0)

    def test_elf_dynamic_imports_are_declarations_not_runtime_observations(self):
        library = bytearray(320)
        library[:64] = elf()
        struct.pack_into('<Q', library, 32, 64)
        struct.pack_into('<HH', library, 54, 56, 2)
        struct.pack_into('<IIQQQQQQ', library, 64, 1, 5, 0, 0x1000, 0, 320, 320, 1)
        struct.pack_into('<IIQQQQQQ', library, 120, 2, 4, 176, 0x10b0, 0, 80, 80, 1)
        for index, pair in enumerate([(5, 0x1100), (10, 17), (1, 0), (1, 8), (0, 0)]):
            struct.pack_into('<QQ', library, 176 + 16 * index, *pair)
        library[256:273] = b'libc.so\0libdl.so\0'
        self.entries[NATIVE] = bytes(library)
        self.write_apk()
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(self.native_result(result)['elf']['needed_libraries'], ['libc.so', 'libdl.so'])
        self.assertEqual(result['proof_limits']['runtime_loading'], 'not_observed')

    def test_cli_emits_json_and_uses_distinct_exit_codes(self):
        command = [sys.executable, str(Path(audit.__file__).resolve()),
                   '--apk', str(self.apk), '--record', str(self.record_path)]
        for expected in [0, 1, 2]:
            record = self.record()
            if expected == 1:
                record['apk_sha256'] = 'a' * 64
            elif expected == 2:
                record['unexpected'] = 'not a command'
            self.record_path.write_text(json.dumps(record))
            process = subprocess.run(command, capture_output=True, text=True)
            result = json.loads(process.stdout)
            self.assertEqual(process.returncode, expected)
            self.assertEqual(result['exit_code'], expected)
            self.assertEqual(process.stderr, '')

    def test_unread_dynamic_metadata_is_not_a_false_abi_contradiction(self):
        library = bytearray(elf())
        struct.pack_into('<Q', library, 32, 4096)
        struct.pack_into('<HH', library, 54, 56, 2)
        self.entries[NATIVE] = bytes(library)
        self.write_apk()
        result = self.inspect()
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['status'], 'partial_inventory')
        self.assertIn('elf_dynamic', self.native_result(result)['metadata_unavailable'])
        self.assertEqual(result['coverage']['contradictory_apk_entries'], 0)


if __name__ == '__main__':
    unittest.main()
