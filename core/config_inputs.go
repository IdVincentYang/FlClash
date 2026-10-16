package main

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
)

var inputCollectionQueued atomic.Bool

type inputCandidateMarker struct {
	YAMLSHA256   string `json:"yamlSha256"`
	RuntimeEpoch string `json:"runtimeEpoch"`
	Client       string `json:"client,omitempty"`
}

func candidateInputID(name string) (string, bool) {
	parts := strings.Split(name, ".")
	if len(parts) != 3 || !validInputID(parts[0]) || len(parts[1]) != 24 || parts[2] != "candidate" {
		return "", false
	}
	if _, err := hex.DecodeString(parts[1]); err != nil {
		return "", false
	}
	return parts[0], true
}

func queueInputCollection() {
	if !inputCollectionQueued.CompareAndSwap(false, true) {
		return
	}
	home := C.Path.HomeDir()
	safeGoDetached("collect configuration inputs", func() {
		defer inputCollectionQueued.Store(false)
		_ = collectConfigInputsAt(home, "")
	})
}

func collectConfigInputs(releasedMarker string) error {
	return collectConfigInputsAt("", releasedMarker)
}

func collectConfigInputsAt(expectedHome, releasedMarker string) error {
	readID, err := lockConfigInputRead()
	if err != nil {
		return err
	}
	defer configMu.Unlock()
	defer appRequests.endDataRead(readID)
	if expectedHome != "" && expectedHome != C.Path.HomeDir() {
		return nil
	}
	root := inputDirectory(C.Path.HomeDir())
	if releasedMarker != "" {
		if _, ok := candidateInputID(releasedMarker); !ok {
			return errors.New("invalid configuration candidate identifier")
		}
		if err := os.Remove(filepath.Join(root, releasedMarker)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	keep := make(map[string]bool)
	activeNonces := make(map[string]bool)
	checkpointMu.Lock()
	if ref, err := readCheckpointLocked(C.Path.HomeDir()); err == nil {
		keep[ref.InputID+".json"] = true
	}
	if p := pendingConfig; p != nil && configFact.Phase != "failed" {
		keep[p.receipt.InputID+".json"] = true
		keep[p.manifest.YAMLSHA256+".yaml"] = true
	}
	if p := appliedConfig; p != nil {
		keep[p.receipt.InputID+".json"] = true
		keep[p.manifest.YAMLSHA256+".yaml"] = true
	}
	if appliedConfig != nil && validInputID(configFact.InputID) {
		keep[configFact.InputID+".json"] = true
	}
	if op := latestConfig.Load(); op != nil && op.reading.Load() {
		keep[op.request.InputID+".json"] = true
	}
	appRequests.mu.Lock()
	client, clientReady := appRequests.client, appRequests.clientReady
	appRequests.mu.Unlock()
	checkpointMu.Unlock()
	entries, err := os.ReadDir(root)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		id, ok := candidateInputID(entry.Name())
		if !ok {
			continue
		}
		var marker inputCandidateMarker
		bytes, err := os.ReadFile(filepath.Join(root, entry.Name()))
		if err != nil {
			return err
		}
		if json.Unmarshal(bytes, &marker) != nil || marker.RuntimeEpoch != configRuntimeEpoch || features.Android && (marker.Client != client || !clientReady) {
			if err := os.Remove(filepath.Join(root, entry.Name())); err != nil {
				return err
			}
			continue
		}
		keep[id+".json"] = true
		activeNonces[strings.Split(entry.Name(), ".")[1]] = true
		if validInputID(marker.YAMLSHA256) {
			keep[marker.YAMLSHA256+".yaml"] = true
		}
	}
	for name := range keep {
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		bytes, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			continue
		}
		var manifest ConfigManifest
		if json.Unmarshal(bytes, &manifest) == nil && validInputID(manifest.YAMLSHA256) {
			keep[manifest.YAMLSHA256+".yaml"] = true
		}
	}
	for _, entry := range entries {
		name := entry.Name()
		parts := strings.Split(name, ".")
		pending := len(parts) == 5 && parts[0] == "" && validInputID(parts[1]) && (parts[2] == "yaml" || parts[2] == "json") && len(parts[3]) == 24 && parts[4] == "pending" && !activeNonces[parts[3]]
		if strings.HasPrefix(name, ".input-") || pending {
			if err := os.Remove(filepath.Join(root, name)); err != nil {
				return err
			}
			continue
		}
		ext := filepath.Ext(name)
		if (ext != ".json" && ext != ".yaml") || !validInputID(strings.TrimSuffix(name, ext)) || keep[name] {
			continue
		}
		if err := os.Remove(filepath.Join(root, name)); err != nil {
			return err
		}
	}
	return nil
}

func init() {
	registerMethod(releaseConfigInputMethod, withArguments(func(marker *string, response MethodResponse) {
		if err := collectConfigInputs(*marker); err != nil {
			response.failure("config_input_release_failed", err.Error(), nil)
			return
		}
		response.success(true)
	}))
}
