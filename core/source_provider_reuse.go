package main

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"slices"
)

func reuseSourceProviderMaterial(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if request.Use == nil || !sourceAcceptanceCurrent(request) {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	plans, err := acceptedSourceProviderPlans(home, *request.Use, request.MaterialHash)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	var plan *sourceProviderPlan
	for i := range plans {
		if plans[i].Key == request.Key && plans[i].Kind == request.Kind && plans[i].Name == request.ProviderName {
			plan = &plans[i]
			break
		}
	}
	if plan == nil {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return sourceAcceptanceResult{}, err
	}
	if _, err := os.Stat(requestRecoveryPath(home)); !os.IsNotExist(err) {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if _, err := os.Stat(filepath.Join(inputDirectory(home), "checkpoint.json")); os.IsNotExist(err) {
		return sourceAcceptanceResult{Status: "missing"}, nil
	} else if err != nil {
		return sourceAcceptanceResult{}, errSourceStore
	}
	checkpointMu.Lock()
	data, readErr := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json"))
	if readErr == nil && bytes.Equal(data, []byte(invalidatedConfigCheckpoint)) {
		checkpointMu.Unlock()
		return sourceAcceptanceResult{Status: "missing"}, nil
	}
	checkpoint, err := readCheckpointLocked(home)
	checkpointMu.Unlock()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	manifest, _, _, _, err := readConfigInput(home, checkpoint.InputID)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if manifest.Version != 2 {
		return sourceAcceptanceResult{}, errSourceReview
	}
	for _, material := range manifest.ProviderMaterials {
		if material.Name != plan.Name || material.Kind != plan.Kind || material.Parent != plan.Parent || material.Declaration != plan.Declaration {
			continue
		}
		if material.Use.Key != plan.Key || plan.Origin == nil && material.Origin != (SourceUse{}) || plan.Origin != nil && !slices.Contains(plan.Origin.Uses, material.Origin) {
			return sourceAcceptanceResult{}, errSourceReview
		}
		body, err := readSourceObject(home, material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		lease, err := pinSourceMaterial(home, material.MaterialHash, request.Source.Client)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		return sourceAcceptanceResult{Status: "reused", BodyBase64: base64.StdEncoding.EncodeToString(body), MaterialHash: material.MaterialHash, MaterialLease: lease}, nil
	}
	return sourceAcceptanceResult{Status: "missing"}, nil
}
