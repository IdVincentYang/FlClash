package main

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/ca"
	C "github.com/metacubex/mihomo/constant"
	MDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/transport/socks5"
	"github.com/metacubex/mihomo/tunnel"
	D "github.com/miekg/dns"
)

type managedDNS struct {
	address string
	mu      sync.Mutex
	queries []string
}

func (d *managedDNS) count() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.queries)
}

func managedDNSServer(t *testing.T, network string, certificate *tls.Certificate) *managedDNS {
	t.Helper()
	d := &managedDNS{}
	server := &D.Server{Net: network, Handler: D.HandlerFunc(func(w D.ResponseWriter, request *D.Msg) {
		response := new(D.Msg)
		response.SetReply(request)
		for _, question := range request.Question {
			d.mu.Lock()
			d.queries = append(d.queries, fmt.Sprintf("%s/%d", question.Name, question.Qtype))
			d.mu.Unlock()
			if question.Qtype == D.TypeA {
				response.Answer = append(response.Answer, &D.A{Hdr: D.RR_Header{Name: question.Name, Rrtype: D.TypeA, Class: D.ClassINET, Ttl: 0}, A: net.ParseIP("127.0.0.1")})
			}
		}
		_ = w.WriteMsg(response)
	})}
	if network == "udp" {
		packet, err := net.ListenPacket("udp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		server.PacketConn, d.address = packet, packet.LocalAddr().String()
	} else {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		d.address = listener.Addr().String()
		if certificate != nil {
			listener = tls.NewListener(listener, &tls.Config{Certificates: []tls.Certificate{*certificate}, MinVersion: tls.VersionTLS12})
		}
		server.Listener = listener
	}
	ready := make(chan struct{})
	server.NotifyStartedFunc = func() { close(ready) }
	go func() { _ = server.ActivateAndServe() }()
	select {
	case <-ready:
	case <-time.After(time.Second):
		t.Fatal("DNS fixture did not start")
	}
	t.Cleanup(func() { _ = server.Shutdown() })
	return d
}

type managedProxy struct {
	address  string
	mu       sync.Mutex
	targets  []string
	fail     atomic.Bool
	controls sync.Map
	allowed  map[string]bool
	auth     auth.Authenticator
}

func (p *managedProxy) count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.targets)
}

func managedSOCKS(t *testing.T, label string, allowed map[string]bool) *managedProxy {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := &managedProxy{address: listener.Addr().String(), allowed: make(map[string]bool)}
	relay, err := net.ListenPacket("udp", listener.Addr().String())
	if err != nil {
		_ = listener.Close()
		t.Fatal(err)
	}
	for address := range allowed {
		p.allowed[address] = true
	}
	t.Cleanup(func() {
		_ = listener.Close()
		_ = relay.Close()
		p.controls.Range(func(key, _ any) bool { _ = key.(net.Conn).Close(); return true })
	})
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			p.controls.Store(conn, true)
			go func() {
				defer conn.Close()
				defer p.controls.Delete(conn)
				_ = conn.SetDeadline(time.Now().Add(6 * time.Second))
				p.mu.Lock()
				authenticator := p.auth
				p.mu.Unlock()
				addr, command, _, err := socks5.ServerHandshake(conn, authenticator)
				if err != nil {
					return
				}
				if command == socks5.CmdUDPAssociate {
					_, _ = io.Copy(io.Discard, conn)
					return
				}
				p.mu.Lock()
				p.targets = append(p.targets, addr.String())
				p.mu.Unlock()
				if p.fail.Load() {
					return
				}
				host, _, err := net.SplitHostPort(addr.String())
				if err == nil && (strings.HasSuffix(host, ".test") || host == "192.0.2.123") {
					if _, err := http.ReadRequest(bufio.NewReader(conn)); err == nil {
						_, _ = fmt.Fprintf(conn, "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", len(label), label)
					}
					return
				}
				p.mu.Lock()
				permitted := p.allowed[addr.String()]
				p.mu.Unlock()
				if !permitted {
					return
				}
				upstream, err := net.DialTimeout("tcp", addr.String(), time.Second)
				if err != nil {
					return
				}
				defer upstream.Close()
				done := make(chan struct{})
				go func() { _, _ = io.Copy(upstream, conn); close(done) }()
				_, _ = io.Copy(conn, upstream)
				_ = conn.Close()
				<-done
			}()
		}
	}()
	go func() {
		buf := make([]byte, 4096)
		for {
			n, client, err := relay.ReadFrom(buf)
			if err != nil {
				return
			}
			addr, payload, err := socks5.DecodeUDPPacket(buf[:n])
			if err != nil {
				continue
			}
			p.mu.Lock()
			p.targets = append(p.targets, "udp:"+addr.String())
			permitted := p.allowed[addr.String()]
			p.mu.Unlock()
			if !permitted || p.fail.Load() {
				continue
			}
			upstream, err := net.DialTimeout("udp", addr.String(), time.Second)
			if err != nil {
				continue
			}
			_ = upstream.SetDeadline(time.Now().Add(time.Second))
			_, _ = upstream.Write(payload)
			response := make([]byte, 4096)
			size, err := upstream.Read(response)
			_ = upstream.Close()
			if err != nil {
				continue
			}
			packet, err := socks5.EncodeUDPPacket(addr, response[:size])
			if err == nil {
				_, _ = relay.WriteTo(packet, client)
			}
		}
	}()
	return p
}

