import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import verify_geo_assets as geo


class GeoVerificationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.reference, self.raw = geo.load_reference(geo.SCRIPT_REPO)

    def alternate_reference(self, data):
        target = self.root / 'assets/data/geo_manifest.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data))
        return self.root

    def make_apk(self, name, manifest=None, overrides=None):
        target = self.root / name
        prefix = 'assets/flutter_assets/assets/data/'
        with zipfile.ZipFile(target, 'w') as archive:
            archive.writestr(prefix + 'geo_manifest.json', manifest or self.raw)
            for entry in self.reference['resources']:
                payload = (geo.SCRIPT_REPO / 'assets/data' / entry['filename']).read_bytes()
                payload = (overrides or {}).get(entry['role'], payload)
                archive.writestr(prefix + entry['filename'], payload)
        return target

    def test_repository_and_external_reference_apk(self):
        result = geo.verify(geo.SCRIPT_REPO, self.make_apk('valid.apk'))
        self.assertTrue(result['ok'])
        self.assertEqual(result['reference_kind'], 'script_repository')
        self.assertFalse(result['publisher_signature_verified'])
        self.assertEqual(result['runtime_loaded_version'], 'not_observed')

    def test_forged_payload_and_self_consistent_apk_manifest_are_rejected(self):
        forged = copy.deepcopy(self.reference)
        body = b'forged payload'
        entry = forged['resources'][0]
        entry['size'] = len(body)
        entry['sha256'] = hashlib.sha256(body).hexdigest()
        apk = self.make_apk('forged.apk', json.dumps(forged).encode(), {entry['role']: body})
        with self.assertRaisesRegex(ValueError, 'external repository reference'):
            geo.verify(geo.SCRIPT_REPO, apk)

    def test_unchanged_apk_manifest_cannot_hide_bad_payload(self):
        apk = self.make_apk('bad.apk', overrides={'ASN': b'broken'})
        result = geo.verify(geo.SCRIPT_REPO, apk)
        self.assertFalse(result['ok'])
        self.assertFalse(result['apk']['ASN']['matches_reference'])

    def test_unknown_schema_rejected(self):
        self.reference['version'] = 99
        with self.assertRaises(ValueError):
            geo.load_reference(self.alternate_reference(self.reference))

    def test_unknown_field_rejected(self):
        self.reference['resources'][0]['trusted'] = True
        with self.assertRaises(ValueError):
            geo.load_reference(self.alternate_reference(self.reference))

    def test_numeric_value_cannot_replace_boolean_evidence(self):
        self.reference['evidence']['independent_signature'] = 0
        with self.assertRaises(ValueError):
            geo.load_reference(self.alternate_reference(self.reference))

    def test_duplicate_role_rejected(self):
        self.reference['resources'][0] = copy.deepcopy(self.reference['resources'][1])
        with self.assertRaises(ValueError):
            geo.load_reference(self.alternate_reference(self.reference))

    def test_role_mapping_conflict_rejected(self):
        self.reference['resources'][0]['filename'] = 'ASN.mmdb'
        with self.assertRaisesRegex(ValueError, 'mapping conflict'):
            geo.load_reference(self.alternate_reference(self.reference))

    def test_duplicate_json_fields_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON field'):
            json.loads('{"version":1,"version":99}', object_pairs_hook=geo.unique_object)

    def test_size_digest_missing_and_symlink_fail(self):
        entry = {'size': 3, 'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}
        path = self.root / 'file'
        self.assertFalse(geo.file_result(path, entry)['matches_reference'])
        path.write_bytes(b'ab')
        self.assertEqual(geo.file_result(path, entry)['error'], 'Size mismatch')
        path.write_bytes(b'abd')
        self.assertEqual(geo.file_result(path, entry)['error'], 'Digest mismatch')
        path.write_bytes(b'abc')
        self.assertTrue(geo.file_result(path, entry)['matches_reference'])
        link = self.root / 'link'
        link.symlink_to(path)
        self.assertFalse(geo.file_result(link, entry)['matches_reference'])

    def test_home_uses_core_sort_order_and_reports_conflict(self):
        entry = {'role': 'MMDB', 'size': 3,
                 'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}
        (self.root / 'GEOIP.metadb').write_bytes(b'abc')
        (self.root / 'Country.mmdb').write_bytes(b'abd')
        result = geo.inspect_home(self.root, [entry])['MMDB']
        self.assertEqual(result['selected_name'], 'Country.mmdb')
        self.assertEqual(result['candidates'], ['Country.mmdb', 'GEOIP.metadb'])
        self.assertTrue(result['ambiguous'])
        self.assertFalse(result['matches_reference'])
        self.assertEqual(result['loaded'], 'not_observed')

    def test_alternative_reference_is_explicit(self):
        root = self.alternate_reference(self.reference)
        result = geo.verify(root)
        self.assertEqual(result['reference_kind'], 'explicit_alternative_repository')
        self.assertFalse(result['ok'])

    def test_unicode_simple_fold_compatible_name(self):
        entry = {'role': 'GEOSITE', 'size': 3,
                 'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}
        (self.root / 'Geoſite.dat').write_bytes(b'abc')
        result = geo.inspect_home(self.root, [entry])['GEOSITE']
        self.assertEqual(result['selected_name'], 'Geoſite.dat')
        self.assertTrue(result['matches_reference'])


if __name__ == '__main__':
    unittest.main()
