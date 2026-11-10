package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
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
	if request.Action == "reuseReviewedProvider" {
		if data, err := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json")); err == nil && bytes.Equal(data, []byte(invalidatedConfigCheckpoint)) && !localGroupBundleCurrent(home, request) {
			return sourceAcceptanceResult{Status: "missing"}, nil
		} else if err != nil && !os.IsNotExist(err) {
			return sourceAcceptanceResult{}, errSourceStore
		}
		return reuseReviewedSourceProvider(home, request, *plan)
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

func reuseCachedSourceProvider(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	missing := sourceAcceptanceResult{Status: "missing"}
	if request.Use == nil || !sourceAcceptanceCurrent(request) {
		return missing, errSourceSuperseded
	}
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return missing, err
	}
	if _, err := os.Stat(requestRecoveryPath(home)); !os.IsNotExist(err) {
		return missing, errSourceReview
	}
	plans, err := acceptedSourceProviderPlans(home, *request.Use, request.MaterialHash)
	if err != nil {
		return missing, err
	}
	index := slices.IndexFunc(plans, func(plan sourceProviderPlan) bool {
		return plan.Key == request.Key && plan.Kind == request.Kind && plan.Name == request.ProviderName
	})
	if index < 0 {
		return missing, errSourceReview
	}
	plan := plans[index]
	candidates, err := cachedSourceProviderCandidates(home, *request.Use)
	if err != nil {
		return missing, err
	}

	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		sourceAuthorityMu.Unlock()
		return missing, err
	}
	if !sourceUseAllowed(permissions, *request.Use) || !sourceUseAllowed(permissions, plan.Parent) {
		sourceAuthorityMu.Unlock()
		return missing, errSourceUseRevoked
	}
	var accepted *SourceProviderMaterial
	for _, material := range candidates {
		if material.Name != plan.Name || material.Kind != plan.Kind || material.Parent != plan.Parent || material.Declaration != plan.Declaration || material.Use.Key != plan.Key || !sourceUseAllowed(permissions, material.Use) {
			continue
		}
		if plan.Origin == nil && material.Origin != (SourceUse{}) || plan.Origin != nil && (!slices.Contains(plan.Origin.Uses, material.Origin) || !sourceUseAllowed(permissions, material.Origin)) {
			continue
		}
		candidate := material
		accepted = &candidate
		break
	}
	sourceAuthorityMu.Unlock()
	if accepted == nil {
		return missing, nil
	}
	body, err := readSourceObject(home, accepted.MaterialHash, sourceCandidateMax)
	if err != nil {
		return missing, err
	}
	lease, err := pinSourceMaterial(home, accepted.MaterialHash, request.Source.Client)
	if err != nil {
		return missing, err
	}
	// This returns bytes, not a replay grant; the caller reviews them in the new composition.
	return sourceAcceptanceResult{Status: "reused", BodyBase64: base64.StdEncoding.EncodeToString(body), MaterialHash: accepted.MaterialHash, MaterialLease: lease}, nil
}

func cachedSourceProviderCandidates(home string, use SourceUse) ([]SourceProviderMaterial, error) {
	var candidates []SourceProviderMaterial
	if p := appliedConfig; p != nil && p.manifest.Version == 2 {
		candidates = append(candidates, p.manifest.ProviderMaterials...)
	}
	checkpointMu.Lock()
	data, readErr := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json"))
	checkpointMu.Unlock()
	if readErr != nil && !os.IsNotExist(readErr) {
		return nil, errSourceStore
	}
	if readErr == nil && !bytes.Equal(data, []byte(invalidatedConfigCheckpoint)) {
		var checkpoint configCheckpoint
		if json.Unmarshal(data, &checkpoint) != nil || checkpoint.Version != 1 || !validInputID(checkpoint.InputID) {
			return nil, errSourceStore
		}
		manifest, err := readConfigManifest(home, checkpoint.InputID)
		if err != nil {
			return nil, err
		}
		candidates = append(candidates, manifest.ProviderMaterials...)
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return nil, err
	}
	if !sourceUseAllowed(permissions, use) {
		return nil, errSourceUseRevoked
	}
	if grant := permissions.Grants[use.Key]; grant != nil && grant.Purposes["config"] != nil {
		if bundle := grant.Purposes["config"].ReviewBundle; bundle != nil && sourceUseAllowed(permissions, bundle.Bound) {
			candidates = append(candidates, bundle.Materials...)
		}
	}
	return candidates, nil
}

func reuseCachedSourceProviders(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	missing := sourceAcceptanceResult{Status: "missing"}
	if request.Use == nil || request.Use.Key != request.Key || request.Kind != "config" || !sourceAcceptanceCurrent(request) {
		return missing, errSourceSuperseded
	}
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return missing, err
	}
	if _, err := os.Stat(requestRecoveryPath(home)); !os.IsNotExist(err) {
		return missing, errSourceReview
	}
	plans, err := acceptedSourceProviderPlans(home, *request.Use, request.MaterialHash)
	if err != nil {
		return missing, err
	}
	candidates, err := cachedSourceProviderCandidates(home, *request.Use)
	if err != nil {
		return missing, err
	}
	materials := make([]SourceProviderMaterial, 0, len(plans))
	for _, plan := range plans {
		index := slices.IndexFunc(candidates, func(material SourceProviderMaterial) bool {
			return material.Name == plan.Name && material.Kind == plan.Kind && material.Parent == plan.Parent && material.Declaration == plan.Declaration && material.Use.Key == plan.Key && (plan.Origin == nil && material.Origin == (SourceUse{}) || plan.Origin != nil && slices.Contains(plan.Origin.Uses, material.Origin))
		})
		if index < 0 {
			return missing, nil
		}
		materials = append(materials, candidates[index])
	}
	if len(sourceMaterialLeases)+len(materials)+1 > sourceMaterialLeaseLimit {
		return missing, errSourceBudget
	}
	use, err := bindSourceProviderMaterials(home, *request.Use, request.MaterialHash, materials)
	if err != nil {
		if errors.Is(err, errSourceStore) || errors.Is(err, errSourceUseRevoked) || errors.Is(err, errSourceBudget) || errors.Is(err, errSourceSuperseded) {
			return missing, err
		}
		return missing, nil
	}
	uses, err := sourceCompositionUses(home, use)
	if err != nil {
		return missing, err
	}
	leases := []string{}
	for _, material := range materials {
		lease, err := pinSourceMaterial(home, material.MaterialHash, request.Source.Client)
		if err != nil {
			for _, id := range leases {
				releaseSourceMaterialLease(id, request.Source.Client)
			}
			return missing, err
		}
		leases = append(leases, lease)
	}
	uses = slices.DeleteFunc(uses, func(dependency SourceUse) bool { return dependency.Kind == "config" })
	return sourceAcceptanceResult{Status: "accepted", Use: &use, Uses: uses, MaterialHash: request.MaterialHash, ProviderMaterials: materials, MaterialLeases: leases}, nil
}
