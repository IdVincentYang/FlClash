package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/tunnel"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/dlclark/regexp2"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

func TestLocalGroupDeltaPreservesSourceAndSupportsRemoval(t *testing.T) {
	base, _, err := decodeSourceContent([]byte(sourceAcceptanceFixture))
	if err != nil {
		t.Fatal(err)
	}
	before := sourceValueHash(base)
	parent := "Pool"
	group := sourceLocalGroup{ID: 7, Name: "Mine", Type: "select", Nodes: []string{"a"}, Parent: &parent, Enabled: true}
	next, err := localGroupDelta(base, nil, []sourceLocalGroup{group})
	if err != nil || sourceValueHash(base) != before {
		t.Fatal("source was mutated", err)
	}
	for _, field := range []string{"proxies", "rules", "dns", "listeners"} {
		if sourceValueHash(base[field]) != sourceValueHash(next[field]) {
			t.Fatal("unrelated field changed", field)
		}
	}
	restored, err := localGroupDelta(next, []sourceLocalGroup{group}, nil)
	if err != nil || localGroupDocumentHash(restored) != localGroupDocumentHash(base) {
		t.Fatal("removal did not restore source groups", err)
	}
	for _, name := range []string{"Pool", "a", "DIRECT", ""} {
		bad := group
		bad.Name = name
		if _, err := localGroupDelta(base, nil, []sourceLocalGroup{bad}); err == nil {
			t.Fatal("accepted invalid name", name)
		}
	}
}

