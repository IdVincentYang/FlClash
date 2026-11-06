#!/usr/bin/env python3
"""Inspect explicitly selected APK/material bytes; never execute build inputs."""

import argparse
from contextlib import ExitStack, contextmanager
import hashlib
import json
import ntpath
import os
from pathlib import Path
import re
import stat
import struct
import sys
import zipfile


MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
MAX_ENTRIES = 10000
ABI = {'arm64-v8a': (64, 183), 'armeabi-v7a': (32, 40),
       'x86': (32, 3), 'x86_64': (64, 62)}
SHA = re.compile(r'^[0-9a-f]{64}$')
GO_MAGIC = b'\xff Go buildinf:'
WASM_MAGIC = b'\0asm\x01\0\0\0'


class Rejected(ValueError):
    pass


class MissingMember(ValueError):
    pass


def keys(value, required, optional=()):
    if (not isinstance(value, dict) or not set(required) <= value.keys()
            or not value.keys() <= set(required) | set(optional)):
        raise Rejected('Unknown or missing record fields')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Rejected('Duplicate JSON field')
        result[key] = value
    return result


def digest(value):
    if not isinstance(value, str) or not SHA.fullmatch(value):
        raise Rejected('Expected lowercase SHA-256')
    return value


def relative_parts(value):
    if (not isinstance(value, str) or not value or '\\' in value
            or '\0' in value or value.startswith('/')
            or ntpath.splitdrive(value)[0]):
        raise Rejected('Expected a relative path within a selected input')
    parts = value.split('/')
    if any(part in ('', '.', '..') for part in parts):
        raise Rejected('Path traversal or empty component')
    return parts


def regular(fd):
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_FILE:
        raise Rejected('Input must be a bounded regular file')


class SelectedInput:
    def __init__(self, path):
        path = Path(path).expanduser()
        if path.is_symlink():
            raise Rejected('Select the actual input, not a symbolic link')
        path = path.resolve(strict=True)
        if not hasattr(os, 'O_NOFOLLOW') or os.open not in os.supports_dir_fd:
            raise Rejected('Safe descriptor-relative reads require POSIX support')
        self.directory = path.is_dir()
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        if self.directory:
            flags |= os.O_DIRECTORY
        self.fd = os.open(path, flags)
        if not self.directory:
            try:
                regular(self.fd)
            except Exception:
                os.close(self.fd)
                raise

    def close(self):
        os.close(self.fd)

    @contextmanager
    def open(self, path=None):
        if not self.directory:
            if path is not None:
                raise Rejected('A selected file does not grant directory access')
            fd = os.dup(self.fd)
        else:
            parts = relative_parts(path)
            with ExitStack() as stack:
                parent = self.fd
                for part in parts[:-1]:
                    parent = os.open(part, os.O_RDONLY | os.O_DIRECTORY
                                     | os.O_NOFOLLOW, dir_fd=parent)
                    stack.callback(os.close, parent)
                try:
                    fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW
                                 | os.O_NONBLOCK, dir_fd=parent)
                except OSError as error:
                    if error.errno in (40, 62):
                        raise Rejected('Symbolic-link input rejected') from error
                    raise
        try:
            regular(fd)
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                stream.seek(0)
                yield stream
        finally:
            os.close(fd)


def read_bounded(stream, limit=MAX_FILE):
    data = stream.read(limit + 1)
    if len(data) > limit:
        raise Rejected('Input exceeds the read limit')
    return data


def archive_entries(archive):
    infos = archive.infolist()
    if len(infos) > MAX_ENTRIES or sum(i.file_size for i in infos) > MAX_TOTAL:
        raise Rejected('Archive exceeds inventory limits')
    seen = set()
    for info in infos:
        name = info.filename[:-1] if info.is_dir() else info.filename
        relative_parts(name)
        if (info.orig_filename != info.filename or info.filename in seen
                or stat.S_ISLNK(info.external_attr >> 16)
                or info.flag_bits & 1 or info.file_size > MAX_FILE):
            raise Rejected('Unsafe, duplicate, encrypted or oversized archive entry')
        seen.add(info.filename)
    return [i for i in infos if not i.is_dir()]


