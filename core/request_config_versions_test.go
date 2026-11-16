package main

import (
	"fmt"
	"os"
	"sync"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func TestRequestKeysConcurrentLifecycle(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	for round := 0; round < 3; round++ {
		var workers sync.WaitGroup
		for worker := 0; worker < 4; worker++ {
			workers.Add(1)
			go func(worker int) {
				defer workers.Done()
				for i := 0; i < 512; i++ {
					keyTestRound(t, r, client, fmt.Sprintf("parallel:%d/%d/%d", round, worker, i))
				}
			}(worker)
		}
		workers.Wait()
		r.mu.Lock()
		bounded := len(r.sources) <= requestHistoryLimit && len(r.operations) <= requestHistoryLimit &&
			len(r.sourceVersions.entries) == len(r.sources) && len(r.operationVersions.entries) == len(r.operations) &&
			r.sourceVersions.cold.Len() == len(r.sources) && r.operationVersions.cold.Len() == len(r.operations)
		r.mu.Unlock()
		if !bounded {
			t.Fatal("completed concurrent work retained a version holder or an auxiliary key")
		}
	}
}

func TestRequestKeysOldCloseAndClientCannotRevokeNewWork(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	old := completionTestLease(t, r, client, "same-node")
	next := completionTestLease(t, r, client, old.spec.Key)
	old.Close()
	if next.Check() != nil {
		t.Fatal("late old close revoked the replacement")
	}
	newClient := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: newClient})
	latest := completionTestLease(t, r, newClient, old.spec.Key)
	result := r.control(appRequestControl{Action: "begin", Client: client, Dataset: r.dataset, Owner: r.owner.ID, Key: old.spec.Key, SourceRevision: latest.spec.SourceRevision, Kind: "maintenance", Mode: "direct", Proxy: "DIRECT", Trigger: "manual", ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}})
	if result.(map[string]string)["error"] != "request_cancelled" {
		t.Fatal("old client began a new operation")
	}
	r.control(appRequestControl{Action: "cancel", Client: client, ID: old.id})
	if latest.Check() != nil {
		t.Fatal("old client's late request revoked the new lease")
	}
}

func TestRequestConfigSourcesSurviveHistoryAndFailureQualification(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	applyTestInput(t, input)
	p := appliedConfig
	appRequests.mu.Lock()
	for i := 0; i < requestHistoryLimit*2; i++ {
		appRequests.sourceVersionLocked(fmt.Sprintf("expired-source:%d", i))
	}
	valid := true
	for key, version := range p.sources {
		valid = valid && appRequests.sourceVersions.matches(key, version)
	}
	appRequests.mu.Unlock()
	if !valid {
		t.Fatal("current configuration lost its source qualification to history")
	}
	configMu.Lock()
	candidate, err := prepareCheckpointCandidate(nil, nil)
	if err == nil {
		err = publishCheckpointCandidate(candidate)
	}
	configMu.Unlock()
	if err != nil || candidate == nil || !candidate.published {
		t.Fatal("protected sources could not publish the real checkpoint", err)
	}
	if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err != nil {
		t.Fatal("history revoked the real replay checkpoint", err)
	}
	before := configStateSnapshot()
	registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: inputHash([]byte("failed replacement"))})
	result := failConfigBuild(&ConfigBuildFailure{Expected: ConfigFence{RuntimeEpoch: before.RuntimeEpoch, Owner: before.Owner, Token: before.Token}, RegisteredToken: registered.Token})
	if result.Status != "retained" || appliedConfig != p {
		t.Fatal("failConfigBuild lost the qualified prior configuration", result.Status)
	}
}

func TestRequestFailedPendingDoesNotPinSourceHistory(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input})
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" {
		t.Fatal(prepared.Status, prepared.Message)
	}
	p := pendingConfig
	if result := abortConfig(prepared.Receipt); result.Status != "blocked" {
		t.Fatal(result.Status)
	}
	if pendingConfig != p || p.sourcePins != nil {
		t.Fatal("failed pending retained source ownership or lost the expected fixture pointer")
	}
	appRequests.mu.Lock()
	for i := 0; i < requestHistoryLimit+1; i++ {
		appRequests.sourceVersionLocked(fmt.Sprintf("after-failure:%d", i))
	}
	for key := range p.sources {
		if appRequests.sourceVersions.entries[key] != nil {
			t.Error("failed dependency remained pinned", key)
		}
	}
	appRequests.mu.Unlock()
	if _, err := pendingForReceipt(prepared.Receipt); err == nil {
		t.Fatal("empty version history revived failed configuration")
	}
}

func requestTestHistoryPressure(t *testing.T, r *appRequestRegistry) {
	t.Helper()
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := 0; i < requestHistoryLimit*2; i++ {
		key := fmt.Sprintf("unrelated-lifetime-pressure:%d", i)
		r.sourceVersionLocked(key)
		r.operationVersionLocked(key)
	}
}

func TestRequestMaterialReceiptSurvivesHistory(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, _ := sourceLocalApprovalFixture(t, "source")
	request = sourceLocalCommitFixture(t, request)
	requestTestHistoryPressure(t, appRequests)
	request.Action = "invalidateMaterialSource"
	sourceMaterialRPCOK(t, request)
	requestTestHistoryPressure(t, appRequests)
	path, _ := sourceMaterialTarget(C.Path.HomeDir(), request.Key, request.Kind)
	if err := atomicConfigFile(path, []byte(request.Body)); err != nil {
		t.Fatal(err)
	}
	request.Action = "publishMaterialCommit"
	result := sourceMaterialRPCOK(t, request)
	if result.Status != "accepted" || result.Use == nil {
		t.Fatal(result)
	}
	if result := appRequests.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client}); result.(map[string]bool)["ok"] != true {
		t.Fatal(result)
	}
	if _, err := os.Stat(requestRecoveryPath(C.Path.HomeDir())); !os.IsNotExist(err) {
		t.Fatal(err)
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	if appRequests.operationVersions.entries[request.Key].pins != 0 {
		t.Fatal("completed material retained its operation")
	}
}

func TestRequestInlineProviderAndCheckpointSurviveHistory(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	port := sourceInlineFixture(t)
	p := appliedConfig
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19002)))
	requestTestHistoryPressure(t, appRequests)
	result := adoptSourceInlineRequest(&request)
	if result.Status != "applied" || appliedConfig != p {
		t.Fatal(result)
	}
	requestTestHistoryPressure(t, appRequests)
	checkpointMu.Lock()
	_, err := readCheckpointLocked(C.Path.HomeDir())
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal("adopted provider checkpoint lost dependencies", err)
	}
}
