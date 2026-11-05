package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
	"github.com/metacubex/mihomo/tunnel"
)

func sourceInlineFixture(t *testing.T, hooks ...func(context.Context, requestscope.Spec) (requestscope.Lease, error)) int {
	t.Helper()
	sourceRuntimeFixture(t)
	if len(hooks) != 0 {
		requestscope.BeginHook = hooks[0]
	}
	sourceReaderHistoryFixture(t)
	appRequests.client, appRequests.clientReady = "controlled-inline-frontend", true
	port := configTestPort(t)
	applyTestInput(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19001)))
	if reason := sourceInlineReaderReason(); reason != "" {
		t.Fatal("controlled fixture unexpectedly created an unsafe reader", reason)
	}
	return port
}

func sourceInlineNextInput(t *testing.T, body string) string {
	t.Helper()
	configMu.Lock()
	defer configMu.Unlock()
	id := sourceRuntimeInputLocked(t, body, nil)
	marker, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: inputHash([]byte(body)), RuntimeEpoch: configRuntimeEpoch, Client: appRequests.client})
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+"."+strings.Repeat("a", 24)+".candidate"), marker); err != nil {
		t.Fatal(err)
	}
	return id
}

func sourceInlineYAML(port, nodePort int) string {
	return configTestYAML(port) + fmt.Sprintf("proxies:\n  - {name: replace, type: socks5, server: 127.0.0.1, port: %d, udp: true}\n  - {name: unchanged, type: socks5, server: 127.0.0.1, port: 19003, udp: true}\nproxy-groups:\n  - {name: accepted, type: select, proxies: [replace, unchanged]}\n  - {name: independent, type: select, proxies: [unchanged]}\n", nodePort)
}

func sourceInlineTestRequest(t *testing.T, id string) ConfigInputRequest {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	manifest, _, _, _, err := readConfigInput(C.Path.HomeDir(), id)
	if err != nil {
		t.Fatal(err)
	}
	appRequests.mu.Lock()
	source := ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{}}
	for _, key := range manifest.Dependencies {
		source.Sources[key] = appRequests.sources[key]
	}
	state := appRequests.state
	appRequests.mu.Unlock()
	fence := observedConfigFence()
	return ConfigInputRequest{InputID: id, ExpectedRun: state, Active: true, Source: source, ExpectedConfig: &fence}
}

func TestSourceInlineRetainsScopeConnectionsAndUnchangedObjects(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	port := sourceInlineFixture(t)
	p := appliedConfig
	scope, receipt := p.scope, p.receipt
	before := tunnel.AllProxies()
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "before-inline")
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19002)))
	result := adoptSourceInlineRequest(&request)
	if result.Status != "applied" || !result.Fact.BusinessActive || !result.Fact.ReplayEligible {
		t.Fatalf("inline adopt failed: %+v", result)
	}
	if appliedConfig != p || p.scope != scope || p.receipt.Token != receipt.Token || p.receipt.Owner != receipt.Owner || p.receipt.InputID == receipt.InputID {
		t.Fatal("inline update replaced the business owner or failed to advance input")
	}
	after := tunnel.AllProxies()
	for _, name := range []string{"DIRECT", "unchanged", "independent"} {
		if before[name] != after[name] {
			t.Fatal("unaffected proxy object changed", name)
		}
	}
	for _, name := range []string{"replace", "accepted", "GLOBAL"} {
		if before[name] == after[name] {
			t.Fatal("affected proxy closure was not rebuilt", name)
		}
	}
	if len(p.sourceInlineRetired) != 1 || len(p.sourceInlineRetired[0].proxies) != 3 {
		t.Fatal("old adapters were not retained for in-flight readers")
	}
	sourceEcho(t, conn, "after-inline")
	ref, err := readCheckpointLocked(C.Path.HomeDir())
	if err != nil || ref.InputID != result.Fact.InputID {
		t.Fatal("checkpoint did not follow actual hot input", err)
	}
	if _, _, _, _, err := readConfigInput(C.Path.HomeDir(), ref.InputID); err != nil {
		t.Fatal("hot input cannot be verified for replay", err)
	}
}

