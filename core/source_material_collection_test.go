package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func sourceMaterialExists(t *testing.T, hash string, want bool) {
	t.Helper()
	_, err := os.Stat(sourceObjectPath(C.Path.HomeDir(), hash))
	if want && err != nil || !want && !os.IsNotExist(err) {
		t.Fatal("unexpected material lifetime", hash, want, err)
	}
}

func collectSourceMaterialFixture(t *testing.T) {
	t.Helper()
	configMu.Lock()
	defer configMu.Unlock()
	if err := collectSourceMaterialsLocked(C.Path.HomeDir()); err != nil {
		t.Fatal(err)
	}
}

func TestSourceMaterialLeasePinsOnlyItsBodyUntilReleaseOrClientRetirement(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	appRequests.client, appRequests.clientReady = "material-client", true
	home := C.Path.HomeDir()
	seal := func(body string) string {
		hash, err := sealSourceObject(home, []byte(body), sourceCandidateMax)
		if err != nil {
			t.Fatal(err)
		}
		return hash
	}
	hash, orphan := seal("held body"), seal("unreferenced body")
	lease, err := pinSourceMaterial(home, hash, appRequests.client)
	if err != nil {
		t.Fatal(err)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, true)
	sourceMaterialExists(t, orphan, false)
	releaseSourceMaterialLease(lease, "different-client")
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, true)
	releaseSourceMaterialLease(lease, appRequests.client)
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, false)
	hash = seal("cancelled frontend body")
	lease, err = pinSourceMaterial(home, hash, appRequests.client)
	if err != nil {
		t.Fatal(err)
	}
	appRequests.client = "replacement-client"
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, false)
	if _, present := sourceMaterialLeases[lease]; present {
		t.Fatal("retired client retained an unconsumable material lease")
	}
}

func TestSourceMaterialRPCLeaseCanBeReleasedAfterItsSourceTicketExpires(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	appRequests.client, appRequests.clientReady = "material-client", true
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:8", Kind: "profile", Body: "mode: rule\n", Identity: inputHash([]byte("rpc source")), Settings: inputHash([]byte("settings")), Source: ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{"profile:8": 0}}}
	rpc := func(request sourceAcceptanceRequest) sourceAcceptanceResult {
		t.Helper()
		data, _ := json.Marshal(request)
		var response struct {
			Result sourceAcceptanceResult
			Error  *MethodError
		}
		if err := json.Unmarshal(businessRPC(t, sourceAcceptanceMethod, string(data)), &response); err != nil || response.Error != nil {
			t.Fatal(response, err)
		}
		return response.Result
	}
	result := rpc(request)
	if result.Status != "reviewRequired" {
		t.Fatal(result)
	}
	request.Action, request.Candidate, request.Routing = "accept", result.Candidate, "source"
	result = rpc(request)
	if result.Status != "accepted" || len(result.MaterialLease) != 48 {
		t.Fatal("real source RPC did not lease its accepted sealed body", result)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, result.MaterialHash, true)
	appRequests.mu.Lock()
	appRequests.sources["profile:8"]++
	appRequests.mu.Unlock()
	released := rpc(sourceAcceptanceRequest{Action: "releaseMaterial", MaterialLease: result.MaterialLease, Source: request.Source})
	if released.Status != "released" {
		t.Fatal(released)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, result.MaterialHash, false)
}

func TestSourceMaterialCollectionPinsMarkersAndCanonicalContracts(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	body := configTestYAML(0)
	id := writeTestInput(t, body)
	hash, err := sealSourceObject(home, []byte(body), sourceCandidateMax)
	if err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(inputDirectory(home), id+"."+strings.Repeat("a", 24)+".candidate")
	data, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: hash, RuntimeEpoch: configRuntimeEpoch})
	if err := atomicConfigFile(marker, data); err != nil {
		t.Fatal(err)
	}
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:8", Kind: "profile", Body: "mode: global\n", Identity: inputHash([]byte("contract fixture")), Settings: inputHash([]byte("settings"))}
	result, err := sourceAcceptance(home, request)
	if err != nil || result.Status != "reviewRequired" {
		t.Fatal(result, err)
	}
	request.Action, request.Candidate, request.Automatic, request.Routing = "accept", result.Candidate, true, "source"
	result, err = sourceAcceptance(home, request)
	if err != nil {
		t.Fatal(err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	contract := permissions.Grants["profile:8"].Purposes["profile"].Contract
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, true)
	sourceMaterialExists(t, contract, true)
	sourceMaterialExists(t, result.MaterialHash, false)
	if err := checkSourceUses(home, []SourceUse{*result.Use}); err != nil {
		t.Fatal("body collection changed canonical permission authority", err)
	}
	if err := os.Remove(marker); err != nil {
		t.Fatal(err)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, hash, false)
	sourceMaterialExists(t, contract, true)
}

func TestSourceMaterialCollectionPinsBothSidesOfDurablePending(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	home := C.Path.HomeDir()
	oldBody, nextBody := configTestYAML(0), configTestYAML(0)+"ipv6: true\n"
	old, next := writeTestInput(t, oldBody), writeTestInput(t, nextBody)
	oldHash, err := sealSourceObject(home, []byte(oldBody), sourceCandidateMax)
	if err != nil {
		t.Fatal(err)
	}
	nextHash, err := sealSourceObject(home, []byte(nextBody), sourceCandidateMax)
	if err != nil {
		t.Fatal(err)
	}
	transaction, err := randomRequestToken()
	if err != nil {
		t.Fatal(err)
	}
	pending := sourceMaterialPending{Version: 1, Transaction: transaction, RuntimeEpoch: "retired-process", Owner: requestscope.Owner{ID: 9}, Token: 1, ParentInput: old, TargetInput: next, ProviderKey: "provider:pending", MaterialHash: nextHash}
	if err := beginSourceMaterialPending(home, pending); err != nil {
		t.Fatal(err)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, oldHash, true)
	sourceMaterialExists(t, nextHash, true)
	if err := clearSourceMaterialPending(home, pending); err != nil {
		t.Fatal(err)
	}
	collectSourceMaterialFixture(t)
	sourceMaterialExists(t, oldHash, false)
	sourceMaterialExists(t, nextHash, false)
}

func TestSourceMaterialCollectionKeepsRetiredInlineInput(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	port := sourceInlineFixture(t)
	p := appliedConfig
	oldInput, oldHash := p.receipt.InputID, p.manifest.YAMLSHA256
	request := sourceInlineTestRequest(t, sourceInlineNextInput(t, sourceInlineYAML(port, 19002)))
	if result := adoptSourceInlineRequest(&request); result.Status != "applied" {
		t.Fatal(result)
	}
	entries, err := os.ReadDir(inputDirectory(C.Path.HomeDir()))
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if _, valid := candidateInputID(entry.Name()); valid {
			if err := os.Remove(filepath.Join(inputDirectory(C.Path.HomeDir()), entry.Name())); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := collectConfigInputs(""); err != nil {
		t.Fatal(err)
	}
	sourceMaterialExists(t, oldHash, true)
	sourceMaterialExists(t, p.manifest.YAMLSHA256, true)
	if _, err := os.Stat(filepath.Join(inputDirectory(C.Path.HomeDir()), oldInput+".json")); err != nil {
		t.Fatal("retired inline input was collected before its objects exited", err)
	}
}
