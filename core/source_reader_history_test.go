package main

import (
	"context"
	"encoding/base64"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/dns"
	D "github.com/miekg/dns"
)

func sourceReaderHistoryFixture(t *testing.T) {
	t.Helper()
	previous := sourceInlineReaderRisk.Swap(nil)
	t.Cleanup(func() { sourceInlineReaderRisk.Store(previous) })
}

func TestSourceReaderHistoryCoversEveryParsedDNSBranch(t *testing.T) {
	for _, branch := range []string{"main", "fallback", "bootstrap", "proxy", "direct", "policy", "proxy-policy"} {
		t.Run(branch, func(t *testing.T) {
			sourceReaderHistoryFixture(t)
			unsafe := []dns.NameServer{{Net: "quic", Addr: "127.0.0.1:853"}}
			cfg := &config.DNS{Enable: true}
			switch branch {
			case "main":
				cfg.NameServer = unsafe
			case "fallback":
				cfg.Fallback = unsafe
			case "bootstrap":
				cfg.DefaultNameserver = unsafe
			case "proxy":
				cfg.ProxyServerNameserver = unsafe
			case "direct":
				cfg.DirectNameServer = unsafe
			case "policy":
				cfg.NameServerPolicy = []dns.Policy{{NameServers: unsafe}}
			case "proxy-policy":
				cfg.ProxyServerPolicy = []dns.Policy{{NameServers: unsafe}}
			}
			recordSourceDNSReaders(cfg)
			if sourceInlineReaderReason() != "quic-dns-reader" {
				t.Fatal("unsafe parsed DNS branch was omitted", branch)
			}
			recordSourceDNSReaders(&config.DNS{Enable: true, NameServer: []dns.NameServer{{Addr: "127.0.0.1:53"}}})
			if sourceInlineReaderReason() != "quic-dns-reader" {
				t.Fatal("new safe settings erased old reader history")
			}
		})
	}
}

func TestSourceReaderHistoryClassifiesActualTransportProperties(t *testing.T) {
	for _, fixture := range []struct {
		name   string
		server dns.NameServer
		safe   bool
	}{
		{"udp", dns.NameServer{Addr: "127.0.0.1:53"}, true},
		{"tcp", dns.NameServer{Net: "tcp", Addr: "127.0.0.1:53"}, true},
		{"dot", dns.NameServer{Net: "tls", Addr: "127.0.0.1:853"}, true},
		{"doh-h1-h2", dns.NameServer{Net: "https", Addr: "https://127.0.0.1/dns-query"}, true},
		{"doh-h3", dns.NameServer{Net: "https", PreferH3: true}, false},
		{"forced-h3", dns.NameServer{Net: "https", Params: map[string]string{"h3": "true"}}, false},
		{"named-udp", dns.NameServer{ProxyName: "proxy"}, false},
		{"rules", dns.NameServer{ProxyName: dns.RespectRules}, false},
		{"dhcp", dns.NameServer{Net: "dhcp"}, false},
		{"unknown", dns.NameServer{Net: "private"}, false},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			sourceReaderHistoryFixture(t)
			recordSourceNameServer(fixture.server)
			if (sourceInlineReaderReason() == "") != fixture.safe {
				t.Fatal("transport property classified incorrectly", sourceInlineReaderReason())
			}
		})
	}
}

func TestSourceReaderHistoryRecordsPrivateFactoriesBeforeConstruction(t *testing.T) {
	sourceReaderHistoryFixture(t)
	raw := config.DefaultRawConfig()
	raw.Proxy = []map[string]any{{"name": "private", "type": "tailscale"}}
	recordSourceRawFactories(raw)
	if sourceInlineReaderReason() != "private-or-unknown-proxy-factory" {
		t.Fatal("private factory did not latch reader risk")
	}
	raw.Proxy = nil
	raw.DNS.Enable = false
	recordSourceRawFactories(raw)
	if sourceInlineReaderReason() != "private-or-unknown-proxy-factory" {
		t.Fatal("failed/closed preparation erased process history")
	}
}

