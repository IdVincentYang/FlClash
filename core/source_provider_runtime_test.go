package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
)

func sourceRuntimeFixture(t *testing.T) {
	t.Helper()
	configTestHome(t)
	begin, resourceHook := requestscope.BeginHook, requestscope.ResourceHook
	requestscope.BeginHook, requestscope.ResourceHook = appRequests.begin, appRequests.lockResource
	t.Cleanup(func() {
		deadline := time.Now().Add(5 * time.Second)
		for inputCollectionQueued.Load() && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		if os.Getenv("FLCLASH_SOURCE_TEST_CHILD") == t.Name() {
			return
		}
		requestscope.BeginHook, requestscope.ResourceHook = begin, resourceHook
	})
	appRequests.state = AppRequestState{ProcessEpoch: "controlled-host-fixture", Revision: 1, IntentRunning: true, Phase: "started", DefaultNetworkKind: "nonVpn", DirectNetworkID: "localhost", ProtectPhase: "none"}
	appRequests.socketGate = func(string, AppRequestState, int) error { return nil }
	t.Cleanup(settleMessageBatcher)
}

func acceptSourceProviderFixture(t *testing.T, plan sourceProviderPlan, body []byte) sourceAcceptanceResult {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	configMu.Lock()
	defer configMu.Unlock()
	return acceptSourceProviderFixtureLocked(t, plan, body)
}

func acceptSourceProviderFixtureLocked(t *testing.T, plan sourceProviderPlan, body []byte) sourceAcceptanceResult {
	t.Helper()
	request := sourceAcceptanceRequest{Action: "review", Key: plan.Key, Kind: plan.Kind, Identity: plan.Declaration, Settings: sourceValueHash(plan.Mapping)}
	request.Provider, request.Parent, request.ProviderName = plan.Mapping, &plan.Parent, plan.Name
	request.Use, request.MaterialHash = &plan.Context, plan.ContextMaterialHash
	if plan.Kind == "provider-rule" {
		request.BodyBase64 = base64.StdEncoding.EncodeToString(body)
		request.Format, _ = plan.Mapping["format"].(string)
		request.Behavior, _ = plan.Mapping["behavior"].(string)
	} else {
		request.Body = string(body)
	}
	result, err := sourceAcceptance(C.Path.HomeDir(), request)
	if err != nil {
		t.Fatal(err)
	}
	if result.Status == "reviewRequired" {
		request.Action, request.Candidate, request.Routing = "accept", result.Candidate, "source"
		request.Automatic = plan.Kind == "provider-proxy"
		result, err = sourceAcceptance(C.Path.HomeDir(), request)
		if err != nil {
			t.Fatal(err)
		}
	}
	if result.Status != "accepted" || result.Use == nil {
		t.Fatal("controlled review did not accept the exact provider material")
	}
	return result
}

func sourceRuntimeInput(t *testing.T, yaml string, bodies map[string][]byte) string {
	t.Helper()
	configMu.Lock()
	defer configMu.Unlock()
	return sourceRuntimeInputLocked(t, yaml, bodies)
}

func sourceRuntimeInputLocked(t *testing.T, yaml string, bodies map[string][]byte) string {
	t.Helper()
	home := C.Path.HomeDir()
	id := writeTestInput(t, yaml)
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	var root SourceUse
	for _, use := range manifest.SourceUses {
		if use.Kind == "config" {
			root = use
		}
	}
	hash, err := sealSourceObject(home, []byte(yaml), sourceCandidateMax)
	if err != nil {
		t.Fatal(err)
	}
	plans, err := acceptedSourceProviderPlans(home, root, hash)
	if err != nil {
		t.Fatal(err)
	}
	for _, plan := range plans {
		body, present := bodies[plan.Kind+":"+plan.Name]
		if !present {
			t.Fatal("missing controlled provider material", plan.Name)
		}
		accepted := acceptSourceProviderFixtureLocked(t, plan, body)
		manifest.ProviderMaterials = append(manifest.ProviderMaterials, SourceProviderMaterial{Name: plan.Name, Kind: plan.Kind, Parent: plan.Parent, Declaration: plan.Declaration, MaterialHash: accepted.MaterialHash, Use: *accepted.Use})
		manifest.SourceUses = append(manifest.SourceUses, *accepted.Use)
	}
	derived, err := bindSourceProviderMaterials(home, root, hash, manifest.ProviderMaterials)
	if err != nil {
		t.Fatal(err)
	}
	manifest.SourceUses = slices.DeleteFunc(manifest.SourceUses, func(use SourceUse) bool { return use.Kind == "config" })
	manifest.SourceUses = canonicalSourceUses(append(manifest.SourceUses, derived))
	data, err = json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	id = inputHash(data)
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	return id
}