func testLocalGroupsApproval(t *testing.T, external bool) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	yaml := configTestYAML(configTestPort(t)) + "proxies:\n  - {name: a, type: socks5, server: 127.0.0.1, port: 9}\nproxy-groups:\n  - {name: Main, type: select, proxies: [a]}\n"
	var materials map[string][]byte
	if external {
		yaml = configTestYAML(configTestPort(t)) + "proxy-providers:\n  pool: {type: http, url: 'http://127.0.0.1:1/never-fetch', proxy: DIRECT, interval: 0}\nproxy-groups:\n  - {name: Main, type: select, use: [pool]}\n"
		materials = map[string][]byte{"provider-proxy:pool": []byte("proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n")}
	}
	applyTestInput(t, sourceRuntimeInput(t, yaml, materials))
	base, _, err := decodeSourceContent(appliedConfig.bytes)
	if err != nil {
		t.Fatal(err)
	}
	parent := "Main"
	group := sourceLocalGroup{ID: 7, Name: "Mine", Type: "select", Nodes: []string{"a"}, Parent: &parent, Enabled: true}
	next, err := localGroupDelta(base, nil, []sourceLocalGroup{group})
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(next)
	epoch, picks := routeStamp()
	fence := &ConfigFence{configRuntimeEpoch, configFact.Version, configFact.Owner, configFact.Token, configFact.InputID, epoch, picks}
	request := sourceAcceptanceRequest{Action: "approveLocalGroups", Key: "config:" + strconv.FormatInt(*appliedConfig.manifest.ProfileID, 10), Kind: "config", ExpectedConfig: fence, Body: string(body), LocalGroups: []sourceLocalGroup{group}}
	home := C.Path.HomeDir()
	appRequests.client, appRequests.clientReady = "local-group-fixture", true
	marker := []byte(`{"version":1,"receipt":"local-group-edit","client":"local-group-fixture"}`)
	if err := os.WriteFile(requestRecoveryPath(home), marker, 0600); err != nil {
		t.Fatal(err)
	}
	appRequests.commits["local-group-edit"] = &appRequestReceipt{registry: appRequests, id: "local-group-edit", client: appRequests.client, begun: true, markerHash: inputHash(marker)}
	request.Receipt = "local-group-edit"
	request.Source = ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{"application-config": appRequests.sources["application-config"]}}
	before, _ := os.ReadFile(sourcePermissionsPath(home))
	foreign := request
	foreign.Receipt = "another-edit"
	if _, err := approveLocalSourceGroups(home, foreign); !errors.Is(err, errSourceReview) {
		t.Fatal("accepted another commit's recovery marker", err)
	}
	changed := request
	next["rules"] = []string{"MATCH,REJECT"}
	badBody, _ := json.Marshal(next)
	changed.Body = string(badBody)
	if _, err := approveLocalSourceGroups(home, changed); !errors.Is(err, errLocalGroups) {
		t.Fatal("non-group mutation accepted", err)
	}
	after, _ := os.ReadFile(sourcePermissionsPath(home))
	if !bytes.Equal(before, after) {
		t.Fatal("rejected delta granted permissions")
	}
	stale := *fence
	stale.Version++
	changed = request
	changed.ExpectedConfig = &stale
	if _, err := approveLocalSourceGroups(home, changed); !errors.Is(err, errSourceSuperseded) {
		t.Fatal("stale input accepted", err)
	}
	result, err := approveLocalSourceGroups(home, request)
	if err != nil || result.Status != "localGroupsAccepted" {
		t.Fatal(result, err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	bundle := permissions.Grants[request.Key].Purposes["config"].ReviewBundle
	if bundle == nil || bundle.BodyHash != inputHash(body) || !sourceUseAllowed(permissions, bundle.Bound) {
		t.Fatal("missing approved configuration", bundle)
	}
	reuse := sourceAcceptanceRequest{Use: &bundle.Initial, MaterialHash: bundle.BodyHash}
	if localGroupBundleCurrent(home, reuse) {
		t.Fatal("local edit permit skipped source invalidation")
	}
	appRequests.sources["application-config"]++
	if !localGroupBundleCurrent(home, reuse) {
		t.Fatal("local edit permit did not cover its own source invalidation")
	}
	appRequests.sources["application-config"]++
	if localGroupBundleCurrent(home, reuse) {
		t.Fatal("local edit permit survived another source invalidation")
	}
}

func TestLocalGroupsApprovalIsBoundToAcceptedInputAndOnlyGroupChanges(t *testing.T) {
	testLocalGroupsApproval(t, false)
}
func TestLocalGroupsApprovalReusesProviderNodes(t *testing.T) {
	testLocalGroupsApproval(t, true)
}

func TestLocalGroupMaterialsRequireUniqueExistingNodesAndExactDefinitions(t *testing.T) {
	for _, inlineProvider := range []bool{false, true} {
		base := map[string]any{"proxies": []map[string]any{{"name": "a", "type": "direct"}}}
		if inlineProvider {
			base = map[string]any{"proxy-providers": map[string]any{"pool": map[string]any{"type": "inline", "payload": []map[string]any{{"name": "a", "type": "direct"}}}}}
		}
		group := sourceLocalGroup{ID: 1, Name: "Mine", Type: "select", Nodes: []string{"a"}, Enabled: true}
		next, err := localGroupDelta(base, nil, []sourceLocalGroup{group})
		if err != nil {
			t.Fatal(err)
		}
		body, _ := json.Marshal(next)
		raw, err := config.UnmarshalRawConfig(body)
		if err != nil {
			t.Fatal(err)
		}
		manifest := ConfigManifest{Version: 2, LocalGroups: []sourceLocalGroup{group}}
		if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); err != nil {
			t.Fatal("valid node rejected", inlineProvider, err)
		}
		raw.Proxy = append(raw.Proxy, map[string]any{"name": "a", "type": "direct"})
		if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); !errors.Is(err, errLocalGroupAmbiguous) {
			t.Fatal("ambiguous node accepted", err)
		}
		raw.Proxy = nil
		if !inlineProvider {
			if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); !errors.Is(err, errLocalGroups) {
				t.Fatal("missing node accepted", err)
			}
		}
		raw.ProxyGroup[0]["name"] = "different"
		if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); !errors.Is(err, errLocalGroups) {
			t.Fatal("metadata mismatch accepted", err)
		}
	}
}

func TestLocalGroupProviderFilterMatchesOnlyExactNames(t *testing.T) {
	name := "a.b$[x](1)+|?`-"
	definition := localGroupDefinition(sourceLocalGroup{Name: "Mine", Type: "select", Nodes: []string{name}}, nil)
	filter := definition["filter"].(string)
	if strings.Contains(filter, "`") {
		t.Fatal("provider filter delimiter was not escaped")
	}
	expression, err := regexp2.Compile(filter, regexp2.None)
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{name, "prefix" + name, name + "\n"} {
		matched, err := expression.MatchString(value)
		if err != nil || matched != (value == name) {
			t.Fatal("inexact selected node", value, err)
		}
	}
}