type managedFixture struct {
	policy       map[string]any
	servers      []*managedDNS
	proxies      []*managedProxy
	target       *httptest.Server
	direct       atomic.Int32
	mixedPort    int
	dnsPort      int
	compilerPath string
}

func managedObject(value any) map[string]any { return value.(map[string]any) }

func managedPort(address string) int {
	_, port, _ := net.SplitHostPort(address)
	var result int
	_, _ = fmt.Sscan(port, &result)
	return result
}

func newManagedFixture(t *testing.T) *managedFixture {
	t.Helper()
	compiler := os.Getenv("FLCLASH_MANAGED_PROFILE_COMPILER")
	if compiler == "" {
		t.Skip("set FLCLASH_MANAGED_PROFILE_COMPILER to the real compiled Dart CLI")
	}
	configTestHome(t)
	t.Cleanup(settleMessageBatcher)
	t.Cleanup(func() { MDNS.ReCreateServer("", nil, nil) })
	data, err := os.ReadFile("../test/fixtures/managed_profile/policy.json")
	if err != nil {
		t.Fatal(err)
	}
	f := &managedFixture{compilerPath: compiler, mixedPort: configTestPort(t), dnsPort: configTestPort(t)}
	if err := json.Unmarshal(data, &f.policy); err != nil {
		t.Fatal(err)
	}
	allowed := make(map[string]bool)
	for index := 0; index < 4; index++ {
		server := managedDNSServer(t, "tcp", nil)
		f.servers = append(f.servers, server)
		allowed[server.address] = true
	}
	f.proxies = []*managedProxy{managedSOCKS(t, "A", allowed), managedSOCKS(t, "B", allowed)}
	f.target = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.direct.Add(1)
		_, _ = io.WriteString(w, "DIRECT")
	}))
	t.Cleanup(f.target.Close)
	services := managedObject(f.policy["dnsServices"])
	for index, name := range []string{"dnsA", "dnsB", "localDns"} {
		managedObject(services[name])["port"] = managedPort(f.servers[index].address)
	}
	managedObject(f.policy["bootstrapDns"])["port"] = managedPort(f.servers[3].address)
	for index, name := range []string{"nodeA", "nodeB"} {
		managedObject(managedObject(f.policy["proxies"])[name])["port"] = managedPort(f.proxies[index].address)
	}
	f.policy["listeners"] = map[string]any{"mixedPort": f.mixedPort, "dnsPort": f.dnsPort}
	return f
}

