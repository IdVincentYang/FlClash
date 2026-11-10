package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
	"testing"

	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func TestApplicationInputBridge(t *testing.T) {
	home := os.Getenv("FLCLASH_APPLICATION_INPUT_BRIDGE_HOME")
	if home == "" {
		t.Skip("local Flutter consumer bridge")
	}
	configTestEnvironment(t)
	previousProxyHook := requestscope.ProxyHook
	defer func() { requestscope.ProxyHook = previousProxyHook }()
	C.SetHomeDir(home)
	isInit.Store(true)
	var fixture *managedFixture
	var running sync.WaitGroup
	var output sync.Mutex
	emit := func(id int, result any) {
		encoded, err := json.Marshal(map[string]any{"id": id, "result": result})
		if err != nil {
			t.Error(err)
			return
		}
		output.Lock()
		fmt.Printf("application-input-bridge:%s\n", encoded)
		output.Unlock()
	}
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 128<<20)
	for scanner.Scan() {
		var call struct {
			ID        int             `json:"id"`
			Method    string          `json:"method"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &call); err != nil {
			t.Fatal(err)
		}
		var result any
		switch call.Method {
		case "sourceFrontendState":
			var snapshot struct {
				Client  string          `json:"client"`
				Dataset uint64          `json:"dataset"`
				State   AppRequestState `json:"state"`
			}
			if err := json.Unmarshal(call.Arguments, &snapshot); err != nil || snapshot.Client == "" || snapshot.State.ProcessEpoch == "" {
				t.Fatal("invalid controlled JVM source frontend snapshot", err)
			}
			configMu.Lock()
			appRequests.publish(snapshot.State)
			appRequests.mu.Lock()
			appRequests.client, appRequests.clientReady, appRequests.dataset = snapshot.Client, true, snapshot.Dataset
			appRequests.mu.Unlock()
			configMu.Unlock()
			result = map[string]bool{"ok": true}
		case "sourceState":
			if err := os.Setenv("FLCLASH_SOURCE_TEST_CHILD", t.Name()); err != nil {
				t.Fatal(err)
			}
			requestscope.BeginHook, requestscope.ResourceHook = appRequests.begin, appRequests.lockResource
			requestscope.ProxyHook = appRequests.bindProxy
			appRequests.socketGate = func(string, AppRequestState, int) error { return nil }
			appRequests.publish(AppRequestState{ProcessEpoch: "refresh-fixture", Revision: 1, IntentRevision: 1, Phase: "stopped", Reason: "initializedIdle", DefaultNetworkKind: "nonVpn", DirectNetworkID: "loopback", ProtectPhase: "none"})
			result = map[string]any{"ok": true}
		case "inlineBlock":
			var kind string
			if err := json.Unmarshal(call.Arguments, &kind); err != nil {
				t.Fatal(err)
			}
			configMu.Lock()
			switch kind {
			case "controller":
				recordSourceReaderRisk("controller-reader")
			case "retired":
				appliedConfig.sourceRetiredCount = sourceRetiredGenerationLimit
			default:
				t.Fatal("unknown inline block fixture")
			}
			configMu.Unlock()
			result = map[string]bool{"ok": true}
		case "source":
			var preview sourceAcceptanceRequest
			if err := json.Unmarshal(call.Arguments, &preview); err != nil {
				t.Fatal(err)
			}
			if preview.Action == "previewProvider" {
				running.Add(1)
				go func(id int, request sourceAcceptanceRequest) {
					defer running.Done()
					body, err := fetchSourceProviderMaterial(home, request)
					envelope := map[string]any{"id": "source-bridge"}
					if err != nil {
						envelope["error"] = map[string]any{"code": "source_material_unavailable", "message": "Provider material is unavailable"}
					} else {
						envelope["result"] = sourceAcceptanceResult{Status: "downloaded", BodyBase64: base64.StdEncoding.EncodeToString(body)}
					}
					emit(id, envelope)
				}(call.ID, preview)
				continue
			}
			frames := captureFrames(t, func() {
				handleMethodCall(&MethodCall{ID: "source-bridge", Method: sourceAcceptanceMethod, Arguments: call.Arguments}, newMethodResponse("source-bridge", nil))
			})
			for _, frame := range frames {
				var envelope struct {
					ID string `json:"id"`
				}
				if json.Unmarshal(frame, &envelope) == nil && envelope.ID == "source-bridge" {
					result = json.RawMessage(frame)
					break
				}
			}
			if result == nil {
				t.Fatal("source RPC did not produce its real response")
			}
		case "refreshState":
			requestscope.ProxyHook = appRequests.bindProxy
			appRequests.socketGate = func(string, AppRequestState, int) error { return nil }
			appRequests.publish(AppRequestState{ProcessEpoch: "refresh-fixture", Revision: 1, IntentRevision: 1, Phase: "stopped", Reason: "initializedIdle", DefaultNetworkKind: "nonVpn", DirectNetworkID: "loopback"})
			result = map[string]any{"ok": true}
		case "refreshRunning":
			appRequests.publish(AppRequestState{ProcessEpoch: "refresh-fixture", Revision: 2, IntentRevision: 2, IntentRunning: true, Phase: "started", Reason: "none", DefaultNetworkKind: "nonVpn", DirectNetworkID: "loopback", ProtectPhase: "none"})
			result = map[string]any{"ok": true}
		case "refreshRead":
			var name string
			if err := json.Unmarshal(call.Arguments, &name); err != nil {
				t.Fatal(err)
			}
			raw, err := handleGetConfig(name)
			if err != nil {
				result = map[string]any{"error": "read_failed"}
			} else {
				result = map[string]any{"value": raw}
			}
		case "refreshValidate":
			var name string
			if err := json.Unmarshal(call.Arguments, &name); err != nil {
				t.Fatal(err)
			}
			result = map[string]any{"value": handleValidateConfig(name)}
		case "refreshRelease":
			var name string
			if err := json.Unmarshal(call.Arguments, &name); err != nil {
				t.Fatal(err)
			}
			result = map[string]any{"value": collectConfigInputs(name) == nil}
		case "refreshGroups":
			result = map[string]any{"value": handleGetProxies()}
		case "refreshSelect":
			var params ChangeProxyParams
			if err := json.Unmarshal(call.Arguments, &params); err != nil {
				t.Fatal(err)
			}
			result = map[string]any{"value": handleChangeProxy(&params)}
		case "refreshProviders":
			result = map[string]any{"value": handleGetExternalProviders()}
		case "fixture", "refreshFixture":
			registry := appRequests
			fixture = newManagedFixture(t)
			if call.Method == "refreshFixture" {
				appRequests = registry
				requestscope.OwnerHook = registry.currentOwner
				requestscope.PhaseHook = registry.setPhase
			}
			C.SetHomeDir(home)
			result = fixture.policy
		case "allowRefreshTarget":
			var target string
			if err := json.Unmarshal(call.Arguments, &target); err != nil || fixture == nil {
				t.Fatal("invalid local target", err)
			}
			host, _, err := net.SplitHostPort(target)
			if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
				t.Fatal("fixture target must be loopback")
			}
			for _, proxy := range fixture.proxies {
				proxy.mu.Lock()
				proxy.allowed[target] = true
				proxy.mu.Unlock()
			}
			result = map[string]any{"ok": true}
		case "materialAuth":
			if fixture == nil {
				t.Fatal("material fixture unavailable")
			}
			var users []auth.AuthUser
			if err := json.Unmarshal(call.Arguments, &users); err != nil || len(users) != 2 {
				t.Fatal("invalid synthetic credentials", err)
			}
			for index, user := range users {
				fixture.proxies[index].mu.Lock()
				fixture.proxies[index].auth = auth.NewAuthenticator([]auth.AuthUser{user})
				fixture.proxies[index].mu.Unlock()
			}
			result = map[string]any{"ok": true}
		case "probe":
			var name string
			if err := json.Unmarshal(call.Arguments, &name); err != nil || fixture == nil {
				t.Fatal("invalid fixture probe", err)
			}
			body, businessErr := fixture.get(name)
			response, dnsErr := fixture.query(name)
			rcode := -1
			if response != nil {
				rcode = response.Rcode
			}
			counts := make([]int, len(fixture.servers))
			for index, server := range fixture.servers {
				counts[index] = server.count()
			}
			result = map[string]any{"body": body, "businessFailed": businessErr != nil, "dnsFailed": dnsErr != nil, "rcode": rcode, "dnsCounts": counts, "proxyCounts": []int{fixture.proxies[0].count(), fixture.proxies[1].count()}, "direct": fixture.direct.Load()}
		case "stop":
			result = map[string]any{"stopped": handleStopListener()}
		case "nativeState":
			appRequests.mu.Lock()
			data, _ := json.Marshal(appRequests.state)
			appRequests.mu.Unlock()
			state := make(map[string]any)
			_ = json.Unmarshal(data, &state)
			token := uint64(0)
			if current := latestConfig.Load(); current != nil {
				token = current.token
			}
			state["configToken"] = token
			result = state
		case "fail":
			var request ConfigBuildFailure
			if err := json.Unmarshal(call.Arguments, &request); err != nil {
				t.Fatal(err)
			}
			result = failConfigBuild(&request)
		case "control":
			var params appRequestControl
			if err := json.Unmarshal(call.Arguments, &params); err != nil {
				t.Fatal(err)
			}
			result = appRequests.control(params)
		case "fact":
			result = configStateSnapshot()
		case "register":
			var request ConfigInputRequest
			if err := json.Unmarshal(call.Arguments, &request); err != nil {
				t.Fatal(err)
			}
			result = registerConfigOperation(methodCallSeq.Add(1), request)
		case "prepare", "install", "activate", "abort":
			var receipt ConfigReceipt
			if err := json.Unmarshal(call.Arguments, &receipt); err != nil {
				t.Fatal(err)
			}
			switch call.Method {
			case "prepare":
				result = prepareConfig(receipt)
			case "install":
				result = installConfig(receipt)
			case "activate":
				result = activateConfig(receipt)
			case "abort":
				result = abortConfig(receipt)
			}
		default:
			t.Fatal("unknown bridge method")
		}
		emit(call.ID, result)
	}
	running.Wait()
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
}
