package main

import (
	"context"
	"sync"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func traceClockFixture(t *testing.T) {
	t.Helper()
	sourceRuleTraces.Lock()
	previous := sourceRuleTraces.sweepAt
	sourceRuleTraces.sweepAt = time.Time{}
	sourceRuleTraces.Unlock()
	t.Cleanup(func() {
		sourceRuleTraces.Lock()
		sourceRuleTraces.sweepAt = previous
		sourceRuleTraces.Unlock()
	})
}

func TestSourceTraceSweepWindow(t *testing.T) {
	traceWorkFixture(t)
	traceClockFixture(t)
	now := time.Now()
	expired, fresh, boundary, delayed := &C.Metadata{}, &C.Metadata{}, &C.Metadata{}, &C.Metadata{}
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	for _, table := range []map[*C.Metadata]*sourceTraceFrame{sourceRuleTraces.active, sourceRuleTraces.pending} {
		table[expired] = &sourceTraceFrame{time: now.Add(-2 * time.Minute)}
		table[fresh] = &sourceTraceFrame{time: now}
		table[boundary] = &sourceTraceFrame{time: now.Add(-time.Minute)}
	}
	sweepSourceRuleTracesLocked(now)
	for _, table := range []map[*C.Metadata]*sourceTraceFrame{sourceRuleTraces.active, sourceRuleTraces.pending} {
		if table[expired] != nil || table[fresh] == nil || table[boundary] == nil {
			t.Fatal("sweep changed the original expiration boundary")
		}
		table[delayed] = &sourceTraceFrame{time: now.Add(-2 * time.Minute)}
	}
	for i := 0; i < 100; i++ {
		sweepSourceRuleTracesLocked(now.Add(time.Second - time.Nanosecond))
	}
	if sourceRuleTraces.pending[delayed] == nil || sourceRuleTraces.active[delayed] == nil || !sourceRuleTraces.sweepAt.Equal(now.Add(time.Second)) {
		t.Fatal("maintenance repeated within the same window")
	}
	sweepSourceRuleTracesLocked(now.Add(time.Second))
	if len(sourceRuleTraces.pending) != 1 || len(sourceRuleTraces.active) != 1 || sourceRuleTraces.pending[fresh] == nil || sourceRuleTraces.active[fresh] == nil {
		t.Fatal("next maintenance did not reclaim expired records")
	}
}

func TestSourceTraceExpiredActiveCannotPublish(t *testing.T) {
	p := traceWorkFixture(t)
	traceClockFixture(t)
	info := observationTracker(49000, C.TCP)
	entered := make(chan *sourceTraceFrame, 1)
	release, done := make(chan struct{}), make(chan struct{})
	result := make(chan bool, 1)
	var once sync.Once
	rule := traceWrapped(t, p, "MATCH", "", func(base C.RuleWrapper) C.RuleWrapper {
		return traceProbeRule{RuleWrapper: base, match: func(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
			sourceRuleTraces.Lock()
			entered <- sourceRuleTraces.active[metadata]
			sourceRuleTraces.Unlock()
			<-release
			recordSourceRuleSetMatch(p, "controlled", &sourceRuleGeneration{use: SourceUse{Key: "provider:controlled"}, digest: "material"}, metadata, true)
			return base.Match(metadata, helper)
		}}
	})
	defer func() {
		once.Do(func() { close(release) })
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Error("expired matcher did not finish")
		}
	}()
	go func() {
		defer close(done)
		matched, target := rule.Match(info.Metadata, C.RuleMatchHelper{})
		result <- matched && target == "DIRECT"
	}()
	var frame *sourceTraceFrame
	select {
	case frame = <-entered:
	case <-time.After(5 * time.Second):
		t.Fatal("active matcher gate was not reached")
	}
	if frame == nil {
		t.Fatal("match was not admitted")
	}
	sourceRuleTraces.Lock()
	frame.time = time.Now().Add(-2 * time.Minute)
	sourceRuleTraces.sweepAt = time.Time{}
	sweepSourceRuleTracesLocked(time.Now())
	sourceRuleTraces.Unlock()
	once.Do(func() { close(release) })
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("expired matcher completion timed out")
	}
	if !<-result || frame.provider != nil {
		t.Error("late provider callback changed routing or retained expired work")
	}
	if provenance := bindSourceTracker(info); provenance.Known || provenance.AppliedRevision != "" {
		t.Error("expired active work produced provenance", provenance)
	}
}

func TestSourceTraceFullTableUsesMaintenanceGate(t *testing.T) {
	for _, active := range []bool{false, true} {
		name := "pending"
		if active {
			name = "active"
		}
		t.Run(name, func(t *testing.T) {
			p := traceWorkFixture(t)
			traceClockFixture(t)
			rule := traceWrapped(t, p, "DOMAIN", "never.test", nil)
			metadata := &C.Metadata{Host: "unmatched.test"}
			expired := &C.Metadata{}
			sourceRuleTraces.Lock()
			table := sourceRuleTraces.pending
			if active {
				table = sourceRuleTraces.active
			}
			for i := 0; i < 2047; i++ {
				table[&C.Metadata{}] = &sourceTraceFrame{time: time.Now()}
			}
			table[expired] = &sourceTraceFrame{time: time.Now().Add(-2 * time.Minute)}
			deadline := time.Now().Add(time.Hour)
			sourceRuleTraces.sweepAt = deadline
			sourceRuleTraces.Unlock()
			for i := 0; i < 100; i++ {
				if matched, _ := rule.Match(metadata, C.RuleMatchHelper{}); matched {
					t.Fatal("capacity changed the actual matcher result")
				}
			}
			sourceRuleTraces.Lock()
			if len(table) != 2048 || table[expired] == nil || !sourceRuleTraces.sweepAt.Equal(deadline) {
				t.Error("full table bypassed the maintenance gate")
			}
			sourceRuleTraces.sweepAt = time.Time{}
			sourceRuleTraces.Unlock()
			rule.Match(metadata, C.RuleMatchHelper{})
			sourceRuleTraces.Lock()
			defer sourceRuleTraces.Unlock()
			if len(table) != 2047 || table[expired] != nil {
				t.Error("due maintenance did not restore admission")
			}
		})
	}
}

