"""Local subscription and echo targets for the application activity UI check."""
import argparse
import json
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from local_fixture import Fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    fixture = Fixture()
    stopped = threading.Event()

    class Subscription(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/profile.yaml':
                self.send_error(404)
                return
            data = fixture.profile().encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/yaml')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Subscription)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for name in ['SIGINT', 'SIGTERM']:
        signal.signal(getattr(signal, name), lambda *_: stopped.set())
    ports = {'url': f'http://10.0.2.2:{server.server_port}/profile.yaml',
             'directPort': fixture.direct, 'proxyPort': fixture.proxy_target}
    (args.out / 'ports.json').write_text(json.dumps(ports))
    print(json.dumps(ports), flush=True)
    try:
        stopped.wait()
    finally:
        (args.out / 'received.json').write_text(json.dumps(fixture.received))
        (args.out / 'proxied.json').write_text(json.dumps(fixture.proxied))
        server.shutdown()
        server.server_close()
        fixture.close()


if __name__ == '__main__':
    main()
