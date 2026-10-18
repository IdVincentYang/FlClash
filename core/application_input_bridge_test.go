package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestApplicationInputBridge(t *testing.T) {
	home := os.Getenv("FLCLASH_APPLICATION_INPUT_BRIDGE_HOME")
	if home == "" {
		t.Skip("local Flutter consumer bridge")
	}
	configTestEnvironment(t)
	C.SetHomeDir(home)
	isInit.Store(true)
	var fixture *managedFixture
	scanner := bufio.NewScanner(os.Stdin)
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
		case "fixture":
			fixture = newManagedFixture(t)
			C.SetHomeDir(home)
			result = fixture.policy
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
		case "prepare", "install", "activate":
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
			}
		default:
			t.Fatal("unknown bridge method")
		}
		encoded, err := json.Marshal(map[string]any{"id": call.ID, "result": result})
		if err != nil {
			t.Fatal(err)
		}
		fmt.Printf("application-input-bridge:%s\n", encoded)
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
}