func TestSourceInlineRejectsStaleMissingAuthorityAndUnsafeHistory(t *testing.T) {
	for _, negative := range []string{"stale-fence", "no-hook", "noop-hook", "no-client", "stopped", "old-quic-reader", "budget", "structure", "missing-target"} {
		t.Run(negative, func(t *testing.T) {
			if !sourceTestIsolation(t) {
				return
			}
			var port int
			switch negative {
			case "no-hook":
				port = sourceInlineFixture(t, nil)
			case "noop-hook":
				port = sourceInlineFixture(t, func(context.Context, requestscope.Spec) (requestscope.Lease, error) {
					return &sourceRuleNoopLease{}, nil
				})
			default:
				port = sourceInlineFixture(t)
			}
			p, oldInput := appliedConfig, configFact.InputID
			before := tunnel.AllProxies()
			yaml := sourceInlineYAML(port, 19002)
			if negative == "structure" {
				yaml = strings.Replace(yaml, "mode: rule", "mode: global", 1)
			}
			if negative == "missing-target" {
				yaml = strings.Replace(yaml, "name: replace,", "name: removed,", 1)
				yaml = strings.Replace(yaml, "proxies: [replace, unchanged]", "proxies: [removed, unchanged]", 1)
				initial := strings.Replace(sourceInlineYAML(port, 19001), "MATCH,DIRECT", "MATCH,replace", 1)
				applyTestInput(t, sourceInlineNextInput(t, initial))
				p, oldInput = appliedConfig, configFact.InputID
				before = tunnel.AllProxies()
				yaml = strings.Replace(yaml, "MATCH,DIRECT", "MATCH,replace", 1)
			}
			request := sourceInlineTestRequest(t, sourceInlineNextInput(t, yaml))
			switch negative {
			case "stale-fence":
				request.ExpectedConfig.Version++
			case "no-client":
				request.Source.Client = ""
			case "stopped":
				appRequests.state.IntentRunning = false
			case "old-quic-reader":
				recordSourceReaderRisk("quic-dns-reader")
			case "budget":
				p.sourceRetiredCount = sourceRetiredGenerationLimit
			}
			result := adoptSourceInlineRequest(&request)
			if result.Status == "applied" || p.receipt.InputID != oldInput {
				t.Fatalf("%s changed input: %+v", negative, result)
			}
			after := tunnel.AllProxies()
			for name, proxy := range before {
				if proxy != after[name] {
					t.Fatal("rejected inline update mutated actual Core map", name)
				}
			}
		})
	}
}

func TestSourceInlinePersistenceFailureRetainsLiveAndRetriesOnlySave(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	port := sourceInlineFixture(t)
	p := appliedConfig
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "before-save-failure")
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19002)))
	writer := writeConfigManifest
	writeConfigManifest = func(path string, bytes []byte) error {
		if filepath.Base(path) == "checkpoint.json" {
			return os.ErrPermission
		}
		return writer(path, bytes)
	}
	t.Cleanup(func() { writeConfigManifest = writer })
	result := adoptSourceInlineRequest(&request)
	if result.Status != "deferred" || !result.Fact.MaterialPending || result.Fact.ReplayEligible || !result.Fact.BusinessActive || p.sourceRecovery == nil {
		t.Fatalf("live save failure was not reported truthfully: %+v", result)
	}
	actual := tunnel.AllProxies()["replace"]
	input, retired := p.receipt.InputID, p.sourceRetiredCount
	sourceEcho(t, conn, "still-live")
	if _, err := readCheckpointLocked(C.Path.HomeDir()); err == nil {
		t.Fatal("old checkpoint remained replayable after actual live change")
	}
	writeConfigManifest = writer
	request = sourceInlineTestRequest(t, request.InputID)
	result = adoptSourceInlineRequest(&request)
	if result.Status != "applied" || result.Fact.MaterialPending || !result.Fact.ReplayEligible || p.receipt.InputID != input || p.sourceRetiredCount != retired || tunnel.AllProxies()["replace"] != actual {
		t.Fatalf("persistence retry rebuilt live proxies: %+v", result)
	}
	sourceEcho(t, conn, "saved-live")
}

