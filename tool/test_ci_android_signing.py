import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from ci_release import ReleaseError, digest, expected_names, prepare_signer, sign_android, verify_apk


@unittest.skipUnless(os.environ.get('FLCLASH_CI_ANDROID_FIXTURE_SDK') and
                     os.environ.get('FLCLASH_CI_ANDROID_FIXTURE_JDK') and
                     os.environ.get('FLCLASH_CI_ANDROID_FIXTURE_FLUTTER'), 'Explicit accepted SDK/JDK/Flutter fixture roots required')
class AndroidSigningTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name).resolve()
        cls.sdk = Path(os.environ['FLCLASH_CI_ANDROID_FIXTURE_SDK']).resolve()
        cls.jdk = Path(os.environ['FLCLASH_CI_ANDROID_FIXTURE_JDK']).resolve()
        flutter = Path(os.environ['FLCLASH_CI_ANDROID_FIXTURE_FLUTTER']).resolve()
        kotlin = flutter / 'packages/flutter_tools/gradle/src/main/kotlin'
        codes = dict(re.findall(r'\b(ARCH_ARM32|ARCH_ARM64|ARCH_X86_64)\s+to\s+([1-9][0-9]*)',
                                (kotlin / 'FlutterPluginConstants.kt').read_text()))
        multiplier = re.findall(r'output.versionCodeOverride = abiVersionCode \* ([1-9][0-9]*) \+',
                                 (kotlin / 'FlutterPlugin.kt').read_text())
        if len(codes) != 3 or len(multiplier) != 1: raise AssertionError('Actual fixed SDK split version rule changed')
        cls.version_offsets = {abi: int(codes[key]) * int(multiplier[0]) for abi, key in
                               [('armeabi-v7a', 'ARCH_ARM32'), ('arm64-v8a', 'ARCH_ARM64'), ('x86_64', 'ARCH_X86_64')]}
        cls.jar = cls.sdk / 'build-tools/37.0.0/lib/apksigner.jar'
        cls.java = cls.jdk / 'bin/java'
        cls.keytool = cls.jdk / 'bin/keytool'
        cls.environment = {'PATH': '/usr/bin:/bin', 'HOME': str(cls.root), 'LANG': 'C', 'JAVA_HOME': str(cls.jdk)}
        cls.classes = cls.root / 'classes'
        cls.classes.mkdir()
        cls.command([cls.jdk / 'bin/javac', '-cp', cls.jar, '-d', cls.classes,
                     Path(__file__).with_name('ci_android_manifest.java').resolve()])
        cls.keys = []
        for index in range(2):
            key = cls.root / f'synthetic-{index}.jks'
            cls.command([cls.keytool, '-genkeypair', '-keystore', key, '-storepass', 'fixture-password',
                         '-keypass', 'fixture-password', '-alias', 'fixture', '-dname', 'CN=Synthetic Local Fixture',
                         '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-storetype', 'JKS'])
            cls.keys.append(key)

    @classmethod
    def command(cls, args):
        result = subprocess.run(list(map(str, args)), env=cls.environment, capture_output=True, timeout=60)
        if result.returncode: raise AssertionError(result.stderr.decode())
        return result.stdout

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.root))
        self.intent = {'version': '1.2.3', 'build_number': 7}
        self.source = self.case / 'candidate'
        self.source.mkdir()
        self.candidates()

    def candidates(self, package='com.follow.clash', version='1.2.3', code=7, bad_abi=False,
                   major=None, mutation=None, only_abi=None):
        manifest = self.case / 'AndroidManifest.xml'
        base = self.case / 'base.apk'
        for abi, elf_class, machine in [('armeabi-v7a', 1, 40), ('arm64-v8a', 2, 183), ('x86_64', 2, 62)]:
            if only_abi is not None and abi != only_abi: continue
            offset = self.version_offsets[abi]
            major_attribute = '' if major is None else f'android:versionCodeMajor="{major}" '
            manifest.write_text(f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{package}" '
                                f'{major_attribute}android:versionCode="{code + offset}" android:versionName="{version}">'
                                '<uses-sdk android:minSdkVersion="24"/><application android:hasCode="false"/></manifest>')
            if base.exists(): base.unlink()
            self.command([self.sdk / 'build-tools/37.0.0/aapt2', 'link', '--manifest', manifest,
                          '-I', self.sdk / 'platforms/android-35/android.jar', '-o', base])
            unsigned = self.case / ('unsigned-' + abi + '.apk')
            shutil.copyfile(base, unsigned)
            if mutation is not None:
                with zipfile.ZipFile(base) as bundle:
                    entries = [(entry, bundle.read(entry)) for entry in bundle.infolist()]
                with zipfile.ZipFile(unsigned, 'w') as bundle:
                    for entry, payload in entries:
                        bundle.writestr(entry, self.mutate_major(payload, mutation)
                                        if entry.filename == 'AndroidManifest.xml' else payload)
            header = bytearray(64)
            header[:6] = b'\x7fELF' + bytes([elf_class, 1])
            header[18:20] = (999 if bad_abi else machine).to_bytes(2, 'little')
            with zipfile.ZipFile(unsigned, 'a') as bundle:
                bundle.writestr('lib/' + abi + '/libfixture.so', header)
                bundle.writestr('assets/fixture.txt', b'Synthetic payload, never executed')
            apk = self.source / f'FlClash-1.2.3-android-{abi}.apk'
            self.command([self.java, '-jar', self.jar, 'sign', '--ks', self.keys[0], '--ks-key-alias', 'fixture',
                          '--ks-pass', 'pass:fixture-password', '--key-pass', 'pass:fixture-password',
                          '--v4-signing-enabled', 'false', '--out', apk, unsigned])

    @staticmethod
    def mutate_major(payload, mutation):
        data = bytearray(payload)
        resource_map = None
        offset = struct.unpack_from('<H', data, 2)[0]
        while offset < len(data):
            kind, header, size = struct.unpack_from('<HHI', data, offset)
            if kind == 0x0180:
                resource_map = offset + header
            if kind == 0x0102 and resource_map is not None:
                start, width, count = struct.unpack_from('<HHH', data, offset + 24)
                if width != 20: raise AssertionError('Unexpected actual aapt2 attribute width')
                for index in range(count):
                    attribute = offset + header + start + width * index
                    name = struct.unpack_from('<I', data, attribute + 4)[0]
                    resource = resource_map + name * 4
                    if struct.unpack_from('<I', data, resource)[0] != 0x01010576: continue
                    if mutation == 'duplicate':
                        end = offset + header + start + width * count
                        data[end:end] = data[attribute:attribute + width]
                        struct.pack_into('<I', data, 4, len(data))
                        struct.pack_into('<I', data, offset + 4, size + width)
                        struct.pack_into('<H', data, offset + 28, count + 1)
                    elif mutation == 'resource-id':
                        struct.pack_into('<I', data, resource, 0)
                    elif mutation == 'name':
                        # Keep the Android resource ID while changing its equal-length string-pool name.
                        for encoding in ('utf-8', 'utf-16le'):
                            before = 'versionCodeMajor'.encode(encoding)
                            after = 'versionCodeMinor'.encode(encoding)
                            if before in data:
                                data = data.replace(before, after)
                                break
                        else: raise AssertionError('Missing actual aapt2 major name')
                    elif mutation == 'namespace':
                        struct.pack_into('<I', data, attribute, 0xffffffff)
                    else:
                        value_type, value = {'string': (0x03, 0), 'boolean': (0x12, 0),
                                             'reference': (0x01, 0x7f010000), 'float': (0x04, 0),
                                             'null': (0x00, 0)}[mutation]
                        data[attribute + 15] = value_type
                        struct.pack_into('<I', data, attribute + 16, value)
                    return bytes(data)
            offset += size
        raise AssertionError('Actual aapt2 manifest lacks versionCodeMajor resource ID')

    def verified(self):
        result = {}
        for apk in self.source.iterdir():
            verify_apk(apk, 'android-candidate', self.intent, self.jar, self.java, self.classes)
            result[apk.name] = {'size': apk.stat().st_size, 'sha256': digest(apk)}
        return result

    def signing_environment(self):
        return dict(self.environment, KEYSTORE=base64.b64encode(self.keys[1].read_bytes()).decode(),
                    KEY_ALIAS='fixture', STORE_PASSWORD='fixture-password', KEY_PASSWORD='fixture-password',
                    GH_TOKEN='synthetic-unrelated-secret', JAVA_TOOL_OPTIONS='-Dsynthetic.unaccepted=secret')

    def test_actual_sdk_parser_three_abis_and_resigning_selected_certificate(self):
        self.candidates(major='0')
        expected = self.verified()
        destination = self.case / 'signed'
        with patch.dict(os.environ, {'JAVA_TOOL_OPTIONS': '-unaccepted-private-option'}):
            certificate = sign_android(self.source, destination, self.intent, self.jar, self.java,
                                       self.classes, self.keytool, self.signing_environment(), expected)
        der = self.command([self.keytool, '-exportcert', '-keystore', self.keys[1], '-alias', 'fixture',
                            '-storepass', 'fixture-password'])
        self.assertEqual(certificate, hashlib.sha256(der).hexdigest())
        self.assertEqual({p.name for p in destination.iterdir()}, expected_names('android-final', '1.2.3'))
        for apk in destination.iterdir():
            verify_apk(apk, 'android-final', self.intent, self.jar, self.java, self.classes, certificate)
            with self.assertRaises(ReleaseError):
                verify_apk(apk, 'android-final', self.intent, self.jar, self.java, self.classes, '0' * 64)

    def test_actual_manifest_major_absent_decimal_zero_and_hex_zero(self):
        for major in (None, '0', '0x0'):
            with self.subTest(major=major):
                self.candidates(major=major)
                self.assertEqual(len(self.verified()), 3)

    def test_actual_signed_major_nonzero_or_malformed_is_rejected_keylessly(self):
        cases = [(value, None) for value in ('1', '-1', '0x80000000')]
        cases += [('0', kind) for kind in ('duplicate', 'string', 'boolean', 'reference',
                                           'float', 'null', 'resource-id', 'name', 'namespace')]
        for major, mutation in cases:
            with self.subTest(major=major, mutation=mutation):
                self.candidates(major=major, mutation=mutation, only_abi='arm64-v8a')
                apk = self.source / 'FlClash-1.2.3-android-arm64-v8a.apk'
                self.command([self.java, '-jar', self.jar, 'verify', apk])
                parsed = subprocess.run([str(self.java), '-cp', str(self.jar) + os.pathsep + str(self.classes),
                                         'CiAndroidManifest', str(apk)], env=self.environment,
                                        capture_output=True, timeout=60)
                self.assertNotEqual(parsed.returncode, 0)
                self.assertIn(b'versionCodeMajor', parsed.stderr)
                self.assertEqual(parsed.stdout, b'')
                with self.assertRaisesRegex(ReleaseError, 'accepted SDK parser'):
                    self.verified()

    def test_actual_manifest_package_version_and_elf_abi_are_enforced(self):
        for changes in [{'package': 'com.follow.clash.dev'}, {'version': '1.2.4'}, {'code': 8}, {'bad_abi': True}]:
            with self.subTest(changes=changes):
                self.candidates(**changes)
                with self.assertRaises(ReleaseError): self.verified()

    def test_candidate_tamper_or_missing_file_fails_before_key_use(self):
        expected = self.verified()
        apk = next(self.source.iterdir())
        with apk.open('ab') as stream: stream.write(b'changed after keyless verification')
        for mode in ('changed', 'missing'):
            with self.subTest(mode=mode), self.assertRaises(ReleaseError):
                sign_android(self.source, self.case / ('rejected-' + mode), self.intent,
                             self.jar, self.java, self.classes, self.keytool, {}, expected)
            if apk.exists(): apk.unlink()
        self.assertFalse(list(self.case.glob('rejected-*')))

    def test_wrong_role_and_bad_key_fail_with_private_cleanup(self):
        with self.assertRaises(ReleaseError):
            verify_apk(next(self.source.iterdir()), 'notes', self.intent, self.jar, self.java, self.classes)
        environment = self.signing_environment()
        environment['STORE_PASSWORD'] = 'wrong-password'
        destination = self.case / 'bad-key'
        with self.assertRaises(ReleaseError):
            sign_android(self.source, destination, self.intent, self.jar, self.java,
                         self.classes, self.keytool, environment, self.verified())
        self.assertFalse((destination / '.signing').exists())

    def candidate_cli_environment(self):
        (self.case / 'pubspec.yaml').write_text('version: 1.2.3+7\n')
        event = self.case / 'event.json'
        event.write_text(json.dumps({'deleted': False, 'ref': 'refs/tags/v1.2.3',
                                    'repository': {'full_name': 'chen08209/FlClash', 'id': 42}}))
        return dict(self.environment, GITHUB_REPOSITORY='chen08209/FlClash', GITHUB_REPOSITORY_ID='42',
                           GITHUB_EVENT_NAME='push', GITHUB_REF_TYPE='tag', GITHUB_REF='refs/tags/v1.2.3',
                           GITHUB_SHA='a' * 40, GITHUB_RUN_ID='12', GITHUB_RUN_ATTEMPT='2',
                           GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(self.case / 'outputs'))

    def test_actual_candidate_cli_rejects_nonzero_major_without_signing_credentials(self):
        self.candidates(major='1', only_abi='arm64-v8a')
        environment = self.candidate_cli_environment()
        rejected = subprocess.run([sys.executable, str(Path(__file__).with_name('ci_release.py').resolve()),
                                   'verify-android-candidate', '--source', str(self.source),
                                   '--jar', str(self.jar), '--classes', str(self.classes)], cwd=self.case,
                                  env=environment, capture_output=True, timeout=60)
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stderr, b'Release qualification or artifact consumption failed\n')
        self.assertFalse(Path(environment['GITHUB_OUTPUT']).exists())

    def test_actual_candidate_cli_emits_the_keyless_binding_used_by_signing_cli(self):
        environment = self.candidate_cli_environment()
        outputs = Path(environment['GITHUB_OUTPUT'])
        command = [sys.executable, str(Path(__file__).with_name('ci_release.py').resolve())]
        verify = subprocess.run([*command, 'verify-android-candidate', '--source', str(self.source),
                                 '--jar', str(self.jar), '--classes', str(self.classes)],
                                cwd=self.case, env=environment, capture_output=True, timeout=60)
        self.assertEqual(verify.returncode, 0, verify.stderr.decode())
        binding = json.loads(outputs.read_text().removeprefix('android_candidates='))
        self.assertEqual(binding, self.verified())
        destination = self.case / 'cli-signed'
        signed = subprocess.run([*command, 'sign', '--source', str(self.source), '--destination', str(destination),
                                 '--jar', str(self.jar), '--classes', str(self.classes)], cwd=self.case,
                                env=dict(environment, **self.signing_environment(), CI_EXPECTED_ANDROID=json.dumps(binding)),
                                capture_output=True, timeout=60)
        self.assertEqual(signed.returncode, 0, signed.stderr.decode())
        self.assertEqual({p.name for p in destination.iterdir()}, expected_names('android-final', '1.2.3'))
        self.assertNotIn(b'fixture-password', signed.stdout + signed.stderr)

    @unittest.skipUnless(os.environ.get('FLCLASH_CI_ANDROID_BUILD_TOOLS_ARCHIVE'), 'Explicit accepted raw archive required')
    def test_signer_preparation_checks_the_actual_raw_archive_before_extracting_jar(self):
        archive = Path(os.environ['FLCLASH_CI_ANDROID_BUILD_TOOLS_ARCHIVE']).resolve()
        repository = Path(__file__).resolve().parents[1]
        receivers = []

        def local_download(url, **kwargs):
            receivers.append(url)
            return archive.open('rb')

        with patch('ci_release.urllib.request.urlopen', side_effect=local_download):
            prepare_signer(repository, self.case / 'prepared-signer')
        self.assertEqual(len(receivers), 1)
        self.assertTrue(receivers[0].startswith('https://dl.google.com/android/repository/'))
        self.assertEqual(digest(self.case / 'prepared-signer/apksigner.jar'), digest(self.jar))
        with patch('ci_release.urllib.request.urlopen', return_value=__import__('io').BytesIO(b'truncated raw archive')):
            with self.assertRaises(ReleaseError): prepare_signer(repository, self.case / 'bad-raw')
        self.assertFalse((self.case / 'bad-raw/apksigner.jar').exists())


if __name__ == '__main__':
    unittest.main()
