package main

import (
	"os"
	"slices"
	"strings"
)

type sourceRecoveryRow struct {
	Key        string `json:"key"`
	Identity   string `json:"identity"`
	Permission string `json:"permission"`
	FileHash   string `json:"fileHash"`
}

type sourceRecoverySnapshot struct {
	Marker      string              `json:"marker"`
	Permissions string              `json:"permissions"`
	Dataset     uint64              `json:"dataset"`
	Rows        []sourceRecoveryRow `json:"rows"`
}

func sourceMaterialRecoverySnapshot(home string, request sourceAcceptanceRequest) (*sourceRecoverySnapshot, error) {
	if err := requestWriterError(); err != nil {
		return nil, err
	}
	if request.Key != "application-config" || request.Kind != "config" || !sourceAcceptanceCurrent(request) || request.Recovery == nil || len(request.Recovery.Rows) > sourceEntityLimit {
		return nil, errSourceSuperseded
	}
	appRequests.mu.Lock()
	busy, dataset := len(appRequests.commits) != 0, appRequests.dataset
	appRequests.mu.Unlock()
	if busy {
		return nil, errRequestCommitBusy
	}
	requestRecoveryMu.Lock()
	marker, err := readRequestRecoveryMarker(home)
	requestRecoveryMu.Unlock()
	if err != nil || marker == nil {
		return nil, errSourceSuperseded
	}
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	sourceAuthorityMu.Unlock()
	if err != nil {
		return nil, err
	}
	rows := map[string]sourceRecoveryRow{}
	for _, row := range request.Recovery.Rows {
		if _, duplicate := rows[row.Key]; duplicate || row.Identity != "" && !validInputID(row.Identity) {
			return nil, errSourceReview
		}
		rows[row.Key] = sourceRecoveryRow{Key: row.Key, Identity: row.Identity}
	}
	for key := range permissions.Grants {
		if strings.HasPrefix(key, "profile:") || strings.HasPrefix(key, "script:") {
			if _, present := rows[key]; !present {
				rows[key] = sourceRecoveryRow{Key: key}
			}
		}
	}
	result := &sourceRecoverySnapshot{Marker: inputHash(marker), Permissions: sourceValueHash(permissions), Dataset: dataset, Rows: []sourceRecoveryRow{}}
	for key, row := range rows {
		kind := "profile"
		if strings.HasPrefix(key, "script:") {
			kind = "script"
		}
		path, err := sourceMaterialTarget(home, key, kind)
		if err != nil {
			return nil, err
		}
		if grant := permissions.Grants[key]; grant != nil {
			row.Permission = grant.Identity
		}
		info, err := os.Lstat(path)
		if err == nil {
			if !info.Mode().IsRegular() || info.Size() > sourceCandidateMax {
				return nil, errSourceReview
			}
			body, err := boundedSourceProviderCache(path)
			if err != nil || len(body) > sourceCandidateMax {
				return nil, errSourceReview
			}
			row.FileHash = inputHash(body)
		} else if !os.IsNotExist(err) {
			return nil, err
		}
		result.Rows = append(result.Rows, row)
	}
	slices.SortFunc(result.Rows, func(a, b sourceRecoveryRow) int { return strings.Compare(a.Key, b.Key) })
	return result, nil
}

func recoverSourceMaterialCommit(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	snapshot, err := sourceMaterialRecoverySnapshot(home, request)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if request.Action == "inspectMaterialRecovery" {
		return sourceAcceptanceResult{Status: "recovery", Recovery: snapshot}, nil
	}
	if sourceValueHash(snapshot) != sourceValueHash(request.Recovery) {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	result := appRequests.control(appRequestControl{Action: "invalidateDataset", Client: request.Source.Client})
	if failed, ok := result.(map[string]string); ok && failed["error"] != "" {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if err := clearOwnedRequestMarker(home, snapshot.Marker); err != nil {
		return sourceAcceptanceResult{}, err
	}
	for key, candidate := range pendingSourceReviews {
		if candidate.material != nil {
			releaseSourceMaterialLease(candidate.material.lease, candidate.request.Source.Client)
		}
		delete(pendingSourceReviews, key)
	}
	return sourceAcceptanceResult{Status: "recovered"}, nil
}
