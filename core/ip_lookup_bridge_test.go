package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"testing"
)

func TestIPLookupBridge(t *testing.T) {
	if os.Getenv("FLCLASH_IP_BRIDGE") == "" {
		t.Skip("local Dart IP consumer bridge")
	}
	registry := revisionRegistry(t)
	var hold atomic.Bool
	var received, cancelled atomic.Int32
	outboundFixture(t, func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
		fmt.Fprint(w, "ip=1.1.1.1\nloc=AU\n")
		if hold.Load() {
			w.(http.Flusher).Flush()
			<-r.Context().Done()
			cancelled.Add(1)
		}
	}, true)
	var output sync.Mutex
	emit := func(id int, result any) {
		payload, _ := json.Marshal(map[string]any{"id": id, "result": result})
		output.Lock()
		fmt.Printf("application-input-bridge:%s\n", payload)
		output.Unlock()
	}
	var running sync.WaitGroup
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
		case "control":
			var p appRequestControl
			if err := json.Unmarshal(call.Arguments, &p); err != nil {
				t.Fatal(err)
			}
			result = registry.control(p)
		case "state":
			registry.mu.Lock()
			payload, _ := json.Marshal(registry.state)
			registry.mu.Unlock()
			var state map[string]any
			_ = json.Unmarshal(payload, &state)
			result = state
		case "route":
			epoch, picks := routeStamp()
			result = map[string]any{"core-epoch": epoch, "picks-version": picks}
		case "hold":
			var value bool
			_ = json.Unmarshal(call.Arguments, &value)
			hold.Store(value)
			result = map[string]any{"ok": true}
		case "counts":
			result = map[string]any{"received": received.Load(), "cancelled": cancelled.Load()}
		case "outbound":
			var p OutboundIpParams
			if err := json.Unmarshal(call.Arguments, &p); err != nil {
				t.Fatal(err)
			}
			running.Add(1)
			go func(id int, p OutboundIpParams) { defer running.Done(); emit(id, handleOutboundIp(&p)) }(call.ID, p)
			continue
		default:
			t.Fatal("unknown bridge method")
		}
		emit(call.ID, result)
	}
	running.Wait()
}
