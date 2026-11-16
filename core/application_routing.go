package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/netip"
	"strconv"
	"strings"

	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	R "github.com/metacubex/mihomo/rules"
	"github.com/metacubex/mihomo/tunnel"
)

type applicationRouteEntry struct {
	GroupID *int64 `json:"groupId,omitempty"`
	Package string `json:"package"`
	Target  string `json:"target"`
}

type applicationHostEntry struct {
	ID      string `json:"id"`
	Package string `json:"package"`
	Type    string `json:"type"`
	Content string `json:"content"`
	Target  string `json:"target"`
	GroupID *int64 `json:"groupId,omitempty"`
}

type applicationRouteSettings struct {
	ProfileID *int64                  `json:"profileId"`
	Version   uint64                  `json:"version"`
	Revision  string                  `json:"revision"`
	Rules     []applicationRouteEntry `json:"rules"`
	HostRules []applicationHostEntry  `json:"hostRules,omitempty"`
}

type applicationRoute struct {
	hostID string
	target string
	rule   C.Rule
}

func validateApplicationRoutes(settings *applicationRouteSettings) error {
	if settings == nil {
		return nil
	}
	if !validInputID(settings.Revision) || len(settings.Rules) > 1024 || len(settings.HostRules) > 2048 {
		return errors.New("invalid application routing settings")
	}
	profile := "-"
	if settings.ProfileID != nil {
		profile = strconv.FormatInt(*settings.ProfileID, 10)
	}
	canonical := profile + "\n" + strconv.FormatUint(settings.Version, 10) + "\n"
	seen := map[string]bool{}
	previous := ""
	for _, entry := range settings.Rules {
		if entry.GroupID != nil && *entry.GroupID < 0 {
			return errors.New("invalid application group")
		}
		if entry.Package == "" || len(entry.Package) > 256 || strings.ContainsAny(entry.Package, ",\x00\r\n\t ") || entry.Target == "" || len(entry.Target) > 256 || strings.ContainsAny(entry.Target, "\x00\r\n") || seen[entry.Package] {
			return errors.New("invalid application routing entry")
		}
		if previous != "" && entry.Package <= previous {
			return errors.New("unsorted application routing entries")
		}
		previous = entry.Package
		id := "-"
		if entry.GroupID != nil {
			id = strconv.FormatInt(*entry.GroupID, 10)
		}
		canonical += entry.Package + "\x00" + entry.Target + "\x00" + id + "\n"
		seen[entry.Package] = true
	}
	if len(settings.HostRules) != 0 {
		canonical += "host-rules\n"
	}
	previous = ""
	seen = map[string]bool{}
	for _, entry := range settings.HostRules {
		id, err := strconv.ParseInt(entry.ID, 10, 64)
		key, hostErr := applicationHostKey(entry.Type, entry.Content)
		if err != nil || id <= 0 || strconv.FormatInt(id, 10) != entry.ID || hostErr != nil ||
			previous != "" && entry.ID <= previous ||
			len(entry.Package) > 256 || strings.ContainsAny(entry.Package, ",\x00\r\n\t ") ||
			entry.Target == "" || len(entry.Target) > 256 || strings.ContainsAny(entry.Target, "\x00\r\n") ||
			entry.GroupID != nil && *entry.GroupID < 0 || seen[entry.Package+"\x00"+key] {
			return errors.New("invalid application host rule")
		}
		previous = entry.ID
		seen[entry.Package+"\x00"+key] = true
		canonical += applicationHostCanonical(entry) + "\n"
	}

	if inputHash([]byte(canonical)) != settings.Revision {
		return errors.New("application routing revision mismatch")
	}
	return nil
}

func applicationHostCanonical(entry applicationHostEntry) string {
	group := "-"
	if entry.GroupID != nil {
		group = strconv.FormatInt(*entry.GroupID, 10)
	}
	return entry.ID + "\x00" + entry.Package + "\x00" + entry.Type + "\x00" + entry.Content + "\x00" + entry.Target + "\x00" + group
}