func sourceEchoConnection(t *testing.T, mixedPort int, permit ...func(string)) net.Conn {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	for _, allow := range permit {
		allow(listener.Addr().String())
	}
	go func() {
		conn, err := listener.Accept()
		if err == nil {
			defer conn.Close()
			_, _ = io.Copy(conn, conn)
		}
	}()
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	_ = conn.SetDeadline(time.Now().Add(8 * time.Second))
	if _, err := socks5.ClientHandshake(conn, socks5.ParseAddr(listener.Addr().String()), socks5.CmdConnect, nil); err != nil {
		t.Fatal(err)
	}
	return conn
}

func sourceEcho(t *testing.T, conn net.Conn, value string) {
	t.Helper()
	if _, err := conn.Write([]byte(value)); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, len(value))
	if _, err := io.ReadFull(conn, buf); err != nil || string(buf) != value {
		t.Fatal("existing business connection was interrupted", string(buf), err)
	}
}

func TestSourceRuleHotAdoptionKeepsScopeAndPersistsActualGeneration(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	yaml := configTestYAML(port) + "rule-providers:\n  accepted:\n    type: http\n    url: http://127.0.0.1:1/controlled\n    format: text\n    behavior: domain\n    interval: 0\n"
	id := sourceRuntimeInput(t, yaml, map[string][]byte{"provider-rule:accepted": []byte("old.invalid\n")})
	applyTestInput(t, id)
	p := appliedConfig
	var runtime *sourceProviderRuntime
	for _, candidate := range p.sourceProviders {
		runtime = candidate
	}
	if runtime == nil || runtime.rule == nil {
		t.Fatal("v2 material did not install the real stable RP wrapper")
	}
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "before")
	scope, receipt := p.scope, p.receipt
	next := []byte("new.invalid\n")
	acceptSourceProviderFixture(t, runtime.plan, next)
	if err := runtime.update(next); err != nil {
		t.Fatal(err)
	}
	if p.scope != scope || p.receipt.Token != receipt.Token || p.receipt.Owner != receipt.Owner || p.receipt.InputID == receipt.InputID || p.scope.Check() != nil {
		t.Fatal("provider update replaced the parent scope or did not advance material identity")
	}
	sourceEcho(t, conn, "after")
	if !runtime.rule.Match(&C.Metadata{Host: "new.invalid"}, C.RuleMatchHelper{}) || runtime.rule.Match(&C.Metadata{Host: "old.invalid"}, C.RuleMatchHelper{}) {
		t.Fatal("real RP matcher did not use the accepted generation")
	}
	ref, err := readCheckpointLocked(C.Path.HomeDir())
	if err != nil || ref.InputID != configFact.InputID || !configFact.ReplayEligible {
		t.Fatal("durable checkpoint differs from actual live material", err)
	}
	if _, _, _, _, err := readConfigInput(C.Path.HomeDir(), ref.InputID); err != nil {
		t.Fatal("adopted material cannot be verified for cold replay", err)
	}
}

func TestSourceRuleLivePersistenceFailureRetriesOnlyPersistence(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	id := sourceRuntimeInput(t, configTestYAML(port)+"rule-providers:\n  accepted: {type: http, url: 'http://127.0.0.1:1/controlled', format: text, behavior: domain}\n", map[string][]byte{"provider-rule:accepted": []byte("old.invalid\n")})
	applyTestInput(t, id)
	p := appliedConfig
	var runtime *sourceProviderRuntime
	for _, candidate := range p.sourceProviders {
		runtime = candidate
	}
	conn := sourceEchoConnection(t, port)
	next := []byte("new.invalid\n")
	acceptSourceProviderFixture(t, runtime.plan, next)
	previous := writeConfigManifest
	t.Cleanup(func() { writeConfigManifest = previous })
	writeConfigManifest = func(path string, data []byte) error {
		if filepath.Base(path) == "checkpoint.json" {
			return os.ErrPermission
		}
		return previous(path, data)
	}
	if err := runtime.update(next); err == nil {
		t.Fatal("failed durable save reported success")
	}
	if !configFact.BusinessActive || configFact.ReplayEligible || !configFact.MaterialPending || p.sourceRecovery == nil || p.scope.Check() != nil {
		t.Fatal("live persistence failure lost actual runtime facts or closed business")
	}
	sourceEcho(t, conn, "still-live")
	if _, err := readCheckpointLocked(C.Path.HomeDir()); err == nil {
		t.Fatal("old checkpoint remained replayable")
	}
	current := runtime.rule.current.Load()
	writeConfigManifest = previous
	if err := runtime.update([]byte("this body must never be parsed during retry")); err != nil {
		t.Fatal(err)
	}
	if runtime.rule.current.Load() != current || len(runtime.rule.generations) != 2 || !configFact.ReplayEligible || configFact.MaterialPending {
		t.Fatal("persistence retry repeated live mutation")
	}
	sourceEcho(t, conn, "saved")
}

