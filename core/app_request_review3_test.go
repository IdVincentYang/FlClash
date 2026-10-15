package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestAppRequestFixedDirectWithRealConfigMap(t *testing.T) {
	r := revisionRegistry(t)
	proxyHook := requestscope.ProxyHook
	requestscope.ProxyHook = r.bindProxy
	defer func() { requestscope.ProxyHook = proxyHook }()
	home := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(home)
	cfg, err := config.ParseRawConfig(config.DefaultRawConfig())
	if err != nil {
		t.Fatal(err)
	}
	for _, pd := range cfg.Providers {
		if closer, ok := pd.(interface{ Close() error }); ok {
			defer closer.Close()
		}
	}
	if cfg.Proxies["DIRECT"] == appDirectProxy {
		t.Fatal("fixture did not create a distinct configured Direct")
	}
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	var requests, gates atomic.Int32
	var deny atomic.Bool
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		requests.Add(1)
		time.Sleep(2 * time.Millisecond)
		_, _ = io.WriteString(w, "fixed Direct")
	}))
	defer origin.Close()
	r.socketGate = func(_ string, state AppRequestState, _ int) error {
		gates.Add(1)
		if deny.Load() || state.DefaultNetworkKind != "nonVpn" || state.DirectNetworkID == "" {
			return requestscope.ErrBlocked
		}
		return nil
	}
	r.client, r.clientReady, r.dataset = "fixed direct client", true, 1
	begin := func(key string) map[string]any {
		result := r.control(appRequestControl{Action: "begin", Client: r.client, Owner: r.currentOwner().ID, Dataset: 1, Kind: "maintenance", Trigger: "manual", Key: key, Proxy: "DIRECT", Mode: "direct", URL: origin.URL, ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}})
		success, ok := result.(map[string]any)
		if !ok {
			t.Fatalf("Direct begin failed: %v", result)
		}
		return success
	}
	get := func(scope map[string]any) {
		u, _ := url.Parse("http://" + scope["endpoint"].(string))
		u.User = url.UserPassword(scope["user"].(string), scope["password"].(string))
		transport := &http.Transport{Proxy: http.ProxyURL(u)}
		defer transport.CloseIdleConnections()
		response, err := (&http.Client{Transport: transport, Timeout: time.Second}).Get(origin.URL)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil || string(body) != "fixed Direct" {
			t.Fatal("private Direct HTTP failed", response.Status, err, string(body))
		}
		r.control(appRequestControl{Action: "cancel", Client: r.client, ID: scope["id"].(string)})
	}
	get(begin("running explicit Direct"))
	state := r.state
	state.Revision++
	state.IntentRunning = false
	state.Phase, state.Reason = "stopped", "userStop"
	r.publish(state)
	get(begin("stopped manual Direct"))
	probe := begin("explicit Direct delay")
	delay := handleTestDelay(&TestDelayParams{ProxyName: "DIRECT", TestUrl: origin.URL, Timeout: 1000, ScopeID: probe["id"].(string)})
	if delay == nil || delay.Value <= 0 || requests.Load() != 3 || gates.Load() < 3 {
		t.Fatal("configured Direct blocked fixed diagnostic or socket gate", delay, requests.Load(), gates.Load())
	}
	r.control(appRequestControl{Action: "cancel", Client: r.client, ID: probe["id"].(string)})
	state.Revision++
	state.IntentRunning = true
	state.Phase, state.Reason = "started", "none"
	r.publish(state)
	for i, node := range []C.Proxy{appDirectProxy, cfg.Proxies["DIRECT"], cfg.Proxies["COMPATIBLE"]} {
		lease, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "request", Key: "strict direct " + strconv.Itoa(i), Proxy: "DIRECT", Mode: "proxy"})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := lease.(*appRequestLease).SelectProxy(node, &C.Metadata{}); err == nil {
			t.Fatal("fixed Direct exception bypassed Strict Proxy")
		}
		lease.Close()
	}
	denied := begin("native gate rejected")
	deny.Store(true)
	failure := handleTestDelay(&TestDelayParams{ProxyName: "DIRECT", TestUrl: origin.URL, Timeout: 1000, ScopeID: denied["id"].(string)})
	if failure != nil && failure.Value > 0 || requests.Load() != 3 {
		t.Fatal("fixed Direct bypassed the real socket gate")
	}
	oldVersion := &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}
	state = r.state
	state.Revision++
	r.publish(state)
	stale := r.control(appRequestControl{Action: "begin", Client: r.client, Owner: r.currentOwner().ID, Dataset: 1, Kind: "maintenance", Trigger: "manual", Key: "old pending native version", Proxy: "DIRECT", Mode: "direct", URL: origin.URL, ExpectedState: oldVersion})
	if _, rejected := stale.(map[string]string); !rejected {
		t.Fatal("native begin accepted the pending operation's old ExpectedState", stale)
	}
}

func TestAppRequestGeoNoHookPreservesRefresh(t *testing.T) {
	begin, owner, active := requestscope.BeginHook, requestscope.OwnerHook, requestscope.OwnerActiveHook
	requestscope.BeginHook, requestscope.OwnerHook, requestscope.OwnerActiveHook = nil, nil, nil
	defer func() {
		requestscope.BeginHook, requestscope.OwnerHook, requestscope.OwnerActiveHook = begin, owner, active
	}()
	home := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(home)
	oldData, _ := os.ReadFile("../assets/data/GEOIP.metadb")
	data, _ := os.ReadFile("../assets/data/ASN.mmdb")
	if err := os.WriteFile(C.Path.MMDB(), oldData, 0600); err != nil {
		t.Fatal(err)
	}
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { _, _ = w.Write(data) }))
	defer origin.Close()
	previous := geodata.MmdbUrl()
	geodata.SetMmdbUrl(origin.URL)
	defer geodata.SetMmdbUrl(previous)
	epoch, _ := routeStamp()
	if err := updater.UpdateGeoResource(context.Background(), "MMDB", nil); err != nil {
		t.Fatal(err)
	}
	next, _ := routeStamp()
	if next != epoch+1 {
		t.Fatal("no-hook Geo lost its existing route refresh", epoch, next)
	}
}
