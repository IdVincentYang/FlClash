package main

import (
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func sourceMaterialRPC(t *testing.T, request sourceAcceptanceRequest) (sourceAcceptanceResult, *MethodError) {
	t.Helper()
	data, _ := json.Marshal(request)
	var response struct {
		Result sourceAcceptanceResult
		Error  *MethodError
	}
	if err := json.Unmarshal(businessRPC(t, sourceAcceptanceMethod, string(data)), &response); err != nil {
		t.Fatal(err)
	}
	return response.Result, response.Error
}

func sourceMaterialRPCOK(t *testing.T, request sourceAcceptanceRequest) sourceAcceptanceResult {
	t.Helper()
	result, err := sourceMaterialRPC(t, request)
	if err != nil {
		t.Fatal(request.Action, err)
	}
	return result
}

func sourceLocalApprovalFixture(t *testing.T, routing string) (sourceAcceptanceRequest, SourceUse) {
	t.Helper()
	sourceRuntimeFixture(t)
	appRequests.client, appRequests.clientReady = "material-commit-client", true
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:10", Kind: "profile", Identity: inputHash([]byte("original source")), Settings: inputHash(nil), Body: "mode: rule\nrules: [\"MATCH,DIRECT\"]\n", Source: ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{"profile:10": 0}}}
	first := sourceMaterialRPCOK(t, request)
	request.Action, request.Candidate, request.Routing = "accept", first.Candidate, "source"
	accepted := sourceMaterialRPCOK(t, request)
	if accepted.Use == nil {
		t.Fatal("initial explicit acceptance returned no canonical use")
	}
	request.Action, request.Candidate, request.Routing = "review", "", routing
	request.MaterialOperation, request.Fresh = "local", routing == "source"
	request.ExpectedState = &requestscope.StateVersion{Epoch: appRequests.state.ProcessEpoch, Revision: appRequests.state.Revision}
	request.Owner, request.Operation = appRequests.owner.ID, appRequests.operations[request.Key]
	first = sourceMaterialRPCOK(t, request)
	if first.Status != "reviewRequired" {
		t.Fatal("fresh/routing material unexpectedly reused formal permission", first)
	}
	request.Action, request.Candidate = "approveMaterial", first.Candidate
	approved := sourceMaterialRPCOK(t, request)
	if approved.Status != "approved" || approved.Use != nil {
		t.Fatal("material approval minted a runnable source use", approved)
	}
	request.MaterialHash = approved.MaterialHash
	if err := checkSourceUses(C.Path.HomeDir(), []SourceUse{*accepted.Use}); err != nil {
		t.Fatal("uncommitted material approval revoked the existing use", err)
	}
	return request, *accepted.Use
}

func sourceLocalCommitFixture(t *testing.T, request sourceAcceptanceRequest) sourceAcceptanceRequest {
	t.Helper()
	request.Action = "grantLocalMaterialCommit"
	granted := sourceMaterialRPCOK(t, request)
	if granted.Status != "granted" || granted.Receipt == "" {
		t.Fatal(granted)
	}
	request.Receipt = granted.Receipt
	control := appRequestControl{Action: "beginCommit", ID: request.Receipt, Client: request.Source.Client}
	if result := appRequests.control(control); result.(map[string]bool)["ok"] != true {
		t.Fatal(result)
	}
	request.Action = "prepareMaterialCommit"
	if result := sourceMaterialRPCOK(t, request); result.Status != "prepared" {
		t.Fatal(result)
	}
	return request
}

