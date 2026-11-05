package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestSourceProviderReuseBeforeStartNeedsAcceptedCheckpoint(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	body := []byte("proxies: [{name: old, type: socks5, server: 127.0.0.1, port: 1, udp: true}]\n")
	var downloads atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		downloads.Add(1)
		_, _ = w.Write(body)
	}))
	defer server.Close()
	yaml := configTestYAML(configTestPort(t)) + "proxy-providers:\n  accepted:\n    type: http\n    url: " + server.URL + "/must-not-download\n    interval: 0\n"
	id := sourceRuntimeInput(t, yaml, map[string][]byte{"provider-proxy:accepted": body})
	applyTestInput(t, id)
	var root SourceUse
	for _, use := range appliedConfig.manifest.SourceUses {
		if use.Kind == "config" {
			root = use
		}
	}
	plans, err := acceptedSourceProviderPlans(home, root, inputHash([]byte(yaml)))
	if err != nil || len(plans) != 1 {
		t.Fatal(plans, err)
	}
	plan := plans[0]
	appRequests.mu.Lock()
	appRequests.client, appRequests.clientReady = "reuse-client", true
	appRequests.state.Phase = "preparing"
	appRequests.mu.Unlock()
	request := sourceAcceptanceRequest{Action: "reuseProvider", Key: plan.Key, Kind: plan.Kind, ProviderName: plan.Name, Use: &root, MaterialHash: inputHash([]byte(yaml)), Source: ConfigSourceTicket{Client: "reuse-client", Dataset: appRequests.dataset, Sources: map[string]uint64{plan.Key: appRequests.sources[plan.Key]}}}
	invoke := func(request sourceAcceptanceRequest) (sourceAcceptanceResult, *MethodError) {
		t.Helper()
		data, _ := json.Marshal(request)
		var response struct {
			Result sourceAcceptanceResult
			Error  *MethodError
		}
		frames := captureFrames(t, func() {
			handleMethodCall(&MethodCall{ID: "reuse-source", Method: sourceAcceptanceMethod, Arguments: data}, newMethodResponse("reuse-source", nil))
		})
		responses := 0
		for _, frame := range frames {
			var envelope struct {
				ID string `json:"id"`
			}
			if err := json.Unmarshal(frame, &envelope); err != nil {
				t.Fatal(err)
			}
			if envelope.ID != "reuse-source" {
				continue
			}
			responses++
			if err := json.Unmarshal(frame, &response); err != nil {
				t.Fatal(err)
			}
		}
		if responses != 1 {
			t.Fatalf("source response count = %d, want 1", responses)
		}
		return response.Result, response.Error
	}
	result, rpcError := invoke(request)
	if rpcError != nil || result.Status != "reused" || result.BodyBase64 != base64.StdEncoding.EncodeToString(body) || len(result.MaterialLease) != 48 {
		t.Fatal("preparing must reuse accepted sealed bytes without opening the unreachable HTTP source", result, rpcError)
	}
	if len(appRequests.leases) != 0 {
		t.Fatal("offline reuse created a network lease")
	}
	if downloads.Load() != 0 {
		t.Fatal("offline reuse contacted the independent HTTP source")
	}
	invoke(sourceAcceptanceRequest{Action: "releaseMaterial", Source: request.Source, MaterialLease: result.MaterialLease})
	for _, change := range []string{"dataset", "source", "root", "provider"} {
		t.Run("wrong "+change, func(t *testing.T) {
			changed := request
			changed.Source.Sources = map[string]uint64{plan.Key: request.Source.Sources[plan.Key]}
			switch change {
			case "dataset":
				changed.Source.Dataset++
			case "source":
				changed.Source.Sources[plan.Key]++
			case "root":
				use := root
				use.Digest = inputHash(nil)
				changed.Use = &use
			case "provider":
				changed.ProviderName = "different"
			}
			if got, err := invoke(changed); err == nil || got.Status == "reused" || got.Status == "missing" {
				t.Fatal("invalid authority became reusable or a network fallback", got, err)
			}
		})
	}
	configMu.Lock()
	changedYAML := strings.Replace(yaml, "/must-not-download", "/different-declaration", 1)
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	changedRoot := acceptSourceOriginFixture(t, home, sourceAcceptanceRequest{Action: "review", Key: root.Key, Kind: root.Kind, Identity: permissions.Grants[root.Key].Identity, Settings: inputHash(nil), Body: changedYAML, Uses: slices.DeleteFunc(slices.Clone(appliedConfig.manifest.SourceUses), func(use SourceUse) bool { return use.Kind == "config" || strings.HasPrefix(use.Kind, "provider-") })})
	configMu.Unlock()
	changed := request
	changed.Use, changed.MaterialHash = &changedRoot, inputHash([]byte(changedYAML))
	if got, err := invoke(changed); err != nil || got.Status != "missing" {
		t.Fatal("changed declaration must not reuse the old material", got, err)
	}
	checkpoint := filepath.Join(inputDirectory(home), "checkpoint.json")
	checkpointBody, err := os.ReadFile(checkpoint)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name, path string
		body       []byte
	}{
		{"recovery barrier", requestRecoveryPath(home), []byte("blocked")},
		{"pending barrier", sourceMaterialPendingPath(home), []byte("invalid pending")},
		{"corrupt checkpoint", checkpoint, []byte("invalid checkpoint")},
		{"corrupt sealed material", sourceObjectPath(home, inputHash(body)), []byte("different")},
	} {
		t.Run(test.name, func(t *testing.T) {
			previous, readErr := os.ReadFile(test.path)
			if err := os.WriteFile(test.path, test.body, 0600); err != nil {
				t.Fatal(err)
			}
			defer func() {
				if os.IsNotExist(readErr) {
					_ = os.Remove(test.path)
				} else {
					_ = os.WriteFile(test.path, previous, 0600)
				}
			}()
			if got, err := invoke(request); err == nil || got.Status == "missing" || got.Status == "reused" {
				t.Fatal("invalid accepted state must be an error, never a download fallback", got, err)
			}
		})
	}
	for _, empty := range []string{invalidatedConfigCheckpoint, `{"version":1,"inputId":"","dependencies":[]}`, `{"version":1,"inputId":""}` + "\n"} {
		if err := os.WriteFile(checkpoint, []byte(empty), 0600); err != nil {
			t.Fatal(err)
		}
		got, err := invoke(request)
		if empty == invalidatedConfigCheckpoint {
			if err != nil || got.Status != "missing" {
				t.Fatal("producer invalidation must be a miss", got, err)
			}
		} else if err == nil || got.Status == "missing" {
			t.Fatal("arbitrary empty checkpoint must remain corrupt", got, err)
		}
	}
	if err := os.WriteFile(checkpoint, checkpointBody, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(checkpoint); err != nil {
		t.Fatal(err)
	}
	if got, err := invoke(request); err != nil || got.Status != "missing" {
		t.Fatal("absent checkpoint must be a visible miss", got, err)
	}
	if err := os.WriteFile(checkpoint, checkpointBody, 0600); err != nil {
		t.Fatal(err)
	}
	permissions, err = readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	grant := permissions.Grants[plan.Key]
	if err := withdrawSourcePermission(home, plan.Key, grant.Incarnation, grant.Revision, true, plan.Kind); err != nil {
		t.Fatal(err)
	}
	if got, err := invoke(request); err == nil || got.Status == "missing" || got.Status == "reused" {
		t.Fatal("revoked material must not become a download fallback", got, err)
	}
}
