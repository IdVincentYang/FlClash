package main

import (
	"sync"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
)

type faultObservedMutex struct {
	sync.Mutex
	vetoBeforeUnlock bool
}

func (m *faultObservedMutex) Unlock() {
	m.vetoBeforeUnlock = requestNativeFault.Load()
	m.Mutex.Unlock()
}

func isolateNativeFault(t *testing.T) {
	t.Helper()
	previous := requestNativeFault.Swap(false)
	t.Cleanup(func() { requestNativeFault.Store(previous) })
}

func TestRequestLockScopeVetoPrecedesOwnedUnlock(t *testing.T) {
	isolateNativeFault(t)
	var mu faultObservedMutex
	failure := func() (result any) {
		defer func() { result = recover() }()
		lock := requestLockScope{mu: &mu}
		defer lock.finish()
		lock.Lock()
		panic("controlled invariant failure")
	}()
	if failure != "controlled invariant failure" || !mu.vetoBeforeUnlock || !mu.TryLock() {
		t.Fatalf("failure=%v veto-before-unlock=%v", failure, mu.vetoBeforeUnlock)
	}
	mu.Mutex.Unlock()
}

func TestRequestControlInvariantFailureReleasesInspectionLocks(t *testing.T) {
	isolateNativeFault(t)
	r := newAppRequestRegistry()
	r.client = "client"
	r.sourceVersions.values = nil
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("missing invariant failure")
			}
		}()
		r.control(appRequestControl{Action: "inspect", Client: "client", Key: "source"})
	}()
	if !requestNativeFault.Load() {
		t.Fatal("missing process veto")
	}
	for _, mu := range []*sync.Mutex{&selectMu, &checkpointMu, &r.mu} {
		if !mu.TryLock() {
			t.Fatal("inspection retained an owned lock")
		}
		mu.Unlock()
	}
	if result := r.control(appRequestControl{Action: "ready", Client: "client"}); result.(map[string]string)["error"] != "request_restart_required" {
		t.Fatal(result)
	}
}

func TestRequestNativeFaultKeepsCleanupAndWriterResponsibility(t *testing.T) {
	isolateNativeFault(t)
	previousWriters := unknownRequestWriters.Swap(0)
	t.Cleanup(func() { unknownRequestWriters.Store(previousWriters) })
	r := newAppRequestRegistry()
	r.state = AppRequestState{ProcessEpoch: "epoch", Revision: 1, IntentRunning: true, Phase: "started", DefaultNetworkKind: "nonVpn", DefaultNetworkID: "network"}
	r.owner, r.phase = requestscope.Owner{ID: 1}, "ready"
	spec := requestscope.Spec{Owner: r.owner, Kind: "provider", Proxy: "DIRECT", Mode: "direct"}
	if !r.allowedLocked(spec) {
		t.Fatal("healthy qualification rejected")
	}
	receipt := &appRequestReceipt{registry: r, id: "writer", client: "client", begun: true, retired: true}
	r.commits[receipt.id] = receipt
	unknownRequestWriters.Store(1)
	requestNativeFault.Store(true)
	if r.allowedLocked(spec) || businessAllowed(nil) || operationRunValidLocked(&configOperation{}) {
		t.Fatal("old qualification survived fault")
	}
	for _, action := range []string{"attach", "ready", "begin", "grant", "registerConfigInput", "clearRecovery"} {
		result := r.control(appRequestControl{Action: action})
		if result.(map[string]string)["error"] != "request_restart_required" {
			t.Fatalf("%s: %v", action, result)
		}
	}
	if unknownRequestWriters.Load() != 1 || r.commits[receipt.id] != receipt {
		t.Fatal("fault abandoned the real writer")
	}
	receipt.Complete()
	if unknownRequestWriters.Load() != 0 || len(r.commits) != 0 || !requestNativeFault.Load() || requestWriterError() == nil {
		t.Fatal("real completion cleared unrelated process fault")
	}
	r.dataReaders = map[string]struct{}{"reader": {}}
	if result := r.control(appRequestControl{Action: "endRead", ID: "reader"}); !result.(map[string]bool)["ok"] || len(r.dataReaders) != 0 {
		t.Fatal("cleanup was blocked")
	}
}
