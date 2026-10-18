package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

func observedConfigFence() ConfigFence {
	fact := configStateSnapshot()
	return ConfigFence{RuntimeEpoch: fact.RuntimeEpoch, Version: fact.Version, Owner: fact.Owner, Token: fact.Token, InputID: fact.InputID, RouteEpoch: fact.RouteEpoch, PicksVersion: fact.PicksVersion}
}

func writeKeptTestInput(t *testing.T, yaml string, dependencies ...string) string {
	t.Helper()
	configMu.Lock()
	defer configMu.Unlock()
	id := writeTestInput(t, yaml, dependencies...)
	marker, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: inputHash([]byte(yaml)), RuntimeEpoch: configRuntimeEpoch})
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+"."+strings.Repeat("c", 24)+".candidate"), marker); err != nil {
		t.Fatal(err)
	}
	return id
}

func managedTestInput(t *testing.T) string {
	t.Helper()
	input := writeKeptTestInput(t, "mixed-port: 0\nmode: rule\nrules: [\"MATCH,REJECT\"]\n")
	return withManagedDescriptor(t, input, "")
}

func withManagedDescriptor(t *testing.T, input, maintenance string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(inputDirectory(C.Path.HomeDir()), input+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	_ = json.Unmarshal(data, &manifest)
	manifest.ManagedPolicy = &ManagedPolicyDescriptor{Version: 1, PolicySHA256: strings.Repeat("a", 64), MaintenanceProxy: maintenance}
	configMu.Lock()
	defer configMu.Unlock()
	data, _ = json.Marshal(manifest)
	id := inputHash(data)
	if err = atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	marker, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: manifest.YAMLSHA256, RuntimeEpoch: configRuntimeEpoch})
	if err = atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+"."+strings.Repeat("c", 24)+".candidate"), marker); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestManagedDescriptorRejectsOpenClosureBeforeReplacement(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	accepted := applyTestInput(t, writeKeptTestInput(t, "mode: rule\nrules: [\"MATCH,DIRECT\"]\n"))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: managedTestInput(t)})
	if result := prepareConfig(receipt); result.Status != "rejected" {
		t.Fatal(result)
	}
	if fact := configStateSnapshot(); fact.Owner != accepted.Fact.Owner || !fact.BusinessActive {
		t.Fatal(fact)
	}
}

func TestConfigFenceRejectsExistingRouteOrFactChanges(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	input := writeKeptTestInput(t, "mode: rule\nrules: [\"MATCH,DIRECT\"]\n")
	applyTestInput(t, input)
	before := observedConfigFence()
	bumpRouteEpoch()
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, ExpectedConfig: &before})
	if result := prepareConfig(receipt); result.Status != "staleInput" {
		t.Fatal(result)
	}
	if !configStateSnapshot().BusinessActive {
		t.Fatal("stale candidate stopped the accepted input")
	}
}

func TestBuildFailureAfterSourceRevocationAndLegalHotWriteBlocksOldOwner(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	applyTestInput(t, writeKeptTestInput(t, "mode: rule\nrules: [\"MATCH,DIRECT\"]\n"))
	before := observedConfigFence()
	checkpointMu.Lock()
	err := invalidateConfigCheckpointLocked("profile:7", false)
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	level := log.ERROR
	if err := updateConfig(&UpdateParams{LogLevel: &level}); err != nil {
		t.Fatal(err)
	}
	if configStateSnapshot().ReplayEligible {
		t.Fatal("hot write resurrected checkpoint")
	}
	if result := failConfigBuild(&ConfigBuildFailure{Expected: before}); result.Status != "blocked" || result.Fact.BusinessActive {
		t.Fatal(result)
	}
}

func TestBuildFailureRetainsQualifiedInputAndNeverClosesNewOwner(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	input := writeKeptTestInput(t, "mode: rule\nrules: [\"MATCH,DIRECT\"]\n")
	applyTestInput(t, input)
	before := observedConfigFence()
	if result := failConfigBuild(&ConfigBuildFailure{Expected: before}); result.Status != "retained" || !result.Fact.BusinessActive {
		t.Fatal(result)
	}
	rejected := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: writeKeptTestInput(t, "rules: [\n")})
	if result := prepareConfig(rejected); result.Status != "rejected" {
		t.Fatal(result)
	}
	if result := failConfigBuild(&ConfigBuildFailure{Expected: before, RegisteredToken: rejected.Token}); result.Status != "retained" {
		t.Fatal(result)
	}
	newer := applyTestInput(t, input)
	if result := failConfigBuild(&ConfigBuildFailure{Expected: before, RegisteredToken: rejected.Token}); result.Status != "superseded" {
		t.Fatal(result)
	}
	if fact := configStateSnapshot(); fact.Owner != newer.Fact.Owner || !fact.BusinessActive {
		t.Fatal("late failure changed new owner", fact)
	}
}

