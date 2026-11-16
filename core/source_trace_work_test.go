package main

import (
	"fmt"
	"sync"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
	R "github.com/metacubex/mihomo/rules"
	RW "github.com/metacubex/mihomo/rules/wrapper"
)

type traceProbeRule struct {
	C.RuleWrapper
	match func(*C.Metadata, C.RuleMatchHelper) (bool, string)
}

func (r traceProbeRule) Match(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
	return r.match(metadata, helper)
}

func traceWorkFixture(t testing.TB) *preparedConfig {
	t.Helper()
	sourceRuleTraces.Lock()
	active, pending, frozen, order := sourceRuleTraces.active, sourceRuleTraces.pending, sourceRuleTraces.frozen, sourceRuleTraces.order
	sourceRuleTraces.active, sourceRuleTraces.pending = map[*C.Metadata]*sourceTraceFrame{}, map[*C.Metadata]*sourceTraceFrame{}
	sourceRuleTraces.frozen, sourceRuleTraces.order = map[string]sourceRuleProvenance{}, nil
	sourceRuleTraces.Unlock()
	t.Cleanup(func() {
		sourceRuleTraces.Lock()
		sourceRuleTraces.active, sourceRuleTraces.pending = active, pending
		sourceRuleTraces.frozen, sourceRuleTraces.order = frozen, order
		sourceRuleTraces.Unlock()
	})
	epoch, picks := routeStamp()
	p := &preparedConfig{}
	p.sourceTrace.Store(&sourceTraceState{input: "controlled-input", routeEpoch: epoch, picksVersion: picks,
		origins: []SourceRuleOrigin{{Origin: "profile:7", Revision: "controlled-revision"}}, materials: map[string]string{"provider:controlled": "material"}})
	return p
}

