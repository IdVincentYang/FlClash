import copy
import hashlib
import io
import json
from pathlib import Path
import shutil
import stat
import tempfile
import tarfile
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import zipfile

from ci_release import (GitHubAPI, ReleaseError, artifact_metadata, consume, event_context,
                        expected_names, gate_binding, pack, pack_pages, pages_intent, producer, qualify, unpack, site_manifest, site_digest, read_pages_tar, verify_pages_artifact)


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve(strict=True)
        self.env = {'GITHUB_REPOSITORY': 'chen08209/FlClash', 'GITHUB_REPOSITORY_ID': '42',
                    'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_TYPE': 'tag',
                    'GITHUB_REF': 'refs/tags/v1.2.3', 'GITHUB_SHA': 'a' * 40,
                    'GITHUB_RUN_ID': '12', 'GITHUB_RUN_ATTEMPT': '2'}
        self.event = {'deleted': False, 'ref': 'refs/tags/v1.2.3',
                      'repository': {'full_name': 'chen08209/FlClash', 'id': 42, 'default_branch': 'main'}}
        self.pubspec = 'name: fixture\nversion: 1.2.3+7\n'
        self.intent = event_context(self.env, self.event, self.pubspec)

    def fixture(self, *, extra=None, inventory_change=None):
        payload = {'release.md': b'# Release\n', 'telegram.md': b'Expected notes\n'}
        inventory = {'schema': 1, 'role': 'notes', 'run_id': 12, 'attempt': 2,
                     'commit': 'a' * 40, 'files': {name: {'size': len(value),
                     'sha256': hashlib.sha256(value).hexdigest()} for name, value in payload.items()}}
        if inventory_change:
            inventory_change(inventory)
        archive = self.root / ('artifact-' + str(len(list(self.root.iterdir()))) + '.zip')
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('inventory.json', json.dumps(inventory))
            for name, value in payload.items():
                bundle.writestr('payload/' + name, value)
            if extra:
                bundle.writestr(*extra)
        return archive

    def test_strict_release_context_and_version(self):
        self.assertEqual((self.intent['version'], self.intent['build_number'], self.intent['stable']), ('1.2.3', 7, 'true'))
        for name, value in [('GITHUB_REPOSITORY', 'fork/repo'), ('GITHUB_REF_TYPE', 'branch'),
                            ('GITHUB_EVENT_NAME', 'workflow_dispatch'), ('GITHUB_REF', 'refs/heads/v1.2.3')]:
            changed = dict(self.env, **{name: value})
            with self.subTest(name=name), self.assertRaises(ReleaseError):
                event_context(changed, self.event, self.pubspec)
        with self.assertRaises(ReleaseError):
            event_context(self.env, self.event, 'version: 1.2.4+7')
        with self.assertRaises(ReleaseError):
            event_context(self.env, dict(self.event, deleted=True), self.pubspec)
        for tag in ('v1.2', 'v01.2.3', 'v1.2.3-pre.0', 'v1.2.3-other.1', 'v1.2.3\n'):
            with self.subTest(tag=tag), self.assertRaises(ReleaseError):
                event_context(dict(self.env, GITHUB_REF='refs/tags/' + tag),
                              dict(self.event, ref='refs/tags/' + tag), self.pubspec)
        pre = event_context(dict(self.env, GITHUB_REF='refs/tags/v1.2.3-pre.2'),
                            dict(self.event, ref='refs/tags/v1.2.3-pre.2'), self.pubspec)
        self.assertEqual(pre['stable'], 'false')

    def test_gate_output_binds_the_current_cohort_before_secret_job_start(self):
        self.assertEqual(gate_binding(self.intent), {'eligible': 'true', 'run_id': 12, 'attempt': 2, 'commit': 'a' * 40})
        env = dict(self.env, GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REF='refs/heads/main')
        output = pages_intent(None, env, self.event)
        self.assertEqual({key: output[key] for key in ('run_id', 'attempt', 'commit')},
                         {'run_id': 12, 'attempt': 2, 'commit': 'a' * 40})
        env['GITHUB_RUN_ATTEMPT'] = ''
        with self.assertRaises(ReleaseError): pages_intent(None, env, self.event)

    def test_exact_android_roles_and_no_filename_manifest_authority(self):
        expected = {'FlClash-1.2.3-android-arm64-v8a.apk', 'FlClash-1.2.3-android-armeabi-v7a.apk',
                    'FlClash-1.2.3-android-x86_64.apk'}
        self.assertEqual(expected_names('android-candidate', '1.2.3'), expected)
        self.assertEqual(expected_names('android-final', '1.2.3'), expected)
        archive = self.fixture()
        paths = unpack(archive, self.root / 'unpacked', 'notes', self.intent)
        self.assertEqual([path.name for path in paths], ['release.md', 'telegram.md'])
        self.assertEqual(paths[1].read_bytes(), b'Expected notes\n')
        with self.assertRaises(ReleaseError):
            unpack(archive, self.root / 'wrong-role', 'android-final', self.intent)

    def test_missing_extra_paths_links_and_candidate_identity_are_rejected(self):
        for name in ('../escape', '/absolute', 'payload/../escape', 'payload\\escape', 'payload/extra'):
            archive = self.fixture(extra=(name, b'unaccepted'))
            with self.subTest(name=name), self.assertRaises(ReleaseError):
                unpack(archive, self.root / ('out-' + str(len(list(self.root.iterdir())))), 'notes', self.intent)
        link = zipfile.ZipInfo('payload/extra')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(ReleaseError):
            unpack(self.fixture(extra=(link, b'/outside')), self.root / 'link', 'notes', self.intent)
        for key, value in [('run_id', 1), ('attempt', 1), ('commit', 'b' * 40), ('role', 'android-final')]:
            archive = self.fixture(inventory_change=lambda data: data.update({key: value}))
            with self.subTest(key=key), self.assertRaises(ReleaseError):
                unpack(archive, self.root / ('out-' + str(len(list(self.root.iterdir())))), 'notes', self.intent)

    def test_payload_hash_and_exact_producer_directory(self):
        archive = self.fixture(inventory_change=lambda data: data['files']['release.md'].update(sha256='0' * 64))
        with self.assertRaises(ReleaseError):
            unpack(archive, self.root / 'corrupt', 'notes', self.intent)
        source = self.root / 'source'
        source.mkdir()
        (source / 'release.md').write_text('# Release\n')
        (source / 'telegram.md').write_text('Expected notes\n')
        pack(source, self.root / 'packed', 'notes', self.intent)
        self.assertEqual(json.loads((self.root / 'packed/inventory.json').read_text())['role'], 'notes')
        (source / 'secret.txt').write_text('synthetic private file')
        with self.assertRaises(ReleaseError):
            pack(source, self.root / 'rejected', 'notes', self.intent)

    def test_producer_output_and_api_cannot_be_replaced_by_candidate_claims(self):
        needs = {'notes': {'result': 'success', 'outputs': {'notes_id': '76', 'notes_sha256': 'c' * 64, 'notes_attempt': '2'}}}
        jobs = [{'id': 5, 'name': 'Notes', 'run_id': 12, 'head_sha': 'a' * 40, 'conclusion': 'success',
                 'steps': [{'name': 'Upload producer artifact', 'conclusion': 'success'}]}]
        self.assertEqual(producer(needs, 'notes', self.intent, jobs), (76, 'c' * 64))
        for change in ('old-attempt', 'missing-id', 'failed-job', 'failed-upload'):
            n, j = copy.deepcopy(needs), copy.deepcopy(jobs)
            if change == 'old-attempt': n['notes']['outputs']['notes_attempt'] = '1'
            if change == 'missing-id': del n['notes']['outputs']['notes_id']
            if change == 'failed-job': j[0]['conclusion'] = 'failure'
            if change == 'failed-upload': j[0]['steps'][0]['conclusion'] = 'failure'
            with self.subTest(change=change), self.assertRaises(ReleaseError):
                producer(n, 'notes', self.intent, j)
        metadata = {'id': 76, 'name': 'build-12-2-notes', 'expired': False, 'digest': 'sha256:' + 'c' * 64,
                    'workflow_run': {'id': 12, 'repository_id': 42, 'head_repository_id': 42, 'head_sha': 'a' * 40}}
        class API:
            def get(inner, path):
                self.assertEqual(path, 'actions/artifacts/76')
                return metadata
        artifact_metadata(API(), self.intent, 'notes', 76, 'c' * 64)
        metadata['workflow_run']['id'] = 13
        with self.assertRaises(ReleaseError):
            artifact_metadata(API(), self.intent, 'notes', 76, 'c' * 64)

    def test_annotation_peel_and_changed_tag_fail_closed(self):
        run = {'id': 12, 'head_sha': 'a' * 40, 'event': 'push', 'run_attempt': 2,
               'repository': {'id': 42}, 'head_repository': {'id': 42}}
        records = {'actions/runs/12': run, 'git/ref/tags/v1.2.3': {'object': {'sha': 'd' * 40, 'type': 'tag'}},
                   'git/tags/' + 'd' * 40: {'object': {'sha': 'a' * 40, 'type': 'commit'}}}
        class API:
            def get(inner, path): return records[path]
        self.assertEqual(qualify(API(), self.intent), self.intent)
        records['git/tags/' + 'd' * 40]['object']['sha'] = 'b' * 40
        with self.assertRaises(ReleaseError): qualify(API(), self.intent)

    def test_pages_preserves_main_push_and_manual_and_separates_source_head(self):
        env = dict(self.env, GITHUB_EVENT_NAME='push', GITHUB_REF='refs/heads/main', GITHUB_SHA='b' * 40)
        event = dict(self.event, ref='refs/heads/main')
        self.assertEqual(pages_intent(None, env, event)['checkout_sha'], 'b' * 40)
        env['GITHUB_EVENT_NAME'] = 'workflow_dispatch'
        self.assertEqual(pages_intent(None, env, event)['eligible'], 'true')
        env['GITHUB_REF'] = 'refs/heads/untrusted'
        with self.assertRaises(ReleaseError): pages_intent(None, env, event)
        env.update(GITHUB_EVENT_NAME='workflow_run', GITHUB_REF='refs/heads/main')
        event.update(action='completed', workflow_run={'id': 12, 'run_attempt': 2, 'head_sha': 'a' * 40})
        run = {'id': 12, 'workflow_id': 9, 'path': '.github/workflows/build.yaml', 'head_sha': 'a' * 40,
               'event': 'push', 'conclusion': 'success', 'status': 'completed', 'run_attempt': 2,
               'repository': {'id': 42}, 'head_repository': {'id': 42}, 'head_branch': 'v1.2.3'}
        jobs = [{'name': name, 'conclusion': 'success', 'head_sha': 'a' * 40} for name in ('Release gate', 'Publish GitHub')]
        records = {'actions/runs/12': run, 'actions/workflows/build.yaml': {'id': 9},
                   'git/ref/tags/v1.2.3': {'object': {'type': 'commit', 'sha': 'a' * 40}}}
        class API:
            def get(inner, path): return records[path]
            def jobs(inner, run_id, attempt):
                self.assertEqual((run_id, attempt), (12, 2)); return jobs
        self.assertEqual(pages_intent(API(), env, event)['checkout_sha'], 'b' * 40)
        for field, value in [('event', 'pull_request'), ('conclusion', 'failure'), ('workflow_id', 10), ('head_repository', {'id': 99})]:
            saved = run[field]; run[field] = value
            with self.subTest(field=field), self.assertRaises(ReleaseError): pages_intent(API(), env, event)
            run[field] = saved
        jobs[0]['conclusion'] = 'skipped'
        with self.assertRaises(ReleaseError): pages_intent(API(), env, event)



class PagesArtifactTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve(strict=True)
        self.site = self.root / 'site'; self.site.mkdir()
        (self.site / 'index.html').write_bytes(b'<html>Expected</html>')
        (self.site / '.nojekyll').write_bytes(b'')
        (self.site / '.well-known').mkdir(); (self.site / '.well-known/example').write_bytes(b'public hidden resource')
        (self.site / '.git').mkdir(); (self.site / '.git/config').write_text('NEVER_ARCHIVE_PRIVATE_METADATA')
        self.expected = {'index.html': {'size': 21, 'sha256': hashlib.sha256(b'<html>Expected</html>').hexdigest()},
                         '.nojekyll': {'size': 0, 'sha256': hashlib.sha256(b'').hexdigest()},
                         '.well-known/example': {'size': 22, 'sha256': hashlib.sha256(b'public hidden resource').hexdigest()}}

    def test_actual_tar_preserves_hidden_site_data_and_normalizes_permissions(self):
        self.assertEqual(site_manifest(self.site), self.expected)
        archive = self.root / 'artifact.tar'
        result = pack_pages(self.site, archive)
        self.assertEqual(result, site_digest(self.expected))
        self.assertNotEqual(archive.read_bytes()[:2], b'\x1f\x8b')
        with tarfile.open(archive) as tar:
            entries = tar.getmembers()
            self.assertIn('./.nojekyll', [entry.name for entry in entries])
            self.assertFalse(any('.git/' in entry.name for entry in entries))
            for entry in entries:
                self.assertEqual(entry.mode, 0o755 if entry.isdir() else 0o644)
                self.assertEqual((entry.uid, entry.gid, entry.uname, entry.gname, entry.mtime), (0, 0, '', '', 0))
        with archive.open('rb') as stream: read_pages_tar(stream, site_digest(self.expected))

    def test_source_links_hardlinks_special_files_and_unreadable_inputs_fail(self):
        linked = self.site / 'link'; linked.symlink_to(self.site / 'index.html')
        with self.assertRaises(ReleaseError): site_manifest(self.site)
        linked.unlink(); os.link(self.site / 'index.html', linked)
        with self.assertRaises(ReleaseError): site_manifest(self.site)
        linked.unlink(); os.mkfifo(linked)
        with self.assertRaises(ReleaseError): site_manifest(self.site)
        linked.unlink(); (self.site / 'index.html').chmod(0)
        try:
            with self.assertRaises(ReleaseError): site_manifest(self.site)
        finally: (self.site / 'index.html').chmod(0o644)

    def test_wrong_tar_member_paths_links_types_permissions_and_duplicates_fail(self):
        for case in ('symlink', 'hardlink', 'special', 'traversal', 'absolute', 'permission', 'duplicate'):
            raw = io.BytesIO()
            with tarfile.open(fileobj=raw, mode='w') as tar:
                member = tarfile.TarInfo('index.html'); member.size = 1; member.mode = 0o644
                if case == 'symlink': member.type = tarfile.SYMTYPE; member.linkname = '/outside'; member.size = 0
                if case == 'hardlink': member.type = tarfile.LNKTYPE; member.linkname = 'other'; member.size = 0
                if case == 'special': member.type = tarfile.FIFOTYPE; member.size = 0
                if case == 'traversal': member.name = '../outside'
                if case == 'absolute': member.name = '/outside'
                if case == 'permission': member.mode = 0
                tar.addfile(member, io.BytesIO(b'x') if member.isfile() else None)
                if case == 'duplicate': tar.addfile(member, io.BytesIO(b'x'))
            with self.subTest(case=case), self.assertRaises(ReleaseError):
                read_pages_tar(io.BytesIO(raw.getvalue()), '0' * 64)

    def test_deploy_gate_binds_this_pages_run_id_and_unique_name(self):
        archive = self.root / 'artifact.tar'; pack_pages(self.site, archive)
        zipped = self.root / 'pages.zip'
        with zipfile.ZipFile(zipped, 'w') as bundle: bundle.write(archive, 'artifact.tar')
        checksum = hashlib.sha256(zipped.read_bytes()).hexdigest()
        env = {'GITHUB_REPOSITORY': 'chen08209/FlClash', 'GITHUB_REPOSITORY_ID': '42', 'GITHUB_EVENT_NAME': 'push',
               'GITHUB_REF': 'refs/heads/main', 'GITHUB_SHA': 'b' * 40, 'GITHUB_RUN_ID': '12', 'GITHUB_RUN_ATTEMPT': '2'}
        event = {'ref': 'refs/heads/main', 'deleted': False, 'repository': {'default_branch': 'main'}}
        needs = {'pages_build': {'result': 'success', 'outputs': {'artifact_id': '76', 'artifact_name': 'pages-12-2',
                 'attempt': '2', 'artifact_sha256': checksum, 'site_sha256': site_digest(self.expected)}}}
        metadata = {'id': 76, 'name': 'pages-12-2', 'expired': False, 'digest': 'sha256:' + checksum,
                    'workflow_run': {'id': 12, 'head_sha': 'b' * 40, 'repository_id': 42, 'head_repository_id': 42}}
        listing = [metadata]
        class API:
            def jobs(inner, run_id, attempt):
                return [{'id': 3, 'name': 'Pages build', 'run_id': 12, 'head_sha': 'b' * 40, 'conclusion': 'success'}]
            def get(inner, path, parameters=None):
                if path == 'actions/artifacts/76': return metadata
                if path == 'actions/runs/12/artifacts': return {'total_count': len(listing), 'artifacts': listing}
                raise AssertionError(path)
            def download(inner, artifact_id, checksum_arg, destination):
                self.assertEqual((artifact_id, checksum_arg), (76, checksum)); shutil.copyfile(zipped, destination)
        self.assertEqual(verify_pages_artifact(API(), env, event, needs, self.root / 'accepted')['artifact_id'], 76)
        listing.append(dict(metadata, id=77))
        with self.assertRaises(ReleaseError):
            verify_pages_artifact(API(), env, event, needs, self.root / 'duplicate')


