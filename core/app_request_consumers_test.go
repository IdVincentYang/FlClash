package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/geodata"
	mihomoHTTP "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/updater"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	ntpTime "github.com/metacubex/mihomo/ntp"
	ntpService "github.com/metacubex/mihomo/ntp/ntp"
	"github.com/metacubex/mihomo/tunnel"
)

func appConsumerHooks(t *testing.T, registry *appRequestRegistry) {
	t.Helper()
	begin, owner, ready, resource := requestscope.BeginHook, requestscope.OwnerHook, requestscope.ReadyHook, requestscope.ResourceHook
	requestscope.BeginHook, requestscope.OwnerHook, requestscope.ReadyHook, requestscope.ResourceHook = registry.begin, registry.currentOwner, registry.waitReady, registry.lockResource
	t.Cleanup(func() {
		requestscope.BeginHook, requestscope.OwnerHook, requestscope.ReadyHook, requestscope.ResourceHook = begin, owner, ready, resource
	})
}

func TestAppRequestGeoValidatesBeforeReplacementAndRejectsRevoked(t *testing.T) {
	valid, err := os.ReadFile("../assets/data/ASN.mmdb")
	if err != nil {
		t.Fatal(err)
	}
	for _, scenario := range []string{"invalid", "valid", "revoked"} {
		t.Run(scenario, func(t *testing.T) {
			originalHome, originalURL := C.Path.HomeDir(), geodata.ASNUrl()
			C.SetHomeDir(t.TempDir())
			defer C.SetHomeDir(originalHome)
			defer geodata.SetASNUrl(originalURL)
			path := C.Path.ASN()
			if err := os.WriteFile(path, []byte("baseline"), 0600); err != nil {
				t.Fatal(err)
			}
			r, lease := appRequestFixture(t)
			appConsumerHooks(t, r)
			r.socketGate = func(string, AppRequestState, int) error { return nil }
			payload := valid
			if scenario == "invalid" {
				payload = []byte("invalid database")
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if scenario == "revoked" {
					state := r.state
					state.Revision++
					r.publish(state)
				}
				_, _ = w.Write(payload)
			}))
			defer server.Close()
			geodata.SetASNUrl(server.URL)
			lease.spec.URL, lease.spec.Resource = server.URL, path
			err := updater.UpdateGeoResource(lease.Context(), "ASN", lease)
			actual, readErr := os.ReadFile(path)
			if readErr != nil {
				t.Fatal(readErr)
			}
			if scenario == "valid" {
				if err != nil || !bytes.Equal(actual, valid) {
					t.Fatal("validated Geo was not installed", err)
				}
			} else if err == nil || string(actual) != "baseline" {
				t.Fatal("invalid or revoked Geo replaced baseline", err)
			}
		})
	}
}

