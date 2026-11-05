package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"

	"github.com/metacubex/mihomo/component/requestscope"
)

type sourceMaterialPending struct {
	Version      int                `json:"version"`
	Transaction  string             `json:"transaction"`
	Cleared      bool               `json:"cleared,omitempty"`
	RuntimeEpoch string             `json:"runtimeEpoch,omitempty"`
	Owner        requestscope.Owner `json:"owner"`
	Token        uint64             `json:"token,omitempty"`
	ParentInput  string             `json:"parentInput,omitempty"`
	TargetInput  string             `json:"targetInput,omitempty"`
	ProviderKey  string             `json:"providerKey,omitempty"`
	MaterialHash string             `json:"materialHash,omitempty"`
}

var writeSourcePending = atomicConfigFile

func sourceMaterialPendingPath(home string) string {
	return filepath.Join(home, "source-acceptance", "pending-material.json")
}

func readSourceMaterialPending(home string) (*sourceMaterialPending, error) {
	f, err := os.Open(sourceMaterialPendingPath(home))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, errSourceStore
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 4097))
	if err != nil || len(data) > 4096 {
		return nil, errSourceStore
	}
	var pending sourceMaterialPending
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&pending) != nil || decoder.Decode(new(any)) != io.EOF || pending.Version != 1 || len(pending.Transaction) != 48 {
		return nil, errSourceStore
	}
	if !pending.Cleared && (pending.RuntimeEpoch == "" || pending.Owner.ID == 0 || pending.Token == 0 || !validInputID(pending.ParentInput) || !validInputID(pending.TargetInput) || !validInputID(pending.MaterialHash) || !validSourceKey(pending.ProviderKey)) {
		return nil, errSourceStore
	}
	return &pending, nil
}

func pendingSourceMaterialBlocksReplay(home string) error {
	pending, err := readSourceMaterialPending(home)
	if err != nil {
		return err
	}
	if pending != nil && !pending.Cleared {
		return errSourceReview
	}
	return nil
}

func beginSourceMaterialPending(home string, pending sourceMaterialPending) error {
	existing, err := readSourceMaterialPending(home)
	if err != nil {
		return err
	}
	if existing != nil && !existing.Cleared {
		return errSourceReview
	}
	if pending.Cleared {
		return errSourceReview
	}
	data, err := json.Marshal(pending)
	if err != nil {
		return err
	}
	if err := writeSourcePending(sourceMaterialPendingPath(home), data); err != nil {
		return err
	}
	stored, err := readSourceMaterialPending(home)
	if err != nil || stored == nil || *stored != pending {
		return errSourceStore
	}
	return nil
}

func clearSourceMaterialPending(home string, expected sourceMaterialPending) error {
	pending, err := readSourceMaterialPending(home)
	if err != nil {
		return err
	}
	if pending == nil || pending.Transaction != expected.Transaction || pending.Cleared {
		return errSourceSuperseded
	}
	if *pending != expected {
		return errSourceSuperseded
	}
	data, err := json.Marshal(sourceMaterialPending{Version: 1, Transaction: expected.Transaction, Cleared: true})
	if err != nil {
		return err
	}
	return writeSourcePending(sourceMaterialPendingPath(home), data)
}
