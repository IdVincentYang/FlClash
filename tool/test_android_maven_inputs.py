import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import android_maven_inputs as maven
from android_input_materials import MaterialError


class MavenInputsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.metadata = self.root / 'verification-metadata.xml'
        self.repository = self.root / 'repository'
        self.repository.mkdir()
        self.payload = self.repository / 'cached.jar'
        self.payload.write_bytes(b'accepted payload')
        self.coordinate = 'org/example/sample/1.0/sample-1.0.jar'
        self.sha = hashlib.sha256(b'accepted payload').hexdigest()
        self.write_metadata()

    def write_metadata(self, key='a' * 40, key_scope='group="org.example" name="sample" version="1.0"'):
        self.metadata.write_text(f'''<verification-metadata xmlns="{maven.NAMESPACE}">
<configuration><verify-metadata>true</verify-metadata><verify-signatures>true</verify-signatures>
<key-servers enabled="false"/><trusted-keys><trusted-key id="{key}" {key_scope}/></trusted-keys></configuration>
<components><component group="org.example" name="sample" version="1.0">
<artifact name="sample-1.0.jar"><sha256 value="{self.sha}"/></artifact>
</component></components></verification-metadata>''')

    def verify(self, files=None):
        return maven.verify_maven_files(self.metadata, self.repository,
                                       files or {self.coordinate: 'cached.jar'})

    def test_known_raw_bytes_pass_without_accepting_gradle_internal_state(self):
        result = self.verify()
        self.assertEqual(result['raw_artifacts_checked'], 1)
        self.assertFalse(result['gradle_internal_cache_accepted'])
        self.assertFalse(result['profile_ready'])

    def test_first_acquisition_needs_no_existing_raw_cache_inputs(self):
        result = maven.verify_maven_files(self.metadata, self.repository, {})
        self.assertEqual(result['raw_artifacts_checked'], 0)
        self.assertFalse(result['profile_ready'])

    def test_native_consumer_cannot_use_a_different_metadata_or_keyring(self):
        keyring = self.root / 'verification-keyring.keys'
        keyring.write_bytes(b'public test key material; identity check only')
        consumer = self.root / 'consumer'
        consumer.mkdir()
        for name in ('verification-metadata.xml', 'verification-keyring.keys'):
            (consumer / name).write_bytes((self.root / name).read_bytes())
        self.assertTrue(maven.verify_native_metadata(self.root, consumer)[
            'native_metadata_matches_canonical'])
        for name in ('verification-metadata.xml', 'verification-keyring.keys'):
            before = (consumer / name).read_bytes()
            (consumer / name).write_bytes(b'candidate supplied root')
            with self.assertRaises(MaterialError):
                maven.verify_native_metadata(self.root, consumer)
            (consumer / name).write_bytes(before)

    def test_same_length_and_mtime_cache_corruption_fails(self):
        before = self.payload.stat()
        self.payload.write_bytes(b'replaced payload')
        os.utime(self.payload, ns=(before.st_atime_ns, before.st_mtime_ns))
        self.assertEqual(self.payload.stat().st_size, before.st_size)
        self.assertEqual(self.payload.stat().st_mtime_ns, before.st_mtime_ns)
        with self.assertRaises(MaterialError):
            self.verify()

    def test_unknown_coordinate_is_rejected_before_opening_selected_file(self):
        private = self.root / 'private'
        private.write_bytes(b'do not read')
        inode = private.stat().st_ino
        original = os.fdopen

        def guarded(fd, *args, **kwargs):
            self.assertNotEqual(os.fstat(fd).st_ino, inode)
            return original(fd, *args, **kwargs)

        with patch.object(os, 'fdopen', guarded), self.assertRaises(MaterialError):
            self.verify({'org/example/unlisted/1.0/unlisted.jar': '../private'})

    def test_raw_cache_cannot_redirect_selected_bytes_outside_root(self):
        (self.repository / 'alias').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            self.verify({self.coordinate: 'alias/private'})
        with self.assertRaises(MaterialError):
            self.verify({self.coordinate: '../private'})

    def test_finite_key_and_strict_settings_are_required(self):
        for key, scope in [('a' * 16, 'group="org.example" name="sample" version="1.0"'),
                           ('a' * 40, 'group="org.example"'),
                           ('a' * 40, 'group="org.example" name="sample" version="1.0" regex="true"')]:
            self.write_metadata(key, scope)
            with self.assertRaises(MaterialError):
                self.verify()
        self.write_metadata()
        valid = self.metadata.read_text()
        for text in [valid.replace('<verify-signatures>true', '<verify-signatures>false'),
                     valid.replace('enabled="false"', 'enabled="true"'),
                     valid.replace('<trusted-keys>', '<trusted-artifacts/><trusted-keys>'),
                     valid.replace('<trusted-keys>', '<ignored-keys/><trusted-keys>')]:
            self.metadata.write_text(text)
            with self.assertRaises(MaterialError):
                self.verify()

    def test_missing_duplicate_hash_and_traversal_metadata_fail(self):
        valid = self.metadata.read_text()
        sha = f'<sha256 value="{self.sha}"/>'
        for text in [valid.replace(sha, ''), valid.replace(sha, sha + sha),
                     valid.replace('name="sample-1.0.jar"', 'name="../outside.jar"')]:
            self.metadata.write_text(text)
            with self.assertRaises(MaterialError):
                self.verify()

    def test_artifact_keys_need_full_fingerprints_and_cannot_add_exemptions(self):
        valid = self.metadata.read_text()
        for addition in ('<pgp value="' + 'a' * 16 + '"/>', '<ignored-keys/>',
                         '<pgp value="' + 'a' * 40 + '" regex="true"/>'):
            self.metadata.write_text(valid.replace('</artifact>', addition + '</artifact>'))
            with self.assertRaises(MaterialError):
                self.verify()
        self.metadata.write_text(valid.replace('</artifact>',
            '<pgp value="' + 'b' * 40 + '"/></artifact>'))
        self.assertEqual(self.verify()['raw_artifacts_checked'], 1)


if __name__ == '__main__':
    unittest.main()