func TestAppRequestNTPUsesScopedUDPAndRetirementRejectsOffset(t *testing.T) {
	for _, retire := range []bool{false, true} {
		t.Run(map[bool]string{false: "current", true: "retired"}[retire], func(t *testing.T) {
			r, _ := appRequestFixture(t)
			state := r.state
			state.Revision++
			state.IntentRunning, state.Phase = true, "started"
			r.publish(state)
			owner := r.newOwner()
			r.setPhase(owner, "ready")
			appConsumerHooks(t, r)
			r.socketGate = func(string, AppRequestState, int) error { return nil }
			server, err := net.ListenPacket("udp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			defer server.Close()
			ntpService.ReCreateNTPService(server.LocalAddr().String(), 1, "DIRECT", tunnel.Tunnel, false)
			defer ntpService.ReCreateNTPService("", 0, "", tunnel.Tunnel, false)
			_ = server.SetReadDeadline(time.Now().Add(2 * time.Second))
			request := make([]byte, 48)
			_, target, err := server.ReadFrom(request)
			if err != nil {
				t.Fatal("scoped NTP did not reach loopback UDP", err)
			}
			if retire {
				next := r.newOwner()
				r.setPhase(next, "ready")
			}
			response := make([]byte, 48)
			response[0], response[1] = 0x24, 1
			stamp := time.Now().Add(3 * time.Second)
			seconds := uint64(stamp.Unix() + 2208988800)
			fraction := uint64(stamp.Nanosecond()) * (1 << 32) / 1000000000
			for _, offset := range []int{16, 32, 40} {
				binary.BigEndian.PutUint64(response[offset:offset+8], seconds<<32|fraction)
			}
			copy(response[24:32], request[40:48])
			_, _ = server.WriteTo(response, target)
			deadline := time.Now().Add(300 * time.Millisecond)
			for !retire && ntpTime.GetOffset() == 0 && time.Now().Before(deadline) {
				time.Sleep(time.Millisecond)
			}
			if retire {
				time.Sleep(20 * time.Millisecond)
				if ntpTime.GetOffset() != 0 {
					t.Fatal("retired NTP updated offset")
				}
			} else if ntpTime.GetOffset() < 2*time.Second {
				t.Fatal("current NTP did not commit its synthetic offset", ntpTime.GetOffset())
			}
		})
	}
}

func TestAppRequestStrictProxyUsesActualHTTPHopAndRejectsNestedDirect(t *testing.T) {
	var originCount, hopCount atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		originCount.Add(1)
		_, _ = w.Write([]byte("synthetic origin"))
	}))
	defer origin.Close()
	hop := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.Method != "CONNECT" || req.Host != origin.Listener.Addr().String() {
			http.Error(w, "blocked synthetic target", 403)
			return
		}
		hopCount.Add(1)
		remote, err := net.Dial("tcp", origin.Listener.Addr().String())
		if err != nil {
			http.Error(w, "synthetic connection failure", 502)
			return
		}
		inbound, _, err := w.(http.Hijacker).Hijack()
		if err != nil {
			_ = remote.Close()
			return
		}
		_, _ = io.WriteString(inbound, "HTTP/1.1 200 Connection established\r\n\r\n")
		go func() { defer inbound.Close(); defer remote.Close(); _, _ = io.Copy(remote, inbound) }()
		_, _ = io.Copy(inbound, remote)
		_ = inbound.Close()
		_ = remote.Close()
	}))
	defer hop.Close()
	host, portText, _ := net.SplitHostPort(hop.Listener.Addr().String())
	port, _ := strconv.Atoi(portText)
	httpAdapter, err := outbound.NewHttp(outbound.HttpOption{Name: "synthetic HTTP hop", Server: host, Port: port})
	if err != nil {
		t.Fatal(err)
	}
	proxy := adapter.NewProxy(httpAdapter)
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{proxy.Name(): proxy}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	r, _ := appRequestFixture(t)
	state := r.state
	state.Revision++
	state.IntentRunning, state.Phase = true, "started"
	r.publish(state)
	owner := r.newOwner()
	r.setPhase(owner, "ready")
	lease, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "request", Mode: "proxy", Proxy: proxy.Name(), Key: "strict positive"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	response, err := mihomoHTTP.HttpRequest(lease.Context(), origin.URL, "GET", nil, nil, mihomoHTTP.WithScope(lease))
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(response.Body)
	_ = response.Body.Close()
	if err != nil || string(body) != "synthetic origin" || originCount.Load() != 1 || hopCount.Load() != 1 {
		t.Fatal("strict proxy did not use actual HTTP hop", err, originCount.Load(), hopCount.Load())
	}
	direct := adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "arbitrary direct alias"}))
	group := func(name string, child C.Proxy, filter string) C.Proxy {
		hc := provider.NewHealthCheck([]C.Proxy{child}, "", 0, 0, false, nil)
		pd, err := provider.NewCompatibleProvider(name+" provider", []C.Proxy{child}, hc)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = pd.Close() })
		selector, err := outboundgroup.NewSelector(outboundgroup.GroupCommonOption{Name: name, ExcludeFilter: filter}, outboundgroup.SelectorOption{}, direct, []P.ProxyProvider{pd})
		if err != nil {
			t.Fatal(err)
		}
		return adapter.NewProxy(selector)
	}
	for _, candidate := range []C.Proxy{group("inner", direct, ""), group("outer", group("nested", direct, ""), ""), group("filtered", proxy, ".*")} {
		scoped, err := r.begin(lease.Context(), requestscope.Spec{Owner: owner, Kind: "request", Mode: "proxy", Key: "strict negative"})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := scoped.(*appRequestLease).SelectProxy(candidate, &C.Metadata{}); err == nil {
			t.Fatal("nested or filtered DIRECT was accepted")
		}
		scoped.Close()
	}
	if originCount.Load() != 1 || hopCount.Load() != 1 {
		t.Fatal("rejected selections sent traffic")
	}
}