class HTTPTest(unittest.TestCase):
    def server(self, handler):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return 'http://127.0.0.1:' + str(server.server_port)

    def test_official_redirect_does_not_forward_authorization_or_cookies(self):
        received = []
        body = b'actual artifact bytes'
        class Sink(BaseHTTPRequestHandler):
            def do_GET(self):
                received.append(dict(self.headers))
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
            def log_message(self, *args): pass
        sink = self.server(Sink)
        api_received = []
        class Source(BaseHTTPRequestHandler):
            def do_GET(self):
                api_received.append((self.path, self.headers.get('Authorization')))
                self.send_response(302); self.send_header('Location', sink + '/artifact?signature=fake-private-query')
                self.send_header('Set-Cookie', 'api-cookie=fake-private-cookie'); self.end_headers()
            def log_message(self, *args): pass
        source = self.server(Source)
        api = GitHubAPI('fake-read-token', origin=source, allow_loopback=True)
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / 'artifact.zip'
            api.download(76, hashlib.sha256(body).hexdigest(), target)
            self.assertEqual(target.read_bytes(), body)
        self.assertEqual(api_received, [('/repos/chen08209/FlClash/actions/artifacts/76/zip', 'Bearer fake-read-token')])
        self.assertNotIn('Authorization', received[0]); self.assertNotIn('Cookie', received[0])
        self.assertNotIn('X-Github-Api-Version', received[0])

    def test_errors_do_not_echo_response_or_signed_url(self):
        class Error(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(403); self.end_headers(); self.wfile.write(b'FAKE_SECRET_BODY signature=FAKE_SIGNED_QUERY')
            def log_message(self, *args): pass
        api = GitHubAPI('fake-token', origin=self.server(Error), allow_loopback=True)
        with self.assertRaises(ReleaseError) as caught: api.get('actions/runs/12')
        self.assertNotIn('FAKE_', str(caught.exception))
        for path in ('../outside', 'https://elsewhere/path', '/other/repository'):
            with self.subTest(path=path), self.assertRaises(ReleaseError): api.get(path)
        with self.assertRaises(ReleaseError): GitHubAPI('fake', origin='https://unaccepted.invalid')

    def test_jobs_pagination_rejects_missing_and_duplicate_items(self):
        api = GitHubAPI('')
        api.get = lambda *args: {'total_count': 2, 'jobs': []}
        with self.assertRaises(ReleaseError): api.jobs(12, 2)
        api.get = lambda *args: {'total_count': 2, 'jobs': [{'id': 1}, {'id': 1}]}
        with self.assertRaises(ReleaseError): api.jobs(12, 2)


if __name__ == '__main__':
    unittest.main()