func traceWrapped(t testing.TB, p *preparedConfig, kind, payload string, probe func(C.RuleWrapper) C.RuleWrapper) C.RuleWrapper {
	t.Helper()
	raw, err := R.ParseRule(kind, payload, "DIRECT", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	wrapped := RW.NewRuleWrapper(raw)
	if probe != nil {
		wrapped = probe(wrapped)
	}
	return sourceTracedRules(p, []C.Rule{wrapped}, nil)[0].(C.RuleWrapper)
}

func fillTraceWork(count int, expired bool) {
	stamp := time.Now()
	if expired {
		stamp = stamp.Add(-2 * time.Minute)
	}
	for i := 0; i < count; i++ {
		sourceRuleTraces.pending[&C.Metadata{}] = &sourceTraceFrame{time: stamp}
	}
}

func TestSourceTraceProviderStorageIsLazy(t *testing.T) {
	p := traceWorkFixture(t)
	info := observationTracker(48001, C.TCP)
	rule := traceWrapped(t, p, "MATCH", "", func(base C.RuleWrapper) C.RuleWrapper {
		return traceProbeRule{RuleWrapper: base, match: func(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
			sourceRuleTraces.Lock()
			frame := sourceRuleTraces.active[metadata]
			if frame == nil || frame.provider != nil {
				t.Error("provider storage was allocated before a provider matched")
			}
			sourceRuleTraces.Unlock()
			generation := &sourceRuleGeneration{use: SourceUse{Key: "provider:controlled"}, digest: "material"}
			recordSourceRuleSetMatch(p, "controlled", generation, metadata, false)
			for i := 0; i < 20; i++ {
				recordSourceRuleSetMatch(p, "controlled", generation, metadata, true)
			}
			return base.Match(metadata, helper)
		}}
	})
	if ok, target := rule.Match(info.Metadata, C.RuleMatchHelper{}); !ok || target != "DIRECT" {
		t.Fatal("underlying rule changed")
	}
	provenance := bindSourceTracker(info)
	if !provenance.Known || provenance.AppliedRevision != "controlled-input" || len(provenance.RuleSet) != 16 {
		t.Fatal("lazy storage lost proven provider matches or its bound", provenance)
	}
}

func TestSourceTracePendingCompletionLimit(t *testing.T) {
	p := traceWorkFixture(t)
	sourceRuleTraces.Lock()
	fillTraceWork(2047, false)
	sourceRuleTraces.Unlock()
	entered, results := make(chan bool, 2), make(chan bool, 2)
	release := make(chan struct{})
	var once sync.Once
	rule := traceWrapped(t, p, "MATCH", "", func(base C.RuleWrapper) C.RuleWrapper {
		return traceProbeRule{RuleWrapper: base, match: func(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
			sourceRuleTraces.Lock()
			entered <- sourceRuleTraces.active[metadata] != nil
			sourceRuleTraces.Unlock()
			<-release
			return base.Match(metadata, helper)
		}}
	})
	var workers sync.WaitGroup
	defer func() { once.Do(func() { close(release) }); workers.Wait() }()
	for i := 0; i < 2; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			ok, target := rule.Match(&C.Metadata{}, C.RuleMatchHelper{})
			results <- ok && target == "DIRECT"
		}()
	}
	for i := 0; i < 2; i++ {
		select {
		case admitted := <-entered:
			if !admitted {
				t.Fatal("fixture did not admit both concurrent matches")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("concurrent admission gate was not reached")
		}
	}
	once.Do(func() { close(release) })
	for i := 0; i < 2; i++ {
		select {
		case ok := <-results:
			if !ok {
				t.Error("capacity changed the underlying match")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("concurrent completion did not finish")
		}
	}
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	if len(sourceRuleTraces.pending) != 2048 || len(sourceRuleTraces.active) != 0 {
		t.Errorf("pending=%d active=%d after two admitted matches", len(sourceRuleTraces.pending), len(sourceRuleTraces.active))
	}
}

func TestSourceTraceWorkLifecycle(t *testing.T) {
	for _, scenario := range []string{"miss", "panic", "reentry", "provider-parent", "provider-digest"} {
		t.Run(scenario, func(t *testing.T) {
			p := traceWorkFixture(t)
			info := observationTracker(48002, C.TCP)
			kind, payload := "MATCH", ""
			if scenario == "miss" {
				kind, payload = "DOMAIN", "never.test"
			}
			rule := traceWrapped(t, p, kind, payload, func(base C.RuleWrapper) C.RuleWrapper {
				return traceProbeRule{RuleWrapper: base, match: func(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
					switch scenario {
					case "panic":
						panic("controlled matcher panic")
					case "reentry":
						inner := traceWrapped(t, p, "MATCH", "", nil)
						inner.Match(metadata, helper)
					case "provider-parent", "provider-digest":
						parent := p
						digest := "wrong-material"
						if scenario == "provider-parent" {
							parent = &preparedConfig{}
							digest = "material"
						}
						recordSourceRuleSetMatch(parent, "controlled", &sourceRuleGeneration{use: SourceUse{Key: "provider:controlled"}, digest: digest}, metadata, true)
					}
					return base.Match(metadata, helper)
				}}
			})
			panicked := false
			func() {
				defer func() {
					if value := recover(); value != nil {
						panicked = true
						if value != "controlled matcher panic" {
							t.Error("unexpected panic", value)
						}
					}
				}()
				rule.Match(info.Metadata, C.RuleMatchHelper{})
			}()
			if panicked != (scenario == "panic") {
				t.Error("panic was swallowed or invented")
			}
			if provenance := bindSourceTracker(info); provenance.Known || provenance.AppliedRevision != "" {
				t.Error("unproven work acquired a source", provenance)
			}
			sourceRuleTraces.Lock()
			defer sourceRuleTraces.Unlock()
			if len(sourceRuleTraces.active) != 0 || len(sourceRuleTraces.pending) != 0 {
				t.Error("work outlived miss, panic, reentry or bind")
			}
		})
	}
}

func TestSourceTraceWrapperConsumers(t *testing.T) {
	p := traceWorkFixture(t)
	rule := traceWrapped(t, p, "DOMAIN", "accepted.test", nil)
	metadata := &C.Metadata{Host: "accepted.test"}
	rule.SetDisabled(true)
	if !rule.IsDisabled() {
		t.Fatal("disabled wrapper was lost")
	}
	if ok, _ := rule.Match(metadata, C.RuleMatchHelper{}); ok {
		t.Fatal("disabled rule matched")
	}
	rule.SetDisabled(false)
	rule.Match(metadata, C.RuleMatchHelper{})
	metadata.Host = "other.test"
	rule.Match(metadata, C.RuleMatchHelper{})
	if rule.HitCount() != 1 || rule.MissCount() != 1 || rule.Unwrap().Payload() != "accepted.test" {
		t.Fatal("wrapper statistics or Unwrap changed")
	}
}

func TestSourceTraceConcurrentWork(t *testing.T) {
	p := traceWorkFixture(t)
	rule := traceWrapped(t, p, "DOMAIN", "never.test", nil)
	var workers sync.WaitGroup
	for i := 0; i < 32; i++ {
		workers.Add(1)
		go func(i int) {
			defer workers.Done()
			metadata := &C.Metadata{Host: fmt.Sprintf("worker-%d.test", i)}
			for j := 0; j < 100; j++ {
				rule.Match(metadata, C.RuleMatchHelper{})
			}
		}(i)
	}
	workers.Wait()
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	if len(sourceRuleTraces.active) != 0 || len(sourceRuleTraces.pending) != 0 || rule.MissCount() != 3200 {
		t.Fatal("concurrent work leaked or lost matches")
	}
}
