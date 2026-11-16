package main

import (
	"fmt"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func keyTestClient(t *testing.T, r *appRequestRegistry) string {
	t.Helper()
	previous := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	t.Cleanup(func() { C.SetHomeDir(previous) })
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: client})
	return client
}

func keyTestSnapshot(t *testing.T, r *appRequestRegistry, client, key string) map[string]any {
	t.Helper()
	result := r.control(appRequestControl{Action: "inspect", Client: client, Key: key})
	snapshot, ok := result.(map[string]any)
	if !ok {
		t.Fatal("inspect failed", result)
	}
	return snapshot
}

func keyTestRound(t *testing.T, r *appRequestRegistry, client, key string) {
	t.Helper()
	snapshot := keyTestSnapshot(t, r, client, key)
	result := r.control(appRequestControl{Action: "begin", Client: client, Key: key, Kind: "maintenance", Trigger: "manual", Mode: "direct", Proxy: "DIRECT", URL: "http://127.0.0.1:1", Dataset: snapshot["dataset"].(uint64), Owner: snapshot["owner"].(uint64), SourceRevision: snapshot["sourceRevision"].(uint64), ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}})
	grant, ok := result.(map[string]any)
	if !ok {
		t.Fatal("begin failed", result)
	}
	r.control(appRequestControl{Action: "cancel", Client: client, ID: grant["id"].(string)})
}

func TestRequestKeysBoundedHistory(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	for round := 0; round < 3; round++ {
		for i := 0; i < 4096; i++ {
			keyTestRound(t, r, client, fmt.Sprintf("icon:localhost/%d/%d", round, i))
			r.control(appRequestControl{Action: "invalidate", Client: client, Key: fmt.Sprintf("retired:%d/%d", round, i)})
		}
		if len(r.sources) > 4096 || len(r.operations) > 4096 {
			t.Fatalf("history grew after completed round %d: sources=%d operations=%d", round, len(r.sources), len(r.operations))
		}
	}
	for i := 0; i < 4; i++ {
		r.control(appRequestControl{Action: "detach", Client: client})
		client = r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
		r.control(appRequestControl{Action: "ready", Client: client})
	}
	if len(r.sources) != 0 || len(r.operations) != 0 {
		t.Fatal("unheld history survived detach", len(r.sources), len(r.operations))
	}
}

func TestRequestKeysExpiredSnapshotCannotReturn(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	key := "connection-exit:retired-entry"
	old := keyTestSnapshot(t, r, client, key)
	for i := 0; i < 4097; i++ {
		keyTestRound(t, r, client, fmt.Sprintf("connection-exit:other-%d", i))
	}
	current := keyTestSnapshot(t, r, client, key)
	if old["sourceRevision"] == current["sourceRevision"] || old["operation"] == current["operation"] {
		t.Fatal("expired snapshot regained its identity", old["sourceRevision"], current["sourceRevision"], old["operation"], current["operation"])
	}
	ticket := ConfigSourceTicket{Client: client, Dataset: old["dataset"].(uint64), Sources: map[string]uint64{key: old["sourceRevision"].(uint64)}}
	r.mu.Lock()
	valid := sourceTicketValidLocked(ticket, []string{key})
	r.mu.Unlock()
	if valid {
		t.Fatal("old source ticket accepted after eviction and recreation")
	}
}
