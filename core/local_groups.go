package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/config"
	RC "github.com/metacubex/mihomo/rules/common"
	"github.com/metacubex/mihomo/tunnel"
)

type sourceLocalGroup struct {
	ID            int64    `json:"id"`
	Name          string   `json:"name"`
	Type          string   `json:"type"`
	Nodes         []string `json:"nodes"`
	Regex         string   `json:"regex,omitempty"`
	MatchedNodes  []string `json:"matchedNodes,omitempty"`
	ExcludedNodes []string `json:"excludedNodes,omitempty"`
	Parents       []string `json:"parents,omitempty"`
	Parent        *string  `json:"parent"`
	Enabled       bool     `json:"enabled"`
	TestURL       string   `json:"testUrl"`
}

var errLocalGroups = errors.New("local group change is unavailable or invalid")
var errLocalGroupInUse = errors.New("local group is still in use")
var errLocalGroupAmbiguous = errors.New("local group node name is ambiguous")

func validateLocalGroupMaterials(home string, manifest ConfigManifest, raw *config.RawConfig) error {
	if manifest.Version != 2 || len(manifest.LocalGroups) == 0 {
		return nil
	}
	if len(manifest.LocalGroups) > 64 {
		return errLocalGroups
	}
	nodes, err := localGroupMaterialNodes(home, manifest, raw)
	if err != nil {
		return err
	}
	inline := map[string]bool{}
	for _, node := range raw.Proxy {
		name, _ := node["name"].(string)
		inline[name] = true
	}
	for _, group := range manifest.LocalGroups {
		if !group.Enabled {
			continue
		}
		if nodes[group.Name] != 0 || len(group.members()) == 0 && group.Regex == "" || len(group.members()) > 1024 {
			return errLocalGroups
		}
		for _, name := range group.members() {
			if nodes[name] > 1 {
				return errLocalGroupAmbiguous
			}
			if nodes[name] == 0 {
				return errLocalGroups
			}
		}
		if group.Regex != "" {
			pool := make([]string, 0, len(nodes))
			for name := range nodes {
				pool = append(pool, name)
			}
			matches, err := matchLocalNodes(group.Regex, pool)
			actual := slices.Clone(group.MatchedNodes)
			slices.Sort(actual)
			if err != nil || !slices.Equal(matches, actual) {
				return errLocalGroups
			}
		}
		definition := localGroupDefinition(group, inline)
		if !slices.ContainsFunc(raw.ProxyGroup, func(actual map[string]any) bool {
			return actual["name"] == group.Name && sourceValueHash(actual) == sourceValueHash(definition)
		}) {
			return errLocalGroups
		}
	}
	return nil
}

func recontextualizeLocalGroupProviders(home string, manifest ConfigManifest, raw *config.RawConfig) (ConfigManifest, error) {
	manifest.ProviderMaterials = slices.Clone(manifest.ProviderMaterials)
	manifest.SourceUses = slices.Clone(manifest.SourceUses)
	providers := sourceProviderMaps(raw)["provider-proxy"]
	for i, material := range manifest.ProviderMaterials {
		if material.Kind != "provider-proxy" {
			continue
		}
		body, err := readSourceObject(home, material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return manifest, err
		}
		document, err := sourceProviderProxyDocument(body, providers[material.Name])
		if err != nil {
			return manifest, err
		}
		summary, err := summarizeSourceProviderProxy(document, raw)
		if err != nil {
			return manifest, err
		}
		if summary.Digest == material.Use.Digest {
			continue
		}
		sourceAuthorityMu.Lock()
		permissions, err := readSourcePermissions(home)
		var grant *SourceGrant
		var purpose *sourcePurposeGrant
		if err == nil && sourceUseAllowed(permissions, material.Use) {
			grant = permissions.Grants[material.Use.Key]
			purpose = grant.Purposes[material.Use.Kind]
		}
		sourceAuthorityMu.Unlock()
		if err != nil || purpose == nil {
			return manifest, errSourceReview
		}
		var contract sourceContentContract
		if purpose.Contract != "" {
			data, err := readSourceObject(home, purpose.Contract, sourceGrantFileLimit)
			if err != nil || json.Unmarshal(data, &contract) != nil {
				return manifest, errSourceStore
			}
		}
		contract.Version, contract.Base = 1, summary
		data, _ := json.Marshal(contract)
		hash, err := sealSourceObject(home, data, sourceGrantFileLimit)
		if err != nil {
			return manifest, err
		}
		use, err := acceptSourceRevisionUses(home, material.Use.Key, grant.Identity, summary.Digest, "source", hash, purpose.Automatic, grant.Revision, material.Kind, nil)
		if err != nil {
			return manifest, err
		}
		manifest.ProviderMaterials[i].Use = use
		for j, old := range manifest.SourceUses {
			if old == material.Use {
				manifest.SourceUses[j] = use
			}
		}
	}
	return manifest, nil
}

