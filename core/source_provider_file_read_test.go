package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func TestSourceFileProviderReadsCandidateWhileFailedWithoutNetworkSession(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	body := []byte("proxies: [{name: local, type: socks5, server: 127.0.0.1, port: 1}]\n")
	path := filepath.Join(home, "local-nodes.yaml")
	if err := os.WriteFile(path, body, 0600); err != nil {
		t.Fatal(err)
	}
	yaml := configTestYAML(configTestPort(t)) + "proxy-providers:\n  local:\n    type: file\n    path: " + path + "\n"
	id := sourceRuntimeInput(t, yaml, map[string][]byte{"provider-proxy:local": body})
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
	plan := plans[0]
	r := appRequests
	r.mu.Lock()
	r.client, r.clientReady = "file-reader", true
	r.state.Phase, r.state.Reason, r.state.IntentRunning = "failed", "setupFailed", false
	r.mu.Unlock()
	request := sourceAcceptanceRequest{Action: "fetchProvider", Key: plan.Key, Kind: plan.Kind, ProviderName: plan.Name, Use: &root, MaterialHash: inputHash([]byte(yaml)), Source: ConfigSourceTicket{Client: r.client, Dataset: r.dataset, Sources: map[string]uint64{plan.Key: r.sources[plan.Key]}}}
	permissions, err := os.ReadFile(sourcePermissionsPath(home))
	if err != nil {
		t.Fatal(err)
	}
	got, err := fetchSourceProviderMaterial(home, request)
	if err != nil || string(got) != string(body) || len(r.leases) != 0 || len(r.dataReaders) != 0 {
		t.Fatal("failed native state must permit this controlled candidate read without network authority", string(got), err, len(r.leases), len(r.dataReaders))
	}
	raw, _ := json.Marshal(request)
	var response struct {
		Result sourceAcceptanceResult
		Error  *MethodError
	}
	if err := json.Unmarshal(businessRPC(t, sourceAcceptanceMethod, string(raw)), &response); err != nil || response.Error != nil || response.Result.Status != "downloaded" || response.Result.Use != nil || response.Result.BodyBase64 != base64.StdEncoding.EncodeToString(body) {
		t.Fatal(response, err)
	}
	if now, _ := os.ReadFile(sourcePermissionsPath(home)); string(now) != string(permissions) {
		t.Fatal("reading a candidate changed canonical permissions")
	}
	for _, mutation := range []string{"client", "dataset", "source", "root"} {
		changed := request
		changed.Source.Sources = map[string]uint64{plan.Key: request.Source.Sources[plan.Key]}
		switch mutation {
		case "client":
			changed.Source.Client = "foreign"
		case "dataset":
			changed.Source.Dataset++
		case "source":
			changed.Source.Sources[plan.Key]++
		case "root":
			use := root
			use.Digest = inputHash(nil)
			changed.Use = &use
		}
		if _, err := fetchSourceProviderMaterial(home, changed); err == nil || len(r.dataReaders) != 0 {
			t.Fatal("invalid authority or leaked read ID", mutation, err, r.dataReaders)
		}
	}
	for _, markerDirectory := range []bool{false, true} {
		marker := requestRecoveryPath(home)
		if markerDirectory {
			err = os.Mkdir(marker, 0700)
		} else {
			err = os.WriteFile(marker, []byte("recovery required"), 0600)
		}
		if err != nil {
			t.Fatal(err)
		}
		_, err = fetchSourceProviderMaterial(home, request)
		_ = os.Remove(marker)
		if err == nil || len(r.dataReaders) != 0 {
			t.Fatal("marker or marker I/O error did not reject and release reader", markerDirectory, err)
		}
	}
	previous := requestscope.BeginHook
	for _, hook := range []func(context.Context, requestscope.Spec) (requestscope.Lease, error){nil, func(context.Context, requestscope.Spec) (requestscope.Lease, error) { return nil, nil }} {
		requestscope.BeginHook = hook
		_, err := fetchSourceProviderMaterial(home, request)
		requestscope.BeginHook = previous
		if err == nil {
			t.Fatal("nil or noop hook qualified a source file read")
		}
	}
	unknownRequestWriters.Add(1)
	_, err = fetchSourceProviderMaterial(home, request)
	unknownRequestWriters.Add(-1)
	if err == nil || len(r.dataReaders) != 0 {
		t.Fatal("unknown writer qualified a file read", err)
	}
	controlCall := func(params appRequestControl) map[string]any {
		t.Helper()
		data, _ := json.Marshal(r.control(params))
		var result map[string]any
		if err := json.Unmarshal(data, &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	control := controlCall(appRequestControl{Action: "lock", Client: r.client})
	commit, _ := control["id"].(string)
	if commit == "" {
		t.Fatal(control)
	}
	done := make(chan error, 1)
	go func() { _, err := fetchSourceProviderMaterial(home, request); done <- err }()
	select {
	case err := <-done:
		t.Fatal("read bypassed in-flight frontend commit", err)
	case <-time.After(50 * time.Millisecond):
	}
	r.control(appRequestControl{Action: "complete", Client: r.client, ID: commit})
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("read did not resume after actual receipt completion")
	}
	if len(r.dataReaders) != 0 {
		t.Fatal("completed read retained its guard")
	}
	control = controlCall(appRequestControl{Action: "lock", Client: r.client})
	if control["id"] == nil {
		t.Fatal("read completion prevented the next real write receipt", control)
	}
	r.control(appRequestControl{Action: "complete", Client: r.client, ID: control["id"].(string)})
	permissionsStore, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	dependencies := permissionsStore.Grants[root.Key].Purposes[root.Kind].BoundUses[root.Digest]
	dependencies = slices.DeleteFunc(slices.Clone(dependencies), func(use SourceUse) bool { return strings.HasPrefix(use.Kind, "provider-") })
	physical := filepath.Join(home, "profiles", "2.yaml")
	if err := os.MkdirAll(filepath.Dir(physical), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(physical, body, 0600); err != nil {
		t.Fatal(err)
	}
	origin := acceptSourceOriginFixture(t, home, sourceAcceptanceRequest{Action: "review", Key: "profile:2", Kind: "provider-proxy", Identity: inputHash([]byte("physical nodes")), Settings: inputHash(nil), Body: string(body)})
	physicalYAML := strings.Replace(yaml, path, physical, 1)
	physicalRoot := acceptSourceOriginFixture(t, home, sourceAcceptanceRequest{Action: "review", Key: root.Key, Kind: root.Kind, Identity: permissionsStore.Grants[root.Key].Identity, Settings: inputHash(nil), Body: physicalYAML, Uses: append(dependencies, origin)})
	physicalPlans, err := acceptedSourceProviderPlans(home, physicalRoot, inputHash([]byte(physicalYAML)))
	if err != nil || len(physicalPlans) != 1 {
		t.Fatal(physicalPlans, err)
	}
	physicalRequest := request
	physicalRequest.Use, physicalRequest.MaterialHash = &physicalRoot, inputHash([]byte(physicalYAML))
	physicalRequest.Key = physicalPlans[0].Key
	physicalRequest.Source.Sources = map[string]uint64{physicalRequest.Key: r.sources[physicalRequest.Key]}
	if got, err := fetchSourceProviderMaterial(home, physicalRequest); err != nil || string(got) != string(body) {
		t.Fatal("physical source candidate", string(got), err)
	}
	permissionsStore, _ = readSourcePermissions(home)
	grant := permissionsStore.Grants[origin.Key]
	if err := withdrawSourcePermission(home, origin.Key, grant.Incarnation, grant.Revision, true, origin.Kind); err != nil {
		t.Fatal(err)
	}
	if _, err := fetchSourceProviderMaterial(home, physicalRequest); err == nil {
		t.Fatal("withdrawn physical source admitted local candidate")
	}

	httpYAML := strings.Replace(yaml, "type: file\n    path: "+path, "type: http\n    url: http://127.0.0.1:1/no-session", 1)
	httpRoot := acceptSourceOriginFixture(t, home, sourceAcceptanceRequest{Action: "review", Key: root.Key, Kind: root.Kind, Identity: permissionsStore.Grants[root.Key].Identity, Settings: inputHash(nil), Body: httpYAML, Uses: dependencies})
	httpPlans, err := acceptedSourceProviderPlans(home, httpRoot, inputHash([]byte(httpYAML)))
	if err != nil || len(httpPlans) != 1 {
		t.Fatal(httpPlans, err)
	}
	httpRequest := request
	httpRequest.Key, httpRequest.Use, httpRequest.MaterialHash = httpPlans[0].Key, &httpRoot, inputHash([]byte(httpYAML))
	httpRequest.Source.Sources = map[string]uint64{httpRequest.Key: r.sources[httpRequest.Key]}
	if _, err := fetchSourceProviderMaterial(home, httpRequest); err == nil {
		t.Fatal("HTTP provider bypassed real network session")
	}

}