func TestLocalGroupRegexpUsesStandardSyntaxAndEffectiveMaterials(t *testing.T) {
	got, err := matchLocalNodes(`(?i)香港|^jp`, []string{"other", "HK", "香港 02", "JP 01", "香港 02"})
	if err != nil || strings.Join(got, ",") != "JP 01,香港 02" {
		t.Fatal(got, err)
	}
	if _, err := matchLocalNodes(`(?=HK)`, []string{"HK"}); err == nil {
		t.Fatal("accepted unsupported lookaround")
	}
	raw, err := config.UnmarshalRawConfig([]byte("proxies: [{name: '香港 01', type: socks5, server: 127.0.0.1, port: 9}, {name: JP, type: socks5, server: 127.0.0.1, port: 9}]\n"))
	if err != nil {
		t.Fatal(err)
	}
	group := sourceLocalGroup{ID: 1, Name: "Mine", Type: "fallback", Regex: "香港", Nodes: []string{"JP"}, MatchedNodes: []string{"JP"}, Enabled: true, TestURL: "http://127.0.0.1/test"}
	manifest := ConfigManifest{Version: 2, LocalGroups: []sourceLocalGroup{group}}
	groups, err := resolveLocalGroupMembers(t.TempDir(), manifest, raw)
	if err != nil || strings.Join(groups[0].MatchedNodes, ",") != "香港 01" || groups[0].Nodes[0] != "JP" {
		t.Fatal(groups, err)
	}
	manifest.LocalGroups = groups
	raw.ProxyGroup = []map[string]any{localGroupDefinition(groups[0], map[string]bool{"香港 01": true, "JP": true})}
	if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); err != nil {
		t.Fatal(err)
	}
	manifest.LocalGroups[0].MatchedNodes = []string{"JP"}
	if err := validateLocalGroupMaterials(t.TempDir(), manifest, raw); err == nil {
		t.Fatal("forged regexp members accepted")
	}
}

func TestLocalGroupMultipleEntrancesAndZeroMatchesFailClosed(t *testing.T) {
	base, _, err := decodeSourceContent([]byte(sourceAcceptanceFixture))
	if err != nil {
		t.Fatal(err)
	}
	base["proxy-groups"] = append(base["proxy-groups"].([]any), map[string]any{"name": "Other", "type": "select", "proxies": []string{"a"}})
	group := sourceLocalGroup{ID: 8, Name: "Mine", Type: "fallback", Regex: "unmatched", Enabled: true, TestURL: "http://127.0.0.1/test", Parents: []string{"Pool", "Other"}}
	next, err := localGroupDelta(base, nil, []sourceLocalGroup{group})
	if err != nil {
		t.Fatal(err)
	}
	definitions, _ := sourceMappings(next["proxy-groups"])
	for _, row := range definitions {
		if row["name"] == "Mine" && row["empty-fallback"] != "REJECT" {
			t.Fatal("empty group did not fail closed", row)
		}
	}
	restored, err := localGroupDelta(next, []sourceLocalGroup{group}, nil)
	if err != nil || localGroupDocumentHash(restored) != localGroupDocumentHash(base) {
		t.Fatal(restored, err)
	}
}

func TestLocalGroupProviderRefreshReevaluatesRegexpWithoutReplacingActiveOwner(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	base, _, err := decodeSourceContent([]byte(configTestYAML(configTestPort(t)) + "proxy-providers:\n  pool: {type: http, url: 'http://127.0.0.1:1/controlled', interval: 0}\n"))
	if err != nil {
		t.Fatal(err)
	}
	local := sourceLocalGroup{ID: 1, Name: "Mine", Type: "fallback", Regex: "^HK", MatchedNodes: []string{"HK-old"}, Enabled: true, TestURL: "http://127.0.0.1:1/test"}
	document, err := localGroupDelta(base, nil, []sourceLocalGroup{local})
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(document)
	id := sourceRuntimeInput(t, string(body), map[string][]byte{"provider-proxy:pool": []byte("proxies: [{name: HK-old, type: socks5, server: 127.0.0.1, port: 1}]\n")})
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	manifest.LocalGroups = []sourceLocalGroup{local}
	data, _ = json.Marshal(manifest)
	id = inputHash(data)
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	applyTestInput(t, id)
	p := appliedConfig
	owner, token := p.receipt.Owner, p.receipt.Token
	var runtime *sourceProviderRuntime
	for _, r := range p.sourceProviders {
		runtime = r
	}
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	acceptSourceProviderFixture(t, runtime.plan, []byte("proxies: [{name: HK-new, type: socks5, server: 127.0.0.1, port: 2}, {name: JP, type: socks5, server: 127.0.0.1, port: 3}]\n"))
	if err := runtime.update([]byte("proxies: [{name: HK-new, type: socks5, server: 127.0.0.1, port: 2}, {name: JP, type: socks5, server: 127.0.0.1, port: 3}]\n")); err != nil {
		t.Fatal(err)
	}
	if p != appliedConfig || p.receipt.Owner != owner || p.receipt.Token != token || strings.Join(p.manifest.LocalGroups[0].MatchedNodes, ",") != "HK-new" {
		t.Fatal("regexp refresh replaced owner or did not match", p.manifest.LocalGroups)
	}
	if got := tunnel.Proxies()["Mine"].Adapter().(outboundgroup.ProxyGroup).Proxies(); len(got) != 1 || got[0].Name() != "HK-new" {
		t.Fatal("live group members were not refreshed", got)
	}
	if _, _, _, _, err := readConfigInput(home, p.receipt.InputID); err != nil {
		t.Fatal("refreshed input cannot replay", err)
	}
	acceptSourceProviderFixture(t, runtime.plan, []byte("proxies: [{name: JP, type: socks5, server: 127.0.0.1, port: 3}]\n"))
	if err := runtime.update([]byte("proxies: [{name: JP, type: socks5, server: 127.0.0.1, port: 3}]\n")); err != nil {
		t.Fatal("zero regexp matches should be a rejected group", err)
	}
	if got := tunnel.Proxies()["Mine"].Adapter().(outboundgroup.ProxyGroup).Now(); got != "REJECT" {
		t.Fatal("zero matches did not fail closed", got)
	}
}

