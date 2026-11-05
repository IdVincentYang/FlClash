package main

import (
	"errors"
	"maps"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/config"
)

type SourceProviderMaterial struct {
	Name         string    `json:"name"`
	Kind         string    `json:"kind"`
	Parent       SourceUse `json:"parent"`
	Declaration  string    `json:"declaration"`
	MaterialHash string    `json:"materialHash"`
	Use          SourceUse `json:"use"`
	Origin       SourceUse `json:"origin,omitempty"`
}

type sourceProviderPlan struct {
	Context             SourceUse             `json:"context"`
	ContextMaterialHash string                `json:"contextMaterialHash"`
	Name                string                `json:"name"`
	Kind                string                `json:"kind"`
	Parent              SourceUse             `json:"parent"`
	Key                 string                `json:"key"`
	Declaration         string                `json:"declaration"`
	Mapping             map[string]any        `json:"mapping"`
	Origin              *sourceProviderOrigin `json:"origin,omitempty"`
}

func sourceProviderPlans(body []byte, uses []SourceUse, parentKey string) ([]sourceProviderPlan, error) {
	raw, err := config.UnmarshalRawConfig(body)
	if err != nil {
		return nil, err
	}
	var parent SourceUse
	for _, use := range uses {
		if use.Kind == "profile" && use.Key == parentKey {
			parent = use
			break
		}
	}
	if parent.Key == "" {
		return nil, errSourceReview
	}
	plans := []sourceProviderPlan{}
	for kind, providers := range sourceProviderMaps(raw) {
		for name, mapping := range providers {
			if mapping["type"] == "inline" {
				continue
			}
			if mapping["type"] != "file" && mapping["type"] != "http" {
				return nil, errSourceReview
			}
			plans = append(plans, sourceProviderPlan{Name: name, Kind: kind, Parent: parent, Key: sourceProviderKey(parent.Key, kind, name), Declaration: sourceProviderDeclaration(parent, kind, name, mapping), Mapping: maps.Clone(mapping)})
		}
	}
	slices.SortFunc(plans, func(a, b sourceProviderPlan) int { return strings.Compare(a.Key, b.Key) })
	return plans, nil
}

func sourceProviderCache(home string, owner uint64, material SourceProviderMaterial) string {
	return filepath.Join(home, "source-acceptance", "live", strconv.FormatUint(owner, 10), sourceValueHash([]string{material.Kind, material.Name}))
}

func sourceProviderKey(parent, kind, name string) string {
	return kind + ":" + sourceValueHash([]string{parent, kind, name})
}

func sourceProviderDeclaration(parent SourceUse, kind, name string, mapping map[string]any) string {
	parent.Digest = ""
	return sourceValueHash(struct {
		Parent  SourceUse      `json:"parent"`
		Kind    string         `json:"kind"`
		Name    string         `json:"name"`
		Mapping map[string]any `json:"mapping"`
	}{parent, kind, name, mapping})
}

func sourceProviderMaps(raw *config.RawConfig) map[string]map[string]map[string]any {
	return map[string]map[string]map[string]any{"provider-proxy": raw.ProxyProvider, "provider-rule": raw.RuleProvider}
}

