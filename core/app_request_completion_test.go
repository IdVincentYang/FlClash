package main

import (
	"fmt"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
)

func completionTestLease(t *testing.T, r *appRequestRegistry, client, key string) *appRequestLease {
	t.Helper()
	snapshot := keyTestSnapshot(t, r, client, key)
	result := r.control(appRequestControl{Action: "begin", Client: client, Key: key, Kind: "maintenance", Trigger: "manual", Mode: "direct", Proxy: "DIRECT", URL: "http://127.0.0.1:1", Dataset: snapshot["dataset"].(uint64), Owner: snapshot["owner"].(uint64), SourceRevision: snapshot["sourceRevision"].(uint64), ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}})
	grant, ok := result.(map[string]any)
	if !ok {
		t.Fatal("fixture admission failed", result)
	}
	l := r.leases[grant["id"].(string)]
	t.Cleanup(l.Close)
	return l
}

func completionTestHold(t *testing.T, r *appRequestRegistry, l *appRequestLease) string {
	t.Helper()
	result := r.control(appRequestControl{Action: "retainCompletion", Client: l.spec.Client, ID: l.id}).(map[string]string)
	if result["id"] == "" {
		t.Fatal("completion admission failed", result)
	}
	return result["id"]
}

func TestRequestCompletionSurvivesClosedLeaseAndHistoryPressure(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	l := completionTestLease(t, r, client, "script:41")
	id := completionTestHold(t, r, l)
	receipt, err := l.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	r.control(appRequestControl{Action: "invalidate", Client: client, Key: l.spec.Key})
	receipt.Complete()
	if !l.closed || len(r.commits) != 0 {
		t.Fatal("continuation retained network or write ownership")
	}
	for i := 0; i < requestHistoryLimit*2; i++ {
		keyTestRound(t, r, client, fmt.Sprintf("icon:after-script-%d", i))
	}
	snapshot := keyTestSnapshot(t, r, client, l.spec.Key)
	if snapshot["operation"] != l.spec.Operation || snapshot["sourceRevision"] != l.spec.SourceRevision+1 || len(r.completionHolds) != 1 {
		t.Fatal("unrelated history discarded a still-running continuation")
	}
	if len(r.operations) > requestHistoryLimit+1 || len(r.sources) > requestHistoryLimit+1 {
		t.Fatal("continuation exceeded the live plus cold bound")
	}
	r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: id})
	r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: id})
	if len(r.completionHolds) != 0 || r.operationVersions.entries[l.spec.Key].pins != 0 || r.sourceVersions.entries[l.spec.Key].pins != 0 {
		t.Fatal("completion or auxiliary ownership survived its release")
	}
}

func TestRequestCompletionAdmissionAndRevocation(t *testing.T) {
	for _, change := range []string{"operation", "source-twice", "dataset", "native", "detach"} {
		t.Run(change, func(t *testing.T) {
			r := revisionRegistry(t)
			client := keyTestClient(t, r)
			l := completionTestLease(t, r, client, "script:42")
			if result := r.control(appRequestControl{Action: "retainCompletion", Client: "wrong", ID: l.id}).(map[string]string); result["error"] == "" {
				t.Fatal("wrong client retained completion")
			}
			id := completionTestHold(t, r, l)
			if result := r.control(appRequestControl{Action: "releaseCompletion", Client: "wrong", ID: id}).(map[string]string); result["error"] == "" || len(r.completionHolds) != 1 {
				t.Fatal("wrong client released completion")
			}
			switch change {
			case "operation":
				next := completionTestLease(t, r, client, l.spec.Key)
				newID := completionTestHold(t, r, next)
				if len(r.completionHolds) != 1 || r.completionHolds[id] != nil {
					t.Fatal("new operation retained old continuation")
				}
				r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: id})
				if r.completionHolds[newID] == nil {
					t.Fatal("old release removed the new continuation")
				}
				r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: newID})
			case "source-twice":
				r.control(appRequestControl{Action: "invalidate", Client: client, Key: l.spec.Key})
				if len(r.completionHolds) != 1 {
					t.Fatal("own material invalidation revoked the continuation")
				}
				r.control(appRequestControl{Action: "invalidate", Client: client, Key: l.spec.Key})
			case "dataset":
				r.control(appRequestControl{Action: "invalidateDataset", Client: client})
			case "native":
				state := r.state
				state.Revision++
				r.publish(state)
			case "detach":
				r.control(appRequestControl{Action: "detach", Client: client})
			}
			if len(r.completionHolds) != 0 {
				t.Fatal("superseded continuation retained its pins", change)
			}
		})
	}
}

func TestRequestCompletionBudgetAndTerminalLeases(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	l := completionTestLease(t, r, client, "script:43")
	var ids []string
	for i := 0; i < requestCompletionLimit; i++ {
		ids = append(ids, completionTestHold(t, r, l))
	}
	if result := r.control(appRequestControl{Action: "retainCompletion", Client: client, ID: l.id}).(map[string]string); result["error"] == "" || l.granted || len(r.commits) != 0 {
		t.Fatal("full completion budget passed the pre-write boundary")
	}
	for _, id := range ids {
		r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: id})
	}
	receipt, err := l.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	if result := r.control(appRequestControl{Action: "retainCompletion", Client: client, ID: l.id}).(map[string]string); result["error"] == "" {
		t.Fatal("granted lease retained new completion authority")
	}
	receipt.Complete()
	l.Close()
	if result := r.control(appRequestControl{Action: "retainCompletion", Client: client, ID: l.id}).(map[string]string); result["error"] == "" || len(r.completionHolds) != 0 {
		t.Fatal("closed lease retained completion")
	}
}

func TestRequestVersionExhaustionRevokesLiveWork(t *testing.T) {
	for _, table := range []string{"source", "operation"} {
		t.Run(table, func(t *testing.T) {
			r := revisionRegistry(t)
			client := keyTestClient(t, r)
			if table == "source" {
				r.sourceVersions.highWater = requestVersionLimit - 2
			}
			l := completionTestLease(t, r, client, "script:44")
			id := completionTestHold(t, r, l)
			receipt, err := l.GrantCommit()
			if err != nil {
				t.Fatal(err)
			}
			if table == "source" {
				r.control(appRequestControl{Action: "invalidate", Client: client, Key: l.spec.Key})
			} else {
				r.operationVersions.highWater = requestVersionLimit - 2
				keyTestSnapshot(t, r, client, "last operation")
				keyTestSnapshot(t, r, client, "unallocatable operation")
			}
			if !l.closed || l.Context().Err() == nil || len(r.completionHolds) != 0 {
				t.Fatal("exhaustion left live qualification or a socket context")
			}
			r.mu.Lock()
			oldSource := r.sourceVersions.matches(l.spec.Key, l.spec.SourceRevision)
			internalAllowed := r.allowedLocked(requestscope.Spec{Owner: r.owner, Kind: "provider-local"})
			r.mu.Unlock()
			if oldSource || internalAllowed {
				t.Fatal("exhaustion preserved source or internal network qualification")
			}
			snapshot := keyTestSnapshot(t, r, client, "after exhaustion")
			if snapshot["sourceRevision"] != uint64(0) || snapshot["operation"] != uint64(0) {
				t.Fatal("exhaustion granted a fresh qualification")
			}
			receipt.Complete()
			r.control(appRequestControl{Action: "releaseCompletion", Client: client, ID: id})
			if len(r.commits) != 0 {
				t.Fatal("exhaustion blocked receipt completion")
			}
		})
	}
}