func managedArtifactDirectory(t *testing.T) string {
	t.Helper()
	root := os.Getenv("FLCLASH_MANAGED_PROFILE_EVIDENCE")
	if root == "" {
		return t.TempDir()
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	directory, err := os.MkdirTemp(root, strings.ReplaceAll(t.Name(), "/", "_")+"-")
	if err != nil {
		t.Fatal(err)
	}
	return directory
}

func (f *managedFixture) compile(t *testing.T) (string, error, string) {
	t.Helper()
	directory := managedArtifactDirectory(t)
	input, output := filepath.Join(directory, "policy.json"), filepath.Join(directory, "managed.yaml")
	data, err := json.MarshalIndent(f.policy, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(input, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(output, []byte("previous-output"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	result, err := exec.CommandContext(ctx, f.compilerPath, "--input", input, "--output", output).CombinedOutput()
	return output, err, string(result)
}

func (f *managedFixture) apply(t *testing.T) {
	t.Helper()
	output, err, message := f.compile(t)
	if err != nil {
		t.Fatalf("real policy compiler: %v: %s", err, message)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	applyTestInput(t, writeTestInput(t, string(data)))
}

func (f *managedFixture) query(name string) (*D.Msg, error) {
	request := new(D.Msg)
	request.SetQuestion(D.Fqdn(name), D.TypeA)
	response, _, err := (&D.Client{Net: "tcp", Timeout: 2 * time.Second}).Exchange(request, fmt.Sprintf("127.0.0.1:%d", f.dnsPort))
	return response, err
}

func (f *managedFixture) get(host string) (string, error) {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", f.mixedPort), time.Second)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
	destination := net.JoinHostPort(host, fmt.Sprint(managedPort(f.target.Listener.Addr().String())))
	if _, err := socks5.ClientHandshake(conn, socks5.ParseAddr(destination), socks5.CmdConnect, nil); err != nil {
		return "", err
	}
	return managedHTTP(conn, destination)
}

func managedHTTP(conn net.Conn, destination string) (string, error) {
	if _, err := fmt.Fprintf(conn, "GET / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", destination); err != nil {
		return "", err
	}
	response, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return string(body), err
}

func TestManagedProfileOrderedConsumers(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		t.Run(fmt.Sprintf("reverse_%v", reverse), func(t *testing.T) {
			f := newManagedFixture(t)
			rules := f.policy["domainRules"].([]any)
			if reverse {
				rules[0], rules[1] = rules[1], rules[0]
			}
			f.apply(t)
			label, index := "A", 0
			if reverse {
				label, index = "B", 1
			}
			if body, err := f.get("exact.example.test"); err != nil || body != label {
				t.Fatal("business first match", body, err)
			}
			if response, err := f.query("exact.example.test"); err != nil || response.Rcode != D.RcodeSuccess || len(response.Answer) != 1 {
				t.Fatal("real DNS first match", response, err)
			}
			for i, server := range f.servers {
				want := 0
				if i == index {
					want = 1
				}
				if server.count() != want {
					t.Fatalf("DNS receiver %d got %d want %d", i, server.count(), want)
				}
			}
			if f.proxies[index].count() != 2 || f.proxies[1-index].count() != 0 || f.direct.Load() != 0 {
				t.Fatal("unexpected business/DNS egress", f.proxies[0].count(), f.proxies[1].count(), f.direct.Load())
			}
			t.Logf("C1 business=%s DNS=%d via=%s otherDNS=0 bootstrap=0 direct=0", label, index, label)
		})
	}
}

func TestManagedProfileDirectDefaultsAndKnownIP(t *testing.T) {
	f := newManagedFixture(t)
	f.apply(t)
	if body, err := f.get("positive.lan.test"); err != nil || body != "DIRECT" {
		t.Fatal("direct domain", body, err)
	}
	if f.servers[2].count() == 0 || f.servers[0].count() != 0 || f.servers[1].count() != 0 || f.servers[3].count() != 0 {
		t.Fatal("DIRECT used the wrong DNS receiver")
	}
	if body, err := f.get("unmatched.other.test"); err != nil || body != "B" {
		t.Fatal("explicit domain default", body, err)
	}
	if response, err := f.query("default-query.other.test"); err != nil || response.Rcode != D.RcodeSuccess {
		t.Fatal("DNS domain default", response, err)
	}
	before := 0
	for _, server := range f.servers {
		before += server.count()
	}
	if body, err := f.get("127.0.0.1"); err != nil || body != "DIRECT" {
		t.Fatal("known IPv4", body, err)
	}
	after := 0
	for _, server := range f.servers {
		after += server.count()
	}
	if after != before || f.servers[3].count() != 0 {
		t.Fatal("known IP introduced a DNS query")
	}
	t.Logf("C2/C9 DIRECT-domain=%d default-DNS=%d known-IP-new-DNS=0 bootstrap=0", f.servers[2].count(), f.servers[1].count())
}

func TestManagedProfileIPv6Consumer(t *testing.T) {
	f := newManagedFixture(t)
	listener, err := net.Listen("tcp", "[::1]:0")
	if err != nil {
		t.Fatal("IPv6 loopback is required for this consumer case", err)
	}
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = io.WriteString(w, "IPv6") }))
	_ = server.Listener.Close()
	server.Listener = listener
	server.Start()
	t.Cleanup(server.Close)
	f.target = server
	f.apply(t)
	if body, err := f.get("::1"); err != nil || body != "IPv6" {
		t.Fatal("known IPv6", body, err)
	}
	for _, dns := range f.servers {
		if dns.count() != 0 {
			t.Fatal("IPv6 introduced target DNS")
		}
	}
	t.Log("C2/C9 IPv6 CIDR consumer succeeded; target DNS=0")
}

func TestManagedProfileRejectionAndEmpty(t *testing.T) {
	for _, empty := range []bool{false, true} {
		t.Run(fmt.Sprintf("empty_%v", empty), func(t *testing.T) {
			f := newManagedFixture(t)
			name := "blocked.denied.test"
			if empty {
				f.policy["domainRules"], f.policy["ipRules"] = []any{}, []any{}
				f.policy["domainDefault"] = map[string]any{"target": map[string]any{"kind": "reject"}}
				f.policy["groups"], f.policy["proxies"] = map[string]any{}, map[string]any{}
				name = "unmatched.other.test"
			} else {
				f.policy["ipRules"] = append([]any{map[string]any{"id": "denyIP", "cidr": "127.0.0.1/32", "target": map[string]any{"kind": "reject"}}}, f.policy["ipRules"].([]any)...)
			}
			f.apply(t)
			if response, err := f.query(name); err != nil || response.Rcode != D.RcodeRefused {
				t.Fatal("local rejection", response, err)
			}
			if body, err := f.get(name); err == nil {
				t.Fatal("rejected business succeeded", body)
			}
			if body, err := f.get("127.0.0.1"); err == nil {
				t.Fatal("address rejection succeeded", body)
			}
			for _, dns := range f.servers {
				if dns.count() != 0 {
					t.Fatal("rejection queried a network DNS service")
				}
			}
			if f.direct.Load() != 0 || f.proxies[0].count() != 0 || f.proxies[1].count() != 0 {
				t.Fatal("rejected business escaped")
			}
			t.Log("C3 business rejected, DNS=REFUSED, network DNS/proxy/direct receipts=0")
		})
	}
}

func TestManagedProfileUDPBranchIsolation(t *testing.T) {
	f := newManagedFixture(t)
	target, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = target.Close() })
	var received atomic.Int32
	go func() {
		buf := make([]byte, 1024)
		for {
			n, addr, err := target.ReadFrom(buf)
			if err != nil {
				return
			}
			received.Add(1)
			_, _ = target.WriteTo(buf[:n], addr)
		}
	}()
	f.apply(t)
	send := func(host string) error {
		control, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", f.mixedPort))
		if err != nil {
			return err
		}
		defer control.Close()
		_ = control.SetDeadline(time.Now().Add(time.Second))
		if _, err := socks5.ClientHandshake(control, socks5.ParseAddr("0.0.0.0:0"), socks5.CmdUDPAssociate, nil); err != nil {
			return err
		}
		packet, err := net.Dial("udp", fmt.Sprintf("127.0.0.1:%d", f.mixedPort))
		if err != nil {
			return err
		}
		defer packet.Close()
		_ = packet.SetDeadline(time.Now().Add(500 * time.Millisecond))
		data, err := socks5.EncodeUDPPacket(socks5.ParseAddr(net.JoinHostPort(host, fmt.Sprint(managedPort(target.LocalAddr().String())))), []byte("synthetic"))
		if err != nil {
			return err
		}
		if _, err := packet.Write(data); err != nil {
			return err
		}
		buf := make([]byte, 1024)
		_, err = packet.Read(buf)
		return err
	}
	if err := send("udp.example.test"); err == nil || received.Load() != 0 {
		t.Fatal("TCP-only domain fell into IP DIRECT", err, received.Load())
	}
	if err := send("127.0.0.1"); err != nil || received.Load() != 1 {
		t.Fatal("legal IP UDP failed", err, received.Load())
	}
	t.Log("C5 domain UDP refused with direct receipts=0; explicit IP UDP receipt=1")
}