func TestSourceGroupWithoutUDPIsNotAnAutomaticRuleTarget(t *testing.T) {
	base := sourceTestSummary(t, sourceAcceptanceFixture)
	if !slices.Contains(base.ProxyTargets, "Pool") {
		t.Fatal("controlled baseline lacks proxy-only UDP target")
	}
	next := sourceTestSummary(t, strings.Replace(sourceAcceptanceFixture, "type: select,", "type: select, disable-udp: true,", 1))
	if slices.Contains(next.ProxyTargets, "Pool") {
		t.Fatal("disable-udp group was granted automatic rule authority")
	}
	for _, value := range []string{"'true'", "'false'", "1", "null"} {
		next := sourceTestSummary(t, strings.Replace(sourceAcceptanceFixture, "type: select,", "type: select, disable-udp: "+value+",", 1))
		if slices.Contains(next.ProxyTargets, "Pool") {
			t.Fatal("unproven weakly typed UDP setting granted automatic rule authority", value)
		}
	}
}

func TestSourceInlineActualNewNodeAndUnchangedProxyConnection(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	sourceReaderHistoryFixture(t)
	appRequests.client, appRequests.clientReady = "controlled-inline-frontend", true
	a := managedSOCKS(t, "old-A", nil)
	nextA := managedSOCKS(t, "new-A", nil)
	b := managedSOCKS(t, "unchanged-B", nil)
	port := configTestPort(t)
	document := func(nodePort int) string {
		body := sourceInlineYAML(port, nodePort)
		body = strings.Replace(body, "port: 19003", fmt.Sprintf("port: %d", managedPort(b.address)), 1)
		return strings.Replace(body, `rules: ["MATCH,DIRECT"]`, `rules: ["IP-CIDR,127.0.0.1/32,independent,no-resolve", "MATCH,accepted"]`, 1)
	}
	applyTestInput(t, sourceInlineNextInput(t, document(managedPort(a.address))))
	conn := sourceEchoConnection(t, port, func(target string) {
		b.mu.Lock()
		b.allowed[target] = true
		b.mu.Unlock()
	})
	sourceEcho(t, conn, "B-before")
	requestNode := func(want string) {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
		if _, err := socks5.ClientHandshake(conn, socks5.ParseAddr("inline.test:80"), socks5.CmdConnect, nil); err != nil {
			t.Fatal(err)
		}
		if body, err := managedHTTP(conn, "inline.test"); err != nil || body != want {
			t.Fatal("actual Core reached the wrong accepted node", body, err)
		}
	}
	requestNode("old-A")
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, document(managedPort(nextA.address))))
	if result := adoptSourceInlineRequest(&request); result.Status != "applied" {
		t.Fatal(result)
	}
	sourceEcho(t, conn, "B-after")
	requestNode("new-A")
	if a.count() != 1 || nextA.count() != 1 || b.count() != 1 {
		t.Fatal("hot update reconnected unchanged traffic or reused the old node")
	}
}

func TestSourceInlineR1RulesUseOriginalMatcherAndKeepConnections(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	sourceReaderHistoryFixture(t)
	appRequests.client, appRequests.clientReady = "controlled-inline-frontend", true
	proxy := managedSOCKS(t, "R1-proxy", nil)
	port := configTestPort(t)
	oldRules := `rules: ['DOMAIN-SUFFIX,protected.test,REJECT', 'DOMAIN,old.test,accepted', 'MATCH,DIRECT']`
	body := strings.Replace(sourceInlineYAML(port, managedPort(proxy.address)), `rules: ["MATCH,DIRECT"]`, oldRules, 1)
	applyTestInput(t, sourceInlineNextInput(t, body))
	p := appliedConfig
	scope, receipt := p.scope, p.receipt
	before := tunnel.AllProxies()
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "before-rule-update")
	next := strings.Replace(body, `'MATCH,DIRECT']`, `'DOMAIN,new.test,accepted', 'MATCH,DIRECT']`, 1)
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, next))
	if result := adoptSourceInlineRequest(&request); result.Status != "applied" {
		t.Fatal(result)
	}
	if p.scope != scope || p.receipt.Token != receipt.Token || p.receipt.Owner != receipt.Owner || len(p.cfg.Rules) != 4 {
		t.Fatal("pure rule update replaced scope or failed to publish its actual rules")
	}
	for name, previous := range before {
		if tunnel.AllProxies()[name] != previous {
			t.Fatal("pure rule update rebuilt the proxy graph", name)
		}
	}
	sourceEcho(t, conn, "after-rule-update")
	branch, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer branch.Close()
	_ = branch.SetDeadline(time.Now().Add(3 * time.Second))
	if _, err := socks5.ClientHandshake(branch, socks5.ParseAddr("new.test:80"), socks5.CmdConnect, nil); err != nil {
		t.Fatal(err)
	}
	if answer, err := managedHTTP(branch, "new.test"); err != nil || answer != "R1-proxy" || proxy.count() != 1 {
		t.Fatal("new rule was not consumed by the actual matcher/proxy", answer, err)
	}
	if _, _, _, _, err := readConfigInput(C.Path.HomeDir(), p.receipt.InputID); err != nil {
		t.Fatal("hot rule manifest is not verifiable for replay", err)
	}
}

