package main

import (
	"testing"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/tunnel"
)

func TestSourceProviderProjectionMatchesOriginalOverrideAndFilter(t *testing.T) {
	body := []byte("proxies:\n  - {name: alpha, type: socks5, server: 127.0.0.1, port: 9001, udp: false}\n  - {name: excluded, type: direct}\n  - {name: beta, type: socks5, server: 127.0.0.1, port: 9002, udp: false}\n")
	declaration := map[string]any{
		"filter": "alpha`beta", "exclude-type": "direct", "dialer-proxy": "original",
		"override": map[string]any{"udp": true, "additional-prefix": "accepted-", "override-expr": []any{`.name |= upcase`, `.server = "127.0.0.2"`, `."dialer-proxy" = "fixed"`}},
	}
	effective, err := sourceProviderProxyDocument(body, declaration)
	if err != nil {
		t.Fatal(err)
	}
	var original provider.ProxySchema
	if err := yaml.Unmarshal(body, &original); err != nil {
		t.Fatal(err)
	}
	declaration["type"], declaration["payload"] = "inline", original.Proxies
	parsed, err := provider.ParseProxyProvider("fixture", declaration, tunnel.Tunnel)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, proxy := range parsed.Proxies() {
			_ = proxy.Close()
		}
		if closer, ok := parsed.(interface{ Close() error }); ok {
			_ = closer.Close()
		}
	})
	nodes, valid := sourceMappings(effective["proxies"])
	if !valid || len(nodes) != len(parsed.Proxies()) || len(nodes) != 2 {
		t.Fatal("pure filter differs from the original provider")
	}
	for i, node := range nodes {
		actual := parsed.Proxies()[i]
		if node["name"] != actual.Name() || node["udp"] != actual.SupportUDP() || actual.Addr() != "127.0.0.2:"+map[int]string{0: "9001", 1: "9002"}[i] {
			t.Fatal("effective capability/identity differs from the original factory", node, actual.Name(), actual.Addr(), actual.SupportUDP())
		}
	}
}

func TestSourceOwnRoutingRejectsEvaluatedProviderOverride(t *testing.T) {
	for _, expression := range []string{`.type = "rematch"`, `.type = ("re" + "match")`} {
		document := map[string]any{"proxy-providers": map[string]any{"source": map[string]any{
			"type": "inline", "payload": []any{map[string]any{"name": "source", "type": "direct"}},
			"override": map[string]any{"override-expr": []any{expression}},
		}}}
		if _, err := sourceRoutingProjection(document, "profile:7"); err == nil {
			t.Fatal("own-routing boundary inspected expression text instead of its effective result")
		}
	}
}