func TestManagedProfileFailureNoAlternateReceiver(t *testing.T) {
	f := newManagedFixture(t)
	f.proxies[0].fail.Store(true)
	f.apply(t)
	response, err := f.query("failed.example.test")
	if err == nil && response.Rcode == D.RcodeSuccess {
		t.Fatal("unavailable DNS path succeeded")
	}
	if f.proxies[0].count() == 0 || f.proxies[1].count() != 0 || f.direct.Load() != 0 {
		t.Fatal("missing failed attempt or alternate egress", f.proxies[0].count(), f.proxies[1].count(), f.direct.Load())
	}
	for _, dns := range f.servers {
		if dns.count() != 0 {
			t.Fatal("failed proxy caused direct/alternate DNS receipt")
		}
	}
	t.Logf("C6 unavailable A: attempts=%d, alternate proxy/direct/DNS receipts=0 within query deadline", f.proxies[0].count())
}

func TestManagedProfileDirectResolverDefault(t *testing.T) {
	for _, reject := range []bool{false, true} {
		t.Run(fmt.Sprintf("reject_%v", reject), func(t *testing.T) {
			f := newManagedFixture(t)
			if reject {
				f.policy["domainDefault"] = map[string]any{"target": map[string]any{"kind": "reject"}}
			}
			f.apply(t)
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			conn, err := tunnel.Proxies()["DIRECT"].DialContext(ctx, &C.Metadata{NetWork: C.TCP, Host: "direct-resolver.other.test", DstPort: uint16(managedPort(f.target.Listener.Addr().String()))})
			if reject {
				if err == nil {
					_ = conn.Close()
					t.Fatal("DirectResolver ignored rejected domain default")
				}
			} else {
				if err != nil {
					t.Fatal("actual DIRECT adapter resolution", err)
				}
				defer conn.Close()
				_ = conn.SetDeadline(time.Now().Add(time.Second))
				if body, err := managedHTTP(conn, f.target.Listener.Addr().String()); err != nil || body != "DIRECT" {
					t.Fatal("actual DIRECT consumer", body, err)
				}
				if f.servers[1].count() == 0 || f.proxies[1].count() == 0 {
					t.Fatal("DirectResolver missed projected default")
				}
			}
			if f.servers[0].count() != 0 || f.servers[2].count() != 0 || f.servers[3].count() != 0 {
				t.Fatal("DirectResolver used its bootstrap/alternate default")
			}
			t.Logf("C7 actual DirectResolver: reject=%v, B-DNS=%d bootstrap=0", reject, f.servers[1].count())
		})
	}
}

