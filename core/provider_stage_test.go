//go:build no_zerotier

package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func stageTestEnvironment(t *testing.T) bool {
	t.Helper()
	if os.Getenv("FLCLASH_STAGE_TEST_CHILD") != t.Name() {
		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
		defer cancel()
		executable, err := os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		parts := strings.Split(t.Name(), "/")
		for i, part := range parts {
			parts[i] = "^" + regexp.QuoteMeta(part) + "$"
		}
		command := exec.CommandContext(ctx, executable, "-test.run="+strings.Join(parts, "/"), "-test.timeout=20s", "-test.v")
		command.Env = append(os.Environ(), "FLCLASH_STAGE_TEST_CHILD="+t.Name())
		output, err := command.CombinedOutput()
		if command.Process != nil {
			t.Logf("provider stage subprocess pid=%d\n%s", command.Process.Pid, output)
		}
		if err != nil {
			t.Fatal("real provider consumer failed", err)
		}
		return false
	}
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	swapConn(&fakeConn{})
	r := appRequests
	requestscope.OwnerHook, requestscope.PhaseHook = r.currentOwner, r.setPhase
	requestscope.BeginHook, requestscope.ResourceHook, requestscope.ReadyHook = r.begin, r.lockResource, r.waitReady
	requestscope.ProxyHook, requestscope.OwnerActiveHook, requestscope.BootstrapHook = r.bindProxy, r.ownerActive, r.needBootstrap
	r.state = AppRequestState{ProcessEpoch: "stage-test", Revision: 1, IntentRunning: true, Phase: "started", DefaultNetworkKind: "nonVpn", DirectNetworkID: "loopback-test", ProtectPhase: "none"}
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	t.Cleanup(func() {
		stagedCore.Lock()
		s := stagedCore.stage
		stagedCore.Unlock()
		if s != nil {
			s.retire()
			select {
			case <-s.done:
			case <-time.After(4 * time.Second):
				t.Error("stage did not exit")
			}
		}
		configMu.Lock()
		revokeBusiness()
		stopBusinessListeners()
		configMu.Unlock()
		for deadline := time.Now().Add(time.Second); inputCollectionQueued.Load() && time.Now().Before(deadline); {
			time.Sleep(time.Millisecond)
		}
		settleMessageBatcher()
	})
	return true
}

func stageInput(t *testing.T, port int, providers, groups string) ConfigReceipt {
	t.Helper()
	yaml := fmt.Sprintf("mixed-port: %d\nmode: rule\nfind-process-mode: off\ngeo-auto-update: false\nexternal-controller: ''\ndns: {enable: false}\nntp: {enable: false}\nprofile: {store-selected: false, store-fake-ip: false}\n%s\n%s\nrules: [\"MATCH,pick\"]\n", port, providers, groups)
	input := writeTestInput(t, yaml)
	registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	result := prepareConfig(registered)
	if result.Status != "prepared" {
		t.Fatal(result)
	}
	return result.Receipt
}

func stageHTTPInput(t *testing.T, port int, url string) ConfigReceipt {
	return stageInput(t, port, fmt.Sprintf("proxy-providers:\n  source:\n    type: http\n    url: %s\n    path: ./source.yaml\n    proxy: DIRECT", url), "proxy-groups:\n  - {name: pick, type: select, use: [source]}")
}

func stageBlockedSource(t *testing.T, body string) (string, <-chan struct{}, func()) {
	t.Helper()
	entered, release := make(chan struct{}), make(chan struct{})
	var once, enteredOnce sync.Once
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		enteredOnce.Do(func() { close(entered) })
		<-release
		_, _ = io.WriteString(w, body)
	}))
	unblock := func() { once.Do(func() { close(release) }) }
	t.Cleanup(func() { unblock(); server.Close() })
	return server.URL, entered, unblock
}

func stageAwait[T any](t *testing.T, ch <-chan T) T {
	t.Helper()
	select {
	case value := <-ch:
		return value
	case <-time.After(4 * time.Second):
		t.Fatal("timed out waiting for real consumer")
	}
	var zero T
	return zero
}

func stageNoBusiness(t *testing.T, port int) {
	t.Helper()
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
	if err != nil {
		return
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(50 * time.Millisecond))
	_, _ = c.Write([]byte{5, 1, 0})
	if n, _ := c.Read(make([]byte, 2)); n != 0 {
		t.Fatal("unaccepted configuration admitted business")
	}
}

