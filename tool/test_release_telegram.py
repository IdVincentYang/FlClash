import importlib.util
import json
from pathlib import Path
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest


spec = importlib.util.spec_from_file_location('release_telegram', Path(__file__).parents[1] / 'release_telegram.py')
telegram = importlib.util.module_from_spec(spec)
spec.loader.exec_module(telegram)


class TelegramTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve(strict=True)
        self.files = []
        for role, name in [('windows-amd64', 'windows-amd64-setup.exe'), ('android-final', 'android-arm64-v8a.apk'),
                           ('macos-arm64', 'macos-arm64.dmg'), ('macos-amd64', 'macos-amd64.dmg')]:
            path = self.root / role / ('FlClash-1.2.3-' + name)
            path.parent.mkdir(); path.write_bytes(('SYNTHETIC-' + role).encode()); self.files.append(path)
        (self.root / 'unselected-secret.txt').write_text('NEVER_SEND_SYNTHETIC_PRIVATE_FILE')

    def server(self, body, status=200):
        received = []
        class Handler(BaseHTTPRequestHandler):
            def do_POST(inner):
                data = inner.rfile.read(int(inner.headers['Content-Length']))
                received.append((inner.path, dict(inner.headers), data))
                inner.send_response(status); inner.send_header('Content-Length', str(len(body)))
                inner.end_headers(); inner.wfile.write(body)
            def log_message(self, *args): pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown)
        return 'http://127.0.0.1:' + str(server.server_port), received

    def test_real_streaming_post_sends_only_explicit_four_files(self):
        files = telegram.release_files(self.root, '1.2.3')
        self.assertEqual(files, self.files)
        origin, received = self.server(b'{"ok":true}')
        telegram.send_release('123:fake_token', 'v1.2.3', '12', files, '<b>Expected notes</b>', origin=origin)
        self.assertEqual(len(received), 1)
        path, headers, body = received[0]
        self.assertEqual(path, '/bot123:fake_token/sendMediaGroup')
        self.assertEqual(len(body), int(headers['Content-Length']))
        self.assertNotIn(b'NEVER_SEND', body)
        for file in self.files: self.assertIn(file.read_bytes(), body)
        self.assertEqual(body.count(b'filename='), 4)
        self.assertIn(b'Expected notes', body)

    def test_rejection_does_not_echo_token_response_or_url(self):
        origin, received = self.server(b'{"ok":false,"description":"SYNTHETIC_SECRET_RESPONSE"}', 400)
        with self.assertRaises(telegram.ReleaseError) as caught:
            telegram.send_release('123:fake_token', 'v1.2.3-pre.1', '12', self.files, '', origin=origin)
        self.assertEqual(str(caught.exception), 'Telegram publication failed')
        self.assertEqual(len(received), 1)
        for origin in ('http://external.invalid', 'https://127.0.0.1', 'http://user:secret@localhost:8081'):
            with self.assertRaises(Exception):
                telegram.send_release('123:fake_token', 'v1.2.3', '12', self.files, '', origin=origin)

    def test_missing_or_linked_selected_file_rejects_before_post(self):
        self.files[0].unlink()
        with self.assertRaises(FileNotFoundError): telegram.release_files(self.root, '1.2.3')
        self.files[0].symlink_to(self.root / 'unselected-secret.txt')
        with self.assertRaises(Exception): telegram.release_files(self.root, '1.2.3')


if __name__ == '__main__':
    unittest.main()
