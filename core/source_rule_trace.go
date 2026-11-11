package main

import (
	"slices"
	"strings"
	"sync"
	"time"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type SourceRuleOrigin struct {
	Start       int      `json:"start"`
	End         int      `json:"end"`
	Origin      string   `json:"origin,omitempty"`
	Revision    string   `json:"revision,omitempty"`
	Candidates  []string `json:"candidates,omitempty"`
	RulesDigest string   `json:"rulesDigest"`
}

type SourceRuleLedger struct {
	Version int                           `json:"version"`
	Lists   map[string][]SourceRuleOrigin `json:"lists"`
}

func sourceRulesDigest(lines []string) string {
	hashes := make([]string, len(lines))
	for i, line := range lines {
		hashes[i] = inputHash([]byte(line))
	}
	return inputHash([]byte(strings.Join(hashes, "")))
}

func validateSourceRuleLedger(manifest ConfigManifest, rules []string, subRules map[string][]string) error {
	ledger := manifest.RuleLedger
	if ledger == nil {
		return nil
	}
	if ledger.Version != 1 || len(ledger.Lists) > sourceEntityLimit {
		return errSourceReview
	}
	lists := map[string][]string{"rules": rules}
	for name, lines := range subRules {
		lists["sub-rules:"+name] = lines
	}
	for name, ranges := range ledger.Lists {
		lines, exists := lists[name]
		if !exists || len(ranges) > sourceEntityLimit {
			return errSourceReview
		}
		end := 0
		for _, origin := range ranges {
			if origin.Start < end || origin.End <= origin.Start || origin.End > len(lines) || origin.RulesDigest != sourceRulesDigest(lines[origin.Start:origin.End]) || len(origin.Candidates) > 8 {
				return errSourceReview
			}
			if origin.Origin != "" {
				bound := slices.ContainsFunc(manifest.SourceUses, func(use SourceUse) bool { return use.Key == origin.Origin && use.Digest == origin.Revision })
				local := strings.HasPrefix(origin.Origin, "override:") || strings.HasPrefix(origin.Origin, "policy:") || origin.Origin == "application-rules"
				if !bound && (!local || !validInputID(origin.Revision)) {
					return errSourceReview
				}
			}
			for _, candidate := range origin.Candidates {
				if !slices.ContainsFunc(manifest.SourceUses, func(use SourceUse) bool { return use.Key == candidate }) {
					return errSourceReview
				}
			}
			end = origin.End
		}
	}
	return nil
}

type sourceRuleSetRevision struct {
	Name     string `json:"name"`
	Revision string `json:"revision"`
}

type sourceRuleProvenance struct {
	Label           string                  `json:"label,omitempty"`
	Known           bool                    `json:"known"`
	Origin          string                  `json:"origin,omitempty"`
	Revision        string                  `json:"revision,omitempty"`
	Candidates      []string                `json:"candidates,omitempty"`
	AppliedRevision string                  `json:"appliedRevision,omitempty"`
	RuleSet         []sourceRuleSetRevision `json:"ruleSets,omitempty"`
	Index           int                     `json:"index"`
}

type sourceTraceState struct {
	profileName              string
	origins                  []SourceRuleOrigin
	routeEpoch, picksVersion uint64
	input                    string
	busy                     bool
	materials                map[string]string
}

type sourceTraceFrame struct {
	parent                    *preparedConfig
	state                     *sourceTraceState
	provider                  map[string]string
	sets                      []sourceRuleSetRevision
	origin                    SourceRuleOrigin
	index                     int
	ruleType, payload, target string
	time                      time.Time
}

var sourceRuleTraces = struct {
	sync.Mutex
	active  map[*C.Metadata]*sourceTraceFrame
	pending map[*C.Metadata]*sourceTraceFrame
	frozen  map[string]sourceRuleProvenance
	order   []string
}{active: map[*C.Metadata]*sourceTraceFrame{}, pending: map[*C.Metadata]*sourceTraceFrame{}, frozen: map[string]sourceRuleProvenance{}}

type sourceTracedRule struct {
	C.RuleWrapper
	parent *preparedConfig
	origin SourceRuleOrigin
	index  int
}

func (r *sourceTracedRule) Match(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
	frame := &sourceTraceFrame{parent: r.parent, state: r.parent.sourceTrace.Load(), provider: map[string]string{}, origin: r.origin, index: r.index, time: time.Now()}
	if frame.state != nil && r.index < len(frame.state.origins) {
		frame.origin = frame.state.origins[r.index]
	}
	epoch, picks := routeStamp()
	if frame.state != nil && (frame.state.routeEpoch != epoch || frame.state.picksVersion != picks) {
		frame.state = nil
	}
	sourceRuleTraces.Lock()
	for key, pending := range sourceRuleTraces.pending {
		if frame.time.Sub(pending.time) > time.Minute {
			delete(sourceRuleTraces.pending, key)
		}
	}
	for key, active := range sourceRuleTraces.active {
		if frame.time.Sub(active.time) > time.Minute {
			delete(sourceRuleTraces.active, key)
		}
	}
	if len(sourceRuleTraces.active) >= 2048 || len(sourceRuleTraces.pending) >= 2048 {
		delete(sourceRuleTraces.pending, metadata)
		delete(sourceRuleTraces.active, metadata)
		sourceRuleTraces.Unlock()
		return r.RuleWrapper.Match(metadata, helper)
	}
	sourceRuleTraces.active[metadata] = frame
	sourceRuleTraces.Unlock()
	complete := false
	defer func() {
		if complete {
			return
		}
		sourceRuleTraces.Lock()
		if sourceRuleTraces.active[metadata] == frame {
			delete(sourceRuleTraces.active, metadata)
			delete(sourceRuleTraces.pending, metadata)
		}
		sourceRuleTraces.Unlock()
	}()
	matched, target := r.RuleWrapper.Match(metadata, helper)
	complete = true
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	if sourceRuleTraces.active[metadata] != frame {
		delete(sourceRuleTraces.pending, metadata)
		return matched, target
	}
	delete(sourceRuleTraces.active, metadata)
	if matched {
		if r.RuleType() == C.SubRules || strings.Contains(strings.ToUpper(r.Payload()), "SUB-RULE,") {
			frame.origin = SourceRuleOrigin{}
			frame.sets, frame.provider = nil, nil
		}
		frame.ruleType, frame.payload, frame.target = r.RuleType().String(), r.Payload(), target
		if r.parent.sourceTrace.Load() != frame.state {
			frame.state = nil
		}
		sourceRuleTraces.pending[metadata] = frame
	}
	return matched, target
}

func recordSourceRuleSetMatch(p *preparedConfig, name string, generation *sourceRuleGeneration, metadata *C.Metadata, matched bool) {
	if !matched {
		return
	}
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	frame := sourceRuleTraces.active[metadata]
	if frame == nil || len(frame.sets) >= 16 {
		return
	}
	if frame.parent != p {
		frame.state = nil
		return
	}
	frame.provider[generation.use.Key] = generation.digest
	if strings.Contains(name, "://") || len(name) > 128 {
		name = ""
	}
	frame.sets = append(frame.sets, sourceRuleSetRevision{Name: name, Revision: generation.digest})
}

func publishSourceTraceState(p *preparedConfig, id string, busy bool) {
	state := &sourceTraceState{input: id, busy: busy, profileName: p.manifest.ProfileName, materials: map[string]string{}}
	state.routeEpoch, state.picksVersion = routeStamp()
	if p.cfg != nil {
		state.origins = make([]SourceRuleOrigin, len(p.cfg.Rules))
		if p.manifest.RuleLedger != nil {
			for _, origin := range p.manifest.RuleLedger.Lists["rules"] {
				for i := origin.Start; i < origin.End && i < len(state.origins); i++ {
					state.origins[i] = origin
				}
			}
		}
	}
	for _, material := range p.manifest.ProviderMaterials {
		state.materials[material.Use.Key] = material.MaterialHash
	}
	p.sourceTrace.Store(state)
}

func installSourceRuleTracing(p *preparedConfig) {
	if p.manifest.Version != 2 {
		return
	}
	publishSourceTraceState(p, p.receipt.InputID, false)
	p.cfg.Rules = sourceTracedRules(p, p.cfg.Rules, p.manifest.RuleLedger)
	for _, runtime := range p.sourceProviders {
		if runtime.rule == nil {
			continue
		}
		name := runtime.plan.Name
		runtime.rule.matched = func(generation *sourceRuleGeneration, metadata *C.Metadata, matched bool) {
			recordSourceRuleSetMatch(p, name, generation, metadata, matched)
		}
	}
}

func sourceTracedRules(p *preparedConfig, rules []C.Rule, ledger *SourceRuleLedger) []C.Rule {
	result := slices.Clone(rules)
	for i, rule := range result {
		wrapped, valid := rule.(C.RuleWrapper)
		if !valid {
			continue
		}
		var origin SourceRuleOrigin
		if ledger != nil {
			for _, candidate := range ledger.Lists["rules"] {
				if i >= candidate.Start && i < candidate.End {
					origin = candidate
					break
				}
			}
		}
		result[i] = &sourceTracedRule{RuleWrapper: wrapped, parent: p, origin: origin, index: i}
	}
	return result
}

func bindSourceTracker(info *statistic.TrackerInfo) sourceRuleProvenance {
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	id := info.UUID.String()
	if frozen, exists := sourceRuleTraces.frozen[id]; exists {
		return frozen
	}
	value := sourceRuleProvenance{Index: -1}
	if frame := sourceRuleTraces.pending[info.Metadata]; frame != nil {
		delete(sourceRuleTraces.pending, info.Metadata)
		if time.Since(frame.time) <= time.Minute && info.Rule == frame.ruleType && info.RulePayload == frame.payload && slices.Contains(info.Chain, frame.target) {
			value.Index, value.Candidates, value.RuleSet = frame.index, slices.Clone(frame.origin.Candidates), slices.Clone(frame.sets)
			if frame.state != nil && !frame.state.busy {
				consistent := true
				for key, hash := range frame.provider {
					if frame.state.materials[key] != hash {
						consistent = false
					}
				}
				if consistent {
					if strings.HasPrefix(frame.origin.Origin, "profile:") {
						value.Label = frame.state.profileName
					}
					value.AppliedRevision = frame.state.input
					value.Origin, value.Revision = frame.origin.Origin, frame.origin.Revision
					value.Known = value.Origin != ""
				}
			}
		}
	}
	if len(sourceRuleTraces.order) >= 4096 {
		delete(sourceRuleTraces.frozen, sourceRuleTraces.order[0])
		sourceRuleTraces.order = sourceRuleTraces.order[1:]
	}
	sourceRuleTraces.order = append(sourceRuleTraces.order, id)
	sourceRuleTraces.frozen[id] = value
	return value
}

type sourceTrackerView struct {
	*statistic.TrackerInfo
	Metadata    *C.Metadata           `json:"metadata"`
	Provenance  sourceRuleProvenance  `json:"provenance"`
	Observation connectionObservation `json:"observation"`
}

func sourceTrackerViewOf(info *statistic.TrackerInfo) sourceTrackerView {
	observed := connectionObservations.view(info)
	return sourceTrackerView{TrackerInfo: info, Metadata: observed.metadata, Provenance: bindSourceTracker(info), Observation: observed.observation}
}

type sourceConnectionSnapshot struct {
	DownloadTotal int64               `json:"downloadTotal"`
	UploadTotal   int64               `json:"uploadTotal"`
	Connections   []sourceTrackerView `json:"connections"`
	Memory        uint64              `json:"memory"`
}

func sourceConnectionView(snapshot *statistic.Snapshot) sourceConnectionSnapshot {
	result := sourceConnectionSnapshot{DownloadTotal: snapshot.DownloadTotal, UploadTotal: snapshot.UploadTotal, Memory: snapshot.Memory, Connections: []sourceTrackerView{}}
	for _, info := range snapshot.Connections {
		result.Connections = append(result.Connections, sourceTrackerViewOf(info))
	}
	return result
}
