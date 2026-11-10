package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

type sourceMaterialLease struct {
	home, digest, client string
}

var sourceMaterialLeases = map[string]sourceMaterialLease{}

func pinSourceMaterial(home, digest, client string) (string, error) {
	if len(sourceMaterialLeases) >= sourceMaterialLeaseLimit {
		return "", errSourceBudget
	}
	if _, err := readSourceObject(home, digest, sourceCandidateMax); err != nil {
		return "", err
	}
	id, err := randomRequestToken()
	if err != nil {
		return "", err
	}
	sourceMaterialLeases[id] = sourceMaterialLease{home: home, digest: digest, client: client}
	return id, nil
}

func releaseSourceMaterialLease(id, client string) {
	if lease, present := sourceMaterialLeases[id]; present && lease.client == client {
		delete(sourceMaterialLeases, id)
	}
}

func collectSourceMaterialsLocked(home string) error {
	keep, inputs := map[string]bool{}, map[string]bool{}
	pinManifest := func(manifest ConfigManifest) {
		keep[manifest.YAMLSHA256] = true
		for _, material := range manifest.ProviderMaterials {
			keep[material.MaterialHash] = true
		}
	}
	for _, p := range []*preparedConfig{pendingConfig, appliedConfig} {
		if p != nil {
			pinManifest(p.manifest)
			for _, id := range p.sourceRetiredInputs {
				inputs[id] = true
			}
		}
	}
	stagedCore.Lock()
	if stage := stagedCore.stage; stage != nil && stage.prepared != nil {
		pinManifest(stage.prepared.manifest)
		for _, id := range stage.prepared.sourceRetiredInputs {
			inputs[id] = true
		}
	}
	stagedCore.Unlock()
	pending, err := readSourceMaterialPending(home)
	if err != nil {
		return err
	}
	if pending != nil && !pending.Cleared {
		inputs[pending.ParentInput], inputs[pending.TargetInput] = true, true
		keep[pending.MaterialHash] = true
	}
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json"))
	if err == nil {
		var checkpoint configCheckpoint
		if json.Unmarshal(data, &checkpoint) != nil || checkpoint.Version != 1 {
			return errSourceStore
		}
		if validInputID(checkpoint.InputID) {
			inputs[checkpoint.InputID] = true
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	appRequests.mu.Lock()
	client, ready := appRequests.client, appRequests.clientReady
	appRequests.mu.Unlock()
	for id, lease := range sourceMaterialLeases {
		if lease.home != home {
			continue
		}
		if lease.client != "" && (lease.client != client || !ready) {
			delete(sourceMaterialLeases, id)
			continue
		}
		keep[lease.digest] = true
	}
	entries, err := os.ReadDir(inputDirectory(home))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		id, valid := candidateInputID(entry.Name())
		if !valid {
			continue
		}
		data, err := os.ReadFile(filepath.Join(inputDirectory(home), entry.Name()))
		var marker inputCandidateMarker
		if err != nil || json.Unmarshal(data, &marker) != nil {
			return errSourceStore
		}
		if marker.RuntimeEpoch == configRuntimeEpoch && (marker.Client == "" || marker.Client == client && ready) {
			inputs[id] = true
			keep[marker.YAMLSHA256] = true
		}
	}
	for id := range inputs {
		data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
		var manifest ConfigManifest
		if err != nil || len(data) > sourceGrantFileLimit || inputHash(data) != id || json.Unmarshal(data, &manifest) != nil {
			return errSourceStore
		}
		pinManifest(manifest)
	}
	for _, candidate := range pendingSourceReviews {
		if validInputID(candidate.request.MaterialHash) {
			keep[candidate.request.MaterialHash] = true
		}
		if candidate.material != nil {
			keep[candidate.material.hash] = true
			if candidate.material.contract != "" {
				keep[candidate.material.contract] = true
			}
		}
	}
	appRequests.mu.Lock()
	for _, receipt := range appRequests.commits {
		if receipt.material != nil && !receipt.material.terminal {
			material := receipt.material.candidate.material
			keep[material.hash] = true
			if material.contract != "" {
				keep[material.contract] = true
			}
		}
	}
	appRequests.mu.Unlock()
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	sourceAuthorityMu.Unlock()
	if err != nil {
		return err
	}
	for _, grant := range permissions.Grants {
		for _, purpose := range grant.Purposes {
			if bundle := purpose.ReviewBundle; bundle != nil && sourceUseAllowed(permissions, bundle.Bound) {
				keep[bundle.BodyHash] = true
				for _, material := range bundle.Materials {
					keep[material.MaterialHash] = true
				}
			}
			if purpose.Contract != "" {
				keep[purpose.Contract] = true
			}
		}
	}
	root := filepath.Join(home, "source-acceptance", "materials")
	entries, err = os.ReadDir(root)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, ".input-") {
			if entry.Type().IsRegular() {
				if err := os.Remove(filepath.Join(root, name)); err != nil {
					return err
				}
			}
			continue
		}
		if !validInputID(name) || entry.Type()&os.ModeSymlink != 0 || entry.IsDir() {
			return errSourceStore
		}
		if keep[name] {
			continue
		}
		if _, err := readSourceObject(home, name, sourceCandidateMax); err != nil {
			return err
		}
		if err := os.Remove(filepath.Join(root, name)); err != nil {
			return err
		}
	}
	return nil
}
