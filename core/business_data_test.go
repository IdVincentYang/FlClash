package main

import (
	"bufio"
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/dialer"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
)

type businessReceipt struct {
	Path          string `json:"path"`
	Host          string `json:"host"`
	Authorization string `json:"authorization"`
	Cookie        string `json:"cookie"`
	Body          string `json:"body"`
}

type businessTrace struct {
	sync.Mutex
	bytes.Buffer
}

func (b *businessTrace) Write(p []byte) (int, error) {
	b.Lock()
	defer b.Unlock()
	return b.Buffer.Write(p)
}

func (b *businessTrace) snapshot() []byte {
	b.Lock()
	defer b.Unlock()
	return bytes.Clone(b.Bytes())
}

type businessWireConn struct {
	net.Conn
	trace *businessTrace
}

func (c businessWireConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	_, _ = c.trace.Write(p[:n])
	return n, err
}

type businessWireListener struct {
	net.Listener
	trace *businessTrace
}

func (l businessWireListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return businessWireConn{c, l.trace}, nil
}

type businessCase struct {
	Name         string            `json:"name"`
	Receipt      businessReceipt   `json:"receipt"`
	Response     string            `json:"response"`
	Events       []json.RawMessage `json:"events"`
	Connections  json.RawMessage   `json:"connections"`
	Traffic      json.RawMessage   `json:"traffic"`
	TLSWireBytes int               `json:"tlsWireBytes"`
	ProxyTargets []string          `json:"proxyTargets"`
	Stopped      bool              `json:"stoppedBeforeUDPResponse,omitempty"`
}

func businessProxyTargets(t *testing.T, proxy *managedProxy, start int, destination string, wantProxy bool) []string {
	t.Helper()
	proxy.mu.Lock()
	targets := append([]string(nil), proxy.targets[start:]...)
	proxy.mu.Unlock()
	if wantProxy {
		if len(targets) != 1 || targets[0] != destination {
			t.Fatalf("independent proxy targets %v, want [%s]", targets, destination)
		}
	} else if len(targets) != 0 {
		t.Fatalf("DIRECT unexpectedly reached proxy: %v", targets)
	}
	return targets
}

func businessRPC(t *testing.T, method CoreMethod, arguments string) json.RawMessage {
	t.Helper()
	return json.RawMessage(captureSingleFrame(t, func() {
		handleMethodCall(&MethodCall{ID: "business-rpc", Method: method, Arguments: json.RawMessage(arguments)}, newMethodResponse("business-rpc", nil))
	}))
}

