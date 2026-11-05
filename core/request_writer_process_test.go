package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func TestSourceUnknownWriterProcessExitRetainsRecoveryBarrier(t *testing.T) {
	phase := os.Getenv("FLCLASH_WRITER_PROCESS_PHASE")
	if phase == "" {
		home := t.TempDir()
		path, err := os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		for _, next := range []string{"writer", "recovery"} {
			cmd := exec.Command(path, "-test.run=^TestSourceUnknownWriterProcessExitRetainsRecoveryBarrier$", "-test.count=1")
			cmd.Env = append(os.Environ(), "FLCLASH_WRITER_PROCESS_PHASE="+next, "FLCLASH_WRITER_PROCESS_HOME="+home)
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%s: %v\n%s", next, err, output)
			}
			if next == "writer" {
				if marker, err := readRequestRecoveryMarker(home); err != nil || marker == nil {
					t.Fatal("process exit removed durable barrier", err)
				}
			}
		}
		if _, err := os.Stat(requestRecoveryPath(home)); !os.IsNotExist(err) {
			t.Fatal("explicit recovery did not clear barrier", err)
		}
		return
	}
	home := os.Getenv("FLCLASH_WRITER_PROCESS_HOME")
	if home == "" {
		t.Fatal("missing owned test home")
	}
	C.SetHomeDir(home)
	r := newAppRequestRegistry()
	appRequests = r
	r.client, r.clientReady = phase, true
	requestscope.BeginHook = r.begin
	if phase == "writer" {
		id := r.control(appRequestControl{Action: "lock", Client: r.client}).(map[string]string)["id"]
		if result := r.control(appRequestControl{Action: "beginCommit", ID: id, Client: r.client}); result.(map[string]bool)["ok"] != true {
			t.Fatal(result)
		}
		if err := os.MkdirAll(filepath.Join(home, "profiles"), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(home, "profiles", "10.yaml"), []byte("rules: [MATCH,DIRECT]\n"), 0600); err != nil {
			t.Fatal(err)
		}
		r.control(appRequestControl{Action: "engineDetach"})
		if unknownRequestWriters.Load() != 1 {
			t.Fatal("no actual unknown writer")
		}
		if _, err := r.beginDataRead(context.Background()); err == nil {
			t.Fatal("writer process resumed reads")
		}
		return
	}
	if unknownRequestWriters.Load() != 0 {
		t.Fatal("fresh OS process retained memory")
	}
	if _, err := beginRequestDataRead(); err == nil {
		t.Fatal("new process silently trusted retained save")
	}
	request := sourceAcceptanceRequest{Action: "inspectMaterialRecovery", Key: "application-config", Kind: "config", Source: ConfigSourceTicket{Client: r.client, Dataset: r.dataset, Sources: map[string]uint64{"application-config": 0}}, Recovery: &sourceRecoverySnapshot{Rows: []sourceRecoveryRow{{Key: "profile:10", Identity: inputHash([]byte("synthetic DB identity"))}}}}
	result, err := recoverSourceMaterialCommit(home, request)
	if err != nil || result.Recovery == nil || len(result.Recovery.Rows) != 1 || result.Recovery.Rows[0].FileHash == "" || result.Recovery.Rows[0].Permission != "" {
		t.Fatal("actual file was not checked independently of permission", result, err)
	}
	request.Action, request.Recovery = "recoverMaterialCommit", result.Recovery
	if result, err := recoverSourceMaterialCommit(home, request); err != nil || result.Status != "recovered" {
		t.Fatal(result, err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil || len(permissions.Grants) != 0 {
		t.Fatal("recovery promoted unapproved material", err)
	}
}
