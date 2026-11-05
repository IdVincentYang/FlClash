package main

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func sourceTraceInput(t *testing.T, yaml string, bodies map[string][]byte) string {
	t.Helper()
	id := sourceRuntimeInput(t, yaml, bodies)
	data, err := os.ReadFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	raw, err := config.UnmarshalRawConfig([]byte(yaml))
	if err != nil {
		t.Fatal(err)
	}
	var profile SourceUse
	for _, use := range manifest.SourceUses {
		if use.Kind == "profile" {
			profile = use
			break
		}
	}
	manifest.RuleLedger = &SourceRuleLedger{Version: 1, Lists: map[string][]SourceRuleOrigin{
		"rules": {{Start: 0, End: len(raw.Rule), Origin: profile.Key, Revision: profile.Digest, RulesDigest: sourceRulesDigest(raw.Rule)}},
	}}
	data, err = json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	id = inputHash(data)
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	return id
}

func sourceTCPTracker(t *testing.T, conn net.Conn, after time.Time) *statistic.TrackerInfo {
	t.Helper()
	_, rawPort, err := net.SplitHostPort(conn.LocalAddr().String())
	if err != nil {
		t.Fatal(err)
	}
	port, _ := strconv.Atoi(rawPort)
	var found *statistic.TrackerInfo
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		info := tracker.Info()
		if info.Metadata.SrcPort == uint16(port) && !info.Start.Before(after) {
			found = info
			return false
		}
		return true
	})
	if found == nil {
		t.Fatal("real Core did not produce a tracker for the controlled business socket")
	}
	return found
}

func TestSourceTraceCorrelatesFinalCoreMatchAndFreezesRuleSetGeneration(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	yaml := "mixed-port: " + strconv.Itoa(port) + "\nmode: rule\nfind-process-mode: off\ngeo-auto-update: false\ndns: {enable: false}\nntp: {enable: false}\nprofile: {store-selected: false}\nrule-providers:\n  accepted: {type: http, url: 'http://127.0.0.1:1/controlled', behavior: ipcidr, format: text}\nrules: ['RULE-SET,accepted,DIRECT', 'MATCH,REJECT']\n"
	old := []byte("127.0.0.1/32\n")
	id := sourceTraceInput(t, yaml, map[string][]byte{"provider-rule:accepted": old})
	applyTestInput(t, id)
	started := time.Now()
	first := sourceEchoConnection(t, port)
	sourceEcho(t, first, "old-rules")
	oldInfo := sourceTCPTracker(t, first, started)
	oldTrace := sourceTrackerViewOf(oldInfo).Provenance
	if !oldTrace.Known || oldTrace.Origin != "profile:7" || oldTrace.AppliedRevision != id || len(oldTrace.RuleSet) != 1 || oldTrace.RuleSet[0].Revision != inputHash(old) {
		t.Fatalf("real match was not bound to its installed input/RP generation: %+v", oldTrace)
	}
	p := appliedConfig
	var runtime *sourceProviderRuntime
	for _, candidate := range p.sourceProviders {
		runtime = candidate
	}
	next := []byte("127.0.0.1/32\n127.0.0.2/32\n")
	acceptSourceProviderFixture(t, runtime.plan, next)
	if err := runtime.update(next); err != nil {
		t.Fatal(err)
	}
	secondStart := time.Now()
	second := sourceEchoConnection(t, port)
	sourceEcho(t, second, "new-rules")
	newTrace := sourceTrackerViewOf(sourceTCPTracker(t, second, secondStart)).Provenance
	if !newTrace.Known || newTrace.AppliedRevision != configFact.InputID || len(newTrace.RuleSet) != 1 || newTrace.RuleSet[0].Revision != inputHash(next) {
		t.Fatalf("new match did not capture the actual new generation: %+v", newTrace)
	}
	if frozen := sourceTrackerViewOf(oldInfo).Provenance; frozen.AppliedRevision != id || frozen.RuleSet[0].Revision != inputHash(old) {
		t.Fatal("late connection read relabeled an old tracker with current config")
	}
	sourceEcho(t, first, "old-connection-still-live")
}

func TestSourceTraceUsesFinalRuleAfterPassAndReportsTransitionUnknown(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	yaml := "mixed-port: " + strconv.Itoa(port) + "\nmode: rule\nfind-process-mode: off\ngeo-auto-update: false\ndns: {enable: false}\nntp: {enable: false}\nprofile: {store-selected: false}\nrules: ['MATCH,PASS', 'MATCH,DIRECT']\n"
	id := sourceTraceInput(t, yaml, nil)
	applyTestInput(t, id)
	started := time.Now()
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "pass")
	trace := sourceTrackerViewOf(sourceTCPTracker(t, conn, started)).Provenance
	if !trace.Known || trace.Index != 1 {
		t.Fatalf("earlier PASS match was reported as the selected rule: %+v", trace)
	}
	publishSourceTraceState(appliedConfig, id, true)
	started = time.Now()
	transition := sourceEchoConnection(t, port)
	sourceEcho(t, transition, "transition")
	unknown := sourceTrackerViewOf(sourceTCPTracker(t, transition, started)).Provenance
	if unknown.Known || unknown.AppliedRevision != "" {
		t.Fatalf("transition guessed a currently installed version: %+v", unknown)
	}
}

func TestSourceTraceRejectsMismatchedOrUnboundLedger(t *testing.T) {
	lines := []string{"MATCH,DIRECT"}
	manifest := ConfigManifest{RuleLedger: &SourceRuleLedger{Version: 1, Lists: map[string][]SourceRuleOrigin{"rules": {{Start: 0, End: 1, Origin: "override:7", Revision: inputHash([]byte("explicit local choice")), RulesDigest: sourceRulesDigest(lines)}}}}}
	if err := validateSourceRuleLedger(manifest, lines, nil); err != nil {
		t.Fatal(err)
	}
	if err := validateSourceRuleLedger(manifest, []string{"MATCH,REJECT"}, nil); err == nil {
		t.Fatal("ledger described a different actual rule")
	}
	manifest.RuleLedger.Lists["rules"][0].Origin = "script:unbound"
	if err := validateSourceRuleLedger(manifest, lines, nil); err == nil {
		t.Fatal("ledger invented a source absent from the accepted composition")
	}
}

func TestSourceTraceDoesNotAttributeUnprovenSubruleToItsOuterAuthor(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	body := strings.Replace(configTestYAML(port), `rules: ["MATCH,DIRECT"]`, `rules: ['SUB-RULE,(NETWORK,TCP),inner', 'MATCH,REJECT']`, 1) + "sub-rules:\n  inner: ['MATCH,DIRECT']\n"
	id := sourceTraceInput(t, body, nil)
	applyTestInput(t, id)
	start := time.Now()
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "actual-subrule")
	info := sourceTCPTracker(t, conn, start)
	trace := sourceTrackerViewOf(info).Provenance
	if trace.Known || trace.Origin != "" || len(trace.RuleSet) != 0 {
		t.Fatalf("outer author was substituted for an unproven inner decision: %+v", trace)
	}
	if info.Rule != C.SubRules.String() {
		t.Fatal("controlled connection did not use the actual subrule path", info.Rule)
	}
}