func TestSourceProxyHotMaintenanceUsesOriginalProviderAndKeepsDirectTCP(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port := configTestPort(t)
	yaml := configTestYAML(port) + "proxy-providers:\n  accepted:\n    type: http\n    url: http://127.0.0.1:1/controlled\n    interval: 0\n    override: {udp: true}\n"
	old := []byte("proxies:\n  - {name: old, type: socks5, server: 127.0.0.1, port: 1, udp: false}\n")
	id := sourceRuntimeInput(t, yaml, map[string][]byte{"provider-proxy:accepted": old})
	applyTestInput(t, id)
	p := appliedConfig
	var runtime *sourceProviderRuntime
	for _, candidate := range p.sourceProviders {
		runtime = candidate
	}
	if runtime.proxy == nil {
		t.Fatal("accepted proxy material did not install the parent wrapper")
	}
	conn := sourceEchoConnection(t, port)
	sourceEcho(t, conn, "before")
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	version, original := runtime.proxy.Version(), runtime.proxy.ProxySetProvider
	oldProxy := runtime.proxy.Proxies()[0]
	scope, token, owner := p.scope, p.receipt.Token, p.receipt.Owner
	if err := runtime.update([]byte("proxies:\n  - {name: new, type: socks5, server: 127.0.0.1, port: 2, udp: false}\n")); err != nil {
		t.Fatal("delegated address/name maintenance was not adopted", err)
	}
	if runtime.proxy.ProxySetProvider != original || runtime.proxy.Version() != version+1 || len(runtime.retiredProxies) != 1 || runtime.retiredProxies[0][0] != oldProxy {
		t.Fatal("proxy maintenance replaced the provider, repeated publication or dropped pinned adapters")
	}
	if p.scope != scope || p.receipt.Token != token || p.receipt.Owner != owner || !runtime.proxy.Proxies()[0].SupportUDP() || runtime.proxy.Proxies()[0].Name() != "new" {
		t.Fatal("proxy maintenance changed parent identity or lost the original override")
	}
	sourceEcho(t, conn, "after")
	before := runtime.proxy.Version()
	p.sourceRetiredCount = sourceRetiredGenerationLimit
	if err := runtime.update([]byte("proxies:\n  - {name: next, type: socks5, server: 127.0.0.1, port: 3, udp: false}\n")); !errors.Is(err, errSourceBudget) {
		t.Fatal("retired generation budget did not defer mutation", err)
	}
	if runtime.proxy.Version() != before || runtime.proxy.Proxies()[0].Name() != "new" {
		t.Fatal("budget failure changed live provider")
	}
	sourceEcho(t, conn, "budget-preserved")
}

func TestSourceProviderConditional304KeepsAcceptedMaterialAndCheckpoint(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	requested := make(chan string, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requested <- r.Header.Get("If-None-Match")
		w.WriteHeader(http.StatusNotModified)
	}))
	defer server.Close()
	old := []byte("old.invalid\n")
	body := configTestYAML(configTestPort(t)) + fmt.Sprintf("rule-providers:\n  accepted: {type: http, url: '%s', behavior: domain, format: text, interval: 0}\n", server.URL)
	applyTestInput(t, sourceRuntimeInput(t, body, map[string][]byte{"provider-rule:accepted": old}))
	p := appliedConfig
	var runtime *sourceProviderRuntime
	for _, candidate := range p.sourceProviders {
		runtime = candidate
	}
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	previous := resource.ETag()
	resource.SetETag(true)
	defer resource.SetETag(previous)
	cachefile.Cache().SetETagWithHash(server.URL, cachefile.EtagWithHash{Hash: utils.MakeHash(old), ETag: "controlled-material"})
	input, generation, version := p.receipt.InputID, runtime.rule.current.Load(), configFact.Version
	if err := runtime.update(nil); err != nil {
		t.Fatal("legitimate conditional response did not retain accepted bytes", err)
	}
	if header := <-requested; header != "controlled-material" {
		t.Fatal("original vehicle did not bind its condition to accepted bytes", header)
	}
	if p.receipt.InputID != input || configFact.Version != version || runtime.rule.current.Load() != generation || p.sourceRetiredCount != 0 {
		t.Fatal("304 changed actual runtime/checkpoint material")
	}
}
