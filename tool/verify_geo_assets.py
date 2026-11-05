#!/usr/bin/env python3
"""Compare Geo files with an explicitly selected, local accepted reference."""

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile


RESOURCE_MAP = {
    'MMDB': ('GEOIP.metadb', 'geoip.metadb', 'maxmind-meta-country'),
    'ASN': ('ASN.mmdb', 'GeoLite2-ASN.mmdb', 'maxmind-asn'),
    'GEOIP': ('GEOIP.dat', 'geoip.dat', 'v2ray-geoip'),
    'GEOSITE': ('GEOSITE.dat', 'geosite.dat', 'v2ray-geosite'),
}
HOME_NAMES = {
    'MMDB': ({'country.mmdb', 'geoip.db', 'geoip.metadb'}, 'geoip.metadb'),
    'ASN': ({'asn.mmdb'}, 'ASN.mmdb'),
    'GEOIP': ({'geoip.dat'}, 'GeoIP.dat'),
    'GEOSITE': ({'geosite.dat'}, 'GeoSite.dat'),
}
SCRIPT_REPO = Path(__file__).resolve().parents[1]


def exact_keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValueError('Unknown or missing schema fields')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON field: ' + key)
        result[key] = value
    return result


def hex_digest(value, length):
    return (isinstance(value, str) and len(value) == length
            and all(c in '0123456789abcdef' for c in value))


def load_reference(repo):
    path = repo / 'assets/data/geo_manifest.json'
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 65536:
        raise ValueError('Reference must be a regular manifest no larger than 64 KiB')
    raw = path.read_bytes()
    data = json.loads(raw, object_pairs_hook=unique_object)
    exact_keys(data, ['version', 'publisher', 'release_commit', 'release_id',
                      'published_at', 'evidence', 'history', 'resources'])
    if type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Unsupported manifest version')
    if (data['publisher'] != 'https://github.com/MetaCubeX/meta-rules-dat'
            or not hex_digest(data['release_commit'], 40)
            or type(data['release_id']) is not int or data['release_id'] <= 0
            or not isinstance(data['published_at'], str)):
        raise ValueError('Invalid publisher reference')
    exact_keys(data['evidence'], ['kind', 'independent_signature', 'build_provenance'])
    if type(data['evidence']['independent_signature']) is not bool or data['evidence'] != {
        'kind': 'accepted-same-channel-github-snapshot',
        'independent_signature': False,
        'build_provenance': 'unproven',
    }:
        raise ValueError('Unsupported evidence claim')
    history = data['history']
    exact_keys(history, ['project_commit', 'original_data_release',
                         'exact_generation_inputs', 'prior_payloads'])
    exact_keys(history['prior_payloads'], RESOURCE_MAP)
    if (not hex_digest(history['project_commit'], 40)
            or history['original_data_release'] != 'unknown'
            or history['exact_generation_inputs'] != 'unknown'
            or not all(hex_digest(v, 64) for v in history['prior_payloads'].values())):
        raise ValueError('Invalid historical reference')
    resources = data['resources']
    if not isinstance(resources, list) or len(resources) != len(RESOURCE_MAP):
        raise ValueError('Expected exactly four resource roles')
    seen = set()
    for entry in resources:
        exact_keys(entry, ['role', 'filename', 'asset_name', 'format', 'asset_id',
                           'size', 'sha256', 'source_url'])
        role = entry['role']
        if not isinstance(role, str) or role not in RESOURCE_MAP or role in seen:
            raise ValueError('Unknown or duplicate resource role')
        seen.add(role)
        if (entry['filename'], entry['asset_name'], entry['format']) != RESOURCE_MAP[role]:
            raise ValueError('Resource role/file mapping conflict: ' + role)
        expected_url = ('https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/'
                        + data['release_commit'] + '/' + entry['asset_name'])
        if (entry['source_url'] != expected_url
                or not hex_digest(entry['sha256'], 64)
                or type(entry['size']) is not int or not 0 < entry['size'] <= 64 * 1024 * 1024
                or type(entry['asset_id']) is not int or entry['asset_id'] <= 0):
            raise ValueError('Invalid asset reference: ' + role)
    return data, raw


