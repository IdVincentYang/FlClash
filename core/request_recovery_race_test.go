package main

import (
	"os"
	"runtime"
	"strings"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func restoredRequestFixture(t *testing.T, invalidate bool) (*appRequestRegistry, appRequestControl, []byte) {
	t.Helper()
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	r := appRequests
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: client})
	marker := []byte("previous interrupted commit\n")
	if err := atomicConfigFile(requestRecoveryPath(C.Path.HomeDir()), marker); err != nil {
		t.Fatal(err)
	}
	id := r.control(appRequestControl{Action: "lock", Client: client}).(map[string]string)["id"]
	t.Cleanup(r.commits[id].Complete)
	params := appRequestControl{Action: "beginCommit", Client: client, ID: id}
	if result := r.control(params); result.(map[string]any)["recovery"] != true {
		t.Fatal(result)
	}
	if invalidate {
		params.Action = "invalidateDataset"
		r.control(params)
	}
	params.Action = "clearRecovery"
	return r, params, marker
}

func waitRecoveryControlLock(t *testing.T) bool {
	t.Helper()
	for deadline := time.Now().Add(2 * time.Second); time.Now().Before(deadline); {
		buffer := make([]byte, 1<<20)
		for _, stack := range strings.Split(string(buffer[:runtime.Stack(buffer, true)]), "\n\n") {
			if strings.Contains(stack, "clearRestoredRequestRecovery") && strings.Contains(stack, "sync.(*Mutex).Lock") {
				return true
			}
		}
		time.Sleep(time.Millisecond)
	}
	return false
}

func TestSourceRecoveryClearQueuedBehindDetach(t *testing.T) {
	r, params, marker := restoredRequestFixture(t, true)
	receipt := r.commits[params.ID]
	configMu.Lock()
	locked := true
	done := make(chan any, 1)
	go func() { done <- r.control(params) }()
	defer func() {
		if locked {
			configMu.Unlock()
			select {
			case <-done:
			case <-time.After(2 * time.Second):
				t.Error("queued control did not exit")
			}
		}
	}()
	if !waitRecoveryControlLock(t) {
		t.Fatal("clearRecovery did not queue at the actual configMu boundary")
	}
	r.detachFrontend()
	if !receipt.retired || unknownRequestWriters.Load() != 1 {
		t.Fatal("actual writer was not retired")
	}
	configMu.Unlock()
	locked = false
	select {
	case result := <-done:
		if errors, ok := result.(map[string]string); !ok || errors["error"] != "request_restart_required" {
			t.Errorf("queued old clear accepted: %v", result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("clearRecovery did not finish")
	}
	stored, err := readRequestRecoveryMarker(C.Path.HomeDir())
	if err != nil || string(stored) != string(marker) {
		t.Fatal("retired writer cleared the durable barrier", err)
	}
	params.Action = "complete"
	r.control(params)
	r.control(params)
	stored, err = readRequestRecoveryMarker(C.Path.HomeDir())
	if unknownRequestWriters.Load() != 0 || err != nil || string(stored) != string(marker) {
		t.Fatal("late/duplicate complete changed marker or writer count", err)
	}
}

func TestSourceRecoveryClearRequiresLiveRestoreReceipt(t *testing.T) {
	for _, change := range []string{"failed", "unready", "no-dataset-invalidation", "foreign-client", "completed", "foreign-marker"} {
		t.Run(change, func(t *testing.T) {
			r, params, marker := restoredRequestFixture(t, change != "no-dataset-invalidation")
			switch change {
			case "failed":
				mark := params
				mark.Action = "markRecovery"
				r.control(mark)
			case "unready":
				r.mu.Lock()
				r.clientReady = false
				r.mu.Unlock()
			case "foreign-client":
				params.Client = "another-client"
			case "completed":
				complete := params
				complete.Action = "complete"
				r.control(complete)
			case "foreign-marker":
				marker = []byte("newer recovery barrier\n")
				if err := atomicConfigFile(requestRecoveryPath(C.Path.HomeDir()), marker); err != nil {
					t.Fatal(err)
				}
			}
			result := r.control(params)
			if errors, ok := result.(map[string]string); !ok || errors["error"] == "" {
				t.Errorf("invalid restore cleared recovery: %v", result)
			}
			stored, err := readRequestRecoveryMarker(C.Path.HomeDir())
			if err != nil || string(stored) != string(marker) {
				t.Fatal("invalid restore changed marker", err)
			}
		})
	}
}

func TestSourceRecoveryClearAllowsQualifiedRestore(t *testing.T) {
	r, params, _ := restoredRequestFixture(t, true)
	if result := r.control(params); result.(map[string]bool)["ok"] != true {
		t.Fatal(result)
	}
	if _, err := os.Stat(requestRecoveryPath(C.Path.HomeDir())); !os.IsNotExist(err) {
		t.Fatal("qualified restore retained marker", err)
	}
	params.Action = "complete"
	if result := r.control(params); result.(map[string]bool)["ok"] != true {
		t.Fatal(result)
	}
	marker := []byte("successor marker\n")
	if err := atomicConfigFile(requestRecoveryPath(C.Path.HomeDir()), marker); err != nil {
		t.Fatal(err)
	}
	r.control(params)
	stored, err := readRequestRecoveryMarker(C.Path.HomeDir())
	if err != nil || string(stored) != string(marker) {
		t.Fatal("duplicate old completion cleared successor", err)
	}
}