func compiledManagedInput(t *testing.T, fixture *managedFixture, maintenance string) string {
	t.Helper()
	path, err, message := fixture.compile(t)
	if err != nil {
		t.Fatal(err, message)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return withManagedDescriptor(t, writeKeptTestInput(t, string(data), "profile:7", "application-config"), maintenance)
}

func applyManagedInput(t *testing.T, input string) ConfigApplyResult {
	t.Helper()
	fence := observedConfigFence()
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true, ExpectedConfig: &fence})
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	if result := installConfig(prepared.Receipt); result.Status != "installed" {
		t.Fatal(result)
	}
	result := activateConfig(prepared.Receipt)
	if result.Status != "activated" {
		t.Fatal(result)
	}
	return result
}

func TestManagedActualConsumersAndWriteClosure(t *testing.T) {
	f := newManagedFixture(t)
	accepted := applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	if accepted.Fact.PolicyVersion != 1 || accepted.Fact.PolicySHA256 != strings.Repeat("a", 64) || accepted.Fact.MixedPort != f.mixedPort {
		t.Fatal(accepted.Fact)
	}
	if body, err := f.get("wide.example.test"); err != nil || body != "A" {
		t.Fatal(body, err)
	}
	if result, err := f.query("wide.example.test"); err != nil || len(result.Answer) == 0 {
		t.Fatal(result, err)
	}
	before := configStateSnapshot()
	direct, warning := tunnel.Direct, log.WARNING
	if err := updateConfig(&UpdateParams{Mode: &direct, LogLevel: &warning}); err == nil {
		t.Fatal("mixed invalid update accepted")
	}
	if configStateSnapshot().Version != before.Version {
		t.Fatal("rejected update mutated the fact")
	}
	if err := updateConfig(&UpdateParams{LogLevel: &warning}); err != nil {
		t.Fatal(err)
	}
	for _, params := range []ChangeProxyParams{
		{GroupName: "GLOBAL", ProxyName: "DIRECT", Owner: before.Owner, Token: before.Token},
		{GroupName: "fc-managed-group-a", ProxyName: "DIRECT", Owner: before.Owner, Token: before.Token},
		{GroupName: "fc-managed-group-a", ProxyName: "fc-managed-proxy-nodeA"},
	} {
		if result := handleChangeProxy(&params); result.Message == "" {
			t.Fatal("illegal or unowned selection accepted", params)
		}
	}
	params := ChangeProxyParams{GroupName: "fc-managed-group-a", ProxyName: "fc-managed-proxy-nodeA", Owner: before.Owner, Token: before.Token}
	if result := handleChangeProxy(&params); result.Message != "" {
		t.Fatal(result)
	}
	if result := handleUpdateExternalProvider("fc-managed-default-domain"); result == nil {
		t.Fatal("managed provider update accepted")
	}
	if result := handleSideLoadExternalProvider("fc-managed-default-domain", []byte("DOMAIN,sideload.test")); result == nil {
		t.Fatal("managed provider sideload accepted")
	}
	manifest, _, _, _, err := readConfigInput(C.Path.HomeDir(), configStateSnapshot().InputID)
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := manifest.SelectedMap["GLOBAL"]; exists {
		t.Fatal("checkpoint restored legacy GLOBAL")
	}
	if len(manifest.SelectedMap) != 2 || manifest.ManagedPolicy.PolicySHA256 != before.PolicySHA256 {
		t.Fatal(manifest)
	}
	revokedFrom := observedConfigFence()
	appRequests.mu.Lock()
	appRequests.client, appRequests.clientReady = "revocation-client", true
	appRequests.mu.Unlock()
	appRequests.control(appRequestControl{Action: "invalidate", Client: "revocation-client", Key: "application-config"})
	if !configStateSnapshot().BusinessActive || configStateSnapshot().ReplayEligible {
		t.Fatal("source revocation confused activity and replay qualification")
	}
	if err := updateConfig(&UpdateParams{LogLevel: &warning}); err != nil {
		t.Fatal(err)
	}
	if configStateSnapshot().ReplayEligible {
		t.Fatal("legal managed hot write resurrected replay")
	}
	if result := failConfigBuild(&ConfigBuildFailure{Expected: revokedFrom}); result.Status != "blocked" || result.Fact.BusinessActive {
		t.Fatal(result)
	}
	if _, err := f.query("unique-after-managed-failure.test"); err == nil {
		t.Fatal("blocked managed DNS still admitted a new query")
	}
}

