package main

import (
	"errors"
	"io"
	"maps"
	"slices"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

type sourceInlineGeneration struct {
	proxies             []C.Proxy
	providers           []P.Provider
	input, materialHash string
}

type sourceInlineGraph struct {
	proxies        map[string]C.Proxy
	providers      map[string]P.ProxyProvider
	ownedProxies   []C.Proxy
	ownedProviders []P.Provider
	retired        sourceInlineGeneration
	tasks          []func()
	names          []string
	changed        bool
}

func (g *sourceInlineGraph) close() {
	for _, p := range g.ownedProviders {
		if closer, valid := p.(io.Closer); valid {
			_ = closer.Close()
		}
	}
	for _, p := range g.ownedProxies {
		_ = p.Close()
	}
}

type sourceProviderView struct {
	P.ProxyProvider
	tasks *[]func()
}

func (v *sourceProviderView) RegisterHealthCheckTask(url string, status utils.IntRanges[uint16], filter string, interval uint) {
	*v.tasks = append(*v.tasks, func() { v.ProxyProvider.RegisterHealthCheckTask(url, status, filter, interval) })
}

func sourceNamedMappings(mappings []map[string]any) (map[string]map[string]any, error) {
	result := map[string]map[string]any{}
	for _, mapping := range mappings {
		name, valid := mapping["name"].(string)
		if !valid || name == "" || result[name] != nil {
			return nil, errSourceReview
		}
		result[name] = mapping
	}
	return result, nil
}

func prepareSourceInlineGraph(p *preparedConfig, old, next *config.RawConfig) (_ *sourceInlineGraph, failure error) {
	g := &sourceInlineGraph{proxies: maps.Clone(p.cfg.Proxies), providers: maps.Clone(p.cfg.Providers)}
	views := map[string]P.ProxyProvider{}
	prepared := false
	defer func() {
		if !prepared {
			for _, pd := range views {
				if _, existing := pd.(*sourceProviderView); !existing {
					if closer, valid := pd.(io.Closer); valid {
						_ = closer.Close()
					}
				}
			}
			g.close()
		}
	}()
	beforeNodes, err := sourceNamedMappings(old.Proxy)
	if err != nil {
		return nil, err
	}
	afterNodes, err := sourceNamedMappings(next.Proxy)
	if err != nil {
		return nil, err
	}
	beforeGroups, err := sourceNamedMappings(old.ProxyGroup)
	if err != nil {
		return nil, err
	}
	afterGroups, err := sourceNamedMappings(next.ProxyGroup)
	if err != nil {
		return nil, err
	}
	if beforeGroups["GLOBAL"] != nil || afterGroups["GLOBAL"] != nil {
		return nil, errSourceForeground
	}
	for name := range afterGroups {
		if afterNodes[name] != nil || beforeGroups[name] == nil && g.proxies[name] != nil {
			return nil, errSourceReview
		}
	}
	dirty := map[string]bool{}
	for name, mapping := range beforeNodes {
		if sourceValueHash(mapping) != sourceValueHash(afterNodes[name]) {
			dirty[name] = true
			if previous := g.proxies[name]; previous != nil {
				g.retired.proxies = append(g.retired.proxies, previous)
			}
			delete(g.proxies, name)
		}
	}
	var allNodes []string
	for _, mapping := range next.Proxy {
		name := mapping["name"].(string)
		if name == "GLOBAL" {
			return nil, errSourceReview
		}
		allNodes = append(allNodes, name)
		if sourceValueHash(mapping) == sourceValueHash(beforeNodes[name]) {
			continue
		}
		if g.proxies[name] != nil {
			return nil, errSourceReview
		}
		proxy, err := adapter.ParseProxy(mapping, adapter.WithTunnelForAPI(tunnel.Tunnel), adapter.WithRequestOwner(requestscope.Owner{ID: p.receipt.Owner}))
		if err != nil {
			return nil, err
		}
		g.ownedProxies = append(g.ownedProxies, proxy)
		g.proxies[name], dirty[name] = proxy, true
	}
	nodesChanged := len(dirty) > 0
	for name, mapping := range beforeGroups {
		if sourceValueHash(mapping) != sourceValueHash(afterGroups[name]) {
			dirty[name] = true
		}
	}
	for name, mapping := range afterGroups {
		if sourceValueHash(mapping) != sourceValueHash(beforeGroups[name]) {
			dirty[name] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for name, mapping := range afterGroups {
			if dirty[name] {
				continue
			}
			members, valid := sourceStrings(mapping["proxies"])
			if !valid {
				return nil, errSourceReview
			}
			depends := slices.ContainsFunc(members, func(member string) bool { return dirty[member] })
			fallback, _ := mapping["empty-fallback"].(string)
			if depends || dirty[fallback] || nodesChanged && (mapping["include-all"] == true || mapping["include-all-proxies"] == true) {
				dirty[name], changed = true, true
			}
		}
	}
	for name := range beforeGroups {
		if !dirty[name] {
			continue
		}
		if previous := g.proxies[name]; previous != nil {
			g.retired.proxies = append(g.retired.proxies, previous)
		}
		delete(g.proxies, name)
		if previous := g.providers[name]; previous != nil && previous.VehicleType() == P.Compatible {
			g.retired.providers = append(g.retired.providers, previous)
			delete(g.providers, name)
		}
	}
	for name, pd := range g.providers {
		views[name] = &sourceProviderView{ProxyProvider: pd, tasks: &g.tasks}
	}
	allProviders := make([]string, 0, len(next.ProxyProvider))
	for name := range next.ProxyProvider {
		allProviders = append(allProviders, name)
	}
	slices.Sort(allProviders)
	slices.Sort(allNodes)
	remaining := map[string]bool{}
	for name := range afterGroups {
		if dirty[name] {
			remaining[name] = true
		}
	}
	for len(remaining) > 0 {
		progress := false
		for _, mapping := range next.ProxyGroup {
			name := mapping["name"].(string)
			if !remaining[name] {
				continue
			}
			members, _ := sourceStrings(mapping["proxies"])
			if slices.ContainsFunc(members, func(member string) bool { return remaining[member] }) {
				continue
			}
			group, err := outboundgroup.ParseProxyGroup(mapping, g.proxies, views, allNodes, allProviders)
			if err != nil {
				return nil, err
			}
			proxy := adapter.NewProxy(group, requestscope.Owner{ID: p.receipt.Owner})
			g.ownedProxies = append(g.ownedProxies, proxy)
			if oldGroup, valid := p.cfg.Proxies[name]; valid {
				if previous, valid := oldGroup.Adapter().(outboundgroup.ProxyGroup); valid {
					if selectable, valid := group.(outboundgroup.SelectAble); valid && group.Type() == C.Selector {
						_ = selectable.Set(previous.Now())
					}
				}
			}
			if candidates := group.Proxies(); len(candidates) == 1 && candidates[0].Name() == "COMPATIBLE" {
				return nil, errors.New("inline group has an implicit direct fallback")
			}
			g.proxies[name] = proxy
			if pd := views[name]; pd != nil && pd.VehicleType() == P.Compatible {
				g.providers[name] = pd
				g.ownedProviders = append(g.ownedProviders, pd)
			}
			delete(remaining, name)
			progress = true
		}
		if !progress {
			return nil, errSourceReview
		}
	}
	g.changed = len(dirty) > 0 || sourceValueHash(old.Proxy) != sourceValueHash(next.Proxy) || sourceValueHash(old.ProxyGroup) != sourceValueHash(next.ProxyGroup)
	ruleSets := [][]C.Rule{p.cfg.Rules}
	for _, rules := range p.cfg.SubRules {
		ruleSets = append(ruleSets, rules)
	}
	for _, rules := range ruleSets {
		for _, rule := range rules {
			if target := rule.Adapter(); target != "" && g.proxies[target] == nil {
				return nil, errors.New("inline update removes a rule target")
			}
		}
	}
	if !g.changed {
		prepared = true
		return g, nil
	}
	g.names = []string{"DIRECT", "REJECT"}
	for _, mapping := range next.Proxy {
		g.names = append(g.names, mapping["name"].(string))
	}
	for _, mapping := range next.ProxyGroup {
		g.names = append(g.names, mapping["name"].(string))
	}
	var defaults []C.Proxy
	for _, name := range g.names {
		if proxy := g.proxies[name]; proxy != nil && proxy.Type() != C.Pass && proxy.Type() != C.PassRule {
			defaults = append(defaults, proxy)
		}
	}
	health := provider.NewHealthCheck(defaults, "", 5000, 0, true, nil)
	defaultProvider, err := provider.NewCompatibleProvider(provider.ReservedName, defaults, health)
	if err != nil {
		return nil, err
	}
	g.ownedProviders = append(g.ownedProviders, defaultProvider)
	if previous := p.cfg.Providers[provider.ReservedName]; previous != nil {
		g.retired.providers = append(g.retired.providers, previous)
	}
	g.providers[provider.ReservedName] = defaultProvider
	if afterGroups["GLOBAL"] == nil {
		global, err := outboundgroup.NewSelector(outboundgroup.GroupCommonOption{Name: "GLOBAL"}, outboundgroup.SelectorOption{}, g.proxies["COMPATIBLE"], []P.ProxyProvider{defaultProvider})
		if err != nil {
			return nil, err
		}
		if previous, valid := p.cfg.Proxies["GLOBAL"].Adapter().(outboundgroup.ProxyGroup); valid {
			_ = global.Set(previous.Now())
		}
		g.retired.proxies = append(g.retired.proxies, p.cfg.Proxies["GLOBAL"])
		proxy := adapter.NewProxy(global, requestscope.Owner{ID: p.receipt.Owner})
		g.proxies["GLOBAL"] = proxy
		g.ownedProxies = append(g.ownedProxies, proxy)
	}
	prepared = true
	return g, nil
}