func businessUDP(t *testing.T, proxy *managedProxy, port int, name string, stop, wantProxy bool) businessCase {
	t.Helper()
	target, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	finished, receipt := make(chan struct{}), make(chan string, 1)
	release := make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	if !stop {
		unblock()
	}
	go func() {
		defer close(finished)
		buffer := make([]byte, 4096)
		n, source, err := target.ReadFrom(buffer)
		if err == nil {
			receipt <- string(buffer[:n])
			<-release
			_, _ = target.WriteTo([]byte("response-body-"+name), source)
		}
	}()
	defer func() { unblock(); _ = target.Close(); <-finished }()
	proxy.mu.Lock()
	proxy.allowed[target.LocalAddr().String()] = true
	proxy.mu.Unlock()
	control, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer control.Close()
	_ = control.SetDeadline(time.Now().Add(3 * time.Second))
	if _, err := socks5.ClientHandshake(control, socks5.ParseAddr("0.0.0.0:0"), socks5.CmdUDPAssociate, nil); err != nil {
		t.Fatal(err)
	}
	packet, err := net.DialTimeout("udp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer packet.Close()
	_ = packet.SetDeadline(time.Now().Add(3 * time.Second))
	observed := businessCase{Name: name}
	proxyStart := proxy.count()
	frames := captureFrames(t, func() {
		data, err := socks5.EncodeUDPPacket(socks5.ParseAddr(target.LocalAddr().String()), []byte("request-body-"+name))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := packet.Write(data); err != nil {
			t.Fatal(err)
		}
		select {
		case observed.Receipt.Body = <-receipt:
		case <-time.After(3 * time.Second):
			t.Fatal("missing independent UDP receipt")
		}
		if observed.Receipt.Body != "request-body-"+name {
			t.Fatal("UDP request differs")
		}
		settleMessageBatcher()
		observed.Connections = businessRPC(t, getConnectionsMethod, "null")
		observed.Traffic = businessRPC(t, getTotalTrafficMethod, "false")
		if stop {
			if !handleStopListener() {
				t.Fatal("UDP stop failed")
			}
			unblock()
			_ = packet.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
		}
		buffer := make([]byte, 4096)
		n, err := packet.Read(buffer)
		if stop {
			if n != 0 || err == nil {
				t.Fatal("held UDP response delivered after Stop", n, err)
			}
			observed.Stopped = true
			settleMessageBatcher()
			return
		}
		if err != nil {
			t.Fatal(err)
		}
		address, payload, err := socks5.DecodeUDPPacket(buffer[:n])
		if err != nil || address.String() != target.LocalAddr().String() || string(payload) != "response-body-"+name {
			t.Fatal("UDP response differs", err)
		}
		observed.Response = string(payload)
	})
	for _, frame := range frames {
		observed.Events = append(observed.Events, json.RawMessage(frame))
	}
	observed.ProxyTargets = businessProxyTargets(t, proxy, proxyStart, "udp:"+target.LocalAddr().String(), wantProxy)
	return observed
}

func businessFailures(t *testing.T, port int, proxy *managedProxy) map[string]any {
	t.Helper()
	var received atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer origin.Close()
	destination := origin.Listener.Addr().String()
	proxy.mu.Lock()
	proxy.allowed[destination] = true
	proxy.mu.Unlock()
	results := make(map[string]any)
	for _, name := range []string{"authentication", "dial", "truncated-sniff"} {
		yaml := businessYAML(port, proxy.address, name == "authentication", name == "truncated-sniff")
		if name == "authentication" {
			yaml = strings.Replace(yaml, "password: node-password", "password: wrong-node-password", 1)
		}
		applyTestInput(t, writeTestInput(t, yaml))
		target := destination
		if name == "dial" {
			target = fmt.Sprintf("127.0.0.1:%d", configTestPort(t))
		}
		c := businessConnection(t, port, target, "socks")
		var readErr error
		var status int
		frames := captureFrames(t, func() {
			request := "POST /failure HTTP/1.1\r\nHost: failure.test\r\nContent-Length: 12\r\n\r\nfailure-body"
			if name == "truncated-sniff" {
				request = "P"
			}
			_, _ = io.WriteString(c, request)
			if name == "truncated-sniff" {
				_ = c.(*net.TCPConn).CloseWrite()
			}
			if name == "truncated-sniff" {
				var response *http.Response
				response, readErr = http.ReadResponse(bufio.NewReader(c), nil)
				if readErr == nil {
					status = response.StatusCode
					response.Body.Close()
				}
			} else {
				_, readErr = c.Read(make([]byte, 1))
			}
			_ = c.Close()
			settleMessageBatcher()
		})
		if received.Load() != 0 || name != "truncated-sniff" && readErr == nil || name == "truncated-sniff" && (readErr != nil || status != http.StatusBadRequest) {
			t.Fatal("failed input reached origin", name, readErr, received.Load())
		}
		var events []json.RawMessage
		for _, frame := range frames {
			events = append(events, json.RawMessage(frame))
		}
		failure := ""
		if readErr != nil {
			failure = readErr.Error()
		}
		results[name] = map[string]any{"readError": failure, "httpStatus": status, "originBusinessReceipts": received.Load(), "events": events}
	}
	return results
}

func businessCancellation(t *testing.T, port int, proxy *managedProxy) map[string]any {
	t.Helper()
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	var received atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.ReadAll(r.Body)
		received.Add(1)
		close(entered)
		<-release
		_, _ = io.WriteString(w, "response-after-stop")
	}))
	defer func() { unblock(); origin.Close() }()
	applyTestInput(t, writeTestInput(t, businessYAML(port, proxy.address, false, false)))
	before := configStateSnapshot()
	c := businessConnection(t, port, origin.Listener.Addr().String(), "socks")
	defer c.Close()
	_, _ = io.WriteString(c, "POST /before-stop HTTP/1.1\r\nHost: cancel.test\r\nContent-Length: 11\r\n\r\nbefore-stop")
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("cancel fixture did not reach origin barrier")
	}
	frames := captureFrames(t, func() {
		if !handleStopListener() {
			t.Fatal("stop failed")
		}
		settleMessageBatcher()
	})
	unblock()
	n, err := c.Read(make([]byte, 4096))
	if n != 0 || err == nil {
		t.Fatal("stopped response delivered after held origin barrier", n, err)
	}
	blocked, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err == nil {
		_ = blocked.SetDeadline(time.Now().Add(time.Second))
		_, err = socks5.ClientHandshake(blocked, socks5.ParseAddr(origin.Listener.Addr().String()), socks5.CmdConnect, nil)
		_ = blocked.Close()
	}
	if err == nil || received.Load() != 1 {
		t.Fatal("new admission after stop", err, received.Load())
	}
	applyTestInput(t, writeTestInput(t, businessYAML(port, proxy.address, false, false)))
	after := configStateSnapshot()
	if after.Owner == before.Owner || !after.BusinessActive {
		t.Fatal("recovery did not obtain a new active owner")
	}
	recovery := businessTCP(t, proxy, port, "socks", "new-owner-recovery", false, false)
	var events []json.RawMessage
	for _, frame := range frames {
		events = append(events, json.RawMessage(frame))
	}
	return map[string]any{"originReceiptsBeforeStop": 1, "originReceiptsAfterNewAttempt": received.Load(), "heldResponseBytesDelivered": n, "newAdmissionError": err.Error(), "beforeOwner": before.Owner, "afterOwner": after.Owner, "events": events, "recovery": recovery}
}

