package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
)

func sourcePendingFixture(t *testing.T) sourceMaterialPending {
	t.Helper()
	transaction, err := randomRequestToken()
	if err != nil {
		t.Fatal(err)
	}
	return sourceMaterialPending{Version: 1, Transaction: transaction, RuntimeEpoch: "old-process", Owner: requestscope.Owner{ID: 7}, Token: 4,
		ParentInput: inputHash([]byte("parent")), TargetInput: inputHash([]byte("target")), MaterialHash: inputHash([]byte("material")), ProviderKey: "provider-rule:fixture"}
}

func TestSourceMaterialPendingSurvivesOwnerReplacementAndQualifiesClear(t *testing.T) {
	home := t.TempDir()
	checkpoint, _ := json.Marshal(configCheckpoint{Version: 1, InputID: inputHash([]byte("parent"))})
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), "checkpoint.json"), checkpoint); err != nil {
		t.Fatal(err)
	}
	pending := sourcePendingFixture(t)
	if err := beginSourceMaterialPending(home, pending); err != nil {
		t.Fatal(err)
	}
	if _, err := readCheckpointLocked(home); err == nil {
		t.Fatal("old checkpoint replayed across a pending hot adoption")
	}
	oldEpoch := configRuntimeEpoch
	configRuntimeEpoch = "new-process"
	t.Cleanup(func() { configRuntimeEpoch = oldEpoch })
	if _, err := readCheckpointLocked(home); err == nil {
		t.Fatal("new runtime owner ignored the persistent barrier")
	}
	wrong := pending
	wrong.Owner.ID++
	if !errors.Is(clearSourceMaterialPending(home, wrong), errSourceSuperseded) {
		t.Fatal("another owner cleared the pending transaction")
	}
	if err := clearSourceMaterialPending(home, pending); err != nil {
		t.Fatal(err)
	}
	if _, err := readCheckpointLocked(home); err != nil {
		t.Fatal("confirmed old material could not regain replay eligibility", err)
	}
	next := sourcePendingFixture(t)
	if err := beginSourceMaterialPending(home, next); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(clearSourceMaterialPending(home, pending), errSourceSuperseded) {
		t.Fatal("late cleanup cleared a new transaction")
	}
	if _, err := readCheckpointLocked(home); err == nil {
		t.Fatal("late cleanup enabled replay")
	}
}

func TestSourceMaterialPendingStorageFailureNeverEnablesReplay(t *testing.T) {
	home := t.TempDir()
	pending := sourcePendingFixture(t)
	old := writeSourcePending
	t.Cleanup(func() { writeSourcePending = old })
	writeSourcePending = func(string, []byte) error { return os.ErrPermission }
	if err := beginSourceMaterialPending(home, pending); err == nil {
		t.Fatal("failed barrier write authorized live mutation")
	}
	writeSourcePending = old
	if err := beginSourceMaterialPending(home, pending); err != nil {
		t.Fatal(err)
	}
	writeSourcePending = func(string, []byte) error { return os.ErrPermission }
	if err := clearSourceMaterialPending(home, pending); err == nil {
		t.Fatal("failed clear was reported as durable")
	}
	if pendingSourceMaterialBlocksReplay(home) == nil {
		t.Fatal("failed clear exposed the old checkpoint")
	}
	if err := os.WriteFile(sourceMaterialPendingPath(home), []byte("corrupt"), 0600); err != nil {
		t.Fatal(err)
	}
	if pendingSourceMaterialBlocksReplay(home) == nil {
		t.Fatal("corrupt barrier enabled replay")
	}
}