func TestSourceInlineUnchangedInputDoesNotConsumeRetirementOrRewriteCheckpoint(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	port := sourceInlineFixture(t)
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19001)))
	if result := adoptSourceInlineRequest(&request); result.Status != "applied" {
		t.Fatal(result)
	}
	p := appliedConfig
	if p.sourceRetiredCount != 0 {
		t.Fatal("metadata adoption consumed adapter retirement budget")
	}
	p.sourceRetiredCount, p.sourceRetiredBytes = sourceRetiredGenerationLimit, sourceMaterialTotal
	request = sourceInlineTestRequest(t, p.receipt.InputID)
	previous := writeConfigManifest
	writes := 0
	writeConfigManifest = func(path string, data []byte) error {
		writes++
		return previous(path, data)
	}
	defer func() { writeConfigManifest = previous }()
	before := p.receipt.InputID
	if result := adoptSourceInlineRequest(&request); result.Status != "applied" {
		t.Fatal(result)
	}
	if writes != 0 || p.receipt.InputID != before || p.sourceRetiredCount != sourceRetiredGenerationLimit {
		t.Fatal("unchanged input rewrote checkpoint or consumed retired generations", writes)
	}
}

func TestSourceInlineRulesDeferUnprovenR1AndMixedChanges(t *testing.T) {
	for _, negative := range []string{"protection", "delete-proxy", "new-default", "complex", "mixed", "old-quic-reader"} {
		t.Run(negative, func(t *testing.T) {
			if !sourceTestIsolation(t) {
				return
			}
			port := sourceInlineFixture(t)
			body := strings.Replace(sourceInlineYAML(port, 19001), `rules: ["MATCH,DIRECT"]`, `rules: ['DOMAIN-SUFFIX,protected.test,REJECT', 'DOMAIN,old.test,accepted', 'MATCH,DIRECT']`, 1)
			applyTestInput(t, sourceInlineNextInput(t, body))
			p, input := appliedConfig, configFact.InputID
			first := p.cfg.Rules[0]
			next := strings.Replace(body, `'MATCH,DIRECT']`, `'DOMAIN,new.test,accepted', 'MATCH,DIRECT']`, 1)
			switch negative {
			case "protection":
				next = strings.Replace(next, "protected.test", "weakened.test", 1)
			case "delete-proxy":
				next = strings.Replace(next, "'DOMAIN,old.test,accepted', ", "", 1)
			case "new-default":
				next = strings.Replace(next, "MATCH,DIRECT", "MATCH,REJECT", 1)
			case "complex":
				next = strings.Replace(next, "DOMAIN,new.test", "DOMAIN-KEYWORD,new", 1)
			case "mixed":
				next = strings.Replace(next, "port: 19001", "port: 19002", 1)
			case "old-quic-reader":
				recordSourceReaderRisk("quic-dns-reader")
			}
			request := sourceInlineTestRequest(t, sourceInlineNextInput(t, next))
			if result := adoptSourceInlineRequest(&request); result.Status != "deferred" {
				t.Fatal("unproven rule transition was not deferred", result)
			}
			if p.receipt.InputID != input || p.cfg.Rules[0] != first || p.scope.Check() != nil {
				t.Fatal("deferred rules changed live state or interrupted business")
			}
		})
	}
}
