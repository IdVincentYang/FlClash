"""Loopback-only echo targets and SOCKS5; proxy forwarding is limited to these targets."""
import json
import select
import socket
import socketserver
import struct
import threading


def exact(stream, count):
    result = b''
    while len(result) < count:
        data = stream.recv(count - len(result))
        if not data:
            raise EOFError('Controlled peer closed')
        result += data
    return result


def destination(stream):
    kind = exact(stream, 1)[0]
    if kind != 1:
        raise ValueError('Only numeric IPv4 fixture destinations are allowed')
    return socket.inet_ntoa(exact(stream, 4)), struct.unpack('!H', exact(stream, 2))[0]


class Fixture:
    def __init__(self):
        self.lock = threading.Lock()
        self.received = []
        self.proxied = []
        self.servers = []
        self.connections = set()
        fixture = self

        class TCP(socketserver.StreamRequestHandler):
            def handle(self):
                self.request.settimeout(120)
                with fixture.lock:
                    fixture.connections.add(self.request)
                try:
                    while True:
                        data = self.rfile.readline(4096)
                        if not data:
                            return
                        value = fixture.record(fixture.received, data)
                        self.wfile.write(data)
                        self.wfile.flush()
                        remaining = int(value.get('bulkBytes', 0))
                        if remaining < 0 or remaining > 1048576:
                            raise ValueError('Bulk budget exceeded')
                        while remaining:
                            chunk = self.rfile.read(min(32768, remaining))
                            if not chunk:
                                return
                            self.wfile.write(chunk)
                            self.wfile.flush()
                            remaining -= len(chunk)
                except (OSError, ValueError):
                    return
                finally:
                    with fixture.lock:
                        fixture.connections.discard(self.request)

        class UDP(socketserver.BaseRequestHandler):
            def handle(self):
                data, stream = self.request
                fixture.record(fixture.received, data)
                stream.sendto(data, self.client_address)

        self.direct = self.echo(TCP, UDP)
        self.proxy_target = self.echo(TCP, UDP)

        class Relay(socketserver.BaseRequestHandler):
            def handle(self):
                data, stream = self.request
                if data[:4] != b'\x00\x00\x00\x01' or len(data) > 4096:
                    return
                host, port = socket.inet_ntoa(data[4:8]), struct.unpack('!H', data[8:10])[0]
                fixture.check_target(host, port)
                fixture.record(fixture.proxied, data[10:])
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as target:
                    target.settimeout(3)
                    target.sendto(data[10:], ('127.0.0.1', port))
                    response = target.recv(4096)
                stream.sendto(data[:10] + response, self.client_address)

        self.relay = self.start(socketserver.ThreadingUDPServer(('127.0.0.1', 0), Relay))

        class Socks(socketserver.BaseRequestHandler):
            def handle(self):
                stream = self.request
                stream.settimeout(120)
                with fixture.lock:
                    fixture.connections.add(stream)
                try:
                    version, count = exact(stream, 2)
                    if version != 5 or 0 not in exact(stream, count):
                        return
                    stream.sendall(b'\x05\x00')
                    version, command, reserved = exact(stream, 3)
                    host, port = destination(stream)
                    if version != 5 or reserved != 0:
                        return
                    if command == 3:
                        stream.sendall(b'\x05\x00\x00\x01' + socket.inet_aton('10.0.2.2') + struct.pack('!H', fixture.relay))
                        while stream.recv(1024):
                            pass
                        return
                    if command != 1:
                        return
                    fixture.check_target(host, port)
                    with socket.create_connection(('127.0.0.1', port), timeout=3) as target:
                        stream.sendall(b'\x05\x00\x00\x01' + b'\x00' * 6)
                        first = bytearray()
                        while True:
                            ready, _, _ = select.select([stream, target], [], [], 120)
                            if not ready:
                                return
                            for current in ready:
                                data = current.recv(4096)
                                if not data:
                                    return
                                if current is stream and b'\n' not in first:
                                    first.extend(data)
                                    if b'\n' in first:
                                        fixture.record(fixture.proxied, first.split(b'\n')[0])
                                (target if current is stream else stream).sendall(data)
                except (OSError, EOFError, ValueError):
                    return
                finally:
                    with fixture.lock:
                        fixture.connections.discard(stream)

        self.socks = self.start(socketserver.ThreadingTCPServer(('127.0.0.1', 0), Socks))

    def start(self, server):
        server.daemon_threads = True
        self.servers.append(server)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server.server_address[1]

    def echo(self, tcp, udp):
        for _ in range(10):
            stream = socketserver.ThreadingTCPServer(('127.0.0.1', 0), tcp)
            try:
                packet = socketserver.ThreadingUDPServer(stream.server_address, udp)
            except OSError:
                stream.server_close()
                continue
            self.start(stream)
            self.start(packet)
            return stream.server_address[1]
        raise RuntimeError('Cannot reserve a shared TCP/UDP fixture port')

    def check_target(self, host, port):
        if host != '10.0.2.2' or port not in {self.direct, self.proxy_target}:
            raise ValueError('Non-fixture destination refused')

    def record(self, target, data):
        value = json.loads(data)
        with self.lock:
            target.append(value)
        return value

    def profile(self):
        return f'''mixed-port: 0
mode: rule
find-process-mode: off
log-level: warning
geo-auto-update: false
dns: {{enable: false}}
ntp: {{enable: false}}
proxies:
  - {{name: fixture.exit, type: socks5, server: 10.0.2.2, port: {self.socks}, udp: true}}
proxy-groups:
  - {{name: fixture.group, type: select, proxies: [fixture.exit]}}
rules:
  - DST-PORT,{self.direct},DIRECT
  - MATCH,fixture.group
'''

    def close(self):
        with self.lock:
            for stream in self.connections:
                try:
                    stream.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        for server in self.servers:
            server.shutdown()
            server.server_close()
