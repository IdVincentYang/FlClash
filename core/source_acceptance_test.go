package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/config"
)

const sourceAcceptanceFixture = `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 19001, password: synthetic-secret, udp: true}
proxy-groups:
  - {name: Pool, type: select, proxies: [a]}
rules:
  - DOMAIN-SUFFIX,blocked.test,REJECT
  - DOMAIN-SUFFIX,example.test,Pool
  - MATCH,DIRECT
`

func sourceTestSummary(t *testing.T, body string) sourceContentSummary {
	t.Helper()
	_, summary, err := decodeSourceContent([]byte(body))
	if err != nil {
		t.Fatal(err)
	}
	return summary
}

func TestSourceOrderedProtectionCounterexamples(t *testing.T) {
	base := sourceTestSummary(t, sourceAcceptanceFixture)
	window := &sourceRuleContract{
		Prefix: []string{"DOMAIN-SUFFIX,blocked.test,REJECT"},
		Slots:  []sourceRuleSlot{{Target: "Pool"}}, Default: "MATCH,DIRECT",
	}
	contract := sourceContentContract{Version: 1, Base: base, Rules: window}
	tests := []struct {
		name, body string
		allowed    bool
	}{
		{"delete proxy expands direct", strings.ReplaceAll(sourceAcceptanceFixture, "  - DOMAIN-SUFFIX,example.test,Pool\n", ""), false},
		{"insert before fixed reject", strings.ReplaceAll(sourceAcceptanceFixture, "rules:\n", "rules:\n  - DOMAIN,blocked.test,Pool\n"), false},
		{"add after fixed reject", strings.ReplaceAll(sourceAcceptanceFixture, "  - MATCH,DIRECT", "  - DOMAIN,another.test,Pool\n  - MATCH,DIRECT"), true},
		{"change default", strings.ReplaceAll(sourceAcceptanceFixture, "MATCH,DIRECT", "MATCH,Pool"), false},
		{"unknown expression", strings.ReplaceAll(sourceAcceptanceFixture, "DOMAIN-SUFFIX,example.test,Pool", "DOMAIN-REGEX,example.*,Pool"), false},
		{"udp capability loss", strings.ReplaceAll(sourceAcceptanceFixture, "udp: true", "udp: false"), false},
		{"fixed condition changes", strings.ReplaceAll(sourceAcceptanceFixture, "blocked.test", "other.test"), false},
		{"fixed decision after variable", strings.ReplaceAll(sourceAcceptanceFixture, "  - MATCH,DIRECT", "  - DOMAIN,guard.test,REJECT\n  - MATCH,DIRECT"), false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			reasons := classifySourceDelta(contract, sourceTestSummary(t, test.body))
			if got := len(reasons) == 0; got != test.allowed {
				t.Fatalf("automatic=%v, reasons=%v", got, reasons)
			}
		})
	}
	proxyBase := base
	proxyBase.Rules = append(slices.Clone(base.Rules[:len(base.Rules)-1]), "MATCH,Pool")
	proxyNext := proxyBase
	proxyNext.Rules = []string{proxyBase.Rules[0], "MATCH,Pool"}
	proxyWindow := *window
	proxyWindow.Default = "MATCH,Pool"
	if !sourceRulesAutomaticallyAllowed(proxyBase, proxyNext, &proxyWindow) {
		t.Fatal("delegated proxy-default deletion rejected")
	}
	bounded := *window
	bounded.Slots = []sourceRuleSlot{{Target: "Pool", Domains: []string{"example.test"}}}
	outside := sourceTestSummary(t, strings.ReplaceAll(sourceAcceptanceFixture, "example.test", "outside.test"))
	if sourceRulesAutomaticallyAllowed(base, outside, &bounded) {
		t.Fatal("condition outside delegated suffix accepted")
	}
}

func TestSourceNodeMaintenanceAndEffectiveChanges(t *testing.T) {
	base := sourceTestSummary(t, sourceAcceptanceFixture)
	contract := sourceContentContract{Version: 1, Base: base}
	maintenance := strings.NewReplacer("name: a,", "name: renamed,", "proxies: [a]", "proxies: [renamed]", "19001", "19002", "synthetic-secret", "rotated-secret").Replace(sourceAcceptanceFixture)
	if reasons := classifySourceDelta(contract, sourceTestSummary(t, maintenance)); len(reasons) != 0 {
		t.Fatalf("delegated node maintenance prompted: %v", reasons)
	}
	encoded, _ := json.Marshal(base)
	if strings.Contains(string(encoded), "synthetic-secret") || strings.Contains(string(encoded), "127.0.0.1") {
		t.Fatal("source summary retained credentials or endpoint")
	}
	for _, test := range []struct{ extra, reason string }{
		{"dns: {nameserver: ['tcp://127.0.0.1:19053']}\n", "dns_changed"},
		{"listeners: [{name: hidden, type: mixed, port: 19080, proxy: DIRECT}]\n", "entry_or_control_changed"},
		{"tunnels: [{proxy: DIRECT}]\n", "entry_or_control_changed"},
		{"unknown-future-capability: true\n", "unclassified_effective_field_changed"},
	} {
		if reasons := classifySourceDelta(contract, sourceTestSummary(t, sourceAcceptanceFixture+test.extra)); !slices.Contains(reasons, test.reason) {
			t.Fatalf("%s not explained: %v", test.reason, reasons)
		}
	}
}