func TestSourceLocalFreshAndRoutingApprovalPublishOnlyAfterOwnedCommit(t *testing.T) {
	for _, routing := range []string{"source", "own"} {
		t.Run(routing, func(t *testing.T) {
			if !sourceTestIsolation(t) {
				return
			}
			request, previous := sourceLocalApprovalFixture(t, routing)
			request.Action = "projectMaterial"
			if result := sourceMaterialRPCOK(t, request); result.Status != "projected" || result.Use != nil {
				t.Fatal("pure preflight acquired formal permission", result)
			}
			generic := appRequests.control(appRequestControl{Action: "lock", Client: request.Source.Client}).(map[string]string)["id"]
			request.Action, request.Receipt = "prepareMaterialCommit", generic
			if _, err := sourceMaterialRPC(t, request); err == nil {
				t.Fatal("ordinary local lock consumed a material approval")
			}
			appRequests.control(appRequestControl{Action: "complete", ID: generic, Client: request.Source.Client})
			request = sourceLocalCommitFixture(t, request)
			request.Action = "invalidateMaterialSource"
			sourceMaterialRPCOK(t, request)
			path, _ := sourceMaterialTarget(C.Path.HomeDir(), request.Key, request.Kind)
			if err := atomicConfigFile(path, []byte(request.Body)); err != nil {
				t.Fatal(err)
			}
			if err := checkSourceUses(C.Path.HomeDir(), []SourceUse{previous}); err != nil {
				t.Fatal("source invalidation prematurely published fresh/routing permission", err)
			}
			request.Action = "publishMaterialCommit"
			published := sourceMaterialRPCOK(t, request)
			if published.Status != "accepted" || published.Use == nil || checkSourceUses(C.Path.HomeDir(), []SourceUse{previous}) == nil {
				t.Fatal("formal replacement failed to revoke the previous exact use", published)
			}
			result := appRequests.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
			if result.(map[string]bool)["ok"] != true {
				t.Fatal(result)
			}
			if _, err := os.Stat(requestRecoveryPath(C.Path.HomeDir())); !os.IsNotExist(err) {
				t.Fatal("successful owned material commit retained its marker", err)
			}
			if _, err := sourceMaterialRPC(t, request); err == nil {
				t.Fatal("completed approval was replayed")
			}
		})
	}
}

func TestSourceIncompleteMaterialReceiptTerminatesAndRecoversWithoutPromotingApproval(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, previous := sourceLocalApprovalFixture(t, "source")
	request = sourceLocalCommitFixture(t, request)
	failed := appRequests.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
	if failed.(map[string]string)["error"] != "request_partial_commit" || len(appRequests.commits) != 0 {
		t.Fatal("incomplete local write retained an immortal receipt", failed)
	}
	started := time.Now()
	if _, err := beginRequestDataRead(); err == nil || time.Since(started) > time.Second {
		t.Fatal("recovery barrier did not reject the read promptly", err)
	}
	attached := appRequests.control(appRequestControl{Action: "attach"}).(map[string]any)
	client := attached["client"].(string)
	ready := appRequests.control(appRequestControl{Action: "ready", Client: client})
	if result, ok := ready.(map[string]bool); ok && result["ready"] == false {
		t.Fatal("ended receipt blocked the new frontend", ready)
	}
	recovery := sourceAcceptanceRequest{Action: "inspectMaterialRecovery", Key: "application-config", Kind: "config", Source: ConfigSourceTicket{Client: client, Dataset: appRequests.dataset, Sources: map[string]uint64{"application-config": appRequests.sources["application-config"]}}, Recovery: &sourceRecoverySnapshot{Rows: []sourceRecoveryRow{{Key: previous.Key, Identity: request.Identity}}}}
	snapshot := sourceMaterialRPCOK(t, recovery)
	if snapshot.Recovery == nil {
		t.Fatal(snapshot)
	}
	recovery.Action, recovery.Recovery = "recoverMaterialCommit", snapshot.Recovery
	if result := sourceMaterialRPCOK(t, recovery); result.Status != "recovered" {
		t.Fatal(result)
	}
	if err := checkSourceUses(C.Path.HomeDir(), []SourceUse{previous}); err != nil {
		t.Fatal("recovery replaced a formal source using an unpublished approval", err)
	}
	read, err := beginRequestDataRead()
	if err != nil {
		t.Fatal("actual frontend recovery could not leave the barrier", err)
	}
	appRequests.endDataRead(read)
	request.Action = "publishMaterialCommit"
	if _, err := sourceMaterialRPC(t, request); err == nil {
		t.Fatal("old-client approval survived terminal recovery")
	}
}

