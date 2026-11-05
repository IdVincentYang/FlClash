package main

import (
	"crypto/md5"
	"encoding/hex"
	"path/filepath"
	"slices"
	"testing"
)

func acceptSourceOriginFixture(t *testing.T, home string, request sourceAcceptanceRequest) SourceUse {
	t.Helper()
	result, err := sourceAcceptance(home, request)
	if err != nil {
		t.Fatal(err)
	}
	if result.Status == "reviewRequired" {
		request.Action, request.Candidate, request.Routing, request.Automatic = "accept", result.Candidate, "source", true
		result, err = sourceAcceptance(home, request)
	}
	if err != nil || result.Status != "accepted" || result.Use == nil {
		t.Fatal(result, err)
	}
	return *result.Use
}

func TestSourcePhysicalProviderRequiresItsOwnExactPurpose(t *testing.T) {
	home := t.TempDir()
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:2", Kind: "provider-proxy", Identity: inputHash([]byte("physical source")), Settings: inputHash(nil), Body: "proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 1}]\n"}
	use := acceptSourceOriginFixture(t, home, request)
	mapping := map[string]any{"type": "file", "path": filepath.Join(home, "profiles", "2.yaml")}
	material := SourceProviderMaterial{Kind: request.Kind, Origin: use}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	validate := func(value SourceProviderMaterial, body string, uses []SourceUse) error {
		return validateSourceProviderOrigin(home, permissions, value, mapping, uses, []byte(body))
	}
	if err := validate(material, request.Body, []SourceUse{use}); err != nil {
		t.Fatal("exact raw node purpose rejected", err)
	}
	missing := material
	missing.Origin = SourceUse{}
	if validate(missing, request.Body, []SourceUse{use}) == nil || validate(material, request.Body, nil) == nil {
		t.Fatal("physical source without its root-bound purpose accepted")
	}
	request.Body = "proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 2}]\n"
	if validate(material, request.Body, []SourceUse{use}) == nil {
		t.Fatal("old raw permission authorized a different body")
	}
	grant := permissions.Grants[request.Key]
	if err := withdrawSourcePermission(home, request.Key, grant.Incarnation, grant.Revision, false, request.Kind); err != nil {
		t.Fatal(err)
	}
	result, err := sourceAcceptance(home, request)
	if err != nil || result.Status != "reviewRequired" {
		t.Fatal("stopped physical auto permission authorized new nodes", result, err)
	}
	if err := checkSourceUses(home, []SourceUse{use}); err != nil {
		t.Fatal("stopping auto revoked the existing exact use", err)
	}
	permissions, _ = readSourcePermissions(home)
	grant = permissions.Grants[request.Key]
	if err := withdrawSourcePermission(home, request.Key, grant.Incarnation, grant.Revision, true, request.Kind); err != nil {
		t.Fatal(err)
	}
	if checkSourceUses(home, []SourceUse{use}) == nil {
		t.Fatal("withdrawn physical purpose remained usable")
	}
}

func TestSourceConfigAutomaticMaintenancePreservesPhysicalBindingIdentities(t *testing.T) {
	home := t.TempDir()
	main := acceptSourceOriginFixture(t, home, sourceAcceptanceRequest{Action: "review", Key: "profile:1", Kind: "profile", Identity: inputHash([]byte("parent")), Settings: inputHash(nil), Body: "rules: [MATCH,DIRECT]\n"})
	nodes := sourceAcceptanceRequest{Action: "review", Key: "profile:2", Kind: "provider-proxy", Identity: inputHash([]byte("nodes")), Settings: inputHash(nil), Body: "proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 1}]\n"}
	use := acceptSourceOriginFixture(t, home, nodes)
	request := sourceAcceptanceRequest{Action: "review", Key: "config:1", Kind: "config", Identity: inputHash([]byte("composition")), Settings: inputHash(nil), Body: "rules: [MATCH,DIRECT]\n", Uses: []SourceUse{main, use}}
	acceptSourceOriginFixture(t, home, request)
	nodes.Body = "proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 2}]\n"
	request.Uses = []SourceUse{main, acceptSourceOriginFixture(t, home, nodes)}
	result, err := sourceAcceptance(home, request)
	if err != nil || result.Status != "accepted" {
		t.Fatal("same source purpose could not maintain nodes", result, err)
	}
	request.Uses = []SourceUse{main}
	result, err = sourceAcceptance(home, request)
	if err != nil || result.Status != "reviewRequired" || !slices.Contains(result.Reasons, "source_bindings_changed") {
		t.Fatal("identical YAML silently dropped a physical source binding", result, err)
	}
	nodes.Key, nodes.Identity = "profile:3", inputHash([]byte("different physical source"))
	request.Uses = []SourceUse{main, acceptSourceOriginFixture(t, home, nodes)}
	result, err = sourceAcceptance(home, request)
	if err != nil || result.Status != "reviewRequired" || !slices.Contains(result.Reasons, "source_bindings_changed") {
		t.Fatal("identical YAML silently substituted a physical source", result, err)
	}
}

func TestSourceClashProviderCacheCannotLoseItsPhysicalBinding(t *testing.T) {
	home := t.TempDir()
	hash := md5.Sum([]byte("42@https://example.test/nodes"))
	mapping := map[string]any{"type": "http", "url": "https://example.test/nodes", "path": filepath.Join(home, "providers", "proxies", hex.EncodeToString(hash[:]))}
	use := SourceUse{Key: "clash-provider:42", Kind: "provider-proxy"}
	if key, err := sourceProviderOriginKey(home, use.Kind, mapping, []SourceUse{use}); err != nil || key != use.Key {
		t.Fatal(key, err)
	}
	if _, err := sourceProviderOriginKey(home, use.Kind, mapping, nil); err == nil {
		t.Fatal("app-owned cache without physical source accepted")
	}
	mapping["url"] = "https://example.test/changed"
	if _, err := sourceProviderOriginKey(home, use.Kind, mapping, []SourceUse{use}); err == nil {
		t.Fatal("cache from a different physical URL accepted")
	}
}