func businessConnection(t *testing.T, port int, destination, inbound string) net.Conn {
	t.Helper()
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	_ = c.SetDeadline(time.Now().Add(4 * time.Second))
	if inbound == "socks" {
		_, err = socks5.ClientHandshake(c, socks5.ParseAddr(destination), socks5.CmdConnect, nil)
	} else if inbound == "connect" {
		_, err = fmt.Fprintf(c, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", destination, destination)
		if err == nil {
			var response *http.Response
			response, err = http.ReadResponse(bufio.NewReader(c), nil)
			if err == nil && response.StatusCode != http.StatusOK {
				err = fmt.Errorf("CONNECT status %d", response.StatusCode)
			}
		}
	}
	if err != nil {
		_ = c.Close()
		t.Fatal(err)
	}
	return c
}

func businessTCP(t *testing.T, proxy *managedProxy, port int, inbound, name string, encrypted, wantProxy bool) businessCase {
	t.Helper()
	entered := make(chan businessReceipt, 1)
	release := make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	defer unblock()
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		entered <- businessReceipt{r.URL.String(), r.Host, r.Header.Get("Authorization"), r.Header.Get("Cookie"), string(body)}
		<-release
		_, _ = io.WriteString(w, "response-body-"+name)
	}))
	wire := &businessTrace{}
	server.Listener = businessWireListener{server.Listener, wire}
	if encrypted {
		server.StartTLS()
	} else {
		server.Start()
	}
	defer func() { unblock(); server.Close() }()
	destination := server.Listener.Addr().String()
	proxy.mu.Lock()
	proxy.allowed[destination] = true
	proxy.mu.Unlock()
	proxyStart := proxy.count()
	c := businessConnection(t, port, destination, inbound)
	defer c.Close()
	if encrypted {
		roots := x509.NewCertPool()
		roots.AddCert(server.Certificate())
		c = tls.Client(c, &tls.Config{RootCAs: roots, ServerName: "example.com", MinVersion: tls.VersionTLS12})
		defer c.Close()
	}
	target := "/business-path-" + name
	if inbound == "http" {
		target = "http://" + destination + target
	}
	hostHeader := "visible-" + name + ".test"
	if inbound == "http" {
		hostHeader = destination
	}
	result := make(chan error, 1)
	var responseBody string
	var observed businessCase
	frames := captureFrames(t, func() {
		go func() {
			body := "request-body-" + name
			_, err := fmt.Fprintf(c, "POST %s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer business-auth-%s\r\nCookie: business-cookie=%s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", target, hostHeader, name, name, len(body), body)
			if err == nil {
				var response *http.Response
				response, err = http.ReadResponse(bufio.NewReader(c), nil)
				if err == nil {
					var data []byte
					data, err = io.ReadAll(response.Body)
					response.Body.Close()
					responseBody = string(data)
				}
			}
			result <- err
		}()
		var receipt businessReceipt
		select {
		case receipt = <-entered:
		case <-time.After(5 * time.Second):
			unblock()
			t.Fatal("origin did not receive business request")
		}
		if receipt.Body != "request-body-"+name || receipt.Authorization != "Bearer business-auth-"+name || receipt.Cookie != "business-cookie="+name || receipt.Path != "/business-path-"+name {
			unblock()
			t.Fatalf("origin receipt differs: %+v", receipt)
		}
		observed.Receipt = receipt
		settleMessageBatcher()
		observed.Connections = json.RawMessage(captureSingleFrame(t, func() {
			handleMethodCall(&MethodCall{ID: "business-connections", Method: getConnectionsMethod}, newMethodResponse("business-connections", nil))
		}))
		unblock()
		if err := <-result; err != nil {
			t.Fatal(err)
		}
		settleMessageBatcher()
	})
	observed.Name, observed.Response = name, responseBody
	observed.ProxyTargets = businessProxyTargets(t, proxy, proxyStart, destination, wantProxy)
	for _, frame := range frames {
		observed.Events = append(observed.Events, json.RawMessage(frame))
	}
	observed.Traffic = json.RawMessage(captureSingleFrame(t, func() {
		handleMethodCall(&MethodCall{ID: "business-traffic", Method: getTotalTrafficMethod, Arguments: json.RawMessage("false")}, newMethodResponse("business-traffic", nil))
	}))
	if responseBody != "response-body-"+name {
		t.Fatalf("response differs: %q", responseBody)
	}
	if encrypted {
		observed.TLSWireBytes = len(wire.snapshot())
		if observed.TLSWireBytes == 0 || bytes.Contains(wire.snapshot(), []byte("request-body-"+name)) || bytes.Contains(wire.snapshot(), []byte("business-auth-"+name)) {
			t.Fatal("TLS wire did not separate endpoint plaintext from ciphertext")
		}
	}
	return observed
}

