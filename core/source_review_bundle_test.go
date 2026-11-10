package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestSourceSubscriptionPreviewHasNoPermissionSideEffects(t *testing.T) {
	home := t.TempDir()
	body := "rules: [MATCH,REJECT]\nrule-providers:\n  first: {type: http, url: 'https://example.invalid/a', behavior: domain, format: text}\n  second: {type: http, url: 'https://example.invalid/b', behavior: domain, format: text}\n"
	result, err := previewSourceReview(home, sourceAcceptanceRequest{Kind: "config", Body: body, Parent: &SourceUse{Key: "profile:1"}})
	if err != nil || result.Status != "preview" || len(result.Providers) != 2 || result.Use != nil {
		t.Fatal(result, err)
	}
	if _, err := os.Stat(sourcePermissionsPath(home)); !os.IsNotExist(err) {
		t.Fatal("preview created canonical permissions", err)
	}
	for _, plan := range result.Providers {
		described, err := previewSourceReview(home, sourceAcceptanceRequest{Kind: plan.Kind, Body: "example.invalid\n", Format: "text", Behavior: "domain"})
		if err != nil || described.Details.Rules != 1 || described.Use != nil {
			t.Fatal(described, err)
		}
	}
	if files, _ := os.ReadDir(home); len(files) != 0 {
		t.Fatal("preview wrote material or grant files")
	}
}

func TestSourceSubscriptionBundleSurvivesFrontendCacheAndHonorsWithdrawal(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	body := []byte("payload: [example.invalid]\n")
	yaml := configTestYAML(configTestPort(t)) + "rule-providers:\n  reviewed: {type: http, url: 'http://127.0.0.1:1/never-download', format: yaml, behavior: domain}\n"
	id := sourceRuntimeInput(t, yaml, map[string][]byte{"provider-rule:reviewed": body})
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	var root SourceUse
	for _, use := range manifest.SourceUses {
		if use.Kind == "config" {
			root = use
		}
	}
	plans, err := acceptedSourceProviderPlans(home, root, inputHash([]byte(yaml)))
	if err != nil || len(plans) != 1 {
		t.Fatal(plans, err)
	}
	if err := rememberSourceReviewBundle(home, root, root, inputHash([]byte(yaml)), manifest.ProviderMaterials); err != nil {
		t.Fatal(err)
	}
	if err := collectSourceMaterialsLocked(home); err != nil {
		t.Fatal(err)
	}
	request := sourceAcceptanceRequest{Use: &root, MaterialHash: inputHash([]byte(yaml))}
	reused, err := reuseReviewedSourceProvider(home, request, plans[0])
	if err != nil || reused.Status != "reused" || reused.MaterialHash != inputHash(body) {
		t.Fatal(reused, err)
	}
	previewRequest := sourceAcceptanceRequest{Parent: &SourceUse{Key: plans[0].Parent.Key}, Body: yaml, ProviderName: "reviewed", Kind: "provider-rule"}
	beforePermissions, _ := os.ReadFile(sourcePermissionsPath(home))
	cached, err := previewCachedSourceProvider(home, previewRequest)
	if err != nil || cached.Status != "reused" || cached.MaterialHash != inputHash(body) {
		t.Fatal(cached, err)
	}
	afterPermissions, _ := os.ReadFile(sourcePermissionsPath(home))
	if string(beforePermissions) != string(afterPermissions) {
		t.Fatal("preview granted permissions")
	}
	contextChanged := previewRequest
	contextChanged.Body += "proxy-groups: [{name: Local, type: select, proxies: [DIRECT]}]\n"
	contextCached, err := previewCachedSourceProvider(home, contextChanged)
	if err != nil || contextCached.Status != "reused" {
		t.Fatal("read-only preview could not reuse the still accepted body in a new context", contextCached, err)
	}
	afterPermissions, _ = os.ReadFile(sourcePermissionsPath(home))
	if string(beforePermissions) != string(afterPermissions) {
		t.Fatal("context preview changed authority")
	}
	changed := previewRequest
	changed.Body = strings.Replace(yaml, "never-download", "changed-url", 1)
	missed, err := previewCachedSourceProvider(home, changed)
	if err != nil || missed.Status != "missing" {
		t.Fatal(missed, err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	child := manifest.ProviderMaterials[0].Use
	grant := permissions.Grants[child.Key]
	if err := withdrawSourcePermission(home, child.Key, grant.Incarnation, grant.Revision, true, child.Kind); err != nil {
		t.Fatal(err)
	}
	refused, err := reuseReviewedSourceProvider(home, request, plans[0])
	if !errors.Is(err, errSourceUseRevoked) || refused.Status == "reused" {
		t.Fatal("withdrawn child was reused", refused, err)
	}
	cached, err = previewCachedSourceProvider(home, previewRequest)
	if err != nil || cached.Status != "missing" {
		t.Fatal("withdrawn preview cache was reused", cached, err)
	}

}