func localGroupDocumentHash(document map[string]any) string {
	copy := make(map[string]any, len(document))
	for key, value := range document {
		copy[key] = value
	}
	groups, _ := sourceMappings(document["proxy-groups"])
	canonical := make([]map[string]any, 0, len(groups))
	for _, group := range groups {
		row := make(map[string]any, len(group)+1)
		for key, value := range group {
			row[key] = value
		}
		if values, ok := sourceStrings(row["proxies"]); row["proxies"] == nil || ok && len(values) == 0 {
			row["proxies"] = []string{}
		}
		canonical = append(canonical, row)
	}
	copy["proxy-groups"] = canonical
	return sourceValueHash(copy)
}

func localGroupDefinition(group sourceLocalGroup, inline map[string]bool) map[string]any {
	members := make([]any, 0, len(group.members()))
	var external bool
	patterns := make([]string, 0, len(group.members()))
	for _, node := range group.members() {
		patterns = append(patterns, strings.ReplaceAll(regexp.QuoteMeta(node), "`", `\x60`))
		if inline[node] {
			members = append(members, node)
		} else {
			external = true
		}
	}
	if len(group.members()) == 0 && group.Regex != "" {
		members = append(members, "REJECT")
	}
	definition := map[string]any{"name": group.Name, "type": group.Type, "proxies": members}
	if group.Regex != "" {
		definition["empty-fallback"] = "REJECT"
	}
	if external {
		definition["include-all-providers"], definition["filter"] = true, "^(?:"+strings.Join(patterns, "|")+")$(?![\\s\\S])"
	}
	if group.Type != "select" {
		definition["url"], definition["interval"] = group.TestURL, 300
	}
	return definition
}

func localGroupDelta(base map[string]any, before, after []sourceLocalGroup) (map[string]any, error) {
	if len(before) > 64 || len(after) > 64 {
		return nil, errLocalGroups
	}
	next := make(map[string]any, len(base))
	for key, value := range base {
		next[key] = value
	}
	inline := map[string]bool{}
	if nodes, ok := sourceMappings(base["proxies"]); ok {
		for _, node := range nodes {
			name, _ := node["name"].(string)
			inline[name] = true
		}
	}
	groups, valid := sourceMappings(next["proxy-groups"])
	groups = slices.Clone(groups)
	if !valid && next["proxy-groups"] != nil {
		return nil, errLocalGroups
	}
	for i, group := range groups {
		encoded, _ := json.Marshal(group)
		var cloned map[string]any
		if json.Unmarshal(encoded, &cloned) != nil {
			return nil, errLocalGroups
		}
		groups[i] = cloned
	}
	for _, old := range before {
		if !old.Enabled {
			continue
		}
		index := slices.IndexFunc(groups, func(group map[string]any) bool { return group["name"] == old.Name })
		if index < 0 || sourceValueHash(groups[index]) != sourceValueHash(localGroupDefinition(old, inline)) {
			return nil, errLocalGroups
		}
		groups = slices.Delete(groups, index, index+1)
		for _, entrance := range old.entrances() {
			for _, group := range groups {
				if group["name"] != entrance {
					continue
				}
				members, ok := sourceStrings(group["proxies"])
				if !ok || !slices.Contains(members, old.Name) {
					return nil, errLocalGroups
				}
				group["proxies"] = slices.DeleteFunc(members, func(name string) bool { return name == old.Name })
			}
		}
	}
	names := map[string]bool{"GLOBAL": true, "DIRECT": true, "REJECT": true, "REJECT-DROP": true, "PASS": true, "PASS-RULE": true, "COMPATIBLE": true}
	for _, group := range groups {
		name, _ := group["name"].(string)
		names[name] = true
	}
	if nodes, ok := sourceMappings(next["proxies"]); ok {
		for _, node := range nodes {
			name, _ := node["name"].(string)
			names[name] = true
		}
	}
	for _, group := range after {
		if !group.Enabled {
			continue
		}
		if group.ID < 0 || strings.TrimSpace(group.Name) == "" || len([]rune(group.Name)) > 128 || strings.ContainsAny(group.Name, "\x00\r\n\t") || names[group.Name] || !slices.Contains([]string{"select", "url-test", "fallback"}, group.Type) || len(group.members()) == 0 && group.Regex == "" || len(group.members()) > 1024 {
			return nil, errLocalGroups
		}
		names[group.Name] = true
		members := map[string]bool{}
		for _, node := range group.members() {
			if node == "" || node == group.Name || members[node] {
				return nil, errLocalGroups
			}
			members[node] = true
		}
		if group.Type != "select" {
			address, err := url.Parse(group.TestURL)
			if err != nil || address.Hostname() == "" || address.Scheme != "http" && address.Scheme != "https" {
				return nil, errLocalGroups
			}
		}
		for _, entrance := range group.entrances() {
			index := slices.IndexFunc(groups, func(parent map[string]any) bool { return parent["name"] == entrance && parent["type"] == "select" })
			if index < 0 {
				return nil, errLocalGroups
			}
			parents, ok := sourceStrings(groups[index]["proxies"])
			if !ok {
				return nil, errLocalGroups
			}
			groups[index]["proxies"] = append(parents, group.Name)
		}
		groups = append(groups, localGroupDefinition(group, inline))
	}
	next["proxy-groups"] = groups
	return next, nil
}

