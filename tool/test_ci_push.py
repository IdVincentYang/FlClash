import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

from ci_push import NativeTools, PushSession, ReleaseError, publish, lfs_configuration


class NativePushTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.tools = NativeTools('/usr/bin/git', '/usr/bin/ssh', shutil.which('git-lfs'))
        self.environment = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root),
                            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                            'GIT_AUTHOR_NAME': 'Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
                            'GIT_COMMITTER_NAME': 'Fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
                            'GIT_TERMINAL_PROMPT': '0'}
        self.remote = self.root / 'remote.git'
        self.seed = self.root / 'seed'
        self.git(self.root, 'init', '--bare', self.remote)
        self.git(self.root, 'init', '--initial-branch=main', self.seed)
        self.secret = '-----BEGIN SYNTHETIC TEST KEY-----\n' + 'fixture-only' * 10 + '\n-----END SYNTHETIC TEST KEY-----\n'
        self.source = self.root / 'source'
        self.source.mkdir()

    def git(self, cwd, *args, allowed=(0,)):
        result = subprocess.run([self.tools.git, *map(str, args)], cwd=cwd, env=self.environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        self.assertIn(result.returncode, allowed, result.stderr.decode())
        return result.stdout

    def initial(self, entries):
        for name, value in entries.items():
            path = self.seed / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'Initial fixture')
        self.git(self.seed, 'remote', 'add', 'origin', self.remote)
        self.git(self.seed, 'push', 'origin', 'main')

    def source_file(self, target='tap', payload=b'accepted cask\n'):
        name = 'Casks/flclash.rb' if target == 'tap' else 'FlClash-1.2.3-android-arm64-v8a.apk'
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    def publication(self, target='tap', **kwargs):
        try:
            return publish(self.source, target, '1.2.3', self.secret, self.root, self.tools,
                           local_remote=self.remote, **kwargs)
        finally:
            self.assertEqual(list(self.root.glob('native-publication-*')), [])

    def names(self):
        return set(self.git(self.root, '--git-dir', self.remote, 'ls-tree', '-r', '--name-only', 'main').decode().splitlines())

    def test_tap_replaces_clone_root_and_no_change_is_success(self):
        self.initial({'README.md': b'old', 'Casks/old.rb': b'old'})
        self.source_file()
        result = self.publication()
        self.assertEqual(result['status'], 'published')
        self.assertEqual(self.names(), {'Casks/flclash.rb'})
        self.assertEqual(self.git(self.root, '--git-dir', self.remote, 'show', 'main:Casks/flclash.rb'), b'accepted cask\n')
        self.assertEqual(self.publication()['status'], 'no_change')

    def test_fdroid_only_replaces_clone_tmp(self):
        self.initial({'README.md': b'protected', 'repo/index.xml': b'protected index', 'tmp/old.apk': b'old'})
        self.source_file('fdroid', b'synthetic apk')
        self.publication('fdroid')
        self.assertEqual(self.names(), {'README.md', 'repo/index.xml', 'tmp/FlClash-1.2.3-android-arm64-v8a.apk'})
        self.assertEqual(self.git(self.root, '--git-dir', self.remote, 'show', 'main:repo/index.xml'), b'protected index')

    def test_missing_main_and_concurrent_update_are_rejected(self):
        self.source_file()
        with self.assertRaises(ReleaseError):
            self.publication()
        self.initial({'README.md': b'old'})

        def concurrent(session):
            (self.seed / 'concurrent').write_bytes(b'new owner')
            self.git(self.seed, 'add', '.')
            self.git(self.seed, 'commit', '-m', 'Concurrent owner')
            self.git(self.seed, 'push', 'origin', 'main')

        with self.assertRaises(ReleaseError):
            self.publication(before_push=concurrent)
        self.assertEqual(self.names(), {'README.md', 'concurrent'})

    def test_parent_configuration_and_secret_environment_are_not_consumed(self):
        self.initial({'README.md': b'old'})
        self.source_file()
        marker = self.root / 'parent-injection'
        script = self.root / 'evil'
        script.write_text('#!/bin/sh\ntouch ' + str(marker) + '\nexit 1\n')
        script.chmod(0o700)
        observed = {}

        def inspect(session):
            observed.update(session.environment)
            self.assertEqual((session.key.stat().st_mode & 0o777, session.root.stat().st_mode & 0o777), (0o600, 0o700))

        with patch.dict(os.environ, {'PATH': str(self.root), 'GIT_SSH_COMMAND': str(script),
                                    'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.hooksPath',
                                    'GIT_CONFIG_VALUE_0': str(self.root), 'SSH_AUTH_SOCK': str(script),
                                    'GIT_LFS_SKIP_PUSH': '1', 'GH_TOKEN': 'synthetic-private-token'}):
            self.publication(before_push=inspect)
        self.assertFalse(marker.exists())
        for name in ('SSH_AUTH_SOCK', 'GH_TOKEN', 'GIT_LFS_SKIP_PUSH'):
            self.assertNotIn(name, observed)

    def test_unproven_group_probe_retains_identity_even_after_parent_exit(self):
        session = PushSession(self.root, self.tools, local_remote=self.remote)
        session.prepare_identity(self.secret)
        try:
            with patch('ci_push.os.killpg', side_effect=PermissionError('synthetic EPERM')):
                with self.assertRaises(ReleaseError): session.run(['/usr/bin/true'], self.root)
            self.assertFalse(session.quiescent)
            self.assertTrue(all(child.poll() is not None for child in session.children))
            with self.assertRaises(ReleaseError): session.close()
            self.assertEqual(session.key.read_text(), self.secret)
            self.assertTrue(session.known_hosts.is_file())
        finally:
            for child in session.children:
                with self.assertRaises(ProcessLookupError): os.killpg(child.pid, 0)
            session.quiescent = True
            session.close()

    def test_source_extra_link_and_changed_host_identity_fail(self):
        self.initial({'README.md': b'old'})
        path = self.source_file()
        extra = self.source / 'extra'
        extra.write_bytes(b'not authorized')
        with self.assertRaises(ReleaseError): self.publication()
        extra.unlink()
        path.unlink()
        path.symlink_to(self.seed / 'README.md')
        with self.assertRaises(ReleaseError): self.publication()
        path.unlink()
        self.source_file()

        def corrupt(session):
            session.known_hosts.write_text('github.com ssh-ed25519 wrong\n')

        with self.assertRaises(ReleaseError): self.publication(before_push=corrupt)
        self.assertEqual(self.names(), {'README.md'})

    def test_unknown_filter_and_lfs_receiver_are_rejected(self):
        self.initial({'.gitattributes': b'tmp/*.apk filter=unknown\n', 'tmp/old': b'old'})
        self.source_file('fdroid')
        with self.assertRaises(ReleaseError): self.publication('fdroid')
        (self.seed / '.gitattributes').write_text('tmp/*.apk filter=lfs\n')
        (self.seed / '.lfsconfig').write_text('[lfs]\n url = https://unaccepted.invalid/lfs\n')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'Unaccepted receiver')
        self.git(self.seed, 'push', 'origin', 'main')
        with self.assertRaises(ReleaseError): self.publication('fdroid')

    def test_native_lfs_effective_github_receiver_keeps_ssh_authentication(self):
        self.initial({'.gitattributes': b'tmp/*.apk filter=lfs\n'})
        session = PushSession(self.root, self.tools, local_remote=self.remote)
        try:
            session.prepare_identity(self.secret)
            session.run([self.tools.git, 'clone', '--branch', 'main', self.remote, session.root / 'clone'], self.root)
            session.git('remote', 'set-url', 'origin', 'git@github.com:chen08209/FlClash-fdroid-repo.git')
            self.assertEqual(lfs_configuration(session, 'FlClash-fdroid-repo', ['tmp/fixture.apk']), ['tmp/fixture.apk'])
        finally:
            session.close()

    @unittest.skipUnless(Path('/usr/sbin/sshd').is_file() and shutil.which('ssh-keygen'), 'Native SSH server fixture unavailable')
    def test_native_ssh_rejects_different_loopback_server_host_key(self):
        host_key = self.root / 'synthetic-host'
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(host_key)],
                       env=self.environment, check=True, capture_output=True)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        config = self.root / 'sshd_config'
        config.write_text(f'ListenAddress 127.0.0.1\nPort {port}\nHostKey {host_key}\n'
                          f'PidFile {self.root}/sshd.pid\nUsePAM no\nPasswordAuthentication no\n'
                          'KbdInteractiveAuthentication no\nPermitRootLogin no\n')
        server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], env=self.environment,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        session = None
        try:
            for _ in range(100):
                if server.poll() is not None:
                    self.fail('Owned SSH server could not start: ' + server.stderr.read().decode())
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.1): break
                except OSError: time.sleep(0.02)
            else: self.fail('Owned SSH server did not become ready')
            session = PushSession(self.root, self.tools, local_remote=self.remote)
            session.prepare_identity(self.secret)
            command = shlex.split(session.environment['GIT_SSH_COMMAND'])
            result = session.run([*command, '-o', 'HostName=127.0.0.1', '-o', f'Port={port}',
                                  '-o', 'HostKeyAlias=github.com', '-o', 'ConnectTimeout=3', 'github.com'],
                                 self.root, allowed=(255,))
            self.assertIn(b'Host key verification failed', result.stderr)
        finally:
            if session: session.close()
            server.terminate()
            server.communicate(timeout=5)

    def test_native_lfs_transfers_synthetic_object_to_controlled_receiver(self):
        if not self.tools.lfs: self.skipTest('Native Git-LFS unavailable')
        self.initial({'.gitattributes': b'tmp/*.apk filter=lfs diff=lfs merge=lfs -text\n', 'README.md': b'protected'})
        payload = b'synthetic native LFS object\n' * 100
        self.source_file('fdroid', payload)
        oid = hashlib.sha256(payload).hexdigest()
        received = []
        batches = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass

            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                if self.path.endswith('/locks/verify'):
                    self.send_response(404)
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                batches.append(request)
                host = 'http://127.0.0.1:' + str(self.server.server_port)
                objects = [{'oid': item['oid'], 'size': item['size'], 'actions': {
                    'upload': {'href': host + '/objects/' + item['oid']}}} for item in request['objects']]
                response = json.dumps({'transfer': 'basic', 'objects': objects}).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.git-lfs+json')
                self.send_header('Content-Length', str(len(response)))
                self.end_headers()
                self.wfile.write(response)

            def do_PUT(self):
                received.append((self.path, self.rfile.read(int(self.headers['Content-Length']))))
                self.send_response(200)
                self.send_header('Content-Length', '0')
                self.end_headers()

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            self.publication('fdroid', local_lfs='http://127.0.0.1:' + str(server.server_port) + '/lfs')
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        self.assertEqual(received, [('/objects/' + oid, payload)])
        self.assertEqual(batches[0]['operation'], 'upload')
        pointer = self.git(self.root, '--git-dir', self.remote, 'show', 'main:tmp/FlClash-1.2.3-android-arm64-v8a.apk')
        self.assertEqual(pointer, f'version https://git-lfs.github.com/spec/v1\noid sha256:{oid}\nsize {len(payload)}\n'.encode())


if __name__ == '__main__':
    unittest.main()
