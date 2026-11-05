package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/transport/socks5"
)

func sourceUDPEchoFixture(t *testing.T, label string) string {
	t.Helper()
	server, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	go func() {
		buffer := make([]byte, 2048)
		for {
			n, peer, err := server.ReadFrom(buffer)
			if err != nil {
				return
			}
			_, _ = server.WriteTo(append([]byte(label+":"), buffer[:n]...), peer)
		}
	}()
	return server.LocalAddr().String()
}

func sourceUDPAssociation(t *testing.T, port int) net.Conn {
	t.Helper()
	address := fmt.Sprintf("127.0.0.1:%d", port)
	control, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = control.Close() })
	_ = control.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := socks5.ClientHandshake(control, socks5.ParseAddr("0.0.0.0:0"), socks5.CmdUDPAssociate, nil); err != nil {
		t.Fatal(err)
	}
	packet, err := net.DialTimeout("udp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = packet.Close() })
	return packet
}

func sourceUDPEcho(t *testing.T, packet net.Conn, target, message, expected string) {
	t.Helper()
	_ = packet.SetDeadline(time.Now().Add(2 * time.Second))
	data, err := socks5.EncodeUDPPacket(socks5.ParseAddr(target), []byte(message))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := packet.Write(data); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, 2048)
	n, err := packet.Read(buffer)
	if err != nil {
		t.Fatal("existing UDP association stopped receiving", err)
	}
	_, body, err := socks5.DecodeUDPPacket(buffer[:n])
	if err != nil || string(body) != expected+":"+message {
		t.Fatal("UDP association used the wrong receiver", string(body), err)
	}
}

func TestSourceProviderHotUpdateKeepsDirectAndUnchangedProviderTCPAndUDP(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	tcp, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = tcp.Close() })
	go func() {
		conn, err := tcp.Accept()
		if err == nil {
			defer conn.Close()
			_, _ = io.Copy(conn, conn)
		}
	}()
	udpB, udpDirect := sourceUDPEchoFixture(t, "provider-B"), sourceUDPEchoFixture(t, "direct")
	hop := managedSOCKS(t, "unchanged-B", map[string]bool{tcp.Addr().String(): true, udpB: true})
	port := configTestPort(t)
	rules := fmt.Sprintf("rules: [\"DST-PORT,%d,BGroup\", \"DST-PORT,%d,DIRECT\", \"NETWORK,UDP,BGroup\", \"MATCH,DIRECT\"]", managedPort(tcp.Addr().String()), managedPort(udpDirect))
	yaml := strings.Replace(configTestYAML(port), "rules: [\"MATCH,DIRECT\"]", rules, 1) + "proxy-providers:\n  A: {type: http, url: 'http://127.0.0.1:1/A', interval: 0}\n  B: {type: http, url: 'http://127.0.0.1:1/B', interval: 0}\nproxy-groups:\n  - {name: BGroup, type: select, use: [B]}\n"
	oldA := []byte("proxies: [{name: old-A, type: socks5, server: 127.0.0.1, port: 1, udp: true}]\n")
	bodyB := []byte(fmt.Sprintf("proxies: [{name: unchanged-B, type: socks5, server: 127.0.0.1, port: %d, udp: true}]\n", managedPort(hop.address)))
	applyTestInput(t, sourceRuntimeInput(t, yaml, map[string][]byte{"provider-proxy:A": oldA, "provider-proxy:B": bodyB}))
	p := appliedConfig
	var a, b *sourceProviderRuntime
	for _, runtime := range p.sourceProviders {
		if runtime.plan.Name == "A" {
			a = runtime
		} else {
			b = runtime
		}
	}
	connB, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = connB.Close() })
	_ = connB.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := socks5.ClientHandshake(connB, socks5.ParseAddr(tcp.Addr().String()), socks5.CmdConnect, nil); err != nil {
		t.Fatal(err)
	}
	direct := sourceEchoConnection(t, port)
	packetB, packetDirect := sourceUDPAssociation(t, port), sourceUDPAssociation(t, port)
	check := func(message string) {
		sourceEcho(t, connB, message)
		sourceEcho(t, direct, message)
		before := hop.count()
		sourceUDPEcho(t, packetB, udpB, message, "provider-B")
		if hop.count() <= before {
			t.Fatal("provider-B UDP silently used DIRECT")
		}
		sourceUDPEcho(t, packetDirect, udpDirect, message, "direct")
	}
	check("before")
	appRequests.control(appRequestControl{Action: "engineDetach"})
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	scope, token, owner := p.scope, p.receipt.Token, p.receipt.Owner
	originalB, versionB, adapterB := b.proxy.ProxySetProvider, b.proxy.Version(), b.proxy.Proxies()[0]
	if err := a.update([]byte("proxies: [{name: new-A, type: socks5, server: 127.0.0.1, port: 2, udp: true}]\n")); err != nil {
		t.Fatal(err)
	}
	if p.scope != scope || p.receipt.Token != token || p.receipt.Owner != owner || b.proxy.ProxySetProvider != originalB || b.proxy.Version() != versionB || b.proxy.Proxies()[0] != adapterB {
		t.Fatal("provider A update changed the parent or untouched provider B")
	}
	check("after")
	p.sourceRetiredCount = sourceRetiredGenerationLimit
	if err := a.update([]byte("proxies: [{name: deferred-A, type: socks5, server: 127.0.0.1, port: 3, udp: true}]\n")); !errors.Is(err, errSourceBudget) {
		t.Fatal("retirement budget did not defer the next update", err)
	}
	check("budget-preserved")
}