func applicationHostKey(kind, content string) (string, error) {
	if kind == "DOMAIN" && len(content) > 0 && len(content) <= 253 && !strings.ContainsAny(content, ",\x00\r\n\t /:\\") {
		return "domain:" + strings.TrimSuffix(strings.ToLower(content), "."), nil
	}
	if kind == "IP-CIDR" || kind == "IP-CIDR6" {
		prefix, err := netip.ParsePrefix(content)
		if err == nil && prefix.Bits() == prefix.Addr().BitLen() && (kind == "IP-CIDR") == prefix.Addr().Is4() {
			return "ip:" + prefix.Addr().Unmap().String(), nil
		}
	}
	return "", errors.New("invalid host condition")
}

func applicationHostRoutesFor(manifest ConfigManifest) map[string]map[string]applicationRoute {
	var settings applicationRouteSettings
	if json.Unmarshal(manifest.AcceptedOverrides["application-routing"], &settings) != nil || validateApplicationRoutes(&settings) != nil {
		return nil
	}
	result := map[string]map[string]applicationRoute{}
	for _, entry := range settings.HostRules {
		target := entry.Target
		if entry.GroupID != nil {
			target = "REJECT"
			for _, group := range manifest.LocalGroups {
				if group.ID == *entry.GroupID && group.Enabled && len(group.members()) > 0 {
					target = group.Name
					break
				}
			}
		}
		rule, err := R.ParseRule(entry.Type, entry.Content, target, nil, nil)
		key, _ := applicationHostKey(entry.Type, entry.Content)
		if err != nil {
			continue
		}
		if result[entry.Package] == nil {
			result[entry.Package] = map[string]applicationRoute{}
		}
		result[entry.Package][key] = applicationRoute{hostID: entry.ID, target: target, rule: rule}
	}
	return result
}

func applicationHostMatches(route applicationRoute, metadata *C.Metadata, host string, ip netip.Addr) bool {
	if metadata.RuleHost() == host && metadata.DstIP == ip {
		matched, _ := route.rule.Match(metadata, C.RuleMatchHelper{})
		return matched
	}
	normalized := *metadata
	normalized.Host, normalized.SniffHost, normalized.DstIP = host, "", ip
	matched, _ := route.rule.Match(&normalized, C.RuleMatchHelper{})
	return matched
}

func matchApplicationHost(routes map[string]applicationRoute, metadata *C.Metadata) (applicationRoute, bool) {
	if len(routes) == 0 {
		return applicationRoute{}, false
	}
	host := strings.TrimSuffix(strings.ToLower(metadata.RuleHost()), ".")
	if route, exists := routes["domain:"+host]; exists && applicationHostMatches(route, metadata, host, metadata.DstIP) {
		return route, true
	}
	ip := metadata.DstIP
	if address, err := netip.ParseAddr(host); err == nil {
		ip = address
	}
	if ip.IsValid() {
		ip = ip.Unmap()
		if route, exists := routes["ip:"+ip.String()]; exists && applicationHostMatches(route, metadata, host, ip) {
			return route, true
		}
	}
	return applicationRoute{}, false
}

func applicationRoutesFor(manifest ConfigManifest) (string, map[string]applicationRoute) {
	var settings applicationRouteSettings
	if json.Unmarshal(manifest.AcceptedOverrides["application-routing"], &settings) != nil || validateApplicationRoutes(&settings) != nil {
		return "", nil
	}
	routes := make(map[string]applicationRoute, len(settings.Rules))
	for _, entry := range settings.Rules {
		target := entry.Target
		if entry.GroupID != nil {
			target = "REJECT"
			for _, group := range manifest.LocalGroups {
				if group.ID == *entry.GroupID && group.Enabled && len(group.members()) > 0 {
					target = group.Name
					break
				}
			}
		}
		rule, err := R.ParseRule("PROCESS-NAME", entry.Package, target, nil, nil)
		if err == nil {
			routes[entry.Package] = applicationRoute{target: target, rule: rule}
		}
	}
	return settings.Revision, routes
}