func TestProviderStageAwaitsRealInitialAndPreservesConsumers(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	url, entered, release := stageBlockedSource(t, "proxies:\n  - {name: local, type: direct}\n")
	port := configTestPort(t)
	receipt := stageHTTPInput(t, port, url)
	result := make(chan ConfigApplyResult, 1)
	go func() { result <- installConfig(receipt) }()
	stageAwait(t, entered)
	configMu.Lock()
	work := pendingConfig.stage
	configMu.Unlock()
	if work == nil {
		t.Fatal("no real stage")
	}
	select {
	case <-work.ready:
		t.Fatal("Initial incorrectly complete")
	default:
	}
	duplicate := make(chan ConfigApplyResult, 1)
	go func() { duplicate <- installConfig(receipt) }()
	stageNoBusiness(t, port)
	if got := activateConfig(receipt); got.Status != "rejected" || got.Fact.BusinessActive {
		t.Fatal(got)
	}
	select {
	case got := <-result:
		t.Fatal("Apply returned before Initial, but installed", got)
	default:
	}
	release()
	if got := stageAwait(t, result); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := stageAwait(t, duplicate); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := activateConfig(receipt); got.Status != "activated" {
		t.Fatal(got)
	}
	providers := handleGetExternalProviders()
	if len(providers) != 1 || providers[0].Count != 1 {
		t.Fatal(providers)
	}
	p, _ := lookupExternalProvider("source")
	encoded, err := json.Marshal(p)
	if err != nil || !strings.Contains(string(encoded), "local") {
		t.Fatal(string(encoded), err)
	}
	lease, err := appRequests.begin(context.Background(), requestscope.Spec{Kind: "maintenance", Trigger: "manual", Mode: "auto", Proxy: "pick", Owner: requestscope.Owner{ID: receipt.Owner}, Key: "provider-route"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	if _, err := lease.(*appRequestLease).SelectProxy(lookupProxy("pick"), &C.Metadata{NetWork: C.TCP}); err != nil {
		t.Fatal(err)
	}
	if !lease.(*appRequestLease).current() {
		t.Fatal("wrapped provider invalidated an unchanged group route")
	}
	if got := handleSideLoadExternalProvider("source", []byte("proxies:\n  - {name: forbidden, type: zerotier, network: '0123456789abcdef'}\n")); got == nil || !strings.Contains(got.Message, "not supported") {
		t.Fatal(got)
	}
	if count := handleGetExternalProvider("source").Count; count != 1 {
		t.Fatal("bad candidate replaced legal set", count)
	}
	var received atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
		_, _ = io.WriteString(w, "normal-business")
	}))
	defer origin.Close()
	c := businessConnection(t, port, origin.Listener.Addr().String(), "socks")
	defer c.Close()
	_, _ = fmt.Fprintf(c, "GET / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", origin.Listener.Addr().String())
	response, err := http.ReadResponse(bufio.NewReader(c), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if string(body) != "normal-business" || received.Load() != 1 {
		t.Fatal(string(body), received.Load())
	}
}

func TestProviderStageFailureTimeoutAndReplacement(t *testing.T) {
	for _, mode := range []string{"failure", "stop", "timeout", "replacement", "source"} {
		t.Run(mode, func(t *testing.T) {
			if !stageTestEnvironment(t) {
				return
			}
			body := "proxies:\n  - {name: local, type: direct}\n"
			if mode == "failure" {
				body = "proxies:\n  - {name: forbidden, type: zerotier, network: '0123456789abcdef'}\n"
			}
			url, entered, release := stageBlockedSource(t, body)
			beforeTimeout := providerStageTimeout
			if mode == "timeout" {
				providerStageTimeout = 100 * time.Millisecond
			}
			t.Cleanup(func() { providerStageTimeout = beforeTimeout })
			port := configTestPort(t)
			receipt := stageHTTPInput(t, port, url)
			result := make(chan ConfigApplyResult, 1)
			go func() { result <- installConfig(receipt) }()
			stageAwait(t, entered)
			configMu.Lock()
			work := pendingConfig.stage
			configMu.Unlock()
			switch mode {
			case "failure":
				release()
			case "stop":
				if !handleStopListener() {
					t.Fatal("stop failed")
				}
			case "replacement":
				registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: receipt.InputID, Active: true})
			case "source":
				appRequests.mu.Lock()
				appRequests.client, appRequests.clientReady = "stage-client", true
				appRequests.mu.Unlock()
				appRequests.control(appRequestControl{Action: "invalidate", Client: "stage-client", Key: "profile:7"})
			}
			got := stageAwait(t, result)
			if got.Status == "installed" || got.Fact.BusinessActive {
				t.Fatal(got)
			}
			stageNoBusiness(t, port)
			release()
			stageAwait(t, work.done)
			providerStageTimeout = beforeTimeout
			recovery := stageInput(t, port, "proxies: [{name: local, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [local]}]")
			if got := installConfig(recovery); got.Status != "installed" {
				t.Fatal(got)
			}
			if got := activateConfig(recovery); got.Status != "activated" || got.Receipt.Owner == receipt.Owner {
				t.Fatal(got)
			}
		})
	}
}