func TestSourceMaterialPermissionWriteFailureKeepsBarrierAndEndsReceipt(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, previous := sourceLocalApprovalFixture(t, "source")
	request = sourceLocalCommitFixture(t, request)
	request.Action = "invalidateMaterialSource"
	sourceMaterialRPCOK(t, request)
	path, _ := sourceMaterialTarget(C.Path.HomeDir(), request.Key, request.Kind)
	if err := atomicConfigFile(path, []byte(request.Body)); err != nil {
		t.Fatal(err)
	}
	writer := writeSourcePermissions
	writeSourcePermissions = func(string, []byte) error { return errors.New("controlled permission persistence failure") }
	request.Action = "publishMaterialCommit"
	_, publishErr := sourceMaterialRPC(t, request)
	writeSourcePermissions = writer
	if publishErr == nil {
		t.Fatal("permission persistence failure was reported as accepted")
	}
	appRequests.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
	if len(appRequests.commits) != 0 {
		t.Fatal("failed permission write left an active memory receipt")
	}
	if _, err := os.Stat(requestRecoveryPath(C.Path.HomeDir())); err != nil {
		t.Fatal("uncertain material/grant commit lost its recovery barrier", err)
	}
	if err := checkSourceUses(C.Path.HomeDir(), []SourceUse{previous}); err != nil {
		t.Fatal("failed permission write replaced the old canonical grant", err)
	}
}

func TestSourceMaterialCannotAttributeAnExternalInvalidateToItsReceipt(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	request, _ := sourceLocalApprovalFixture(t, "source")
	request = sourceLocalCommitFixture(t, request)
	appRequests.control(appRequestControl{Action: "invalidate", Client: request.Source.Client, Key: request.Key})
	request.Action = "invalidateMaterialSource"
	if _, err := sourceMaterialRPC(t, request); err == nil {
		t.Fatal("external +1 source revision was claimed by the material receipt")
	}
	request.Action = "publishMaterialCommit"
	if _, err := sourceMaterialRPC(t, request); err == nil {
		t.Fatal("unattributed source mutation authorized material publication")
	}
	appRequests.control(appRequestControl{Action: "complete", ID: request.Receipt, Client: request.Source.Client})
	if len(appRequests.commits) != 0 {
		t.Fatal("failed source attribution leaked its receipt")
	}
}

func TestSourceLocalMaterialApprovalCannotSurviveStopOwnerOrGrantChanges(t *testing.T) {
	for _, change := range []string{"stop", "owner", "withdraw", "client"} {
		t.Run(change, func(t *testing.T) {
			if !sourceTestIsolation(t) {
				return
			}
			request, previous := sourceLocalApprovalFixture(t, "source")
			switch change {
			case "stop":
				state := appRequests.state
				state.Revision++
				state.IntentRevision++
				state.IntentRunning, state.Phase = false, "stopped"
				appRequests.control(appRequestControl{Action: "publish", State: state})
			case "owner":
				_, cleanups := appRequests.nextConfigOwner()
				finishRequestCleanup(cleanups)
			case "withdraw":
				permissions, _ := readSourcePermissions(C.Path.HomeDir())
				grant := permissions.Grants[request.Key]
				if err := withdrawSourcePermission(C.Path.HomeDir(), request.Key, previous.Incarnation, grant.Revision, true, request.Kind); err != nil {
					t.Fatal(err)
				}
			case "client":
				appRequests.control(appRequestControl{Action: "attach"})
			}
			request.Action = "grantLocalMaterialCommit"
			if _, err := sourceMaterialRPC(t, request); err == nil {
				t.Fatal("old local approval survived", change)
			}
			if len(appRequests.commits) != 0 {
				t.Fatal("rejected approval created a local write receipt")
			}
		})
	}
}
