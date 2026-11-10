package main

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/config"
)

type sourceReviewBundle struct {
	Initial   SourceUse                `json:"initial"`
	Bound     SourceUse                `json:"bound"`
	BodyHash  string                   `json:"bodyHash"`
	Materials []SourceProviderMaterial `json:"materials"`
	LocalEdit *ConfigSourceTicket      `json:"localEdit,omitempty"`
}

func rememberSourceReviewBundle(home string, initial, bound SourceUse, hash string, materials []SourceProviderMaterial, localEdit ...ConfigSourceTicket) error {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	if initial.Kind != "config" || initial.Key != bound.Key || !sourceUseAllowed(permissions, initial) || !sourceUseAllowed(permissions, bound) || !validInputID(hash) {
		return errSourceReview
	}
	grant := permissions.Grants[bound.Key]
	bundle := &sourceReviewBundle{Initial: initial, Bound: bound, BodyHash: hash, Materials: slices.Clone(materials)}
	if len(localEdit) == 1 && localEdit[0].Client != "" {
		ticket := localEdit[0]
		ticket.Sources = map[string]uint64{"application-config": ticket.Sources["application-config"] + 1}
		bundle.LocalEdit = &ticket
	}
	grant.Purposes[bound.Kind].ReviewBundle = bundle
	grant.Revision++
	return saveSourcePermissions(home, permissions)
}

func localGroupBundleCurrent(home string, request sourceAcceptanceRequest) bool {
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	var ticket *ConfigSourceTicket
	if err == nil && request.Use != nil && sourceUseAllowed(permissions, *request.Use) {
		bundle := permissions.Grants[request.Use.Key].Purposes[request.Use.Kind].ReviewBundle
		if bundle != nil && bundle.BodyHash == request.MaterialHash && (*request.Use == bundle.Initial || *request.Use == bundle.Bound) && sourceUseAllowed(permissions, bundle.Bound) {
			ticket = bundle.LocalEdit
		}
	}
	sourceAuthorityMu.Unlock()
	if ticket == nil || ticket.Client == "" {
		return false
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	return sourceTicketValidLocked(*ticket, []string{"application-config"})
}

func reuseReviewedSourceProvider(home string, request sourceAcceptanceRequest, plan sourceProviderPlan) (sourceAcceptanceResult, error) {
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		sourceAuthorityMu.Unlock()
		return sourceAcceptanceResult{}, err
	}
	if request.Use == nil || !sourceUseAllowed(permissions, *request.Use) {
		sourceAuthorityMu.Unlock()
		return sourceAcceptanceResult{}, errSourceUseRevoked
	}
	purpose := permissions.Grants[request.Use.Key].Purposes[request.Use.Kind]
	bundle := purpose.ReviewBundle
	if bundle == nil || bundle.BodyHash != request.MaterialHash || (*request.Use != bundle.Initial && *request.Use != bundle.Bound) || !sourceUseAllowed(permissions, bundle.Bound) {
		sourceAuthorityMu.Unlock()
		return sourceAcceptanceResult{Status: "missing"}, nil
	}
	dependencies := slices.Clone(purpose.BoundUses[bundle.Bound.Digest])
	sourceAuthorityMu.Unlock()
	body, err := readSourceObject(home, bundle.BodyHash, sourceCandidateMax)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	raw, err := config.UnmarshalRawConfig(body)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	id, err := strconv.ParseInt(strings.TrimPrefix(request.Use.Key, "config:"), 10, 64)
	if err != nil {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if err := validateSourceProviderMaterials(home, ConfigManifest{Version: 2, ProfileID: &id, SourceUses: dependencies, ProviderMaterials: bundle.Materials}, raw); err != nil {
		return sourceAcceptanceResult{}, err
	}
	for _, material := range bundle.Materials {
		if material.Name != plan.Name || material.Kind != plan.Kind || material.Parent != plan.Parent || material.Declaration != plan.Declaration || material.Use.Key != plan.Key {
			continue
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

func previewCachedSourceProvider(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	missing := sourceAcceptanceResult{Status: "missing"}
	if request.Parent == nil {
		return missing, errSourceReview
	}
	plans, err := previewSourceProviderPlans(home, request.Body, request.Parent.Key, request.Uses)
	if err != nil {
		return missing, err
	}
	var preview *sourceProviderPlan
	for i := range plans {
		if plans[i].Name == request.ProviderName && plans[i].Kind == request.Kind {
			preview = &plans[i]
			break
		}
	}
	if preview == nil {
		return missing, errSourceReview
	}
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		sourceAuthorityMu.Unlock()
		return missing, err
	}
	grant := permissions.Grants["config:"+strings.TrimPrefix(request.Parent.Key, "profile:")]
	var bundle *sourceReviewBundle
	if grant != nil && grant.Purposes["config"] != nil {
		bundle = grant.Purposes["config"].ReviewBundle
	}
	if bundle == nil || !sourceUseAllowed(permissions, bundle.Bound) {
		sourceAuthorityMu.Unlock()
		return missing, nil
	}
	bound, hash := bundle.Bound, bundle.BodyHash
	sourceAuthorityMu.Unlock()
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return missing, nil
	}
	if _, err := os.Stat(requestRecoveryPath(home)); !os.IsNotExist(err) {
		return missing, nil
	}
	if data, err := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json")); err == nil && bytes.Equal(data, []byte(invalidatedConfigCheckpoint)) {
		return missing, nil
	} else if err != nil && !os.IsNotExist(err) {
		return missing, errSourceStore
	}
	accepted, err := acceptedSourceProviderPlans(home, bound, hash)
	if err != nil {
		return missing, err
	}
	for _, plan := range accepted {
		if plan.Name == preview.Name && plan.Kind == preview.Kind && sourceValueHash(plan.Mapping) == sourceValueHash(preview.Mapping) {
			request.Use, request.MaterialHash = &bound, hash
			return reuseReviewedSourceProvider(home, request, plan)
		}
	}
	return missing, nil
}