func managedCertificate(t *testing.T, correctIP bool) (tls.Certificate, string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ip := "127.0.0.1"
	if !correctIP {
		ip = "127.0.0.2"
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "synthetic managed DNS"}, IPAddresses: []net.IP{net.ParseIP(ip)}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, IsCA: true, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}, string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
}

func TestManagedProfileDoTIdentity(t *testing.T) {
	for _, scenario := range []string{"trusted", "wrong-IP", "untrusted"} {
		t.Run(scenario, func(t *testing.T) {
			f := newManagedFixture(t)
			certificate, pemText := managedCertificate(t, scenario != "wrong-IP")
			dot := managedDNSServer(t, "tcp", &certificate)
			for _, proxy := range f.proxies {
				proxy.mu.Lock()
				proxy.allowed[dot.address] = true
				proxy.mu.Unlock()
			}
			service := managedObject(managedObject(f.policy["dnsServices"])["dnsA"])
			service["protocol"], service["port"] = "tls", managedPort(dot.address)
			f.apply(t)
			if scenario != "untrusted" {
				if err := ca.AddCertificate(pemText); err != nil {
					t.Fatal(err)
				}
			}
			t.Cleanup(ca.ResetCertificate)
			response, err := f.query("tls.example.test")
			if scenario == "trusted" {
				if err != nil || response.Rcode != D.RcodeSuccess || dot.count() != 1 {
					t.Fatal("trusted DoT failed", response, err, dot.count())
				}
			} else if (err == nil && response.Rcode == D.RcodeSuccess) || dot.count() != 0 {
				t.Fatal("invalid DoT identity succeeded", response, err, dot.count())
			}
			if f.proxies[0].count() == 0 || f.proxies[1].count() != 0 {
				t.Fatal("wrong DoT proxy egress")
			}
			for _, dns := range f.servers {
				if dns.count() != 0 {
					t.Fatal("DoT failure downgraded to a plaintext/alternate server")
				}
			}
			t.Logf("C8 %s: DoT queries=%d A-attempts=%d plaintext/alternate=0", scenario, dot.count(), f.proxies[0].count())
		})
	}
}

