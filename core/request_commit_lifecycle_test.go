package main

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func TestSourceDetachedCommitReadinessRegression(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	r := appRequests
	r.client, r.clientReady = "lost-engine", true
	id := r.control(appRequestControl{Action: "lock", Client: r.client}).(map[string]string)["id"]
	receipt := r.commits[id]
	t.Cleanup(receipt.Complete)
	if result := r.control(appRequestControl{Action: "beginCommit", ID: id, Client: r.client}); result.(map[string]bool)["ok"] != true {
		t.Fatal(result)
	}
	r.control(appRequestControl{Action: "engineDetach"})
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: client})
	if !r.clientReady {
		t.Fatal("new client waits on abandoned receipt instead of showing recovery")
	}
}

func TestSourceDetachedWriterRequiresRealCompletion(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, _ := sourceLocalApprovalFixture(t, "source")
	request = sourceLocalCommitFixture(t, request)
	r := appRequests
	receipt := r.commits[request.Receipt]
	t.Cleanup(func() { receipt.Complete() })
	marker, err := readRequestRecoveryMarker(C.Path.HomeDir())
	if err != nil || marker == nil {
		t.Fatal(err)
	}
	r.control(appRequestControl{Action: "engineDetach"})
	if !receipt.retired || unknownRequestWriters.Load() != 1 {
		t.Fatal("writer not retired exactly once")
	}
	r.control(appRequestControl{Action: "engineDetach"})
	if unknownRequestWriters.Load() != 1 {
		t.Fatal("duplicate detach counted twice")
	}
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	ready := r.control(appRequestControl{Action: "ready", Client: client})
	if ready.(map[string]any)["state"] == nil || !r.clientReady {
		t.Fatal("retired writer blocked recovery UI", ready)
	}
	start := time.Now()
	if _, err := r.beginDataRead(context.Background()); !errors.Is(err, errRequestWriterUnknown) {
		t.Fatal(err)
	}
	if err := r.waitFrontendCommits(context.Background()); !errors.Is(err, errRequestWriterUnknown) {
		t.Fatal(err)
	}
	if time.Since(start) > time.Second {
		t.Fatal("read waited on unknown writer")
	}
	for _, action := range []string{"lock", "beginCommit", "clearRecovery"} {
		result := r.control(appRequestControl{Action: action, Client: client, ID: request.Receipt})
		if result.(map[string]string)["error"] != errRequestWriterUnknown.Error() {
			t.Fatal(action, result)
		}
	}
	request.Action = "publishMaterialCommit"
	if _, err := sourceMaterialRPC(t, request); err == nil || err.Code != errRequestWriterUnknown.Error() {
		t.Fatal("retired candidate published", err)
	}
	request.Action = "review"
	if _, err := sourceMaterialRPC(t, request); err == nil || err.Code != errRequestWriterUnknown.Error() {
		t.Fatal("new trust while writer unknown", err)
	}
	recovery := sourceAcceptanceRequest{Key: "application-config", Kind: "config", Source: ConfigSourceTicket{Client: client, Dataset: r.dataset, Sources: map[string]uint64{"application-config": 0}}, Recovery: &sourceRecoverySnapshot{}}
	if _, err := sourceMaterialRecoverySnapshot(C.Path.HomeDir(), recovery); !errors.Is(err, errRequestWriterUnknown) {
		t.Fatal("offline check raced writer", err)
	}
	configReceipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: inputHash([]byte("blocked config"))})
	if result := prepareConfig(configReceipt); result.Message != errRequestWriterUnknown.Error() {
		t.Fatal("configuration bypass", result)
	}
	if latestConfig.Load().reading.Load() {
		t.Fatal("rejected config retained its active read pin")
	}
	// Rebuilding a registry or native state is not process death.
	fresh := newAppRequestRegistry()
	if _, err := fresh.beginDataRead(context.Background()); !errors.Is(err, errRequestWriterUnknown) {
		t.Fatal("new registry forgot writer", err)
	}
	fresh.publish(AppRequestState{ProcessEpoch: "replacement", Revision: 1})
	if requestWriterError() == nil {
		t.Fatal("native epoch released writer")
	}
	foreign := []byte("foreign recovery marker\n")
	if err := os.WriteFile(requestRecoveryPath(C.Path.HomeDir()), foreign, 0600); err != nil {
		t.Fatal(err)
	}
	result := r.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
	if result.(map[string]string)["error"] != "request_partial_commit" || unknownRequestWriters.Load() != 0 {
		t.Fatal(result)
	}
	r.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
	if unknownRequestWriters.Load() != 0 {
		t.Fatal("duplicate completion underflow")
	}
	stored, _ := readRequestRecoveryMarker(C.Path.HomeDir())
	if string(stored) != string(foreign) {
		t.Fatal("late completion cleared foreign marker")
	}
	if len(marker) == 0 {
		t.Fatal("missing original durable marker")
	}
	if _, err := sourceMaterialRecoverySnapshot(C.Path.HomeDir(), recovery); err != nil {
		t.Fatal("ended writer still blocks explicit offline check", err)
	}
}

func TestSourceDetachBeforeBeginCannotEnterWriter(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, _ := sourceLocalApprovalFixture(t, "source")
	request.Action = "grantLocalMaterialCommit"
	granted := sourceMaterialRPCOK(t, request)
	r := appRequests
	phase := r.phase
	r.control(appRequestControl{Action: "engineDetach"})
	if unknownRequestWriters.Load() != 0 || len(r.commits) != 0 || r.phase != phase {
		t.Fatal("empty receipt retired running state")
	}
	if result := r.control(appRequestControl{Action: "beginCommit", Client: request.Source.Client, ID: granted.Receipt}); result.(map[string]string)["error"] != "request_cancelled" {
		t.Fatal(result)
	}
	if _, err := os.Stat(requestRecoveryPath(C.Path.HomeDir())); !os.IsNotExist(err) {
		t.Fatal("empty receipt left marker", err)
	}
}

func TestSourceFrontendCommitBudgetAndOrdinaryDetach(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	r := appRequests
	r.client, r.clientReady = "budget-client", true
	phase := r.phase
	r.control(appRequestControl{Action: "engineDetach"})
	if unknownRequestWriters.Load() != 0 || r.phase != phase {
		t.Fatal("ordinary detach changed runtime qualification")
	}
	r.clientReady = true
	for i := 0; i < frontendCommitLimit; i++ {
		result := r.control(appRequestControl{Action: "lock", Client: r.client})
		if result.(map[string]string)["id"] == "" {
			t.Fatal(result)
		}
	}
	if result := r.control(appRequestControl{Action: "lock", Client: r.client}); result.(map[string]string)["error"] != "request_commit_busy" {
		t.Fatal("unbounded frontend receipts", result)
	}
	r.control(appRequestControl{Action: "engineDetach"})
	if len(r.commits) != 0 || unknownRequestWriters.Load() != 0 {
		t.Fatal("unstarted receipts were not released")
	}
}