func TestProviderStageWaitsForAllProxyAndRuleMaterials(t *testing.T) {
	for _, broken := range []bool{false, true} {
		t.Run(fmt.Sprint(broken), func(t *testing.T) {
			if !stageTestEnvironment(t) {
				return
			}
			if err := os.WriteFile(filepath.Join(C.Path.HomeDir(), "file.yaml"), []byte("proxies: [{name: file-node, type: direct}]"), 0600); err != nil {
				t.Fatal(err)
			}
			proxyURL, proxyEntered, proxyRelease := stageBlockedSource(t, "proxies: [{name: http-node, type: direct}]")
			ruleBody := "payload:\n  - example.test\n"
			if broken {
				ruleBody = "not-a-rule-file"
			}
			ruleURL, ruleEntered, ruleRelease := stageBlockedSource(t, ruleBody)
			port := configTestPort(t)
			receipt := stageInput(t, port, fmt.Sprintf(`proxy-providers:
  file: {type: file, path: ./file.yaml}
  remote: {type: http, url: %s, path: ./http.yaml, proxy: DIRECT}
rule-providers:
  domains: {type: http, behavior: domain, url: %s, path: ./rules.yaml, proxy: DIRECT}`, proxyURL, ruleURL), "proxy-groups: [{name: pick, type: select, use: [file, remote]}]")
			result := make(chan ConfigApplyResult, 1)
			go func() { result <- installConfig(receipt) }()
			stageAwait(t, proxyEntered)
			stageAwait(t, ruleEntered)
			proxyRelease()
			stageNoBusiness(t, port)
			select {
			case got := <-result:
				t.Fatal("late rule material was skipped", got)
			default:
			}
			ruleRelease()
			got := stageAwait(t, result)
			if broken {
				if got.Status == "installed" || got.Fact.BusinessActive {
					t.Fatal(got)
				}
				stageNoBusiness(t, port)
				return
			}
			if got.Status != "installed" {
				t.Fatal(got)
			}
			if got := activateConfig(receipt); got.Status != "activated" {
				t.Fatal(got)
			}
			if got := handleGetExternalProvider("domains"); got.Count != 1 {
				t.Fatal(got)
			}
			if err := handleSideLoadExternalProvider("domains", []byte("payload:\n  - updated.test\n")); err != nil {
				t.Fatal(err)
			}
			if got := handleGetExternalProvider("file"); got.Count != 1 {
				t.Fatal(got)
			}
		})
	}
}

func TestProviderStageStopWhileApplyStillOwnsCore(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var once, releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	t.Cleanup(unblock)
	requestscope.PhaseHook = func(owner requestscope.Owner, phase string) {
		appRequests.setPhase(owner, phase)
		if phase == "inner" {
			once.Do(func() { close(entered); <-release })
		}
	}
	providerStageTimeout = 200 * time.Millisecond
	port := configTestPort(t)
	receipt := stageInput(t, port, "proxies: [{name: local, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [local]}]")
	result := make(chan ConfigApplyResult, 1)
	go func() { result <- installConfig(receipt) }()
	stageAwait(t, entered)
	configMu.Lock()
	old := pendingConfig.stage
	configMu.Unlock()
	stopped := make(chan bool, 1)
	go func() { stopped <- handleStopListener() }()
	if !stageAwait(t, stopped) {
		t.Fatal("Stop failed")
	}
	if got := stageAwait(t, result); got.Status == "installed" {
		t.Fatal(got)
	}
	stageNoBusiness(t, port)
	next := stageInput(t, port, "proxies: [{name: next, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [next]}]")
	if got := installConfig(next); got.Status == "installed" {
		t.Fatal("new Apply bypassed old work", got)
	}
	stagedCore.Lock()
	retained := stagedCore.stage == old
	stagedCore.Unlock()
	if !retained {
		t.Fatal("unfinished Apply lost its admission")
	}
	unblock()
	stageAwait(t, old.done)
	recovery := stageInput(t, port, "proxies: [{name: recovered, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [recovered]}]")
	if got := installConfig(recovery); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := activateConfig(recovery); got.Status != "activated" {
		t.Fatal(got)
	}
}