def varint(data, offset):
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise Rejected('Truncated variable-length integer')
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
    raise Rejected('Oversized variable-length integer')


def go_metadata(data):
    """Read Go >=1.18 inline build info, as described by debug/buildinfo."""
    offset = data.find(GO_MAGIC)
    while offset >= 0:
        if offset % 16 == 0 and offset + 32 <= len(data) and data[offset + 15] & 2:
            try:
                size, start = varint(data, offset + 32)
                version = data[start:start + size].decode('utf-8')
                size, start = varint(data, start + size)
                module = data[start:start + size]
                if (version.startswith('go') and len(module) == size
                        and len(module) >= 33 and module[-17] == 10):
                    text = module[16:-16].decode('utf-8')
                    deps, settings = [], {}
                    for line in text.splitlines():
                        fields = line.split('\t')
                        if fields[0] in ('dep', '=>'):
                            deps.append(fields)
                        if fields[0] == 'build' and len(fields) == 2:
                            key, _, value = fields[1].partition('=')
                            if key in ('GOOS', 'GOARCH', '-tags', '-buildmode',
                                       'vcs.revision', 'vcs.modified'):
                                settings[key] = value
                    return {'version': version, 'settings': settings,
                            'module_declarations': deps,
                            'proof': 'embedded declarations, not build attestation'}
            except (Rejected, UnicodeError):
                pass
        offset = data.find(GO_MAGIC, offset + 1)
    return None


def dex_classes(data):
    if len(data) < 112 or data[:4] != b'dex\n' or data[7] != 0:
        raise Rejected('Invalid or truncated DEX header')
    if data[4:7] not in (b'035', b'037', b'038', b'039', b'040', b'041'):
        return None

    def u32(offset):
        if offset + 4 > len(data):
            raise Rejected('DEX offset outside the selected entry')
        return struct.unpack_from('<I', data, offset)[0]

    if u32(40) == 0x78563412:
        return None
    if u32(32) != len(data) or u32(40) != 0x12345678:
        raise Rejected('Invalid DEX size or byte order')
    strings_size, strings = u32(56), u32(60)
    types_size, types = u32(64), u32(68)
    count, classes = u32(96), u32(100)
    if (strings + strings_size * 4 > len(data)
            or types + types_size * 4 > len(data)
            or classes + count * 32 > len(data)):
        raise Rejected('DEX table outside the selected entry')
    result = []
    for index in range(count):
        type_id = u32(classes + index * 32)
        if type_id >= types_size:
            raise Rejected('Invalid DEX type index')
        string_id = u32(types + type_id * 4)
        if string_id >= strings_size:
            raise Rejected('Invalid DEX string index')
        _, start = varint(data, u32(strings + string_id * 4))
        end = data.find(b'\0', start)
        if end < 0:
            raise Rejected('Unterminated DEX descriptor')
        result.append(data[start:end].decode('utf-8', errors='replace'))
    return sorted(result)