func TestSourceTCPNodeRotationDoesNotGrantUDPAutomaticRuleTargets(t *testing.T) {
	body := "proxies: [{name: old, type: socks5, server: 127.0.0.1, port: 1, udp: false}]\nproxy-groups: [{name: Pool, type: select, proxies: [old]}]\nrules: [\"MATCH,Pool\"]\n"
	base := sourceTestSummary(t, body)
	next := sourceTestSummary(t, strings.ReplaceAll(body, "old", "new"))
	if reasons := classifySourceDelta(sourceContentContract{Version: 1, Base: base}, next); len(reasons) != 0 {
		t.Fatal("pure TCP proxy maintenance required routing delegation", reasons)
	}
	if slices.Contains(base.ProxyTargets, "Pool") || slices.Contains(next.ProxyTargets, "Pool") {
		t.Fatal("TCP-only maintenance authorized an R1 UDP rule target")
	}
	mixed := strings.ReplaceAll(body, "proxies: [old]", "proxies: [DIRECT, old]")
	base = sourceTestSummary(t, mixed)
	next = sourceTestSummary(t, strings.ReplaceAll(mixed, "old", "new"))
	if reasons := classifySourceDelta(sourceContentContract{Version: 1, Base: base}, next); !slices.Contains(reasons, "group_binding_changed") {
		t.Fatal("removing selected node from a mixed group could change its DIRECT fallback", reasons)
	}
}