func TestManagedProfileCLIRejectionsKeepOutput(t *testing.T) {
	for _, scenario := range []string{"DoH", "bootstrap-DoH", "missing-group", "empty-group", "UDP-capability", "long-auth", "control-auth"} {
		t.Run(scenario, func(t *testing.T) {
			f := newManagedFixture(t)
			switch scenario {
			case "DoH":
				managedObject(managedObject(f.policy["dnsServices"])["dnsA"])["protocol"] = "https"
			case "bootstrap-DoH":
				managedObject(f.policy["bootstrapDns"])["protocol"] = "https"
			case "missing-group":
				managedObject(managedObject(f.policy["domainDefault"])["target"])["group"] = "missing"
			case "empty-group":
				managedObject(f.policy["groups"])["a"] = []any{}
			case "UDP-capability":
				managedObject(managedObject(f.policy["dnsServices"])["dnsA"])["protocol"] = "udp"
			case "long-auth", "control-auth":
				node := managedObject(managedObject(f.policy["proxies"])["nodeA"])
				node["username"] = "synthetic-secret"
				if scenario == "long-auth" {
					node["password"] = strings.Repeat("x", 256)
				} else {
					node["password"] = "synthetic-secret\nprivate"
				}
			}
			output, err, message := f.compile(t)
			if err == nil || strings.Contains(message, "synthetic-secret") {
				t.Fatal("invalid input succeeded or diagnostic leaked authentication")
			}
			data, readErr := os.ReadFile(output)
			if readErr != nil || string(data) != "previous-output" {
				t.Fatal("rejection replaced previous output", readErr)
			}
			t.Logf("C4/C6/C10 %s: nonzero, old output unchanged, diagnostic has no credential", scenario)
		})
	}
}

