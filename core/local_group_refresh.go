package main

import (
	"encoding/json"
	"path/filepath"
	"strconv"

	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/config"
)

type localGroupRefresh struct {
	manifest   ConfigManifest
	body       []byte
	raw        *config.RawConfig
	parsedHash string
	graph      *sourceInlineGraph
}

func prepareLocalGroupRefresh(home string, p *preparedConfig, manifest ConfigManifest) (*localGroupRefresh, error) {
	old, _, err := decodeConfigDocument(p.bytes)
	if err != nil {
		return nil, err
	}
	groups, err := resolveLocalGroupMembers(home, manifest, old)
	if err != nil {
		return nil, err
	}
	if sourceValueHash(groups) == sourceValueHash(manifest.LocalGroups) {
		if err := validateLocalGroupMaterials(home, manifest, old); err != nil {
			return nil, err
		}
		return nil, nil
	}
	if reason := sourceInlineReaderReason(); reason != "" {
		return nil, errSourceForeground
	}
	var base map[string]any
	if err := yaml.Unmarshal(p.bytes, &base); err != nil {
		return nil, err
	}
	document, err := localGroupDelta(base, manifest.LocalGroups, groups)
	if err != nil {
		return nil, err
	}
	body, err := yaml.Marshal(document)
	if err != nil {
		return nil, err
	}
	if p.sourceRetiredBytes+len(p.bytes)+len(body) > sourceMaterialTotal {
		return nil, errSourceBudget
	}
	_, summary, err := decodeSourceContent(body)
	if err != nil {
		return nil, err
	}
	next, parsed, err := decodeConfigDocument(body)
	if err != nil {
		return nil, err
	}
	manifest.LocalGroups = groups
	if err := validateLocalGroupMaterials(home, manifest, next); err != nil {
		return nil, err
	}
	manifest, err = recontextualizeLocalGroupProviders(home, manifest, next)
	if err != nil {
		return nil, err
	}
	if err := validateSourceProviderMaterials(home, manifest, next); err != nil {
		return nil, err
	}
	key := "config:" + strconv.FormatInt(*manifest.ProfileID, 10)
	manifest, err = acceptLocalGroupComposition(home, key, ConfigSourceTicket{}, manifest, summary, body)
	if err != nil {
		return nil, err
	}
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), manifest.YAMLSHA256+".yaml"), body); err != nil {
		return nil, err
	}
	selectMu.Lock()
	graph, err := prepareSourceInlineGraph(p, old, next)
	selectMu.Unlock()
	if err != nil {
		return nil, err
	}
	if err := patchConfigInput(next, manifest.AcceptedOverrides); err != nil {
		graph.close()
		return nil, err
	}
	return &localGroupRefresh{manifest: manifest, body: body, raw: next, parsedHash: parsed, graph: graph}, nil
}

func localGroupConfigurationEqual(a, b []sourceLocalGroup) bool {
	left, right := append([]sourceLocalGroup(nil), a...), append([]sourceLocalGroup(nil), b...)
	for i := range left {
		left[i].MatchedNodes = nil
	}
	for i := range right {
		right[i].MatchedNodes = nil
	}
	return sourceValueHash(left) == sourceValueHash(right)
}

func resolvedLocalGroupConfig(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	var manifest ConfigManifest
	if len(request.Body) > sourceGrantFileLimit || json.Unmarshal([]byte(request.Body), &manifest) != nil || manifest.Version != 2 || manifest.ProfileID == nil || request.Kind != "config" || request.Key != "config:"+strconv.FormatInt(*manifest.ProfileID, 10) {
		return sourceAcceptanceResult{}, errLocalGroups
	}
	// Only an existing accepted local expression authorizes automatic member changes.
	p := appliedConfig
	if p == nil || p.manifest.ProfileID == nil || *p.manifest.ProfileID != *manifest.ProfileID || !localGroupConfigurationEqual(p.manifest.LocalGroups, manifest.LocalGroups) {
		return sourceAcceptanceResult{Status: "unchanged"}, nil
	}
	body, err := readSourceObject(home, manifest.YAMLSHA256, sourceCandidateMax)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	raw, _, err := decodeConfigDocument(body)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if err := validateInputSourceUses(home, manifest, body); err != nil {
		return sourceAcceptanceResult{}, err
	}
	groups, err := resolveLocalGroupMembers(home, manifest, raw)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if sourceValueHash(groups) == sourceValueHash(manifest.LocalGroups) {
		return sourceAcceptanceResult{Status: "unchanged"}, nil
	}
	var base map[string]any
	if err := yaml.Unmarshal(body, &base); err != nil {
		return sourceAcceptanceResult{}, err
	}
	document, err := localGroupDelta(base, manifest.LocalGroups, groups)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	body, err = yaml.Marshal(document)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	_, summary, err := decodeSourceContent(body)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	raw, _, err = decodeConfigDocument(body)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	manifest.LocalGroups = groups
	if err := validateLocalGroupMaterials(home, manifest, raw); err != nil {
		return sourceAcceptanceResult{}, err
	}
	manifest, err = recontextualizeLocalGroupProviders(home, manifest, raw)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	manifest, err = acceptLocalGroupComposition(home, request.Key, ConfigSourceTicket{}, manifest, summary, body)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	return sourceAcceptanceResult{Status: "resolved", Document: map[string]any{"yaml": string(body), "manifest": manifest}}, nil
}