func businessYAML(port int, proxyAddress string, useProxy, sniff bool) string {
	host, proxyPort, _ := net.SplitHostPort(proxyAddress)
	target := "DIRECT"
	if useProxy {
		target = "audit-proxy"
	}
	return fmt.Sprintf(`mixed-port: %d
allow-lan: false
mode: rule
find-process-mode: off
geo-auto-update: false
external-controller: ''
dns: {enable: false}
ntp: {enable: false}
profile: {store-selected: false, store-fake-ip: false}
sniffer:
  enable: %t
  parse-pure-ip: true
  sniff:
    HTTP: {ports: [1-65535], override-destination: false}
    TLS: {ports: [1-65535], override-destination: false}
proxies:
  - {name: audit-proxy, type: socks5, server: %s, port: %s, udp: true, username: node-user, password: node-password}
rules: ["MATCH,%s"]
`, port, sniff, host, proxyPort, target)
}

func businessManaged(t *testing.T, root string) ([]businessCase, []ConfigFact) {
	t.Helper()
	fixture := newManagedFixture(t)
	home := filepath.Join(root, "managed-core-home")
	if err := os.MkdirAll(home, 0700); err != nil {
		t.Fatal(err)
	}
	C.SetHomeDir(home)
	for _, name := range []string{"nodeA", "nodeB"} {
		managedObject(managedObject(fixture.policy["proxies"])[name])["udp"] = true
	}
	var cases []businessCase
	var facts []ConfigFact
	for _, useProxy := range []bool{false, true} {
		target := map[string]any{"kind": "direct"}
		if useProxy {
			target = map[string]any{"kind": "proxy", "group": "a"}
		}
		managedObject(fixture.policy["ipRules"].([]any)[0])["target"] = target
		result := applyManagedInput(t, compiledManagedInput(t, fixture, "fc-managed-group-a"))
		if !result.Fact.BusinessActive || result.Fact.PolicyVersion != 1 {
			t.Fatal("managed input was not actually active", result)
		}
		facts = append(facts, result.Fact)
		for _, inbound := range []string{"socks", "http", "connect"} {
			name := fmt.Sprintf("managed-proxy-%t-%s", useProxy, inbound)
			cases = append(cases, businessTCP(t, fixture.proxies[0], fixture.mixedPort, inbound, name, inbound == "connect", useProxy))
		}
		cases = append(cases, businessUDP(t, fixture.proxies[0], fixture.mixedPort, fmt.Sprintf("managed-udp-proxy-%t", useProxy), false, useProxy))
	}
	captureFrames(t, func() { handleStopListener(); settleMessageBatcher() })
	return cases, facts
}

