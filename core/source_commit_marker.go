package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"

	C "github.com/metacubex/mihomo/constant"
)

type requestCommitMarker struct {
	Version int    `json:"version"`
	Receipt string `json:"receipt"`
	Client  string `json:"client"`
}

var requestRecoveryMu sync.Mutex

func requestRecoveryPath(home string) string {
	return filepath.Join(home, "request-recovery-required")
}

func readRequestRecoveryMarker(home string) ([]byte, error) {
	data, err := os.ReadFile(requestRecoveryPath(home))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil || len(data) > sourceGrantFileLimit {
		return nil, errSourceStore
	}
	return data, nil
}

func ensureRequestRecoveryMarker(home string) error {
	requestRecoveryMu.Lock()
	defer requestRecoveryMu.Unlock()
	data, err := readRequestRecoveryMarker(home)
	if err != nil || data != nil {
		return err
	}
	return atomicConfigFile(requestRecoveryPath(home), []byte("recovery required\n"))
}

func beginRequestCommitMarker(r *appRequestRegistry, params appRequestControl) any {
	configMu.Lock()
	defer configMu.Unlock()
	if err := requestWriterError(); err != nil {
		return map[string]string{"error": err.Error()}
	}
	r.mu.Lock()
	receipt := r.commits[params.ID]
	valid := receipt != nil && !receipt.retired && receipt.client == params.Client && r.client == params.Client && r.clientReady
	r.mu.Unlock()
	if !valid {
		return map[string]string{"error": "request_cancelled"}
	}
	requestRecoveryMu.Lock()
	defer requestRecoveryMu.Unlock()
	home := C.Path.HomeDir()
	data, err := readRequestRecoveryMarker(home)
	if err != nil {
		return map[string]string{"error": "request_partial_commit"}
	}
	var existing requestCommitMarker
	if data != nil && (json.Unmarshal(data, &existing) != nil || existing.Version != 1 || existing.Receipt != receipt.id || existing.Client != receipt.client) {
		receipt.begun = true
		receipt.recoveryHash = inputHash(data)
		return map[string]any{"ok": true, "recovery": true}
	}
	if data == nil {
		data, _ = json.Marshal(requestCommitMarker{Version: 1, Receipt: receipt.id, Client: receipt.client})
		if err := atomicConfigFile(requestRecoveryPath(home), data); err != nil {
			receipt.failed = true
			return map[string]string{"error": "request_partial_commit"}
		}
	}
	receipt.begun = true
	receipt.markerHash = inputHash(data)
	return map[string]bool{"ok": true}
}

func markRequestCommitRecovery(r *appRequestRegistry, params appRequestControl) any {
	configMu.Lock()
	defer configMu.Unlock()
	r.mu.Lock()
	valid := r.client == params.Client && params.Client != ""
	receipt := r.commits[params.ID]
	if receipt != nil && receipt.client == params.Client {
		receipt.failed = true
	}
	r.mu.Unlock()
	if !valid || receipt != nil && receipt.retired {
		return map[string]string{"error": "request_cancelled"}
	}
	if err := ensureRequestRecoveryMarker(C.Path.HomeDir()); err != nil {
		return map[string]string{"error": "request_partial_commit"}
	}
	return map[string]bool{"ok": true}
}

func clearOwnedRequestMarker(home, hash string) error {
	requestRecoveryMu.Lock()
	defer requestRecoveryMu.Unlock()
	data, err := readRequestRecoveryMarker(home)
	if err != nil || data == nil {
		return err
	}
	if hash == "" || inputHash(data) != hash {
		return errSourceSuperseded
	}
	if err := os.Remove(requestRecoveryPath(home)); err != nil {
		return err
	}
	dir, err := os.Open(home)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func completeRequestCommit(r *appRequestRegistry, params appRequestControl) any {
	configMu.Lock()
	defer configMu.Unlock()
	r.mu.Lock()
	receipt := r.commits[params.ID]
	r.mu.Unlock()
	if receipt == nil || receipt.client != params.Client {
		return map[string]string{"error": "request_cancelled"}
	}
	if receipt.retired {
		_ = finishSourceMaterialCommit(receipt)
		receipt.Complete()
		return map[string]string{"error": "request_partial_commit"}
	}
	err := finishSourceMaterialCommit(receipt)
	if err != nil {
		receipt.failed = true
	}
	if !receipt.failed && receipt.markerHash != "" {
		if clearErr := clearOwnedRequestMarker(C.Path.HomeDir(), receipt.markerHash); clearErr != nil {
			err = clearErr
		}
	}
	receipt.Complete()
	if receipt.failed || err != nil {
		_ = ensureRequestRecoveryMarker(C.Path.HomeDir())
		return map[string]string{"error": "request_partial_commit"}
	}
	return map[string]bool{"ok": true}
}

func clearRestoredRequestRecovery(r *appRequestRegistry, params appRequestControl) any {
	configMu.Lock()
	defer configMu.Unlock()
	if err := requestWriterError(); err != nil {
		return map[string]string{"error": err.Error()}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	receipt := r.commits[params.ID]
	valid := receipt != nil && receipt.registry == r && receipt.begun && !receipt.retired && !receipt.failed &&
		receipt.client == params.Client && r.client == params.Client && r.clientReady && receipt.datasetInvalidated
	if !valid || receipt.recoveryHash == "" {
		return map[string]string{"error": "request_commit_recovery_required"}
	}
	if err := clearOwnedRequestMarker(C.Path.HomeDir(), receipt.recoveryHash); err != nil && !errors.Is(err, os.ErrNotExist) {
		return map[string]string{"error": "request_commit_recovery_required"}
	}
	receipt.recoveryHash = ""
	return map[string]bool{"ok": true}
}