func TestManagedProfileAuthenticationConsumer(t *testing.T) {
	f := newManagedFixture(t)
	password := strings.Repeat("雪", 85)
	node := managedObject(managedObject(f.policy["proxies"])["nodeA"])
	node["username"], node["password"] = "synthetic", password
	f.proxies[0].mu.Lock()
	f.proxies[0].auth = auth.NewAuthenticator([]auth.AuthUser{{User: "synthetic", Pass: password}})
	f.proxies[0].mu.Unlock()
	f.apply(t)
	if body, err := f.get("authentication.example.test"); err != nil || body != "A" {
		t.Fatal("actual SOCKS5 authentication did not preserve 255 UTF-8 bytes", err)
	}
	if response, err := f.query("authentication.example.test"); err != nil || response.Rcode != D.RcodeSuccess {
		t.Fatal("authenticated DNS path failed", err)
	}
	t.Log("C10 actual SOCKS5 accepted 255 UTF-8 credential bytes for business and DNS")
}

func TestManagedProfileLocalUDPDNS(t *testing.T) {
	for _, proxied := range []bool{false, true} {
		t.Run(fmt.Sprintf("proxied_%v", proxied), func(t *testing.T) {
			f := newManagedFixture(t)
			server := managedDNSServer(t, "udp", nil)
			name, serviceID := "udp.lan.test", "localDns"
			if proxied {
				name, serviceID = "udp.example.test", "dnsA"
				managedObject(managedObject(f.policy["proxies"])["nodeA"])["udp"] = true
				f.proxies[0].mu.Lock()
				f.proxies[0].allowed[server.address] = true
				f.proxies[0].mu.Unlock()
			}
			service := managedObject(managedObject(f.policy["dnsServices"])[serviceID])
			service["protocol"], service["port"] = "udp", managedPort(server.address)
			f.apply(t)
			if response, err := f.query(name); err != nil || response.Rcode != D.RcodeSuccess || server.count() != 1 {
				t.Fatal("local UDP DNS consumer", response, err, server.count())
			}
			want := 0
			if proxied {
				want = 1
			}
			if f.proxies[0].count() != want || f.proxies[1].count() != 0 {
				t.Fatal("UDP DNS wrong egress", f.proxies[0].count(), f.proxies[1].count())
			}
			for _, other := range f.servers {
				if other.count() != 0 {
					t.Fatal("UDP DNS also contacted another service")
				}
			}
			t.Logf("C2/C6 local UDP DNS: proxied=%v queries=1 proxy-A=%d otherDNS=0", proxied, want)
		})
	}
}

func TestManagedProfileIPDefaultProxy(t *testing.T) {
	f := newManagedFixture(t)
	f.policy["ipDefault"] = map[string]any{"kind": "proxy", "group": "b"}
	f.apply(t)
	if body, err := f.get("192.0.2.123"); err != nil || body != "B" {
		t.Fatal("explicit IP proxy default", body, err)
	}
	if f.proxies[1].count() != 1 || f.proxies[0].count() != 0 || f.direct.Load() != 0 {
		t.Fatal("unexpected IP default egress")
	}
	for _, server := range f.servers {
		if server.count() != 0 {
			t.Fatal("IP default queried a target domain")
		}
	}
	t.Log("C2/C9 TEST-NET literal consumed by local B proxy; no external dial or target DNS")
}

func TestManagedProfileCLIWriteFailure(t *testing.T) {
	f := newManagedFixture(t)
	output, err, _ := f.compile(t)
	if err != nil {
		t.Fatal("valid compiler precondition", err)
	}
	if err := os.WriteFile(output, []byte("previous-output"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	input := filepath.Join(filepath.Dir(output), "policy.json")
	command := exec.CommandContext(ctx, "/bin/sh", "-c", "ulimit -f 1; exec \"$1\" --input \"$2\" --output \"$3\"", "managed-write-test", f.compilerPath, input, output)
	if err := command.Run(); err == nil {
		t.Fatal("child file-size limit did not force a write failure")
	}
	data, err := os.ReadFile(output)
	if err != nil || string(data) != "previous-output" {
		t.Fatal("failed write replaced previous output", err)
	}
	if err := filepath.Walk(filepath.Dir(output), func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && info.Mode().Perm() != 0600 {
			return fmt.Errorf("non-private output file")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	t.Log("C10 child-only file-size failure: previous output intact; any partial files private")
}