func TestBusinessDataReview(t *testing.T) {
	root := os.Getenv("FLCLASH_BUSINESS_DATA_EVIDENCE")
	if root == "" {
		t.Skip("explicit local data review; requires an isolated test process")
	}
	if dialer.DefaultSocketHook != nil {
		t.Fatal("data review requires an isolated Core test process")
	}
	var mu sync.Mutex
	var sockets []string
	// Keep the hook installed until process exit; concurrent socket creation must never observe nil.
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		mu.Lock()
		sockets = append(sockets, network+":"+address)
		mu.Unlock()
		host, port, err := net.SplitHostPort(address)
		if err == nil && (net.ParseIP(host).IsLoopback() || port == "0") {
			return nil
		}
		return fmt.Errorf("data review blocks non-loopback socket")
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	configTestHome(t)
	home := filepath.Join(root, "core-home")
	if err := os.MkdirAll(home, 0700); err != nil {
		t.Fatal(err)
	}
	C.SetHomeDir(home)
	proxy := managedSOCKS(t, "audit", map[string]bool{})
	proxy.mu.Lock()
	proxy.auth = auth.NewAuthenticator([]auth.AuthUser{{User: "node-user", Pass: "node-password"}})
	proxy.mu.Unlock()
	port := configTestPort(t)
	var cases []businessCase
	handleStartLog()
	t.Cleanup(handleStopLog)
	t.Cleanup(settleMessageBatcher)
	for _, useProxy := range []bool{false, true} {
		for _, sniff := range []bool{false, true} {
			applyTestInput(t, writeTestInput(t, businessYAML(port, proxy.address, useProxy, sniff)))
			for _, inbound := range []string{"socks", "http", "connect"} {
				name := fmt.Sprintf("proxy-%t-sniff-%t-%s", useProxy, sniff, inbound)
				cases = append(cases, businessTCP(t, proxy, port, inbound, name, inbound == "connect", useProxy))
			}
			cases = append(cases, businessUDP(t, proxy, port, fmt.Sprintf("udp-proxy-%t-sniff-%t", useProxy, sniff), false, useProxy))
		}
	}
	failures := businessFailures(t, port, proxy)
	cancellation := businessCancellation(t, port, proxy)
	applyTestInput(t, writeTestInput(t, businessYAML(port, proxy.address, false, false)))
	cases = append(cases, businessUDP(t, proxy, port, "udp-held-response-stop", true, false))
	captureFrames(t, func() { handleStopListener(); settleMessageBatcher() })
	var managedFacts []ConfigFact
	if os.Getenv("FLCLASH_MANAGED_PROFILE_COMPILER") != "" {
		managed, facts := businessManaged(t, root)
		cases = append(cases, managed...)
		managedFacts = facts
	}
	settleMessageBatcher()
	mu.Lock()
	attempts := append([]string(nil), sockets...)
	mu.Unlock()
	data, err := json.MarshalIndent(map[string]any{"cases": cases, "managedFacts": managedFacts, "failures": failures, "cancellation": cancellation, "sockets": attempts, "coreHome": home, "scope": "host TCP/UDP; managed only when managedFacts populated; Android/native require separate evidence"}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "tcp.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	for _, observed := range cases {
		channels := append(bytes.Clone(observed.Connections), observed.Traffic...)
		for _, frame := range observed.Events {
			channels = append(channels, frame...)
		}
		for _, secret := range []string{"request-body-" + observed.Name, "response-body-" + observed.Name, "business-auth-" + observed.Name, "business-cookie=" + observed.Name, "node-password"} {
			if bytes.Contains(channels, []byte(secret)) {
				t.Errorf("unexpected business secret in Core metadata/log channel: %s", secret)
			}
		}
	}
}