func TestManagedCheckpointReplayKeepsClosureAndRevocation(t *testing.T) {
	f := newManagedFixture(t)
	accepted := applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	warning := log.WARNING
	if err := updateConfig(&UpdateParams{LogLevel: &warning}); err != nil {
		t.Fatal(err)
	}
	replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, raw, _, err := readConfigInput(C.Path.HomeDir(), replay.InputID)
	if err != nil || manifest.ManagedPolicy == nil || manifest.ManagedPolicy.PolicySHA256 != accepted.Fact.PolicySHA256 || raw.Mode != tunnel.Rule || raw.LogLevel != warning {
		t.Fatal(manifest, raw, err)
	}
	replay.Active = true
	prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), replay))
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" {
		t.Fatal(installed)
	}
	if result := activateConfig(installed.Receipt); result.Status != "activated" {
		t.Fatal(result)
	}
	if body, err := f.get("wide.example.test"); err != nil || body != "A" {
		t.Fatal(body, err)
	}
	appRequests.mu.Lock()
	appRequests.client, appRequests.clientReady = "replay-revocation", true
	appRequests.mu.Unlock()
	appRequests.control(appRequestControl{Action: "invalidate", Client: "replay-revocation", Key: "application-config"})
	if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err == nil {
		t.Fatal("revoked managed checkpoint remained replayable")
	}
}

func TestManagedMaintenanceInspectionKeepsDefaultAndOwnerTogether(t *testing.T) {
	f := newManagedFixture(t)
	first := applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	secondInput := compiledManagedInput(t, f, "fc-managed-group-b")
	r := appRequests
	r.mu.Lock()
	r.client, r.clientReady = "inspection-client", true
	r.state = AppRequestState{ProcessEpoch: "native", Revision: 1, IntentRevision: 1, IntentRunning: true, Phase: "started", ProtectPhase: "none"}
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	r.mu.Unlock()
	previousHook := requestscope.ProxyHook
	requestscope.ProxyHook = r.bindProxy
	t.Cleanup(func() { requestscope.ProxyHook = previousHook; r.closePrivate() })
	r.mu.Lock()
	registryHeld := true
	defer func() {
		if registryHeld {
			r.mu.Unlock()
		}
	}()
	inspected := make(chan any, 1)
	go func() {
		inspected <- r.control(appRequestControl{Action: "inspect", Client: "inspection-client", Key: "coherent-inspection"})
	}()
	serialized := false
	for deadline := time.Now().Add(time.Second); time.Now().Before(deadline); {
		if !selectMu.TryLock() {
			serialized = true
			break
		}
		selectMu.Unlock()
		time.Sleep(time.Millisecond)
	}
	if !serialized {
		t.Fatal("inspection did not protect its policy/owner snapshot")
	}
	replaced := make(chan ConfigApplyResult, 1)
	go func() { replaced <- applyManagedInput(t, secondInput) }()
	r.mu.Unlock()
	registryHeld = false
	old := (<-inspected).(map[string]any)
	if old["owner"] != first.Fact.Owner || old["maintenanceProxy"] != "fc-managed-group-a" {
		t.Fatal("mixed inspection identity", old)
	}
	var second ConfigApplyResult
	select {
	case second = <-replaced:
	case <-time.After(5 * time.Second):
		t.Fatal("configuration replacement did not complete after inspection")
	}
	begin := func(snapshot map[string]any) any {
		state := snapshot["state"].(AppRequestState)
		return r.control(appRequestControl{Action: "begin", Client: "inspection-client", Owner: snapshot["owner"].(uint64), Dataset: snapshot["dataset"].(uint64), Kind: "maintenance", Trigger: "manual", Key: "coherent-inspection", Mode: "proxy", Proxy: snapshot["maintenanceProxy"].(string), URL: "http://maintenance.test/", ExpectedState: &requestscope.StateVersion{Epoch: state.ProcessEpoch, Revision: state.Revision}})
	}
	if result := begin(old); result.(map[string]string)["error"] != "managed_maintenance_target_required" {
		t.Fatal("old inspection acquired the new owner", result)
	}
	if f.proxies[0].count() != 0 || f.proxies[1].count() != 0 || f.direct.Load() != 0 {
		t.Fatal("stale inspection sent a request")
	}
	current := r.control(appRequestControl{Action: "inspect", Client: "inspection-client", Key: "coherent-inspection"}).(map[string]any)
	if current["owner"] != second.Fact.Owner || current["maintenanceProxy"] != "fc-managed-group-b" {
		t.Fatal("new inspection did not use the new default", current)
	}
	lease, ok := begin(current).(map[string]any)
	if !ok {
		t.Fatal("current inspection could not acquire a lease")
	}
	proxyURL, _ := url.Parse("http://" + lease["endpoint"].(string))
	proxyURL.User = url.UserPassword(lease["user"].(string), lease["password"].(string))
	transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
	defer transport.CloseIdleConnections()
	response, err := (&http.Client{Transport: transport, Timeout: time.Second}).Get("http://maintenance.test/")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(response.Body)
	_ = response.Body.Close()
	if string(body) != "B" || f.proxies[0].count() != 0 || f.proxies[1].count() != 1 || f.direct.Load() != 0 {
		t.Fatal("default and receiver differed", string(body))
	}
}

