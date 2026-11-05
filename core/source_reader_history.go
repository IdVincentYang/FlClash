package main

import (
	"encoding/json"
	"slices"
	"strings"
	"sync/atomic"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
)

var sourceInlineReaderRisk atomic.Pointer[string]

func recordSourceReaderRisk(reason string) { sourceInlineReaderRisk.CompareAndSwap(nil, &reason) }

func sourceInlineReaderReason() string {
	if reason := sourceInlineReaderRisk.Load(); reason != nil {
		return *reason
	}
	return ""
}

func recordSourceNameServer(server dns.NameServer) {
	if server.ProxyAdapter != nil {
		recordSourceReaderRisk("private-dns-reader")
		return
	}
	if server.ProxyName != "" {
		recordSourceReaderRisk("named-dns-reader")
		return
	}
	for key := range server.Params {
		if !slices.Contains([]string{"skip-cert-verify", "name-cert-verify", "disable-reuse", "h3"}, key) {
			recordSourceReaderRisk("unknown-dns-parameter")
			return
		}
	}
	switch server.Net {
	case "", "tcp", "tls", "rcode":
	case "https":
		if server.PreferH3 || server.Params["h3"] == "true" || slices.Contains(dns.DefaultHTTPVersions, C.HTTPVersion3) {
			recordSourceReaderRisk("http3-dns-reader")
		}
	case "system":
	case "quic":
		recordSourceReaderRisk("quic-dns-reader")
	case "dhcp":
		recordSourceReaderRisk("dhcp-dns-reader")
	default:
		recordSourceReaderRisk("unknown-dns-reader")
	}
}

func recordSourceDNSReaders(cfg *config.DNS) {
	if cfg == nil {
		recordSourceReaderRisk("unknown-dns-history")
		return
	}
	if !cfg.Enable {
		return
	}
	for _, servers := range [][]dns.NameServer{cfg.NameServer, cfg.Fallback, cfg.DefaultNameserver, cfg.ProxyServerNameserver, cfg.DirectNameServer} {
		for _, server := range servers {
			recordSourceNameServer(server)
		}
	}
	for _, policies := range [][]dns.Policy{cfg.NameServerPolicy, cfg.ProxyServerPolicy} {
		for _, policy := range policies {
			for _, server := range policy.NameServers {
				recordSourceNameServer(server)
			}
		}
	}
}

func sourceNodeFactoryRisk(document map[string]any) string {
	nodes, valid := sourceMappings(document["proxies"])
	if !valid {
		return "unknown-proxy-factory"
	}
	for _, node := range nodes {
		if name, _ := node["dialer-proxy"].(string); name != "" {
			return "named-proxy-dialer"
		}
		if plugin, present := node["plugin"]; present && plugin != "" && plugin != nil {
			return "private-proxy-plugin"
		}
		if node["dns"] != nil {
			return "private-proxy-dns"
		}
		kind, _ := node["type"].(string)
		if !slices.Contains([]string{"direct", "reject", "reject-drop", "socks5", "ss", "ssr", "vmess", "vless", "trojan", "http"}, strings.ToLower(kind)) {
			return "private-or-unknown-proxy-factory"
		}
	}
	return ""
}

func recordSourceNodeFactories(document map[string]any) {
	if reason := sourceNodeFactoryRisk(document); reason != "" {
		recordSourceReaderRisk(reason)
	}
}

func recordSourceRawFactories(raw *config.RawConfig) {
	if raw == nil {
		recordSourceReaderRisk("unknown-factory-history")
		return
	}
	nodes := make([]any, 0, len(raw.Proxy))
	for _, node := range raw.Proxy {
		nodes = append(nodes, node)
	}
	recordSourceNodeFactories(map[string]any{"proxies": nodes})
	for _, declaration := range raw.ProxyProvider {
		if payload, present := declaration["payload"]; present {
			body, err := json.Marshal(map[string]any{"proxies": payload})
			if err != nil {
				recordSourceReaderRisk("unknown-provider-factory")
				continue
			}
			effective, err := sourceProviderProxyDocument(body, declaration)
			if err != nil {
				recordSourceReaderRisk("unknown-provider-factory")
				continue
			}
			recordSourceNodeFactories(effective)
		}
	}
	if raw.NTP.Enable {
		recordSourceReaderRisk("ntp-reader")
	}
	if raw.ExternalController != "" || raw.ExternalControllerTLS != "" || raw.ExternalControllerPipe != "" || raw.ExternalControllerUnix != "" {
		recordSourceReaderRisk("controller-reader")
	}
}