def needed_libraries(data):
    """Read ELF dynamic imports; these declarations do not prove loading."""
    wide = data[4] == 2
    endian = '<' if data[5] == 1 else '>'
    header = struct.unpack_from(endian + ('Q' if wide else 'I'), data, 32 if wide else 28)[0]
    size, count = struct.unpack_from(endian + 'HH', data, 54 if wide else 42)
    if count == 0:
        return []
    if count > 1024 or size < (56 if wide else 32) or header + size * count > len(data):
        raise Rejected('Invalid ELF program-header table')
    loads, dynamic = [], None
    for index in range(count):
        start = header + size * index
        kind = struct.unpack_from(endian + 'I', data, start)[0]
        offset, address = struct.unpack_from(endian + ('QQ' if wide else 'II'), data,
                                            start + (8 if wide else 4))
        length = struct.unpack_from(endian + ('Q' if wide else 'I'), data,
                                    start + (32 if wide else 16))[0]
        if offset + length > len(data):
            raise Rejected('ELF segment outside the selected entry')
        if kind == 1:
            loads.append((offset, address, length))
        elif kind == 2:
            dynamic = (offset, length)
    if dynamic is None:
        return []
    needed, string_address, string_size = [], None, None
    step = 16 if wide else 8
    for start in range(dynamic[0], dynamic[0] + dynamic[1] - step + 1, step):
        tag, value = struct.unpack_from(endian + ('QQ' if wide else 'II'), data, start)
        if tag == 0:
            break
        if tag == 1:
            needed.append(value)
        elif tag == 5:
            string_address = value
        elif tag == 10:
            string_size = value
    if not needed:
        return []
    if string_address is None or string_size is None:
        raise Rejected('ELF dynamic string table is missing')
    for offset, address, length in loads:
        if address <= string_address and string_address + string_size <= address + length:
            table = data[offset + string_address - address:offset + string_address - address + string_size]
            result = []
            for start in needed:
                end = table.find(b'\0', start)
                if start >= len(table) or end < 0:
                    raise Rejected('Invalid ELF dynamic library name')
                result.append(table[start:end].decode('utf-8', errors='replace'))
            return result
    raise Rejected('ELF dynamic string table is not file-backed')


def inspect_entry(name, data):
    item = {'entry': name, 'size': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'kind': 'resource',
            'has_reference': False, 'reference_status': 'uncovered',
            'links': [], 'contradictions': []}
    parts = name.split('/')
    if name.startswith('lib/') and name.endswith('.so'):
        item.update(kind='native', abi=parts[1] if len(parts) == 3 else None)
        minimum = 52 if len(data) > 4 and data[4] == 1 else 64
        if len(data) < minimum or data[:4] != b'\x7fELF' or data[5] not in (1, 2):
            item['contradictions'].append('invalid_elf')
        else:
            width = {1: 32, 2: 64}.get(data[4])
            machine = struct.unpack_from('<H' if data[5] == 1 else '>H', data, 18)[0]
            item['elf'] = {'bits': width, 'machine': machine}
            if ABI.get(item['abi']) != (width, machine) or data[5] != 1:
                item['contradictions'].append('elf_abi_mismatch')
            if width is not None:
                try:
                    item['elf']['needed_libraries'] = needed_libraries(data)
                except Rejected as error:
                    item.setdefault('metadata_unavailable', []).append('elf_dynamic')
                    item['elf']['dynamic_metadata_error'] = str(error)
        go = go_metadata(data)
        if go is not None:
            item['go'] = go
        offsets, start = [], 0
        while (start := data.find(WASM_MAGIC, start)) >= 0:
            if len(offsets) == MAX_ENTRIES:
                item['wasm_scan_truncated'] = True
                break
            offsets.append(start)
            start += len(WASM_MAGIC)
        item['wasm_magic_candidates'] = offsets
    elif name.endswith('.dex'):
        item['kind'] = 'dex'
        try:
            classes = dex_classes(data)
            if classes is None:
                item['metadata_unavailable'] = ['dex_format']
            else:
                item['dex'] = {'class_count': len(classes), 'definitions': classes}
        except Rejected as error:
            item['contradictions'].append(str(error))
    elif name.startswith('assets/'):
        item['kind'] = 'asset'
    elif name.startswith('META-INF/') or name == 'AndroidManifest.xml':
        item['kind'] = 'package_metadata'
    return item