func TestProviderStageShutdownTimeoutKeepsInitialQuarantined(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	url, entered, release := stageBlockedSource(t, "proxies: [{name: local, type: direct}]")
	providerStageTimeout = 150 * time.Millisecond
	port := configTestPort(t)
	receipt := stageHTTPInput(t, port, url)
	installed := make(chan ConfigApplyResult, 1)
	go func() { installed <- installConfig(receipt) }()
	stageAwait(t, entered)
	returning, allowReturn := make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(allowReturn) }) }
	t.Cleanup(unblock)
	configMu.Lock()
	work := pendingConfig.stage
	original := pendingConfig.cfg.Providers["source"].(*stagedProxyProvider).ProxySetProvider
	original.SetAfterUpdate(func() { close(returning); <-allowReturn })
	configMu.Unlock()
	release()
	stageAwait(t, returning)
	if handleShutdown() {
		t.Fatal("unfinished Initial was reported as closed")
	}
	stagedCore.Lock()
	closing := stagedCore.shutdown
	stagedCore.Unlock()
	if !isInit.Load() || handleInitClash(&InitParams{HomeDir: C.Path.HomeDir()}) {
		t.Fatal("timed out Shutdown released Init")
	}
	if handleShutdown() {
		t.Fatal("repeat Shutdown falsely completed")
	}
	stagedCore.Lock()
	same := stagedCore.shutdown == closing && stagedCore.stage == work
	stagedCore.Unlock()
	if !same {
		t.Fatal("repeat Shutdown spawned replacement work")
	}
	stageNoBusiness(t, port)
	unblock()
	stageAwait(t, installed)
	stageAwait(t, closing.done)
	if isInit.Load() || !shutdownGuardedCore(methodCallSeq.Load()) {
		t.Fatal("actual closure did not finish")
	}
	if !handleInitClash(&InitParams{HomeDir: C.Path.HomeDir()}) {
		t.Fatal("fresh Init could not recover")
	}
}

