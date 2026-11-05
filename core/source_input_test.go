package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestSourceInputBindsExactCompositionAndAncestors(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	configTestHome(t)
	body := []byte("mode: rule\nrules: ['MATCH,REJECT']\n")
	id := writeTestInput(t, string(body))
	data, err := os.ReadFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	if err := validateInputSourceUses(C.Path.HomeDir(), manifest, body); err != nil {
		t.Fatal(err)
	}
	t.Run("removed dependency", func(t *testing.T) {
		changed := manifest
		changed.Dependencies = nil
		changed.SourceUses = slices.Clone(manifest.SourceUses[1:])
		if err := validateInputSourceUses(C.Path.HomeDir(), changed, body); err == nil {
			t.Fatal("omitted source bypassed accepted composition")
		}
	})
	t.Run("changed output", func(t *testing.T) {
		if err := validateInputSourceUses(C.Path.HomeDir(), manifest, []byte("rules: ['MATCH,DIRECT']\n")); err == nil {
			t.Fatal("unaccepted final output was admitted")
		}
	})
	t.Run("duplicate root", func(t *testing.T) {
		changed := manifest
		changed.SourceUses = append(slices.Clone(manifest.SourceUses), manifest.SourceUses[len(manifest.SourceUses)-1])
		if err := validateInputSourceUses(C.Path.HomeDir(), changed, body); err == nil {
			t.Fatal("ambiguous root was admitted")
		}
	})
	permissions, err := readSourcePermissions(C.Path.HomeDir())
	if err != nil {
		t.Fatal(err)
	}
	script := permissions.Grants["script:9"]
	if err := withdrawSourcePermission(C.Path.HomeDir(), "script:9", script.Incarnation, script.Revision, true); err != nil {
		t.Fatal(err)
	}
	root := manifest.SourceUses[len(manifest.SourceUses)-1]
	if err := checkSourceUses(C.Path.HomeDir(), []SourceUse{root}); err == nil {
		t.Fatal("root remained usable after its script was revoked")
	}
	if err := validateInputSourceUses(C.Path.HomeDir(), manifest, body); err == nil {
		t.Fatal("revoked ancestor was admitted")
	}
}

func TestSourceOwnRoutingCannotBeRestoredByFinalAcceptance(t *testing.T) {
	for _, body := range []string{
		"rules: ['MATCH,PASS']\n",
		"rules: ['DOMAIN,local.invalid,REJECT']\n",
		"rules: ['MATCH,REJECT','MATCH,REJECT']\n",
		"rules: ['MATCH,REJECT']\nlisteners: [{name: bypass, port: 19080, proxy: DIRECT}]\n",
		"rules: ['MATCH,REJECT']\ntunnels: [{network: tcp, proxy: DIRECT}]\n",
		"rules: ['MATCH,REJECT']\nproxies: [{name: bypass, type: rematch}]\n",
		"rules: ['MATCH,REJECT']\nproxy-providers: {inline: {type: inline, payload: [{name: bypass, type: rematch}]}}\n",
		"rules: ['MATCH,group']\nproxy-groups: [{name: group, type: select, proxies: [PASS]}]\n",
		"rules: ['RULE-SET,@source-dns,DIRECT','MATCH,REJECT']\n",
	} {
		document, _, err := decodeSourceContent([]byte(body))
		if err != nil {
			t.Fatal(err)
		}
		if err := validateOwnRoutingInput(document, "profile:7"); err == nil {
			t.Fatalf("excluded routing entry was accepted: %s", body)
		}
	}
	document, _, err := decodeSourceContent([]byte("rules: ['DOMAIN,local.invalid,REJECT','MATCH,DIRECT']\n"))
	if err != nil {
		t.Fatal(err)
	}
	if err := validateOwnRoutingInput(document, "profile:7"); err != nil {
		t.Fatalf("explicit local routing rejected: %v", err)
	}
}

func TestSourceNodePurposeCannotBypassOwnRouting(t *testing.T) {
	home := t.TempDir()
	identity := inputHash([]byte("own-routing-source"))
	if _, err := acceptSourceRevision(home, "profile:7", identity, inputHash(nil), "own", "", false, 0, "profile"); err != nil {
		t.Fatal(err)
	}
	_, err := sourceAcceptance(home, sourceAcceptanceRequest{
		Action: "review", Key: "profile:7", Kind: "provider-proxy", Identity: identity,
		Settings: inputHash(nil), Body: "proxies: [{name: bypass, type: rematch}]\n",
	})
	if err == nil {
		t.Fatal("node-only generic approval could restore rematch")
	}
}

func TestSourceEqualYAMLPreservesBothAcceptedMaterialBindings(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	configTestHome(t)
	home := C.Path.HomeDir()
	body := []byte("rules: ['MATCH,REJECT']\n")
	id := writeTestInput(t, string(body))
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var old ConfigManifest
	if err := json.Unmarshal(data, &old); err != nil {
		t.Fatal(err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	script := permissions.Grants["script:9"]
	nextScript, err := acceptSourceRevision(home, "script:9", script.Identity, inputHash([]byte("new explicitly accepted code")), "source", "", false, script.Revision, "script")
	if err != nil {
		t.Fatal(err)
	}
	next := old
	next.SourceUses = slices.Clone(old.SourceUses)
	for i, use := range next.SourceUses {
		if use.Kind == "script" {
			next.SourceUses[i] = nextScript
		}
	}
	_, summary, err := decodeSourceContent(body)
	if err != nil {
		t.Fatal(err)
	}
	root := permissions.Grants["config:7"]
	dependencies := canonicalSourceUses(next.SourceUses[:len(next.SourceUses)-1])
	newRoot, err := acceptSourceRevisionUses(home, "config:7", root.Identity, sourceCompositionDigest(summary.Digest, dependencies), "source", "", false, root.Revision, "config", dependencies)
	if err != nil {
		t.Fatal(err)
	}
	if newRoot.Digest == old.SourceUses[len(old.SourceUses)-1].Digest {
		t.Fatal("different accepted material bindings reused the same use digest")
	}
	next.SourceUses[len(next.SourceUses)-1] = newRoot
	for _, manifest := range []ConfigManifest{old, next} {
		if err := validateInputSourceUses(home, manifest, body); err != nil {
			t.Fatal("accepting new material invalidated an existing qualified binding", err)
		}
	}
	slices.Reverse(next.SourceUses)
	if err := validateInputSourceUses(home, next, body); err != nil {
		t.Fatal("binding depended on receipt list order", err)
	}
}