func approveLocalSourceGroups(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if err := requestWriterError(); err != nil {
		return sourceAcceptanceResult{}, err
	}
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return sourceAcceptanceResult{}, err
	}
	requestRecoveryMu.Lock()
	marker, markerErr := readRequestRecoveryMarker(home)
	requestRecoveryMu.Unlock()
	if markerErr != nil {
		return sourceAcceptanceResult{}, markerErr
	}
	if marker != nil || requestscope.BeginHook != nil {
		appRequests.mu.Lock()
		receipt := appRequests.commits[request.Receipt]
		valid := receipt != nil && receipt.registry == appRequests && receipt.begun && !receipt.retired && !receipt.failed && receipt.material == nil && receipt.client == request.Source.Client && appRequests.client == request.Source.Client && appRequests.clientReady && receipt.markerHash != "" && inputHash(marker) == receipt.markerHash
		appRequests.mu.Unlock()
		if !valid {
			return sourceAcceptanceResult{}, fmt.Errorf("local group commit: %w", errSourceReview)
		}
	}
	p := appliedConfig
	if p == nil || p.manifest.ProfileID == nil || p.manifest.ManagedPolicy != nil || request.Kind != "config" || request.Key != "config:"+strconv.FormatInt(*p.manifest.ProfileID, 10) || request.ExpectedConfig == nil || len(request.Body) > sourceCandidateMax {
		return sourceAcceptanceResult{}, errLocalGroups
	}
	request.LocalGroupsBefore = p.manifest.LocalGroups
	selectMu.Lock()
	checkpointMu.Lock()
	current := configFenceMatchesLocked(request.ExpectedConfig) && configFact.ProfileID != nil && *configFact.ProfileID == *p.manifest.ProfileID && (configFact.Phase == "ready" || configFact.Phase == "installed")
	checkpointMu.Unlock()
	if current {
		for _, old := range request.LocalGroupsBefore {
			for _, entrance := range old.entrances() {
				retained := slices.ContainsFunc(request.LocalGroups, func(next sourceLocalGroup) bool {
					return next.Enabled && next.Name == old.Name && slices.Contains(next.entrances(), entrance)
				})
				if proxy := tunnel.Proxies()[entrance]; old.Enabled && !retained && proxy != nil {
					if group, ok := proxy.Adapter().(outboundgroup.ProxyGroup); ok && group.Now() == old.Name {
						selectMu.Unlock()
						return sourceAcceptanceResult{}, errLocalGroupInUse
					}
				}
			}
			if !old.Enabled || slices.ContainsFunc(request.LocalGroups, func(next sourceLocalGroup) bool { return next.Enabled && next.Name == old.Name }) {
				continue
			}
			for _, rule := range p.raw.Rule {
				_, _, target, _ := RC.ParseRulePayload(rule, true)
				if target == old.Name {
					selectMu.Unlock()
					return sourceAcceptanceResult{}, errLocalGroupInUse
				}
			}
			for _, definition := range p.raw.ProxyGroup {
				members, _ := sourceStrings(definition["proxies"])
				if slices.Contains(members, old.Name) && !slices.Contains(old.entrances(), fmt.Sprint(definition["name"])) {
					selectMu.Unlock()
					return sourceAcceptanceResult{}, errLocalGroupInUse
				}
			}
			for name, proxy := range tunnel.Proxies() {
				if group, ok := proxy.Adapter().(outboundgroup.ProxyGroup); ok && name != old.Name && group.Now() == old.Name {
					selectMu.Unlock()
					return sourceAcceptanceResult{}, errLocalGroupInUse
				}
			}
		}
	}
	selectMu.Unlock()
	if !current {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	base, _, err := decodeSourceContent(p.bytes)
	if err != nil {
		return sourceAcceptanceResult{}, fmt.Errorf("local group input: %w", err)
	}
	expected, err := localGroupDelta(base, request.LocalGroupsBefore, request.LocalGroups)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if request.Body == "" {
		body, err := yaml.Marshal(expected)
		if err != nil || len(body) > sourceCandidateMax {
			return sourceAcceptanceResult{}, errLocalGroups
		}
		request.Body = string(body)
	}
	document, summary, err := decodeSourceContent([]byte(request.Body))
	if err != nil || localGroupDocumentHash(expected) != localGroupDocumentHash(document) {
		return sourceAcceptanceResult{}, errLocalGroups
	}
	raw, err := config.UnmarshalRawConfig([]byte(request.Body))
	if err != nil {
		return sourceAcceptanceResult{}, fmt.Errorf("local group config: %w: %v", errSourceReview, err)
	}
	baseline, err := config.UnmarshalRawConfig(p.bytes)
	if err != nil {
		return sourceAcceptanceResult{}, fmt.Errorf("local group baseline config: %w: %v", errSourceReview, err)
	}
	if err := validateSourceProviderMaterials(home, p.manifest, baseline); err != nil {
		return sourceAcceptanceResult{}, fmt.Errorf("local group baseline: %w", err)
	}
	if err := checkSourceUses(home, p.manifest.SourceUses); err != nil {
		return sourceAcceptanceResult{}, err
	}
	manifest := p.manifest
	manifest.LocalGroups = request.LocalGroups
	if err := validateLocalGroupMaterials(home, manifest, raw); err != nil {
		return sourceAcceptanceResult{}, err
	}
	selectMu.Lock()
	defer selectMu.Unlock()
	checkpointMu.Lock()
	current = configFenceMatchesLocked(request.ExpectedConfig)
	checkpointMu.Unlock()
	if !current || !sourceAcceptanceCurrent(request) && request.Source.Client != "" {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	manifest, err = recontextualizeLocalGroupProviders(home, manifest, raw)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if err := validateSourceProviderMaterials(home, manifest, raw); err != nil {
		return sourceAcceptanceResult{}, fmt.Errorf("local group providers: %w", err)
	}
	manifest, err = acceptLocalGroupComposition(home, request.Key, request.Source, manifest, summary, []byte(request.Body))
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	picks := map[string]string{}
	for name, proxy := range tunnel.Proxies() {
		if group, ok := proxy.Adapter().(*outboundgroup.Selector); ok {
			picks[name] = group.Now()
		}
	}
	return sourceAcceptanceResult{Status: "localGroupsAccepted", SelectedMap: picks, Document: map[string]any{"yaml": request.Body, "manifest": manifest}}, nil
}

func (g sourceLocalGroup) members() []string {
	if g.Regex != "" {
		return slices.DeleteFunc(slices.Clone(g.MatchedNodes), func(name string) bool { return slices.Contains(g.ExcludedNodes, name) })
	}
	return g.Nodes
}

func (g sourceLocalGroup) entrances() []string {
	values := slices.Clone(g.Parents)
	if g.Parent != nil && !slices.Contains(values, *g.Parent) {
		values = append(values, *g.Parent)
	}
	return values
}

func matchLocalNodes(pattern string, names []string) ([]string, error) {
	if len(pattern) > 4096 || len(names) > 16384 {
		return nil, errSourceBudget
	}
	expression, err := regexp.Compile(pattern)
	if err != nil {
		return nil, err
	}
	result := make([]string, 0)
	seen := map[string]bool{}
	for _, name := range names {
		if len(name) > 4096 {
			return nil, errSourceBudget
		}
		if !seen[name] && expression.MatchString(name) {
			result = append(result, name)
			seen[name] = true
		}
	}
	slices.Sort(result)
	return result, nil
}

func localGroupMaterialNodes(home string, manifest ConfigManifest, raw *config.RawConfig) (map[string]int, error) {
	nodes := map[string]int{}
	collect := func(definitions []map[string]any) {
		for _, definition := range definitions {
			if name, ok := definition["name"].(string); ok {
				nodes[name]++
			}
		}
	}
	collect(raw.Proxy)
	inline := map[string]bool{}
	for _, node := range raw.Proxy {
		name, _ := node["name"].(string)
		inline[name] = true
	}
	providers := sourceProviderMaps(raw)["provider-proxy"]
	for _, declaration := range providers {
		if declaration["type"] != "inline" {
			continue
		}
		body, err := json.Marshal(map[string]any{"proxies": declaration["payload"]})
		if err != nil {
			return nil, errLocalGroups
		}
		document, err := sourceProviderProxyDocument(body, declaration)
		if err != nil {
			return nil, err
		}
		definitions, ok := sourceMappings(document["proxies"])
		if !ok {
			return nil, errLocalGroups
		}
		collect(definitions)
	}
	for _, material := range manifest.ProviderMaterials {
		if material.Kind != "provider-proxy" {
			continue
		}
		body, err := readSourceObject(home, material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return nil, err
		}
		document, err := sourceProviderProxyDocument(body, providers[material.Name])
		if err != nil {
			return nil, err
		}
		definitions, ok := sourceMappings(document["proxies"])
		if !ok {
			return nil, errLocalGroups
		}
		collect(definitions)
	}
	return nodes, nil
}

func resolveLocalGroupMembers(home string, manifest ConfigManifest, raw *config.RawConfig) ([]sourceLocalGroup, error) {
	nodes, err := localGroupMaterialNodes(home, manifest, raw)
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(nodes))
	for name := range nodes {
		names = append(names, name)
	}
	groups := slices.Clone(manifest.LocalGroups)
	for i, group := range groups {
		if !group.Enabled || group.Regex == "" {
			continue
		}
		matches, err := matchLocalNodes(group.Regex, names)
		if err != nil {
			return nil, err
		}
		groups[i].MatchedNodes = matches
	}
	return groups, nil
}