func validateSourceProviderMaterials(home string, manifest ConfigManifest, raw *config.RawConfig) error {
	if manifest.Version != 2 {
		return nil
	}
	if manifest.ProfileID == nil || len(manifest.ProviderMaterials) > sourceEntityLimit {
		return errSourceReview
	}
	parent := "profile:" + strconv.FormatInt(*manifest.ProfileID, 10)
	var parentUse SourceUse
	for _, use := range manifest.SourceUses {
		if use.Key == parent && use.Kind == "profile" {
			parentUse = use
		}
	}
	materials := map[string]SourceProviderMaterial{}
	for _, material := range manifest.ProviderMaterials {
		id := material.Kind + ":" + material.Name
		if _, duplicate := materials[id]; duplicate {
			return errSourceReview
		}
		materials[id] = material
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	for kind, providers := range sourceProviderMaps(raw) {
		for name, mapping := range providers {
			if mapping["type"] == "inline" {
				continue
			}
			if mapping["type"] != "file" && mapping["type"] != "http" {
				return errSourceReview
			}
			id := kind + ":" + name
			material, present := materials[id]
			declaration := sourceProviderDeclaration(parentUse, kind, name, mapping)
			if !present || material.Parent != parentUse || material.Declaration != declaration || material.Use.Key != sourceProviderKey(parent, kind, name) || material.Use.Kind != kind || !slices.Contains(manifest.SourceUses, material.Use) || !sourceUseAllowed(permissions, material.Use) {
				return errors.New("provider material lacks its accepted declaration and composition binding")
			}
			grant := permissions.Grants[material.Use.Key]
			if grant.Identity != declaration {
				return errSourceReview
			}
			body, err := readSourceObject(home, material.MaterialHash, sourceCandidateMax)
			if err != nil {
				return err
			}
			if err := validateSourceProviderOrigin(home, permissions, material, mapping, manifest.SourceUses, body); err != nil {
				return err
			}
			var summary sourceContentSummary
			if kind == "provider-rule" {
				format, _ := mapping["format"].(string)
				behavior, _ := mapping["behavior"].(string)
				summary, err = summarizeSourceRuleContent(body, format, behavior)
			} else {
				document, decodeErr := sourceProviderProxyDocument(body, mapping)
				err = decodeErr
				if err == nil {
					if permissions.Grants[parent].Routing == "own" {
						_, err = sourceRoutingProjection(document, parent)
					}
					if err == nil {
						summary, err = summarizeSourceProviderProxy(document, raw)
					}
				}
			}
			if err != nil || summary.Digest != material.Use.Digest {
				return errSourceReview
			}
			delete(materials, id)
		}
	}
	if len(materials) != 0 {
		return errSourceReview
	}
	return nil
}

func projectSourceProviderFiles(home string, p *preparedConfig) error {
	if err := validateSourceProviderMaterials(home, p.manifest, p.raw); err != nil {
		return err
	}
	for _, material := range p.manifest.ProviderMaterials {
		mapping := sourceProviderMaps(p.raw)[material.Kind][material.Name]
		projected := maps.Clone(mapping)
		projected["type"], projected["path"], projected["interval"] = "file", sourceProviderCache(home, p.receipt.Owner, material), 0
		delete(projected, "url")
		if material.Kind == "provider-proxy" {
			projected["type"], projected["url"] = "http", "source-accepted://"+material.Use.Key
		}
		delete(projected, "header")
		body, err := readSourceObject(home, material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return err
		}
		if err := atomicConfigFile(projected["path"].(string), body); err != nil {
			return err
		}
		sourceProviderMaps(p.raw)[material.Kind][material.Name] = projected
	}
	return nil
}

func bindSourceProviderMaterials(home string, previous SourceUse, materialHash string, materials []SourceProviderMaterial) (SourceUse, error) {
	plans, err := acceptedSourceProviderPlans(home, previous, materialHash)
	if err != nil || len(plans) != len(materials) {
		return SourceUse{}, errSourceReview
	}
	body, err := readSourceObject(home, materialHash, sourceCandidateMax)
	if err != nil {
		return SourceUse{}, err
	}
	raw, err := config.UnmarshalRawConfig(body)
	if err != nil {
		return SourceUse{}, err
	}
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	if err != nil || !sourceUseAllowed(permissions, previous) {
		sourceAuthorityMu.Unlock()
		if err != nil {
			return SourceUse{}, err
		}
		return SourceUse{}, errSourceUseRevoked
	}
	dependencies := slices.Clone(permissions.Grants[previous.Key].Purposes[previous.Kind].BoundUses[previous.Digest])
	sourceAuthorityMu.Unlock()
	dependencies = slices.DeleteFunc(dependencies, func(use SourceUse) bool {
		return slices.ContainsFunc(plans, func(plan sourceProviderPlan) bool {
			return use.Key == plan.Key && use.Kind == plan.Kind || plan.Origin != nil && use.Key == plan.Origin.Key && use.Kind == plan.Kind
		})
	})
	for _, material := range materials {
		dependencies = append(dependencies, material.Use)
		if material.Origin.Key != "" {
			dependencies = append(dependencies, material.Origin)
		}
	}
	dependencies = canonicalSourceUses(dependencies)
	id, err := strconv.ParseInt(strings.TrimPrefix(previous.Key, "config:"), 10, 64)
	if err != nil {
		return SourceUse{}, errSourceReview
	}
	manifest := ConfigManifest{Version: 2, ProfileID: &id, SourceUses: dependencies, ProviderMaterials: materials}
	if err := validateSourceProviderMaterials(home, manifest, raw); err != nil {
		return SourceUse{}, err
	}
	_, summary, err := decodeSourceContent(body)
	if err != nil {
		return SourceUse{}, err
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err = readSourcePermissions(home)
	if err != nil {
		return SourceUse{}, err
	}
	if !sourceUseAllowed(permissions, previous) {
		return SourceUse{}, errSourceUseRevoked
	}
	for _, use := range dependencies {
		if !sourceUseAllowed(permissions, use) {
			return SourceUse{}, errSourceUseRevoked
		}
	}
	grant := permissions.Grants[previous.Key]
	purpose := grant.Purposes[previous.Kind]
	digest := sourceCompositionDigest(summary.Digest, dependencies)
	if slices.Contains(purpose.Accepted, digest) && slices.Equal(canonicalSourceUses(purpose.BoundUses[digest]), dependencies) {
		return sourceUseReceipt(previous.Key, previous.Kind, digest, grant), nil
	}
	if !slices.Contains(purpose.Accepted, digest) {
		purpose.Accepted = append(purpose.Accepted, digest)
	}
	if purpose.BoundUses == nil {
		purpose.BoundUses = map[string][]SourceUse{}
	}
	purpose.BoundUses[digest] = dependencies
	grant.Revision++
	if err := saveSourcePermissions(home, permissions); err != nil {
		return SourceUse{}, err
	}
	return sourceUseReceipt(previous.Key, previous.Kind, digest, grant), nil
}
