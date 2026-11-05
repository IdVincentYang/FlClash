package main

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/component/requestscope"
)

type sourceMaterialApprovalState struct {
	choice   sourceAcceptanceRequest
	hash     string
	contract string
	lease    string
	receipt  string
}

type sourceMaterialCommit struct {
	candidate *sourceReviewCandidate
	prepared  bool
	published bool
	terminal  bool
	revision  uint64
}

func sourceMaterialTarget(home, key, kind string) (string, error) {
	directory, suffix, prefix := "profiles", ".yaml", "profile:"
	if kind == "script" {
		directory, suffix, prefix = "scripts", ".js", "script:"
	} else if kind != "profile" && kind != "provider-proxy" {
		return "", errSourceReview
	}
	if !strings.HasPrefix(key, prefix) {
		return "", errSourceReview
	}
	id := strings.TrimPrefix(key, prefix)
	value, err := strconv.ParseInt(id, 10, 64)
	if err != nil || value < 0 || strconv.FormatInt(value, 10) != id {
		return "", errSourceReview
	}
	return filepath.Join(home, directory, id+suffix), nil
}

func checkSourceMaterialCapture(request sourceAcceptanceRequest) error {
	if _, err := sourceMaterialTarget("", request.Key, request.Kind); err != nil || request.Provider != nil || len(request.Uses) != 0 || requestscope.BeginHook == nil {
		return errSourceReview
	}
	if request.MaterialOperation == "network" {
		appRequests.mu.Lock()
		lease := appRequests.leases[request.Session]
		valid := lease != nil && lease.registry == appRequests && !lease.granted && lease.spec.Client == request.Source.Client && lease.spec.Key == request.Key && lease.spec.Dataset == request.Source.Dataset && lease.spec.SourceRevision == request.Source.Sources[request.Key]
		appRequests.mu.Unlock()
		if !valid || lease.Check() != nil {
			return errSourceSuperseded
		}
		return nil
	}
	if request.MaterialOperation != "local" || request.Session != "" || request.ExpectedState == nil {
		return errSourceReview
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	if !sourceTicketValidLocked(request.Source, []string{request.Key}) || request.ExpectedState.Epoch == "" || request.ExpectedState.Epoch != appRequests.state.ProcessEpoch || request.ExpectedState.Revision != appRequests.state.Revision || request.Owner != appRequests.owner.ID || request.Operation != appRequests.operations[request.Key] {
		return errSourceSuperseded
	}
	return nil
}

func sourceMaterialGrantUnchanged(home string, candidate *sourceReviewCandidate) error {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	if sourceValueHash(permissions.Grants[candidate.request.Key]) != candidate.grantFingerprint {
		return errSourceSuperseded
	}
	return nil
}

func approveSourceMaterial(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	candidate, contract, hash, err := prepareReviewedSource(home, request)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if candidate.material != nil || candidate.request.MaterialOperation != request.MaterialOperation || candidate.request.Session != request.Session || sourceValueHash(candidate.request.ExpectedState) != sourceValueHash(request.ExpectedState) || candidate.request.Owner != request.Owner || candidate.request.Operation != request.Operation {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	if err := checkSourceMaterialCapture(candidate.request); err != nil {
		return sourceAcceptanceResult{}, err
	}
	if err := sourceMaterialGrantUnchanged(home, candidate); err != nil {
		return sourceAcceptanceResult{}, err
	}
	candidate.material = &sourceMaterialApprovalState{choice: request, hash: hash, contract: contract}
	return sourceAcceptanceResult{Status: "approved", Candidate: candidate.id, MaterialHash: hash, Routing: request.Routing}, nil
}

func sourceApprovedMaterial(request sourceAcceptanceRequest) (*sourceReviewCandidate, error) {
	candidate := pendingSourceReviews[request.Key]
	if candidate == nil || candidate.id != request.Candidate || candidate.material == nil || candidate.request.Source.Client != request.Source.Client || candidate.material.hash != request.MaterialHash {
		return nil, errSourceSuperseded
	}
	return candidate, nil
}

func sourceMaterialReceipt(request sourceAcceptanceRequest, candidate *sourceReviewCandidate) (*appRequestReceipt, error) {
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	receipt := appRequests.commits[request.Receipt]
	if receipt == nil || !sourceMaterialCommitCurrentLocked(receipt, candidate) {
		return nil, errSourceSuperseded
	}
	if candidate.request.MaterialOperation == "network" {
		if receipt.spec == nil || receipt.id != candidate.request.Session || receipt.spec.Key != candidate.request.Key || receipt.spec.Client != receipt.client || receipt.spec.Dataset != candidate.request.Source.Dataset || receipt.spec.SourceRevision != candidate.request.Source.Sources[candidate.request.Key] {
			return nil, errSourceSuperseded
		}
	} else if receipt.material == nil || receipt.material.candidate != candidate {
		return nil, errSourceSuperseded
	}
	if receipt.material != nil && (receipt.material.candidate != candidate || receipt.material.terminal) {
		return nil, errSourceSuperseded
	}
	return receipt, nil
}

func sourceMaterialCommitCurrentLocked(receipt *appRequestReceipt, candidate *sourceReviewCandidate) bool {
	r := receipt.registry
	if r.commits[receipt.id] != receipt || receipt.client != candidate.request.Source.Client || receipt.failed || receipt.retired || requestWriterError() != nil || r.client != receipt.client || !r.clientReady || r.dataset != candidate.request.Source.Dataset {
		return false
	}
	owner, operation := candidate.request.Owner, candidate.request.Operation
	if candidate.request.MaterialOperation == "network" {
		if receipt.spec == nil {
			return false
		}
		owner, operation = receipt.spec.Owner.ID, receipt.spec.Operation
	}
	return owner == r.owner.ID && operation == r.operations[candidate.request.Key]
}

func handleSourceMaterialCommit(home string, request sourceAcceptanceRequest) (bool, sourceAcceptanceResult, error) {
	switch request.Action {
	case "inspectMaterialRecovery", "recoverMaterialCommit":
		if !isInit.Load() {
			return true, sourceAcceptanceResult{}, errSourceSuperseded
		}
		result, err := recoverSourceMaterialCommit(home, request)
		return true, result, err
	case "releaseMaterialApproval":
		candidate := pendingSourceReviews[request.Key]
		if candidate != nil && candidate.id == request.Candidate && candidate.request.Source.Client == request.Source.Client && candidate.material != nil && candidate.material.receipt == "" {
			releaseSourceMaterialLease(candidate.material.lease, candidate.request.Source.Client)
			delete(pendingSourceReviews, request.Key)
		}
		return true, sourceAcceptanceResult{Status: "released"}, nil
	case "grantLocalMaterialCommit", "prepareMaterialCommit", "invalidateMaterialSource", "publishMaterialCommit", "projectMaterial":
	default:
		return false, sourceAcceptanceResult{}, nil
	}
	if !isInit.Load() {
		return true, sourceAcceptanceResult{}, errSourceSuperseded
	}
	candidate, err := sourceApprovedMaterial(request)
	if err != nil {
		return true, sourceAcceptanceResult{}, err
	}
	result, err := sourceMaterialCommitAction(home, request, candidate)
	return true, result, err
}

func sourceMaterialCommitAction(home string, request sourceAcceptanceRequest, candidate *sourceReviewCandidate) (sourceAcceptanceResult, error) {
	if err := requestWriterError(); err != nil {
		return sourceAcceptanceResult{}, err
	}
	if err := sourceMaterialGrantUnchanged(home, candidate); err != nil {
		return sourceAcceptanceResult{}, err
	}
	if request.Action == "projectMaterial" {
		if candidate.request.Kind != "profile" || candidate.material.receipt != "" || !sourceAcceptanceCurrent(candidate.request) {
			return sourceAcceptanceResult{}, errSourceSuperseded
		}
		if err := checkSourceMaterialCapture(candidate.request); err != nil {
			return sourceAcceptanceResult{}, err
		}
		document, _, err := decodeSourceContent(candidate.body)
		if err == nil && candidate.material.choice.Routing == "own" {
			document, err = sourceRoutingProjection(document, candidate.request.Key)
		}
		return sourceAcceptanceResult{Status: "projected", Document: document, MaterialHash: candidate.material.hash}, err
	}
	if request.Action == "grantLocalMaterialCommit" {
		if candidate.request.MaterialOperation != "local" || candidate.material.receipt != "" {
			return sourceAcceptanceResult{}, errSourceReview
		}
		if err := checkSourceMaterialCapture(candidate.request); err != nil {
			return sourceAcceptanceResult{}, err
		}
		id, err := randomRequestToken()
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		appRequests.mu.Lock()
		defer appRequests.mu.Unlock()
		if !sourceTicketValidLocked(candidate.request.Source, []string{candidate.request.Key}) || candidate.request.ExpectedState.Epoch != appRequests.state.ProcessEpoch || candidate.request.ExpectedState.Revision != appRequests.state.Revision || candidate.request.Owner != appRequests.owner.ID || candidate.request.Operation != appRequests.operations[candidate.request.Key] {
			return sourceAcceptanceResult{}, errSourceSuperseded
		}
		if len(appRequests.dataReaders) != 0 {
			return sourceAcceptanceResult{}, errRequestCommitBusy
		}
		for _, receipt := range appRequests.commits {
			if receipt.client != "" {
				return sourceAcceptanceResult{}, errRequestCommitBusy
			}
		}
		appRequests.commits[id] = &appRequestReceipt{registry: appRequests, id: id, client: candidate.request.Source.Client, material: &sourceMaterialCommit{candidate: candidate}}
		candidate.material.receipt = id
		return sourceAcceptanceResult{Status: "granted", Receipt: id}, nil
	}
	receipt, err := sourceMaterialReceipt(request, candidate)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if request.Action == "prepareMaterialCommit" {
		if receipt.markerHash == "" || candidate.material.receipt != "" && candidate.material.receipt != receipt.id {
			return sourceAcceptanceResult{}, errSourceReview
		}
		requestRecoveryMu.Lock()
		data, err := readRequestRecoveryMarker(home)
		requestRecoveryMu.Unlock()
		if err != nil || data == nil || inputHash(data) != receipt.markerHash {
			return sourceAcceptanceResult{}, errSourceStore
		}
		appRequests.mu.Lock()
		current := appRequests.sources[candidate.request.Key] == candidate.request.Source.Sources[candidate.request.Key]
		appRequests.mu.Unlock()
		if !current || receipt.material != nil && receipt.material.prepared {
			return sourceAcceptanceResult{}, errSourceSuperseded
		}
		receipt.material = &sourceMaterialCommit{candidate: candidate, prepared: true}
		candidate.material.receipt = receipt.id
		return sourceAcceptanceResult{Status: "prepared", Receipt: receipt.id}, nil
	}
	commit := receipt.material
	if commit == nil || !commit.prepared || commit.published {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	if request.Action == "invalidateMaterialSource" {
		if err := invalidateSourceMaterialCommit(home, receipt); err != nil {
			return sourceAcceptanceResult{}, err
		}
		return sourceAcceptanceResult{Status: "invalidated"}, nil
	}
	appRequests.mu.Lock()
	current := commit.revision != 0 && appRequests.sources[candidate.request.Key] == commit.revision
	appRequests.mu.Unlock()
	if !current {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	requestRecoveryMu.Lock()
	marker, markerErr := readRequestRecoveryMarker(home)
	requestRecoveryMu.Unlock()
	if markerErr != nil || marker == nil || inputHash(marker) != receipt.markerHash {
		return sourceAcceptanceResult{}, errSourceStore
	}
	path, err := sourceMaterialTarget(home, candidate.request.Key, candidate.request.Kind)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() {
		return sourceAcceptanceResult{}, errSourceReview
	}
	body, err := boundedSourceProviderCache(path)
	if err != nil || len(body) > sourceCandidateMax || inputHash(body) != candidate.material.hash {
		return sourceAcceptanceResult{}, errSourceReview
	}
	file, err := os.Open(path)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	err = file.Sync()
	_ = file.Close()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	directory, err := os.Open(filepath.Dir(path))
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	err = directory.Sync()
	_ = directory.Close()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	appRequests.mu.Lock()
	if !sourceMaterialCommitCurrentLocked(receipt, candidate) || appRequests.sources[candidate.request.Key] != commit.revision {
		appRequests.mu.Unlock()
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	result, err := acceptReviewedSource(home, candidate.material.choice)
	if err != nil {
		appRequests.mu.Unlock()
		return sourceAcceptanceResult{}, err
	}
	commit.published = true
	appRequests.mu.Unlock()
	if err := reconcileSourceScopesLocked(home); err != nil {
		receipt.failed = true
		return sourceAcceptanceResult{}, err
	}
	return result, nil
}

func invalidateSourceMaterialCommit(home string, receipt *appRequestReceipt) error {
	commit, r := receipt.material, receipt.registry
	candidate := commit.candidate
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	r.mu.Lock()
	if !sourceMaterialCommitCurrentLocked(receipt, candidate) || commit.revision != 0 || r.sources[candidate.request.Key] != candidate.request.Source.Sources[candidate.request.Key] {
		r.mu.Unlock()
		return errSourceSuperseded
	}
	r.sources[candidate.request.Key]++
	commit.revision = r.sources[candidate.request.Key]
	r.permits = map[string]requestscope.Spec{}
	var leases []*appRequestLease
	for _, lease := range r.leases {
		if lease.spec.Key == candidate.request.Key && lease.spec.Client == receipt.client {
			leases = append(leases, lease)
		}
	}
	r.changedLocked()
	r.mu.Unlock()
	err := invalidateConfigCheckpointLocked(candidate.request.Key, false)
	for _, lease := range leases {
		lease.Close()
	}
	return err
}

func finishSourceMaterialCommit(receipt *appRequestReceipt) error {
	commit := receipt.material
	if commit == nil {
		return nil
	}
	commit.terminal = true
	candidate := commit.candidate
	if pendingSourceReviews[candidate.request.Key] == candidate {
		delete(pendingSourceReviews, candidate.request.Key)
	}
	releaseSourceMaterialLease(candidate.material.lease, receipt.client)
	if commit.prepared && !commit.published {
		return errors.New("source material commit requires recovery")
	}
	return nil
}