func TestLocalGroupRegexpRecalculationKeepsManualExclusions(t *testing.T) {
	raw, err := config.UnmarshalRawConfig([]byte("proxies: [{name: HK-1, type: socks5, server: 127.0.0.1, port: 1}, {name: HK-2, type: socks5, server: 127.0.0.1, port: 2}, {name: HK-3, type: socks5, server: 127.0.0.1, port: 3}]\n"))
	if err != nil {
		t.Fatal(err)
	}
	local := sourceLocalGroup{ID: 9, Name: "Mine", Type: "fallback", Regex: "^HK", MatchedNodes: []string{"HK-1", "HK-2"}, ExcludedNodes: []string{"HK-2"}, Enabled: true, TestURL: "http://127.0.0.1/test"}
	groups, err := resolveLocalGroupMembers(t.TempDir(), ConfigManifest{Version: 2, LocalGroups: []sourceLocalGroup{local}}, raw)
	if err != nil || strings.Join(groups[0].members(), ",") != "HK-1,HK-3" || strings.Join(groups[0].MatchedNodes, ",") != "HK-1,HK-2,HK-3" {
		t.Fatal(groups, err)
	}
}

func TestLocalGroupsCannotRemoveSelectedEntranceReference(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	body := configTestYAML(configTestPort(t)) + "proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\nproxy-groups: [{name: Main, type: select, proxies: [a, Mine]}, {name: Mine, type: select, proxies: [a]}]\n"
	id := sourceRuntimeInput(t, body, nil)
	path := filepath.Join(inputDirectory(home), id+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	old := sourceLocalGroup{ID: 7, Name: "Mine", Type: "select", Nodes: []string{"a"}, Parents: []string{"Main"}, Enabled: true}
	manifest.LocalGroups = []sourceLocalGroup{old}
	data, _ = json.Marshal(manifest)
	id = inputHash(data)
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	applyTestInput(t, id)
	selector := tunnel.Proxies()["Main"].Adapter().(*outboundgroup.Selector)
	if err := selector.Set("Mine"); err != nil {
		t.Fatal(err)
	}
	epoch, picks := routeStamp()
	fence := &ConfigFence{configRuntimeEpoch, configFact.Version, configFact.Owner, configFact.Token, configFact.InputID, epoch, picks}
	appRequests.client, appRequests.clientReady = "local-reference-fixture", true
	marker := []byte(`{"version":1,"receipt":"local-reference-edit","client":"local-reference-fixture"}`)
	if err := os.WriteFile(requestRecoveryPath(home), marker, 0600); err != nil {
		t.Fatal(err)
	}
	appRequests.commits["local-reference-edit"] = &appRequestReceipt{registry: appRequests, id: "local-reference-edit", client: appRequests.client, begun: true, markerHash: inputHash(marker)}
	next := old
	next.Parents = nil
	request := sourceAcceptanceRequest{Key: "config:" + strconv.FormatInt(*manifest.ProfileID, 10), Kind: "config", Receipt: "local-reference-edit", ExpectedConfig: fence, LocalGroups: []sourceLocalGroup{next}, Source: ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{"application-config": appRequests.sources["application-config"]}}}
	if _, err := approveLocalSourceGroups(home, request); !errors.Is(err, errLocalGroupInUse) {
		t.Fatal("removed selected reference", err)
	}
	if selector.Now() != "Mine" {
		t.Fatal("changed the active selection")
	}
}
