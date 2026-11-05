package main

import (
	"context"
	"net"
	"net/netip"
	"strconv"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestAppRequestListenPacketUsesQualifiedSOCKSAndRetires(t *testing.T) {
	r := revisionRegistry(t)
	target, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	hop := managedSOCKS(t, "packet-hop", map[string]bool{target.LocalAddr().String(): true})
	host, portText, _ := net.SplitHostPort(hop.address)
	port, _ := strconv.Atoi(portText)
	proxyAdapter, err := outbound.NewSocks5(outbound.Socks5Option{Name: "qualified-packet-hop", Server: host, Port: port, UDP: true})
	if err != nil {
		t.Fatal(err)
	}
	defer proxyAdapter.Close()
	proxy := adapter.NewProxy(proxyAdapter)
	oldProxies, oldProviders := tunnel.AllProxies(), tunnel.ProvidersSnapshot()
	tunnel.UpdateProxies(map[string]C.Proxy{proxy.Name(): proxy}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	lease, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "maintenance", Trigger: "manual", Mode: "proxy", Proxy: proxy.Name(), Key: "packet-hop"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	remote := netip.MustParseAddrPort(target.LocalAddr().String())
	conn, err := lease.Dialer().ListenPacket(lease.Context(), "udp", "", remote)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.WriteTo([]byte("qualified-packet"), target.LocalAddr()); err != nil {
		t.Fatal(err)
	}
	_ = target.SetReadDeadline(time.Now().Add(time.Second))
	buf := make([]byte, 256)
	n, sender, err := target.ReadFrom(buf)
	if err != nil || string(buf[:n]) != "qualified-packet" || hop.count() != 1 {
		t.Fatalf("qualified packet did not traverse the independent hop: %q %d %v", buf[:n], hop.count(), err)
	}
	owner := r.newOwner()
	r.setPhase(owner, "ready")
	_, _ = target.WriteTo([]byte("late-packet"), sender)
	_ = conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	if _, _, err := conn.ReadFrom(buf); err == nil {
		t.Fatal("retired packet association delivered a late response")
	}
	if _, err := conn.WriteTo([]byte("retired-packet"), target.LocalAddr()); err == nil {
		t.Fatal("retired packet association remained writable")
	}
}

func TestAppRequestListenPacketDirectAutoAndStrictBoundaries(t *testing.T) {
	r := revisionRegistry(t)
	target, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	direct := adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "packet-direct-alias"}))
	oldProxies, oldProviders := tunnel.AllProxies(), tunnel.ProvidersSnapshot()
	tunnel.UpdateProxies(map[string]C.Proxy{direct.Name(): direct}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	remote := netip.MustParseAddrPort(target.LocalAddr().String())
	for _, spec := range []requestscope.Spec{
		{Mode: "direct", Proxy: "DIRECT"},
		{Mode: "auto", Proxy: ""},
		{Mode: "proxy", Proxy: "missing-packet-proxy"},
		{Mode: "proxy", Proxy: direct.Name()},
	} {
		spec.Owner, spec.Kind, spec.Trigger, spec.Key = r.currentOwner(), "maintenance", "manual", "packet-boundary"
		lease, err := r.begin(context.Background(), spec)
		if err != nil {
			t.Fatal(err)
		}
		conn, err := lease.Dialer().ListenPacket(lease.Context(), "udp", "", remote)
		if spec.Mode == "proxy" {
			lease.Close()
			if err == nil {
				_ = conn.Close()
				t.Fatalf("strict packet request accepted %q", spec.Proxy)
			}
			continue
		}
		if err != nil {
			lease.Close()
			t.Fatal(err)
		}
		_, err = conn.WriteTo([]byte(spec.Mode), target.LocalAddr())
		if err != nil {
			t.Fatal(err)
		}
		_ = target.SetReadDeadline(time.Now().Add(time.Second))
		buffer := make([]byte, 256)
		n, _, err := target.ReadFrom(buffer)
		if err != nil || string(buffer[:n]) != spec.Mode {
			t.Fatal("explicit Direct or Auto packet was not received", err)
		}
		_ = conn.Close()
		lease.Close()
	}
	_ = target.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	if _, _, err := target.ReadFrom(make([]byte, 256)); err == nil {
		t.Fatal("strict packet failure fell through to Direct")
	}
}