def read_reference(ref, selections):
    keys(ref, ('input', 'sha256'), ('path', 'member', 'relation'))
    digest(ref['sha256'])
    if 'relation' in ref and ref['relation'] not in (
            'same_bytes', 'transform_input', 'source_file', 'embedded_bytes'):
        raise Rejected('Unsupported material relation')
    alias = ref['input']
    if not isinstance(alias, str) or alias not in selections:
        raise Rejected('Reference input was not explicitly selected')
    if 'path' in ref:
        relative_parts(ref['path'])
    with selections[alias].open(ref.get('path')) as stream:
        if 'member' not in ref:
            return read_bounded(stream)
        relative_parts(ref['member'])
        with zipfile.ZipFile(stream) as archive:
            names = {i.filename for i in archive_entries(archive)}
            if ref['member'] not in names:
                raise MissingMember('Expected member is absent from the selected archive')
            with archive.open(ref['member']) as member:
                return read_bounded(member)


def check_reference(ref, selections):
    result = {'input': ref.get('input'), 'path': ref.get('path'),
              'member': ref.get('member')}
    try:
        data = read_reference(ref, selections)
        result['actual_sha256'] = hashlib.sha256(data).hexdigest()
        result['status'] = ('matched' if result['actual_sha256'] == ref['sha256']
                            else 'contradiction')
        return result, data
    except FileNotFoundError:
        result['status'] = 'unavailable'
        return result, None
    except MissingMember:
        result['status'] = 'contradiction'
        result['reason'] = 'expected_archive_member_missing'
        return result, None


def apply_record(report, record, selections, archive):
    keys(record, ('apk_sha256', 'objects'), ('source_inputs', 'r8'))
    digest(record['apk_sha256'])
    if record['apk_sha256'] != report['apk']['sha256']:
        report['contradictions'].append('apk_hash_mismatch')
    objects = record['objects']
    if not isinstance(objects, list) or len(objects) > MAX_ENTRIES:
        raise Rejected('Expected a bounded object list')
    actual = {item['entry']: item for item in report['objects']}
    seen = set()
    for expected in objects:
        keys(expected, ('entry', 'sha256'), ('origin', 'links', 'expect'))
        relative_parts(expected['entry'])
        digest(expected['sha256'])
        name = expected['entry']
        if name in seen:
            raise Rejected('Duplicate object record')
        seen.add(name)
        if name not in actual:
            report['records_not_in_apk'].append(name)
            continue
        item = actual[name]
        item['has_reference'] = True
        item['reference_status'] = 'matched'
        if expected['sha256'] != item['sha256']:
            item['contradictions'].append('entry_hash_mismatch')
        origin = expected.get('origin')
        if origin is not None and (not isinstance(origin, str) or len(origin) > 1024):
            raise Rejected('Invalid origin label')
        item['declared_origin'] = origin
        observed = {'abi': item.get('abi'),
                    'go_version': item.get('go', {}).get('version'),
                    'go_revision': item.get('go', {}).get('settings', {}).get('vcs.revision'),
                    'go_tags': item.get('go', {}).get('settings', {}).get('-tags'),
                    'dex_class_count': item.get('dex', {}).get('class_count')}
        expectation = expected.get('expect', {})
        keys(expectation, (), observed.keys())
        for field, value in expectation.items():
            if field == 'dex_class_count':
                if type(value) is not int or value < 0:
                    raise Rejected('Expected a nonnegative DEX class count')
            elif not isinstance(value, str) or not value or len(value) > 1024:
                raise Rejected('Expected nonempty metadata text')
            if observed[field] is None:
                item.setdefault('metadata_unavailable', []).append(field)
            elif observed[field] != value:
                item['contradictions'].append('metadata_mismatch:' + field)
        links = expected.get('links', [])
        if not isinstance(links, list) or len(links) > 1000:
            raise Rejected('Expected a bounded link list')
        for ref in links:
            if not isinstance(ref, dict):
                raise Rejected('Invalid material link')
            relation = ref.get('relation')
            if relation not in ('same_bytes', 'transform_input', 'source_file', 'embedded_bytes'):
                raise Rejected('Unsupported material relation')
            link, data = check_reference(ref, selections)
            link['relation'] = relation
            if link['status'] == 'matched':
                if relation == 'same_bytes' and link['actual_sha256'] != item['sha256']:
                    link['status'] = 'contradiction'
                elif relation == 'embedded_bytes':
                    if not data:
                        raise Rejected('Empty embedded payload')
                    parent = archive.read(name)
                    offset = parent.find(data)
                    link.update(offset=offset, size=len(data))
                    if offset < 0:
                        link['status'] = 'contradiction'
                elif relation in ('transform_input', 'source_file'):
                    link['limitation'] = 'input hash only; transformation/generation not proven'
            if link['status'] == 'contradiction':
                item['contradictions'].append('material_link_mismatch')
            item['links'].append(link)
    sources = record.get('source_inputs', [])
    if not isinstance(sources, list) or len(sources) > MAX_ENTRIES:
        raise Rejected('Expected bounded source inputs')
    for ref in sources:
        if not isinstance(ref, dict):
            raise Rejected('Invalid source input')
        if ref.get('relation') not in (None, 'source_file'):
            raise Rejected('Source inputs only assert input identity')
        result, _ = check_reference(ref, selections)
        report['source_inputs'].append(result)
    if 'r8' in record:
        ref = record['r8']
        if not isinstance(ref, dict):
            raise Rejected('Invalid R8 reference')
        if ref.get('relation') not in (None, 'source_file'):
            raise Rejected('R8 reference only asserts input identity')
        result, data = check_reference(ref, selections)
        report['r8'] = result
        if result['status'] == 'matched':
            definitions = {name for item in report['objects']
                           for name in item.get('dex', {}).get('definitions', [])}
            names = []
            for line in data.decode('utf-8', errors='replace').splitlines():
                match = re.fullmatch(r'([^ #\s][^ ]*) -> ([^ ]+):', line)
                if match and 'L' + match[2].replace('.', '/') + ';' in definitions:
                    names.append(match[1])
            result['original_names_mapping_to_defined_classes'] = sorted(set(names))
            result['limitation'] = 'R8 names do not prove generation or runtime reachability; zero is not absence'


