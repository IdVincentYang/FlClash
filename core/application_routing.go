package main

import (
	"context"
	"encoding/json"
	"errors"
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

type applicationRouteSettings struct {
	ProfileID *int64                  `json:"profileId"`
	Version   uint64                  `json:"version"`
	Revision  string                  `json:"revision"`
	Rules     []applicationRouteEntry `json:"rules"`
}

type applicationRoute struct {
	target string
	rule   C.Rule
}

func validateApplicationRoutes(settings *applicationRouteSettings) error {
	if settings == nil {
		return nil
	}
	if !validInputID(settings.Revision) || len(settings.Rules) > 1024 {
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
	if inputHash([]byte(canonical)) != settings.Revision {
		return errors.New("application routing revision mismatch")
	}
	return nil
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
	if state == nil || len(state.applicationRoutes) == 0 {
		return nil, "", nil
	}
	if state.busy || lease.Check() != nil {
		return nil, "", requestscope.ErrBlocked
	}
	identity := connectionObservations.routingIdentity(metadata)
	if identity.Status != "known" && identity.Status != "ambiguous" || identity.UID == nil || identity.UserScope != "current" || len(identity.Packages) == 0 {
		return nil, "", nil
	}
	var selected applicationRoute
	for _, name := range identity.Packages {
		candidate, ok := state.applicationRoutes[name]
		if !ok || selected.target != "" && selected.target != candidate.target {
			return nil, "", nil
		}
		selected = candidate
	}
	if lease.Check() != nil || p.sourceTrace.Load() != state {
		return nil, "", requestscope.ErrBlocked
	}
	target := selected.target
	if _, exists := tunnel.AllProxies()[target]; !exists {
		target = "REJECT"
		selected.rule, _ = R.ParseRule("PROCESS-NAME", identity.Packages[0], target, nil, nil)
	}
	sourceRuleTraces.Lock()
	if len(sourceRuleTraces.pending) < 2048 {
		sourceRuleTraces.pending[metadata] = &sourceTraceFrame{
			parent: p, state: state, index: -1, time: time.Now(),
			origin:   SourceRuleOrigin{Origin: "application-rules", Revision: state.applicationRevision},
			ruleType: selected.rule.RuleType().String(), payload: selected.rule.Payload(), target: target,
		}
	}
	sourceRuleTraces.Unlock()
	return selected.rule, target, nil
}