func TestSourceGrantWithdrawalAndIncarnation(t *testing.T) {
	home := t.TempDir()
	identity, digest, contract := inputHash([]byte("source origin")), inputHash([]byte("accepted")), inputHash([]byte("contract"))
	use, err := acceptSourceRevision(home, "profile:1", identity, digest, "source", contract, true, 0)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(sourcePermissionsPath(home))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("permissions file privacy: %v, %v", info, err)
	}
	if err := withdrawSourcePermission(home, use.Key, use.Incarnation, 1, false); err != nil {
		t.Fatal(err)
	}
	if err := checkSourceUses(home, []SourceUse{use}); err != nil {
		t.Fatalf("stopping future maintenance revoked exact use: %v", err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil || permissions.Grants[use.Key].Purposes["profile"].Automatic {
		t.Fatalf("future delegation survived restart read: %v", err)
	}
	if err := withdrawSourcePermission(home, use.Key, use.Incarnation, 1, true); !errors.Is(err, errSourceSuperseded) {
		t.Fatalf("late withdrawal accepted: %v", err)
	}
	if err := withdrawSourcePermission(home, use.Key, use.Incarnation, 2, true); err != nil {
		t.Fatal(err)
	}
	if err := checkSourceUses(home, []SourceUse{use}); !errors.Is(err, errSourceUseRevoked) {
		t.Fatalf("use revocation ignored: %v", err)
	}
	other, err := acceptSourceRevision(home, use.Key, inputHash([]byte("different origin")), digest, "source", "", false, 0)
	if err != nil || other.Incarnation == use.Incarnation {
		t.Fatalf("new source inherited incarnation: %v", err)
	}
	if err := checkSourceUses(home, []SourceUse{use}); !errors.Is(err, errSourceUseRevoked) {
		t.Fatalf("old incarnation survived: %v", err)
	}
}

func TestSourcePurposesDoNotShareDelegationOrRevocation(t *testing.T) {
	home := t.TempDir()
	identity := inputHash([]byte("one physical source"))
	profile, err := acceptSourceRevision(home, "profile:1", identity, inputHash([]byte("full profile")), "source", "", false, 0)
	if err != nil {
		t.Fatal(err)
	}
	nodes, err := acceptSourceRevision(home, "profile:1", identity, inputHash([]byte("nodes only")), "source", inputHash([]byte("node contract")), true, 1, "provider-proxy")
	if err != nil {
		t.Fatal(err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil || permissions.Grants[profile.Key].Purposes["profile"].Automatic || !permissions.Grants[profile.Key].Purposes["provider-proxy"].Automatic {
		t.Fatalf("node delegation changed full-profile authority: %v", err)
	}
	if err := withdrawSourcePermission(home, nodes.Key, nodes.Incarnation, 2, true, "provider-proxy"); err != nil {
		t.Fatal(err)
	}
	if err := checkSourceUses(home, []SourceUse{profile}); err != nil {
		t.Fatalf("independent profile use revoked: %v", err)
	}
	if err := checkSourceUses(home, []SourceUse{nodes}); !errors.Is(err, errSourceUseRevoked) {
		t.Fatalf("node use revocation ignored: %v", err)
	}
}

func TestSourcePermissionFileFailureAndBounds(t *testing.T) {
	home := t.TempDir()
	identity, digest := inputHash([]byte("identity")), inputHash([]byte("body"))
	previousWrite := writeSourcePermissions
	writeSourcePermissions = func(string, []byte) error { return errors.New("synthetic disk failure") }
	t.Cleanup(func() { writeSourcePermissions = previousWrite })
	if _, err := acceptSourceRevision(home, "profile:1", identity, digest, "source", "", false, 0); !errors.Is(err, errSourceStore) {
		t.Fatalf("write failure accepted: %v", err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil || len(permissions.Grants) != 0 {
		t.Fatalf("failed write created authority: %v", err)
	}
	writeSourcePermissions = previousWrite
	if err := os.MkdirAll(filepath.Dir(sourcePermissionsPath(home)), 0700); err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{`{"version":999,"grants":{}}`, `{"version":1,"grants":{}} {}`, strings.Repeat("x", sourceGrantFileLimit+1)} {
		if err := os.WriteFile(sourcePermissionsPath(home), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := readSourcePermissions(home); !errors.Is(err, errSourceStore) {
			t.Fatalf("malformed permissions accepted: %v", err)
		}
	}
}

func TestSourceReviewBindingAndAutomaticCandidate(t *testing.T) {
	previous := pendingSourceReviews
	pendingSourceReviews = map[string]*sourceReviewCandidate{}
	t.Cleanup(func() { pendingSourceReviews = previous })
	home := t.TempDir()
	request := sourceAcceptanceRequest{
		Action: "review", Key: "profile:1", Identity: inputHash([]byte("origin")),
		Settings: inputHash([]byte("settings")), Kind: "profile", Body: sourceAcceptanceFixture,
		Source: ConfigSourceTicket{Sources: map[string]uint64{"profile:1": 0}},
	}
	first, err := sourceAcceptance(home, request)
	if err != nil || first.Status != "reviewRequired" {
		t.Fatalf("first use accepted silently: %+v, %v", first, err)
	}
	accept := request
	accept.Action, accept.Candidate, accept.Routing, accept.Automatic = "accept", first.Candidate, "source", true
	late := accept
	late.Settings = inputHash([]byte("new settings"))
	if _, err := sourceAcceptance(home, late); !errors.Is(err, errSourceSuperseded) {
		t.Fatalf("old review applied to new settings: %v", err)
	}
	accepted, err := sourceAcceptance(home, accept)
	if err != nil || accepted.Use == nil {
		t.Fatalf("explicit acceptance failed: %+v, %v", accepted, err)
	}
	request.Body = strings.ReplaceAll(request.Body, "19001", "19002")
	updated, err := sourceAcceptance(home, request)
	if err != nil || updated.Status != "accepted" || updated.Use == nil {
		t.Fatalf("delegated rotation rejected: %+v, %v", updated, err)
	}
	forced := request
	forced.ForceReview = true
	manual, err := sourceAcceptance(home, forced)
	if err != nil || manual.Status != "reviewRequired" {
		t.Fatalf("explicit re-review silently reused the current decision: %+v %v", manual, err)
	}
	if err := checkSourceUses(home, []SourceUse{*updated.Use}); err != nil {
		t.Fatalf("opening re-review revoked current accepted use: %v", err)
	}
	request.Body += "dns: {nameserver: ['tcp://127.0.0.1:19053']}\n"
	pending, err := sourceAcceptance(home, request)
	if err != nil || pending.Status != "reviewRequired" || !slices.Contains(pending.Reasons, "dns_changed") {
		t.Fatalf("high-impact change accepted: %+v, %v", pending, err)
	}
	if err := checkSourceUses(home, []SourceUse{*updated.Use}); err != nil {
		t.Fatalf("unaccepted candidate invalidated accepted use: %v", err)
	}
	request.Body += "unknown: true\n"
	newer, err := sourceAcceptance(home, request)
	if err != nil || newer.Candidate == pending.Candidate {
		t.Fatalf("new candidate not separately bound: %v", err)
	}
	accept.Candidate = pending.Candidate
	if _, err := sourceAcceptance(home, accept); !errors.Is(err, errSourceSuperseded) {
		t.Fatalf("replaced candidate accepted: %v", err)
	}
}

func TestScriptPermissionRequiresExactCode(t *testing.T) {
	previous := pendingSourceReviews
	pendingSourceReviews = map[string]*sourceReviewCandidate{}
	t.Cleanup(func() { pendingSourceReviews = previous })
	home := t.TempDir()
	request := sourceAcceptanceRequest{Action: "review", Key: "script:1", Kind: "script", Identity: inputHash([]byte("script source")), Settings: inputHash(nil), Body: "function main(config) { return config; }"}
	first, err := sourceAcceptance(home, request)
	if err != nil {
		t.Fatal(err)
	}
	accept := request
	accept.Action, accept.Candidate, accept.Routing, accept.Automatic = "accept", first.Candidate, "source", true
	if _, err := sourceAcceptance(home, accept); !errors.Is(err, errSourceReview) {
		t.Fatalf("automatic new code delegation allowed: %v", err)
	}
	accept.Automatic = false
	if _, err := sourceAcceptance(home, accept); err != nil {
		t.Fatal(err)
	}
	request.Body += "\nconsole.log('synthetic');"
	changed, err := sourceAcceptance(home, request)
	if err != nil || changed.Status != "reviewRequired" || !slices.Contains(changed.Reasons, "script_code_changed") {
		t.Fatalf("new code accepted: %+v, %v", changed, err)
	}
}

func TestSourceDNSPolicyOrderRequiresReview(t *testing.T) {
	first := sourceAcceptanceFixture + `dns:
  nameserver-policy:
    '+.example.test': [tcp://127.0.0.1:19053]
    'a.example.test': [tcp://127.0.0.1:19054]
`
	second := sourceAcceptanceFixture + `dns:
  nameserver-policy:
    'a.example.test': [tcp://127.0.0.1:19054]
    '+.example.test': [tcp://127.0.0.1:19053]
`
	base := sourceTestSummary(t, first)
	next := sourceTestSummary(t, second)
	if base.Digest == next.Digest || !slices.Contains(classifySourceDelta(sourceContentContract{Version: 1, Base: base}, next), "dns_changed") {
		t.Fatal("DNS policy precedence was erased by unordered map normalization")
	}
}

func TestSourceRoutingProjectionPreservesIndependentDNSAndOrder(t *testing.T) {
	body := sourceAcceptanceFixture + `sub-rules:
  hidden: [MATCH,DIRECT]
listeners:
  - {name: injected, type: mixed, port: 19080, proxy: DIRECT}
tunnels:
  - {network: tcp, address: '127.0.0.1:19081', target: '127.0.0.1:19082', proxy: DIRECT}
rule-providers:
  shared: {type: inline, behavior: domain, payload: [example.test]}
  business-only: {type: http, behavior: domain, url: 'http://127.0.0.1:19083/rules'}
dns:
  nameserver-policy:
    'rule-set:shared': [tcp://127.0.0.1:19053]
    '+.example.test': [tcp://127.0.0.1:19054]
  fake-ip-filter: ['rule-set:shared']
sniffer:
  skip-domain: ['rule-set:shared']
`
	document, _, err := decodeSourceContent([]byte(body))
	if err != nil {
		t.Fatal(err)
	}
	projected, err := sourceRoutingProjection(document, "profile:1")
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"rules", "sub-rules", "listeners", "tunnels"} {
		if _, present := projected[key]; present {
			t.Fatalf("source routing entry survived: %s", key)
		}
	}
	providers, ok := projected["rule-providers"].(map[string]any)
	if !ok || len(providers) != 1 || providers["shared"] != nil || providers["business-only"] != nil {
		t.Fatalf("provider purpose/name isolation failed: %v", providers)
	}
	encoded, err := json.Marshal(projected)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := config.UnmarshalRawConfig(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if raw.DNS.NameServerPolicy.Len() != 2 || !strings.HasPrefix(raw.DNS.NameServerPolicy.Oldest().Key, "rule-set:@source-") || raw.DNS.NameServerPolicy.Newest().Key != "+.example.test" {
		t.Fatal("projection reordered Core's actual DNS policy decoder")
	}
	if !strings.HasPrefix(raw.DNS.FakeIPFilter[0], "rule-set:@source-") || !strings.HasPrefix(raw.Sniffer.SkipDomain[0], "rule-set:@source-") {
		t.Fatal("independent consumer references were not rewritten")
	}
	if document["rules"] == nil || document["listeners"] == nil {
		t.Fatal("projection mutated the unaccepted source document")
	}
}