func applicationRuleKeys(settings applicationRouteSettings) map[string]string {
	keys := make(map[string]string, len(settings.Rules))
	for _, entry := range settings.Rules {
		id := "-"
		if entry.GroupID != nil {
			id = strconv.FormatInt(*entry.GroupID, 10)
		}
		keys[entry.Package] = inputHash([]byte(entry.Target + "\x00" + id))
	}
	for _, entry := range settings.HostRules {
		keys["@host:"+entry.ID] = inputHash([]byte(applicationHostCanonical(entry)))
	}
	return keys
}

func (s *connectionObservationStore) routingIdentity(metadata *C.Metadata) applicationIdentity {
	key := connectionIngressKey(metadata)
	s.Lock()
	ingress, exists := s.pending[key]
	valid := exists && time.Since(ingress.time) < time.Minute && sameConnectionIngress(ingress.metadata, metadata)
	s.Unlock()
	if !valid {
		return unknownApplication("notObserved")
	}
	if ingress.identity != nil {
		return *ingress.identity
	}
	if ingress.resolve == nil {
		return unknownApplication("notObserved")
	}
	identity := ingress.resolve(metadata)
	s.Lock()
	if current, ok := s.pending[key]; ok && current.metadata == ingress.metadata && current.time == ingress.time {
		current.identity, current.resolve = &identity, nil
		s.pending[key] = current
	}
	s.Unlock()
	return identity
}

func resolveApplicationRoute(_ context.Context, lease requestscope.Lease, metadata *C.Metadata) (C.Rule, string, error) {
	p := preparedConfigGate.Load()
	if p == nil || lease != p.scope || metadata.Type == C.INNER {
		return nil, "", nil
	}
	state := p.sourceTrace.Load()
	if state == nil || len(state.applicationRoutes) == 0 && len(state.applicationHostRoutes) == 0 {
		return nil, "", nil
	}
	if state.busy || lease.Check() != nil {
		return nil, "", requestscope.ErrBlocked
	}

	var selected applicationRoute
	scoped := len(state.applicationRoutes) != 0 || len(state.applicationHostRoutes) > 1 || len(state.applicationHostRoutes) == 1 && state.applicationHostRoutes[""] == nil
	if scoped {
		identity := connectionObservations.routingIdentity(metadata)
		if (identity.Status == "known" || identity.Status == "ambiguous") && identity.UID != nil && identity.UserScope == "current" && len(identity.Packages) != 0 {
			consistent := true
			for _, name := range identity.Packages {
				candidate, ok := matchApplicationHost(state.applicationHostRoutes[name], metadata)
				if !ok {
					candidate, ok = state.applicationRoutes[name]
				}
				if !ok || selected.target != "" && selected.target != candidate.target {
					consistent = false
					break
				}
				selected = candidate
			}
			if !consistent {
				selected = applicationRoute{}
			}
		}
	}
	if selected.target == "" && tunnel.Mode() == tunnel.Rule {
		selected, _ = matchApplicationHost(state.applicationHostRoutes[""], metadata)
	}
	if selected.target == "" {
		return nil, "", nil
	}

	if lease.Check() != nil || p.sourceTrace.Load() != state {
		return nil, "", requestscope.ErrBlocked
	}
	target := selected.target
	if _, exists := tunnel.AllProxies()[target]; !exists {
		target = "REJECT"
		kind := "PROCESS-NAME"
		switch selected.rule.RuleType() {
		case C.Domain:
			kind = "DOMAIN"
		case C.IPCIDR:
			kind = "IP-CIDR"
		}
		selected.rule, _ = R.ParseRule(kind, selected.rule.Payload(), target, nil, nil)
	}
	sourceRuleTraces.Lock()
	sweepSourceRuleTracesLocked(time.Now())
	if sourceTracePendingRoomLocked(metadata) {
		sourceRuleTraces.pending[metadata] = &sourceTraceFrame{
			parent: p, state: state, index: -1, time: time.Now(),
			origin:   SourceRuleOrigin{Origin: "application-rules", Revision: state.applicationRevision},
			ruleType: selected.rule.RuleType().String(), payload: selected.rule.Payload(), target: target,
		}
	}
	sourceRuleTraces.Unlock()
	return selected.rule, target, nil
}