func TestSourceReaderHistorySafeRealDNSTransports(t *testing.T) {
	for _, transport := range []string{"udp", "tcp", "tls", "https"} {
		t.Run(transport, func(t *testing.T) {
			sourceReaderHistoryFixture(t)
			server := dns.NameServer{Net: transport}
			if transport == "https" {
				httpServer := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					body, err := io.ReadAll(io.LimitReader(r.Body, 4096))
					if r.Method == http.MethodGet {
						body, err = base64.RawURLEncoding.DecodeString(r.URL.Query().Get("dns"))
					}
					if err != nil {
						http.Error(w, "read", 400)
						return
					}
					question := new(D.Msg)
					if question.Unpack(body) != nil {
						http.Error(w, "DNS", 400)
						return
					}
					answer := new(D.Msg)
					answer.SetReply(question)
					answer.Answer = []D.RR{&D.A{Hdr: D.RR_Header{Name: question.Question[0].Name, Rrtype: D.TypeA, Class: D.ClassINET}, A: net.ParseIP("127.0.0.1")}}
					encoded, _ := answer.Pack()
					w.Header().Set("Content-Type", "application/dns-message")
					_, _ = w.Write(encoded)
				}))
				t.Cleanup(httpServer.Close)
				server.Addr, server.Params = httpServer.URL+"/dns-query", map[string]string{"skip-cert-verify": "true"}
			} else if transport == "tls" {
				certificate, _ := managedCertificate(t, true)
				upstream := managedDNSServer(t, "tcp", &certificate)
				server.Addr, server.Params = upstream.address, map[string]string{"skip-cert-verify": "true"}
			} else {
				upstream := managedDNSServer(t, transport, nil)
				server.Addr = upstream.address
				if transport == "udp" {
					server.Net = ""
				}
			}
			recordSourceNameServer(server)
			if sourceInlineReaderReason() != "" {
				t.Fatal("safe transport acquired unsafe reader history", sourceInlineReaderReason())
			}
			resolver := dns.NewResolver(dns.Config{Main: []dns.NameServer{server}})
			t.Cleanup(resolver.ResetConnection)
			question := new(D.Msg)
			question.SetQuestion("actual-reader.test.", D.TypeA)
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			response, err := resolver.ExchangeContext(ctx, question)
			if err != nil || len(response.Answer) != 1 {
				t.Fatal("safe real DNS transport did not receive its localhost answer", err)
			}
		})
	}
}

func TestSourceReaderHistorySafeUDPTruncationUsesRealTCP(t *testing.T) {
	sourceReaderHistoryFixture(t)
	tcp := managedDNSServer(t, "tcp", nil)
	packet, err := net.ListenPacket("udp", tcp.address)
	if err != nil {
		t.Fatal(err)
	}
	var truncated atomic.Int32
	udp := &D.Server{PacketConn: packet, Handler: D.HandlerFunc(func(w D.ResponseWriter, question *D.Msg) {
		truncated.Add(1)
		answer := new(D.Msg)
		answer.SetReply(question)
		answer.Truncated = true
		_ = w.WriteMsg(answer)
	})}
	go func() { _ = udp.ActivateAndServe() }()
	t.Cleanup(func() { _ = udp.Shutdown() })
	server := dns.NameServer{Addr: tcp.address}
	recordSourceNameServer(server)
	resolver := dns.NewResolver(dns.Config{Main: []dns.NameServer{server}})
	t.Cleanup(resolver.ResetConnection)
	question := new(D.Msg)
	question.SetQuestion("truncated-reader.test.", D.TypeA)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	response, err := resolver.ExchangeContext(ctx, question)
	if err != nil || len(response.Answer) != 1 || tcp.count() != 1 || truncated.Load() != 1 || sourceInlineReaderReason() != "" {
		t.Fatal("UDP truncation did not keep its safe TCP consumer", err, tcp.count(), truncated.Load())
	}
}