def file_result(path, entry):
    result = {'path': str(path), 'matches_reference': False}
    if path.is_symlink() or not path.is_file():
        result['error'] = 'Missing, non-regular or symbolic-link file'
        return result
    result['size'] = path.stat().st_size
    if result['size'] != entry['size']:
        result['error'] = 'Size mismatch'
        return result
    with path.open('rb') as stream:
        result['sha256'] = hashlib.file_digest(stream, 'sha256').hexdigest()
    result['matches_reference'] = result['sha256'] == entry['sha256']
    if not result['matches_reference']:
        result['error'] = 'Digest mismatch'
    return result


def inspect_apk(path, entries, reference_raw):
    results = {}
    prefix = 'assets/flutter_assets/assets/data/'
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        manifest_name = prefix + 'geo_manifest.json'
        if names.count(manifest_name) != 1:
            raise ValueError('APK must contain exactly one bundled manifest')
        info = archive.getinfo(manifest_name)
        if info.file_size != len(reference_raw) or archive.read(info) != reference_raw:
            raise ValueError('APK manifest differs from the external repository reference')
        for entry in entries:
            name = prefix + entry['filename']
            result = {'entry': name, 'matches_reference': False}
            if names.count(name) != 1:
                result['error'] = 'Missing or duplicate APK asset'
            elif archive.getinfo(name).file_size != entry['size']:
                result['error'] = 'APK asset size mismatch'
            else:
                with archive.open(name) as stream:
                    result['sha256'] = hashlib.file_digest(stream, 'sha256').hexdigest()
                result['matches_reference'] = result['sha256'] == entry['sha256']
                if not result['matches_reference']:
                    result['error'] = 'APK asset digest mismatch'
            results[entry['role']] = result
    return results


def inspect_home(home, entries):
    if not home.is_dir():
        raise ValueError('Explicit home directory does not exist')
    names = sorted(p.name for p in home.iterdir() if not p.is_dir() or p.is_symlink())
    results = {}
    for entry in entries:
        aliases, fallback = HOME_NAMES[entry['role']]
        candidates = [n for n in names if n.casefold() in aliases]
        selected = candidates[0] if candidates else fallback
        result = file_result(home / selected, entry)
        result.update(candidates=candidates, selected_name=selected,
                      ambiguous=len(candidates) > 1, loaded='not_observed')
        results[entry['role']] = result
    return results


def verify(repo, apk=None, home=None):
    reference, raw = load_reference(repo)
    entries = reference['resources']
    result = {
        'reference': str(repo / 'assets/data/geo_manifest.json'),
        'reference_kind': 'script_repository' if repo.resolve() == SCRIPT_REPO else 'explicit_alternative_repository',
        'reference_sha256': hashlib.sha256(raw).hexdigest(),
        'publisher_signature_verified': False,
        'runtime_loaded_version': 'not_observed',
        'repository': {e['role']: file_result(repo / 'assets/data' / e['filename'], e) for e in entries},
    }
    if apk is not None:
        result['apk'] = inspect_apk(apk, entries, raw)
    if home is not None:
        result['home'] = inspect_home(home, entries)
    result['ok'] = all(
        item['matches_reference'] and not item.get('ambiguous', False)
        for section in ['repository', 'apk', 'home'] if section in result
        for item in result[section].values()
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=SCRIPT_REPO,
                        help='Explicit alternative repository reference; never read the APK as a trust root')
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--home', type=Path, help='Explicit synthetic home to inspect; no automatic discovery')
    args = parser.parse_args()
    try:
        result = verify(args.repo, args.apk, args.home)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        result = {'ok': False, 'error': str(error)}
    print(json.dumps(result, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