func TestProviderStageShutdownFencesInitAndOldArrivals(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	url, entered, release := stageBlockedSource(t, "proxies:\n  - {name: local, type: direct}\n")
	port := configTestPort(t)
	receipt := stageHTTPInput(t, port, url)
	installed := make(chan ConfigApplyResult, 1)
	go func() { installed <- installConfig(receipt) }()
	stageAwait(t, entered)
	initialReturning, allowReturn := make(chan struct{}), make(chan struct{})
	var allowOnce sync.Once
	unblockReturn := func() { allowOnce.Do(func() { close(allowReturn) }) }
	t.Cleanup(unblockReturn)
	configMu.Lock()
	original := pendingConfig.cfg.Providers["source"].(*stagedProxyProvider).ProxySetProvider
	original.SetAfterUpdate(func() { close(initialReturning); <-allowReturn })
	configMu.Unlock()
	release()
	stageAwait(t, initialReturning)
	closed := make(chan bool, 1)
	go func() { closed <- handleShutdown() }()
	for deadline := time.Now().Add(time.Second); !coreLifecycleUnavailable(0); {
		if time.Now().After(deadline) {
			t.Fatal("shutdown not entered")
		}
		time.Sleep(time.Millisecond)
	}
	otherHome := filepath.Join(t.TempDir(), "new-home")
	if handleInitClash(&InitParams{HomeDir: otherHome}) || !isInit.Load() || C.Path.HomeDir() == otherHome {
		t.Fatal("shutdown falsely released initialization")
	}
	beforeInit := methodCallSeq.Add(1)
	frames := captureFrames(t, func() {
		handleMethodCall(&MethodCall{ID: "closing", Method: getIsInitMethod}, newMethodResponse("closing", nil))
		arguments, _ := json.Marshal(InitParams{HomeDir: otherHome})
		handleMethodCall(&MethodCall{ID: "closing-init", Method: initClashMethod, Arguments: arguments}, newMethodResponse("closing-init", nil))
	})
	found := map[string]json.RawMessage{}
	for _, frame := range frames {
		var envelope map[string]any
		_ = json.Unmarshal(frame, &envelope)
		if id, ok := envelope["id"].(string); ok && (id == "closing" || id == "closing-init") && strings.Contains(string(frame), "core_lifecycle_unavailable") {
			found[id] = frame
		}
	}
	if len(found) != 2 {
		t.Fatal("missing real lifecycle error reply")
	}
	if path := os.Getenv("FLCLASH_PROVIDER_LIFECYCLE_RESPONSE"); path != "" {
		data, err := json.Marshal(found)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	stageNoBusiness(t, port)
	select {
	case <-closed:
		t.Fatal("physical shutdown finished before original Initial returned")
	default:
	}
	unblockReturn()
	if !stageAwait(t, closed) {
		t.Fatal("shutdown failed")
	}
	stageAwait(t, installed)
	if isInit.Load() {
		t.Fatal("physical shutdown did not clear initialization")
	}
	if guardedInitClash(&InitParams{HomeDir: otherHome}, beforeInit) {
		t.Fatal("queued Init recreated after shutdown")
	}
	if !handleInitClash(&InitParams{HomeDir: otherHome}) || C.Path.HomeDir() != otherHome {
		t.Fatal("fresh Init failed")
	}
	if !shutdownGuardedCore(beforeInit) || !isInit.Load() {
		t.Fatal("old Shutdown touched new initialization")
	}
}

func TestZeroTierDisabledFactoryAndOfflineCache(t *testing.T) {
	if _, err := adapter.ParseProxy(map[string]any{"name": "forbidden", "type": "zerotier", "network": "0123456789abcdef"}); err == nil || !strings.Contains(err.Error(), "no_zerotier") {
		t.Fatal(err)
	}
	if !stageTestEnvironment(t) {
		return
	}
	path := filepath.Join(C.Path.HomeDir(), "offline.yaml")
	if err := os.WriteFile(path, []byte("proxies:\n  - {name: excluded, type: zerotier, network: '0123456789abcdef'}\n  - {name: local, type: direct}\n"), 0600); err != nil {
		t.Fatal(err)
	}
	receipt := stageInput(t, configTestPort(t), "proxy-providers:\n  source:\n    type: file\n    path: ./offline.yaml\n    exclude-type: zerotier", "proxy-groups: [{name: pick, type: select, use: [source]}]")
	if got := installConfig(receipt); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := activateConfig(receipt); got.Status != "activated" {
		t.Fatal(got)
	}
}

func TestZeroTierDisabledRejectsConfigMaterials(t *testing.T) {
	for _, kind := range []string{"node", "inline", "file", "http-cache", "checkpoint"} {
		t.Run(kind, func(t *testing.T) {
			if !stageTestEnvironment(t) {
				return
			}
			forbidden := "{name: forbidden, type: zerotier, network: '0123456789abcdef'}"
			providers := "proxies: [" + forbidden + "]"
			groups := "proxy-groups: [{name: pick, type: select, proxies: [forbidden]}]"
			switch kind {
			case "inline":
				providers = "proxy-providers:\n  source:\n    type: inline\n    payload: [" + forbidden + "]"
			case "file", "http-cache":
				if err := os.WriteFile(filepath.Join(C.Path.HomeDir(), "bad.yaml"), []byte("proxies: ["+forbidden+"]"), 0600); err != nil {
					t.Fatal(err)
				}
				providers = "proxy-providers:\n  source:\n    type: file\n    path: ./bad.yaml"
				if kind == "http-cache" {
					url, _, release := stageBlockedSource(t, "proxies: ["+forbidden+"]")
					release()
					providers = fmt.Sprintf("proxy-providers:\n  source:\n    type: http\n    url: %s\n    path: ./bad.yaml\n    proxy: DIRECT", url)
				}
			}
			if kind != "node" && kind != "checkpoint" {
				groups = "proxy-groups: [{name: pick, type: select, use: [source]}]"
			}
			port := configTestPort(t)
			receipt := stageInput(t, port, providers, groups)
			var legacy []byte
			checkpoint := filepath.Join(inputDirectory(C.Path.HomeDir()), "checkpoint.json")
			if kind == "checkpoint" {
				legacy, _ = json.Marshal(configCheckpoint{Version: 1, InputID: receipt.InputID, Dependencies: []string{"profile:7", "script:9"}})
				if err := atomicConfigFile(checkpoint, legacy); err != nil {
					t.Fatal(err)
				}
				replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
				if err != nil {
					t.Fatal(err)
				}
				replay.Active = true
				prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), replay))
				if prepared.Status != "prepared" {
					t.Fatal(prepared)
				}
				receipt = prepared.Receipt
			}
			got := installConfig(receipt)
			if got.Status == "installed" || got.Fact.BusinessActive || !strings.Contains(got.Message, "ZeroTier is not supported on Android") {
				t.Fatal(got)
			}
			stageNoBusiness(t, port)
			if kind == "checkpoint" {
				data, err := os.ReadFile(checkpoint)
				if err != nil || string(data) != string(legacy) || got.Fact.ReplayEligible {
					t.Fatal("rejected replay renewed authority", err, got)
				}
			} else if _, err := os.Stat(checkpoint); !os.IsNotExist(err) {
				t.Fatal("rejected material published a checkpoint", err)
			}
		})
	}
}

