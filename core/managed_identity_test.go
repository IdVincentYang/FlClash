package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/transport/socks5"
	D "github.com/miekg/dns"
)

func identityDNS(t *testing.T, answer netip.Addr) *managedDNS {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	d := &managedDNS{address: listener.Addr().String()}
	ready := make(chan struct{})
	server := &D.Server{Listener: listener, Net: "tcp", NotifyStartedFunc: func() { close(ready) },
		Handler: D.HandlerFunc(func(w D.ResponseWriter, request *D.Msg) {
			response := new(D.Msg)
			response.SetReply(request)
			for _, q := range request.Question {
				d.mu.Lock()
				d.queries = append(d.queries, fmt.Sprintf("%s/%d", q.Name, q.Qtype))
				d.mu.Unlock()
				if q.Qtype == D.TypeA {
					response.Answer = append(response.Answer, &D.A{
						Hdr: D.RR_Header{Name: q.Name, Rrtype: D.TypeA, Class: D.ClassINET, Ttl: 60},
						A:   net.IP(answer.AsSlice()),
					})
				}
			}
			_ = w.WriteMsg(response)
		})}
	t.Cleanup(func() { _ = server.Shutdown() })
	go func() { _ = server.ActivateAndServe() }()
	select {
	case <-ready:
	case <-time.After(time.Second):
		t.Fatal("identity DNS did not start")
	}
	return d
}

func identityBusiness(f *managedFixture, original, address, marker string) (string, string, error) {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", f.mixedPort), time.Second)
	if err != nil {
		return "", "", err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
	destination := net.JoinHostPort(address, fmt.Sprint(managedPort(f.target.Listener.Addr().String())))
	if _, err := socks5.ClientHandshake(conn, socks5.ParseAddr(destination), socks5.CmdConnect, nil); err != nil {
		return "", "", err
	}
	request := fmt.Sprintf("GET /%s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", marker, original)
	if _, err := io.WriteString(conn, request); err != nil {
		return "", request, err
	}
	response, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		return "", request, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return string(body), request, err
}

func TestManagedProfileSharedIPInvestigation(t *testing.T) {
	if os.Getenv("FLCLASH_MANAGED_IDENTITY_INVESTIGATION") != "1" {
		t.Skip("explicit local identity investigation")
	}
	if dialer.DefaultSocketHook != nil {
		t.Fatal("investigation requires an isolated Core test process")
	}
	var mu sync.Mutex
	var blocked []string
	// This guard lives for the isolated process; an in-flight dial must never see it cleared.
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		host, _, err := net.SplitHostPort(address)
		ip, parseErr := netip.ParseAddr(host)
		if err == nil && parseErr == nil && ip.IsLoopback() {
			return nil
		}
		mu.Lock()
		blocked = append(blocked, network+":"+address)
		mu.Unlock()
		return fmt.Errorf("identity investigation blocks non-loopback socket")
	}
	f := newManagedFixture(t)
	answer := netip.MustParseAddr("192.0.2.123")
	if !answer.IsGlobalUnicast() {
		t.Fatal("answer would bypass real mapping middleware")
	}
	const a, b = "a.identity.test", "b.identity.test"
	f.policy["domainRules"] = []any{
		map[string]any{"id": "a", "type": "DOMAIN", "value": a, "target": map[string]any{"kind": "proxy", "group": "a"}, "dnsService": "dnsA"},
		map[string]any{"id": "b", "type": "DOMAIN", "value": b, "target": map[string]any{"kind": "proxy", "group": "b"}, "dnsService": "dnsB"},
	}
	f.policy["domainDefault"] = map[string]any{"target": map[string]any{"kind": "reject"}}
	f.policy["ipRules"] = []any{}
	f.policy["ipDefault"] = map[string]any{"kind": "reject"}
	for index, name := range []string{"dnsA", "dnsB"} {
		server := identityDNS(t, answer)
		f.servers[index] = server
		managedObject(managedObject(f.policy["dnsServices"])[name])["port"] = managedPort(server.address)
		for _, proxy := range f.proxies {
			proxy.mu.Lock()
			proxy.allowed[server.address] = true
			proxy.mu.Unlock()
		}
	}
	f.apply(t)
	for name, want := range map[string]string{a: "A", b: "B"} {
		if body, _, err := identityBusiness(f, name, name, "domain-control"); err != nil || body != want {
			t.Fatal("explicit domain control", name, body, err)
		}
	}
	if body, _, err := identityBusiness(f, "literal-ip", answer.String(), "before-dns"); err == nil || body != "" {
		t.Fatal("unmapped IP must use explicit REJECT default", body, err)
	}
	var records []map[string]any
	for _, name := range []string{a, b} {
		response, err := f.query(name)
		if err != nil || len(response.Answer) != 1 {
			t.Fatal("real DNS query", name, response, err)
		}
		ip, ok := response.Answer[0].(*D.A)
		if !ok || ip.A.String() != answer.String() {
			t.Fatal("unexpected DNS answer", response)
		}
		host, exists := resolver.FindHostByIP(answer)
		if !exists || host != name {
			t.Fatal("real DNS did not populate mapping", name, host, exists)
		}
		records = append(records, map[string]any{"event": "dns", "originalDomain": name, "answer": answer.String(), "observedMapping": host})
	}
	beforeA, beforeB := f.proxies[0].count(), f.proxies[1].count()
	body, request, err := identityBusiness(f, a, answer.String(), "original-a-after-b")
	if err != nil {
		t.Fatal("business probe did not reach an independent receiver", err)
	}
	records = append(records, map[string]any{"event": "business", "originalDomain": a, "connectAddress": answer.String(),
		"request": request, "expectedReceiver": "A", "actualReceiver": body,
		"proxyAConnections": f.proxies[0].count() - beforeA, "proxyBConnections": f.proxies[1].count() - beforeB})
	if f.servers[0].count() != 1 || f.servers[1].count() != 1 {
		t.Fatal("independent DNS receivers", f.servers[0].count(), f.servers[1].count())
	}
	mu.Lock()
	denied := append([]string{}, blocked...)
	mu.Unlock()
	directory := managedArtifactDirectory(t)
	data, _ := json.MarshalIndent(map[string]any{"records": records, "nonLoopbackSocketsBlocked": denied,
		"directReceipts": f.direct.Load(), "counterexample": body != "A", "scope": "host TCP SOCKS IP, no AVD/UDP/DIRECT wire proof"}, "", "  ")
	if err := os.WriteFile(filepath.Join(directory, "identity.json"), append(data, '\n'), 0600); err != nil {
		t.Fatal(err)
	}
	t.Log("identity evidence", directory)
	if len(denied) != 0 || f.direct.Load() != 0 {
		t.Fatal("unexpected attempted route", denied, f.direct.Load())
	}
	if body != "A" || !strings.Contains(request, "Host: "+a) {
		t.Errorf("original domain A expected receiver A, actual receiver %s", body)
	}
}
