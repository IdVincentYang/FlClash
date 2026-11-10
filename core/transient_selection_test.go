package main

import (
	"encoding/json"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

type transientHealthProxy struct {
	C.Proxy
	alive atomic.Bool
}

func (p *transientHealthProxy) AliveForTestUrl(string) bool { return p.alive.Load() }

func TestTransientAutomaticSelectionFailsOverAndIsNotRestored(t *testing.T) {
	for _, strategy := range []string{"url-test", "fallback"} {
		t.Run(strategy, func(t *testing.T) {
			a, b := &transientHealthProxy{Proxy: namedProxy("a")}, &transientHealthProxy{Proxy: namedProxy("b")}
			a.alive.Store(true)
			b.alive.Store(true)
			pd, err := provider.NewCompatibleProvider("nodes", []C.Proxy{a, b}, provider.NewHealthCheck([]C.Proxy{a, b}, "", 0, 0, true, nil))
			if err != nil {
				t.Fatal(err)
			}
			var group pickableGroup
			if strategy == "url-test" {
				group, err = outboundgroup.NewURLTest(outboundgroup.GroupCommonOption{Name: "Mine"}, outboundgroup.URLTestOption{}, namedProxy("REJECT"), []P.ProxyProvider{pd})
			} else {
				group, err = outboundgroup.NewFallback(outboundgroup.GroupCommonOption{Name: "Mine"}, outboundgroup.FallbackOption{}, namedProxy("REJECT"), []P.ProxyProvider{pd})
			}
			if err != nil {
				t.Fatal(err)
			}
			beforeFact, beforePending, beforeApplied := configFact, pendingConfig, appliedConfig
			configFact.Owner = 777
			configFact.Phase = "ready"
			pendingConfig = nil
			appliedConfig = nil
			proxies, providers := tunnel.Proxies(), tunnel.ProvidersSnapshot()
			tunnel.UpdateProxies(map[string]C.Proxy{"Mine": adapter.NewProxy(group.(outboundgroup.ProxyGroup))}, nil)
			t.Cleanup(func() {
				selectMu.Lock()
				delete(transientSelections, "Mine")
				tunnel.UpdateProxies(proxies, providers)
				configFact, pendingConfig, appliedConfig = beforeFact, beforePending, beforeApplied
				selectMu.Unlock()
			})
			if result := handleChangeProxy(&ChangeProxyParams{GroupName: "Mine", ProxyName: "b", Transient: true, Owner: 777}); result.Message != "" {
				t.Fatal(result)
			}
			selectMu.Lock()
			now := group.Now()
			picks, err := checkpointSelectionsLocked()
			selectMu.Unlock()
			if err != nil || now != "b" {
				t.Fatal(now, err)
			}
			if _, ok := picks["Mine"]; ok {
				t.Fatal("automatic selection was checkpointed", picks)
			}
			patchSelectGroup(map[string]string{"Mine": "a"})
			selectMu.Lock()
			now = group.Now()
			selectMu.Unlock()
			if now != "b" {
				t.Fatal("persistent map overwrote transient choice", now)
			}
			b.alive.Store(false)
			deadline := time.Now().Add(2 * time.Second)
			for {
				selectMu.Lock()
				now = group.Now()
				data, _ := group.(outboundgroup.ProxyGroup).MarshalJSON()
				selectMu.Unlock()
				var state struct {
					Fixed string `json:"fixed"`
				}
				_ = json.Unmarshal(data, &state)
				if now == "a" && state.Fixed == "" {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("did not relinquish failed preference", now, state.Fixed)
				}
				time.Sleep(20 * time.Millisecond)
			}
			b.alive.Store(true)
			selectMu.Lock()
			data, _ := group.(outboundgroup.ProxyGroup).MarshalJSON()
			selectMu.Unlock()
			var state struct {
				Fixed string `json:"fixed"`
			}
			_ = json.Unmarshal(data, &state)
			if state.Fixed != "" {
				t.Fatal("recovered node restored an old manual preference")
			}
		})
	}
}

func TestInactiveSelectorCanChangeWithoutStartingBusiness(t *testing.T) {
	group := selectorGroup(t, "Main", "a", "b")
	oldFact, oldPending, oldApplied := configFact, pendingConfig, appliedConfig
	proxies, providers := tunnel.Proxies(), tunnel.ProvidersSnapshot()
	configFact = ConfigFact{Owner: 777, Token: 12, Phase: "installed", BusinessActive: false}
	pendingConfig = &preparedConfig{}
	appliedConfig = nil
	tunnel.UpdateProxies(map[string]C.Proxy{"Main": group}, nil)
	t.Cleanup(func() {
		configFact, pendingConfig, appliedConfig = oldFact, oldPending, oldApplied
		tunnel.UpdateProxies(proxies, providers)
	})
	result := handleChangeProxy(&ChangeProxyParams{GroupName: "Main", ProxyName: "b", Owner: 777, Token: 12})
	if result.Message != "" || !result.Changed || groupNow(t, group) != "b" || configFact.BusinessActive || configFact.Phase != "installed" {
		t.Fatal(result, configFact)
	}
	configFact.Phase = "parsing"
	result = handleChangeProxy(&ChangeProxyParams{GroupName: "Main", ProxyName: "a", Owner: 777, Token: 12})
	if result.Message == "" || groupNow(t, group) != "b" {
		t.Fatal("selection crossed config preparation", result)
	}
}