func TestSourceTraceAppHookMaintenance(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	applyTestInput(t, sourceTraceInput(t, "mode: direct\nfind-process-mode: off\ngeo-auto-update: false\nrules: ['MATCH,DIRECT']\n", nil))
	if err := updateConfig(&UpdateParams{ApplicationRouting: modeAppSettings(false, "DIRECT")}); err != nil {
		t.Fatal(err)
	}
	p := appliedConfig
	traceWorkFixture(t)
	traceClockFixture(t)
	info := observationTracker(49001, C.TCP)
	modeRemember(info.Metadata, connectionConfiguration{Status: "unknown"})
	sourceRuleTraces.Lock()
	fillTraceWork(2048, true)
	sourceRuleTraces.Unlock()
	rule, target, err := resolveApplicationRoute(context.Background(), p.scope, info.Metadata)
	if err != nil || rule == nil || target != "DIRECT" {
		t.Fatal("maintenance changed App routing", target, err)
	}
	info.Rule, info.RulePayload = rule.RuleType().String(), rule.Payload()
	sourceRuleTraces.Lock()
	if frame := sourceRuleTraces.pending[info.Metadata]; len(sourceRuleTraces.pending) != 1 || frame == nil || frame.index != -1 || sourceRuleTraces.sweepAt.IsZero() {
		t.Error("App hook did not reclaim through the shared maintenance gate")
	}
	fillTraceWork(2047, false)
	old := &sourceTraceFrame{time: time.Now(), state: &sourceTraceState{input: "unrelated-old-input"}}
	sourceRuleTraces.pending[info.Metadata] = old
	deadline := time.Now().Add(time.Hour)
	sourceRuleTraces.sweepAt = deadline
	sourceRuleTraces.Unlock()
	_, target, err = resolveApplicationRoute(context.Background(), p.scope, info.Metadata)
	if err != nil || target != "DIRECT" {
		t.Fatal("full-table replacement changed routing", target, err)
	}
	sourceRuleTraces.Lock()
	if len(sourceRuleTraces.pending) != 2048 || sourceRuleTraces.pending[info.Metadata] == old || !sourceRuleTraces.sweepAt.Equal(deadline) {
		t.Error("same-key replacement grew the table or bypassed the gate")
	}
	sourceRuleTraces.Unlock()
	if provenance := bindSourceTracker(info); !provenance.Known || provenance.Index != -1 || provenance.AppliedRevision != p.sourceTrace.Load().input {
		t.Fatal("replacement retained the wrong App evidence", provenance)
	}
	expired := observationTracker(49002, C.TCP)
	sourceRuleTraces.Lock()
	sourceRuleTraces.pending[expired.Metadata] = &sourceTraceFrame{time: time.Now().Add(-2 * time.Minute), state: p.sourceTrace.Load(), index: 0,
		origin: SourceRuleOrigin{Origin: "profile:7"}, ruleType: expired.Rule, target: "DIRECT"}
	sourceRuleTraces.Unlock()
	ordinary := traceWrapped(t, p, "DOMAIN", "never.test", nil)
	ordinary.Match(&C.Metadata{Host: "unmatched.test"}, C.RuleMatchHelper{})
	sourceRuleTraces.Lock()
	if sourceRuleTraces.pending[expired.Metadata] == nil || !sourceRuleTraces.sweepAt.Equal(deadline) {
		t.Error("ordinary matcher ignored the shared maintenance gate")
	}
	sourceRuleTraces.Unlock()
	if provenance := bindSourceTracker(expired); provenance.Known || provenance.AppliedRevision != "" || provenance.Index != -1 {
		t.Error("deferred physical deletion extended evidence validity", provenance)
	}
	next := observationTracker(49003, C.TCP)
	modeRemember(next.Metadata, connectionConfiguration{Status: "unknown"})
	sourceRuleTraces.Lock()
	sourceRuleTraces.pending[&C.Metadata{}] = &sourceTraceFrame{time: time.Now()}
	sourceRuleTraces.Unlock()
	_, target, err = resolveApplicationRoute(context.Background(), p.scope, next.Metadata)
	if err != nil || target != "DIRECT" {
		t.Fatal("trace saturation blocked App routing", target, err)
	}
	sourceRuleTraces.Lock()
	defer sourceRuleTraces.Unlock()
	if len(sourceRuleTraces.pending) != 2048 || sourceRuleTraces.pending[next.Metadata] != nil {
		t.Error("full table admitted a new App trace")
	}
}