func acceptLocalGroupComposition(home, key string, source ConfigSourceTicket, manifest ConfigManifest, summary sourceContentSummary, body []byte) (ConfigManifest, error) {
	dependencies := slices.DeleteFunc(slices.Clone(manifest.SourceUses), func(use SourceUse) bool { return use.Kind == "config" })
	initialDependencies := slices.DeleteFunc(slices.Clone(dependencies), func(use SourceUse) bool {
		return slices.ContainsFunc(manifest.ProviderMaterials, func(material SourceProviderMaterial) bool { return material.Use == use })
	})
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	var identity, contractHash string
	var revision uint64
	var automatic bool
	var contract sourceContentContract
	if err == nil {
		grant := permissions.Grants[key]
		if grant == nil || grant.Purposes["config"] == nil {
			err = fmt.Errorf("local group parent grant: %w", errSourceReview)
		} else {
			purpose := grant.Purposes["config"]
			identity, revision, automatic = grant.Identity, grant.Revision, purpose.Automatic
			if purpose.Contract != "" {
				var data []byte
				data, err = readSourceObject(home, purpose.Contract, sourceGrantFileLimit)
				if err == nil {
					err = json.Unmarshal(data, &contract)
				}
			}
		}
	}
	sourceAuthorityMu.Unlock()
	if err != nil {
		return ConfigManifest{}, err
	}
	contract.Version, contract.Base, contract.Bindings = 1, summary, sourceBindingIdentities(initialDependencies)
	encoded, _ := json.Marshal(contract)
	contractHash, err = sealSourceObject(home, encoded, sourceGrantFileLimit)
	if err != nil {
		return ConfigManifest{}, err
	}
	hash, err := sealSourceObject(home, body, sourceCandidateMax)
	if err != nil {
		return ConfigManifest{}, err
	}
	initial, err := acceptSourceRevisionUses(home, key, identity, sourceCompositionDigest(summary.Digest, initialDependencies), "source", contractHash, automatic, revision, "config", initialDependencies)
	if err != nil {
		return ConfigManifest{}, err
	}
	bound := initial
	if !slices.Equal(initialDependencies, dependencies) {
		bound, err = acceptSourceRevisionUses(home, key, identity, sourceCompositionDigest(summary.Digest, dependencies), "source", contractHash, automatic, revision+1, "config", dependencies)
		if err != nil {
			return ConfigManifest{}, err
		}
	}
	if err := rememberSourceReviewBundle(home, initial, bound, hash, manifest.ProviderMaterials, source); err != nil {
		return ConfigManifest{}, err
	}
	manifest.SourceUses, err = sourceCompositionUses(home, bound)
	if err != nil {
		return ConfigManifest{}, err
	}
	manifest.YAMLSHA256 = hash
	return manifest, nil
}