func TestManagedMaintenanceDefaultIsExplicitAndOwnerBound(t *testing.T) {
	f := newManagedFixture(t)
	applyManagedInput(t, compiledManagedInput(t, f, ""))
	r := appRequests
	r.mu.Lock()
	r.client, r.clientReady = "managed-client", true
	r.state = AppRequestState{ProcessEpoch: "synthetic-managed", Revision: 1, IntentRevision: 1, IntentRunning: true, Phase: "started", Reason: "userStart", DefaultNetworkKind: "nonVpn", DirectNetworkID: "synthetic-network", ProtectPhase: "none"}
	r.mu.Unlock()
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	previousHook := requestscope.ProxyHook
	requestscope.ProxyHook = r.bindProxy
	t.Cleanup(func() { requestscope.ProxyHook = previousHook; r.closePrivate() })
	begin := func(target string, owner uint64) any {
		return r.control(appRequestControl{Action: "begin", Client: r.client, Owner: owner, Dataset: r.dataset, Kind: "maintenance", Trigger: "manual", Key: "managed-maintenance", Mode: "proxy", Proxy: target, URL: "http://maintenance.test/", ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}})
	}
	if result := begin("GLOBAL", configFact.Owner); result.(map[string]string)["error"] != "managed_maintenance_target_required" {
		t.Fatal(result)
	}
	if f.proxies[0].count() != 0 || f.proxies[1].count() != 0 {
		t.Fatal("absent default sent a request")
	}
	oldOwner := configFact.Owner
	applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	if result := begin("GLOBAL", oldOwner); result.(map[string]string)["error"] != "managed_maintenance_target_required" {
		t.Fatal("old owner accepted", result)
	}
	for _, target := range []string{"", "GLOBAL", "fc-managed-proxy-nodeB"} {
		result, ok := begin(target, configFact.Owner).(map[string]any)
		if !ok {
			t.Fatal("explicit accepted target unavailable", target)
		}
		proxyURL, _ := url.Parse("http://" + result["endpoint"].(string))
		proxyURL.User = url.UserPassword(result["user"].(string), result["password"].(string))
		transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
		response, err := (&http.Client{Transport: transport, Timeout: time.Second}).Get("http://maintenance.test/")
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(response.Body)
		_ = response.Body.Close()
		transport.CloseIdleConnections()
		expected := "A"
		if target == "fc-managed-proxy-nodeB" {
			expected = "B"
		}
		if string(body) != expected {
			t.Fatal("wrong maintenance receiver", string(body), expected)
		}
	}
	if result := begin("old-group", configFact.Owner); result.(map[string]string)["error"] != "managed_maintenance_target_required" {
		t.Fatal(result)
	}
	if f.direct.Load() != 0 || f.proxies[0].count() != 2 || f.proxies[1].count() != 1 {
		t.Fatal("maintenance receiver counts", f.direct.Load(), f.proxies[0].count(), f.proxies[1].count())
	}
}