func TestProviderStageAcceptsOfflineHTTPProviderCache(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	path := filepath.Join(C.Path.HomeDir(), "source.yaml")
	if err := os.WriteFile(path, []byte("proxies: [{name: cached, type: direct}]"), 0600); err != nil {
		t.Fatal(err)
	}
	receipt := stageHTTPInput(t, configTestPort(t), fmt.Sprintf("http://127.0.0.1:%d", configTestPort(t)))
	if got := installConfig(receipt); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := activateConfig(receipt); got.Status != "activated" {
		t.Fatal(got)
	}
	if got := handleGetExternalProvider("source"); got.Count != 1 {
		t.Fatal(got)
	}
}

type stageHeldClose struct {
	net.Conn
	entered, release chan struct{}
	once             sync.Once
}

func (conn *stageHeldClose) Close() error {
	conn.once.Do(func() { close(conn.entered); <-conn.release; _ = conn.Conn.Close() })
	return nil
}

func TestProviderStageRetirementJoinsTrackedNetworkClose(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	port := configTestPort(t)
	receipt := stageInput(t, port, "proxies: [{name: local, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [local]}]")
	if got := installConfig(receipt); got.Status != "installed" {
		t.Fatal(got)
	}
	if got := activateConfig(receipt); got.Status != "activated" {
		t.Fatal(got)
	}
	lease, err := appRequests.begin(context.Background(), requestscope.Spec{Kind: "maintenance", Trigger: "manual", Mode: "direct", Owner: requestscope.Owner{ID: receipt.Owner}, Key: "owned-close"})
	if err != nil {
		t.Fatal(err)
	}
	inbound, peer := net.Pipe()
	t.Cleanup(func() { _ = peer.Close() })
	conn := &stageHeldClose{Conn: inbound, entered: make(chan struct{}), release: make(chan struct{})}
	var once sync.Once
	unblock := func() { once.Do(func() { close(conn.release) }) }
	t.Cleanup(unblock)
	if err := lease.TrackConn(conn); err != nil {
		t.Fatal(err)
	}
	configMu.Lock()
	work := pendingConfig.stage
	configMu.Unlock()
	if !handleStopListener() {
		t.Fatal("stop failed")
	}
	stageAwait(t, conn.entered)
	work.abandon()
	select {
	case <-work.done:
		t.Fatal("retired work released admission before owned Close returned")
	default:
	}
	providerStageTimeout = 150 * time.Millisecond
	next := stageInput(t, port, "proxies: [{name: next, type: direct}]", "proxy-groups: [{name: pick, type: select, proxies: [next]}]")
	if got := installConfig(next); got.Status == "installed" {
		t.Fatal(got)
	}
	unblock()
	stageAwait(t, work.done)
}
