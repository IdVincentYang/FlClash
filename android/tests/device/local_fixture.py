"""Local AVD-only HTTP/SOCKS5/TCP-DNS fixture; never forwards off the host."""
import argparse
import http.server
import ipaddress
import json
import select
import signal
import socket
import socketserver
import struct
import threading

lock = threading.Lock()
state = {'proxyConnections': 0, 'proxyTarget': 0, 'directTarget': 0,
         'dnsQueries': 0, 'proxyEnabled': True}
servers = []
parser = argparse.ArgumentParser()
for name in ('http', 'socks', 'dns', 'proxy-target', 'direct-target'):
    parser.add_argument('--' + name + '-port', type=int, default=0)
ports = parser.parse_args()
socketserver.ThreadingTCPServer.allow_reuse_address = True


def exact(stream, size):
    data = b''
    while len(data) < size:
        part = stream.recv(size - len(data))
        if not part:
            raise OSError('closed')
        data += part
    return data


def start(server):
    servers.append(server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server.server_address[1]


class Target(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        key = self.server.label
        with lock:
            state[key] += 1
        body = key.encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


proxy_target = http.server.ThreadingHTTPServer(('127.0.0.1', ports.proxy_target_port), Target)
proxy_target.label = 'proxyTarget'
proxy_port = start(proxy_target)
direct_target = http.server.ThreadingHTTPServer(('127.0.0.1', ports.direct_target_port), Target)
direct_target.label = 'directTarget'
direct_port = start(direct_target)


class Socks(socketserver.BaseRequestHandler):
    def handle(self):
        stream = self.request
        stream.settimeout(5)
        try:
            version, methods = exact(stream, 2)
            if version != 5:
                return
            exact(stream, methods)
            stream.sendall(b'\x05\x00')
            version, command, _, family = exact(stream, 4)
            if family == 1:
                host = str(ipaddress.IPv4Address(exact(stream, 4)))
            elif family == 3:
                host = exact(stream, exact(stream, 1)[0]).decode('ascii')
            else:
                return
            port = struct.unpack('!H', exact(stream, 2))[0]
            with lock:
                state['proxyConnections'] += 1
                enabled = state['proxyEnabled']
            if version != 5 or command != 1 or not enabled or host not in {'10.0.2.2', 'avd.service.test'} or port not in {proxy_port, direct_port}:
                stream.sendall(b'\x05\x05\x00\x01' + b'\x00' * 6)
                return
            with socket.create_connection(('127.0.0.1', port), timeout=3) as target:
                stream.sendall(b'\x05\x00\x00\x01' + b'\x00' * 6)
                while True:
                    ready, _, _ = select.select([stream, target], [], [], 5)
                    if not ready:
                        return
                    for current in ready:
                        data = current.recv(4096)
                        if not data:
                            return
                        (target if current is stream else stream).sendall(data)
        except OSError:
            return


socks_port = start(socketserver.ThreadingTCPServer(('127.0.0.1', ports.socks_port), Socks))


class Dns(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(3)
        try:
            query = exact(self.request, struct.unpack('!H', exact(self.request, 2))[0])
            offset, labels = 12, []
            while query[offset]:
                length = query[offset]
                labels.append(query[offset + 1:offset + 1 + length].decode('ascii'))
                offset += length + 1
            end = offset + 5
            name = '.'.join(labels)
            qtype = struct.unpack('!H', query[offset + 1:offset + 3])[0]
            allowed = name.endswith('.service.test')
            with lock:
                state['dnsQueries'] += 1
            answer = b''
            if allowed and qtype == 1:
                answer = b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 0, 4) + socket.inet_aton('10.0.2.2')
            flags = 0x8180 if allowed else 0x8185
            response = query[:2] + struct.pack('!HHHHH', flags, 1, bool(answer), 0, 0) + query[12:end] + answer
            self.request.sendall(struct.pack('!H', len(response)) + response)
        except (OSError, IndexError, UnicodeError):
            return


dns_port = start(socketserver.ThreadingTCPServer(('127.0.0.1', ports.dns_port), Dns))


class Control(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/profile':
            body = (f'''mixed-port: 7890
mode: rule
allow-lan: false
log-level: warning
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: redir-host
  nameserver: [tcp://10.0.2.2:{dns_port}]
  default-nameserver: [tcp://10.0.2.2:{dns_port}]
proxies:
  - {{name: LocalNode, type: socks5, server: 10.0.2.2, port: {socks_port}, udp: false}}
proxy-groups:
  - {{name: LocalProxy, type: select, proxies: [LocalNode]}}
rules:
  - DST-PORT,{proxy_port},LocalProxy
  - DST-PORT,{direct_port},DIRECT
  - DST-PORT,{self.server.server_address[1]},DIRECT
  - MATCH,REJECT
''').encode()
        elif self.path in {'/status', '/proxy/on', '/proxy/off'}:
            with lock:
                if self.path != '/status':
                    state['proxyEnabled'] = self.path == '/proxy/on'
                body = json.dumps(state).encode()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


http_port = start(http.server.ThreadingHTTPServer(('127.0.0.1', ports.http_port), Control))
print(json.dumps({'httpPort': http_port, 'socksPort': socks_port,
                  'dnsPort': dns_port, 'proxyTargetPort': proxy_port,
                  'directTargetPort': direct_port}), flush=True)
stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stop.set())
try:
    stop.wait()
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
