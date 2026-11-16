package main

import (
	"fmt"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func BenchmarkSourceTraceChain(b *testing.B) {
	for _, distinct := range []bool{false, true} {
		for _, pending := range []int{0, 128, 1024, 2047} {
			b.Run(fmt.Sprintf("distinct_%t/pending_%d", distinct, pending), func(b *testing.B) {
				p := traceWorkFixture(b)
				rules := make([]C.RuleWrapper, 100)
				for i := range rules {
					if i != 0 && !distinct {
						rules[i] = rules[0]
					} else {
						rules[i] = traceWrapped(b, p, "DOMAIN", fmt.Sprintf("never-%d.test", i), nil)
					}
				}
				sourceRuleTraces.Lock()
				fillTraceWork(pending, false)
				sourceRuleTraces.Unlock()
				metadata := &C.Metadata{Host: "unmatched.test"}
				rules[0].Match(metadata, C.RuleMatchHelper{})
				b.ReportAllocs()
				b.ResetTimer()
				for i := 0; i < b.N; i++ {
					for _, rule := range rules {
						rule.Match(metadata, C.RuleMatchHelper{})
					}
				}
				b.StopTimer()
				b.ReportMetric(100, "rules/op")
				if len(sourceRuleTraces.pending) != pending || len(sourceRuleTraces.active) != 0 {
					b.Fatal("benchmark workload changed")
				}
			})
		}
	}
}

func BenchmarkSourceTraceMatched(b *testing.B) {
	for _, provider := range []bool{false, true} {
		b.Run(fmt.Sprintf("provider_%t", provider), func(b *testing.B) {
			p := traceWorkFixture(b)
			generation := &sourceRuleGeneration{use: SourceUse{Key: "provider:controlled"}, digest: "material"}
			rule := traceWrapped(b, p, "MATCH", "", func(base C.RuleWrapper) C.RuleWrapper {
				return traceProbeRule{RuleWrapper: base, match: func(metadata *C.Metadata, helper C.RuleMatchHelper) (bool, string) {
					if provider {
						recordSourceRuleSetMatch(p, "controlled", generation, metadata, true)
					}
					return base.Match(metadata, helper)
				}}
			})
			metadata := &C.Metadata{}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				rule.Match(metadata, C.RuleMatchHelper{})
			}
			b.StopTimer()
			if frame := sourceRuleTraces.pending[metadata]; frame == nil || provider && len(frame.provider) != 1 {
				b.Fatal("matched benchmark did not retain its frame")
			}
		})
	}
}

func BenchmarkSourceTraceParallel(b *testing.B) {
	p := traceWorkFixture(b)
	rule := traceWrapped(b, p, "DOMAIN", "never.test", nil)
	sourceRuleTraces.Lock()
	fillTraceWork(1024, false)
	sourceRuleTraces.Unlock()
	b.ReportAllocs()
	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		metadata := &C.Metadata{Host: "unmatched.test"}
		for pb.Next() {
			for i := 0; i < 100; i++ {
				rule.Match(metadata, C.RuleMatchHelper{})
			}
		}
	})
	b.StopTimer()
	b.ReportMetric(100, "rules/op")
	if len(sourceRuleTraces.pending) != 1024 || len(sourceRuleTraces.active) != 0 {
		b.Fatal("parallel benchmark workload changed")
	}
}

func BenchmarkSourceTraceCold(b *testing.B) {
	for _, count := range []int{0, 1024, 2048} {
		b.Run(fmt.Sprintf("each_%d", count), func(b *testing.B) {
			if b.N != 1 {
				b.Fatal("run each cold case in its own process with -benchtime=1x -count=1")
			}
			p := traceWorkFixture(b)
			rule := traceWrapped(b, p, "DOMAIN", "never.test", nil)
			sourceRuleTraces.Lock()
			fillTraceWork(count, true)
			for i := 0; i < count; i++ {
				sourceRuleTraces.active[&C.Metadata{}] = &sourceTraceFrame{time: time.Now().Add(-2 * time.Minute)}
			}
			sourceRuleTraces.Unlock()
			metadata := &C.Metadata{Host: "unmatched.test"}
			b.ReportAllocs()
			b.ResetTimer()
			rule.Match(metadata, C.RuleMatchHelper{})
			b.StopTimer()
			if len(sourceRuleTraces.pending) != 0 || len(sourceRuleTraces.active) != 0 {
				b.Fatal("cold benchmark did not execute the due sweep")
			}
		})
	}
}