def finalize(report):
    objects = report['objects']
    for item in objects:
        if item['contradictions']:
            item['reference_status'] = 'contradiction'
        matched = [link for link in item['links'] if link['status'] == 'matched']
        item['material_status'] = ('byte_correspondence_only' if any(
            link['relation'] in ('same_bytes', 'embedded_bytes') for link in matched)
            else 'input_identity_only' if matched else 'unbound')
        item['unknowns'] = ['publisher_authentication', 'generation_causality',
                            'runtime_loading']
        if not matched:
            item['unknowns'].append('material_lineage')
    sources = report['source_inputs'] + ([report['r8']] if 'r8' in report else [])
    link_count = sum(len(item['links']) for item in objects)
    unresolved = sum(link['status'] == 'unavailable' for item in objects
                     for link in item['links']) + sum(x['status'] == 'unavailable' for x in sources)
    unavailable_metadata = sum(len(x.get('metadata_unavailable', [])) for x in objects)
    conflicts = (len(report['contradictions']) + len(report['records_not_in_apk'])
                 + sum(bool(item['contradictions']) for item in objects)
                 + sum(x['status'] == 'contradiction' for x in sources))
    covered = sum(item['has_reference'] for item in objects)
    report['coverage'] = {
        'apk_entries': len(objects), 'entries_with_reference': covered,
        'entries_without_reference': len(objects) - covered,
        'entry_reference_coverage_complete': bool(objects) and covered == len(objects),
        'native_entries': sum(x['kind'] == 'native' for x in objects),
        'dex_entries': sum(x['kind'] == 'dex' for x in objects),
        'material_links': link_count, 'unavailable_inputs': unresolved,
        'unavailable_metadata_fields': unavailable_metadata,
        'entries_without_checked_material_links': sum(
            not any(link['status'] == 'matched' for link in x['links']) for x in objects),
        'wasm_magic_candidates': sum(len(x.get('wasm_magic_candidates', [])) for x in objects),
        'contradictory_apk_entries': sum(bool(x['contradictions']) for x in objects),
        'contradictory_source_inputs': sum(x['status'] == 'contradiction' for x in sources),
        'apk_context_mismatches': len(report['contradictions']),
        'expected_entries_missing_from_apk': len(report['records_not_in_apk']),
    }
    packaged = {x['entry'].rsplit('/', 1)[-1] for x in objects if x['kind'] == 'native'}
    report['native_imports_not_in_apk'] = sorted({name for x in objects
                                                for name in x.get('elf', {}).get('needed_libraries', [])
                                                if name not in packaged})
    if report['errors']:
        report['status'], code = 'rejected_input', 2
    elif conflicts:
        report['status'], code = 'contradiction', 1
    else:
        complete = bool(objects) and covered == len(objects) and not unresolved and not unavailable_metadata
        report['status'] = 'consistent_entry_references' if complete else 'partial_inventory'
        code = 0
    report['exit_code'] = code
    return report


def inspect(apk, record_path=None, inputs=(), expected_abi=None):
    report = {'apk': {}, 'objects': [], 'source_inputs': [],
              'records_not_in_apk': [], 'contradictions': [], 'errors': [],
              'reference_kind': 'explicit_external_record' if record_path else 'no_reference',
              'proof_limits': {'publisher_authentication': 'not_assessed',
                               'source_generation': 'not_proven',
                               'runtime_loading': 'not_observed',
                               'source_inputs': 'selected identities only, not compilation, inclusion or a complete input closure',
                               'embedded_code_scan': 'WASM magic candidates only; not exhaustive'}}
    try:
        with ExitStack() as stack:
            apk_input = SelectedInput(apk)
            stack.callback(apk_input.close)
            with apk_input.open() as stream:
                report['apk'] = {'size': os.fstat(stream.fileno()).st_size,
                                 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
                stream.seek(0)
                with zipfile.ZipFile(stream) as archive:
                    infos = archive_entries(archive)
                    if not any(i.filename == 'AndroidManifest.xml' for i in infos):
                        raise Rejected('APK has no AndroidManifest.xml')
                    for info in infos:
                        with archive.open(info) as member:
                            data = read_bounded(member)
                        item = inspect_entry(info.filename, data)
                        if (expected_abi and item['kind'] == 'native'
                                and item.get('abi') != expected_abi):
                            item['contradictions'].append('unexpected_abi')
                        report['objects'].append(item)
                    selections = {}
                    for spec in inputs:
                        alias, sep, path = spec.partition('=')
                        if (not sep or not re.fullmatch(r'[a-z][a-z0-9_-]*', alias)
                                or alias in selections):
                            raise Rejected('Expected unique input name=path')
                        selected = SelectedInput(path)
                        stack.callback(selected.close)
                        selections[alias] = selected
                    if record_path is not None:
                        selected = SelectedInput(record_path)
                        stack.callback(selected.close)
                        with selected.open() as record:
                            value = json.loads(read_bounded(record, 4 * 1024 * 1024),
                                               object_pairs_hook=unique_object)
                        apply_record(report, value, selections, archive)
    except (Rejected, OSError, ValueError, RuntimeError, zipfile.BadZipFile,
            NotImplementedError) as error:
        report['errors'].append({'kind': type(error).__name__, 'reason': str(error)})
    return finalize(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--record', type=Path)
    parser.add_argument('--input', action='append', default=[], metavar='NAME=PATH')
    parser.add_argument('--abi', choices=sorted(ABI))
    args = parser.parse_args()
    report = inspect(args.apk, args.record, args.input, args.abi)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return report['exit_code']


if __name__ == '__main__':
    sys.exit(main())
