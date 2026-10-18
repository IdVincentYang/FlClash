package main

import (
	"context"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type inspectionMatcherLease struct {
	*appRequestLease
	entered, release chan struct{}
	paused           atomic.Bool
}

func (l *inspectionMatcherLease) Check() error {
	var callers [32]uintptr
	frames := runtime.CallersFrames(callers[:runtime.Callers(1, callers[:])])
	for {
		frame, more := frames.Next()
		if strings.HasSuffix(frame.Function, "/tunnel.matchScoped") && l.paused.CompareAndSwap(false, true) {
			close(l.entered)
			<-l.release
			break
		}
		if !more {
			break
		}
	}
	return l.appRequestLease.Check()
}

func TestAppRequestInspectionCompletesWithMatcherAndQueuedInstall(t *testing.T) {
	if os.Getenv("FLCLASH_INSPECTION_LOCK_CHILD") != "1" {
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		defer cancel()
		executable, err := os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		command := exec.CommandContext(ctx, executable, "-test.run=^TestAppRequestInspectionCompletesWithMatcherAndQueuedInstall$", "-test.timeout=8s", "-test.v")
		command.Env = append(os.Environ(), "FLCLASH_INSPECTION_LOCK_CHILD=1")
		output, err := command.CombinedOutput()
		if command.Process != nil {
			t.Logf("inspection subprocess pid=%d\n%s", command.Process.Pid, output)
		}
		if err != nil {
			t.Fatal("real inspect/matcher/install did not complete", err)
		}
		return
	}
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	input := writeKeptTestInput(t, "mixed-port: 0\nmode: rule\nrules: [\"MATCH,REJECT\"]\n")
	first := applyTestInput(t, input)
	r := appRequests
	r.publish(AppRequestState{ProcessEpoch: "inspection-lock", Revision: 1, IntentRunning: true, Phase: "started", Reason: "userStart", DefaultNetworkKind: "nonVpn", DirectNetworkID: "loopback", ProtectPhase: "none"})
	r.mu.Lock()
	r.client, r.clientReady = "inspection-lock-client", true
	r.mu.Unlock()
	expectedHint := r.control(appRequestControl{Action: "inspect", Client: "inspection-lock-client"}).(map[string]any)["hasProxy"]
	lease, err := r.begin(context.Background(), requestscope.Spec{Kind: "maintenance", Trigger: "manual", Mode: "auto", Owner: requestscope.Owner{ID: first.Fact.Owner}, Key: "inspection-lock"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	barrier := &inspectionMatcherLease{appRequestLease: lease.(*appRequestLease), entered: make(chan struct{}), release: make(chan struct{})}
	inbound, peer := net.Pipe()
	defer peer.Close()
	matched := make(chan struct{})
	go func() {
		tunnel.Tunnel.HandleAppTCPConn(lease.Context(), inbound, &C.Metadata{NetWork: C.TCP, Type: C.INNER, Host: "inspection.example.test", DstIP: netip.MustParseAddr("127.0.0.1"), DstPort: 9}, barrier)
		close(matched)
	}()
	go func() { _, _ = peer.Write([]byte{1}) }()
	select {
	case <-barrier.entered:
	case <-time.After(3 * time.Second):
		t.Fatal("actual matcher did not hold its config read lock")
	}
	prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true}))
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	installed := make(chan ConfigApplyResult, 1)
	go func() { installed <- installConfig(prepared.Receipt) }()
	waitBlocked := func(function, lock string) {
		t.Helper()
		buf := make([]byte, 1<<20)
		for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
			for _, stack := range strings.Split(string(buf[:runtime.Stack(buf, true)]), "\n\n") {
				if strings.Contains(stack, function) && strings.Contains(stack, lock) {
					t.Log("observed real blocked boundary", function, lock)
					return
				}
			}
			time.Sleep(time.Millisecond)
		}
		t.Fatal("expected real blocked boundary was not reached", function, lock)
	}
	waitBlocked("/tunnel.UpdateProxies", "sync.(*RWMutex).Lock")
	inspected := make(chan any, 1)
	go func() { inspected <- r.control(appRequestControl{Action: "inspect", Client: "inspection-lock-client"}) }()
	waitBlocked("/tunnel.AllProxies", "sync.(*RWMutex).RLock")
	close(barrier.release)
	select {
	case <-matched:
	case <-time.After(2 * time.Second):
		t.Fatal("old matcher could not finish its actual lease.Check")
	}
	select {
	case result := <-installed:
		if result.Status != "installed" {
			t.Fatal(result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("queued actual install did not complete")
	}
	select {
	case result := <-inspected:
		if snapshot, ok := result.(map[string]any); !ok || snapshot["owner"] != prepared.Receipt.Owner || snapshot["hasProxy"] != expectedHint {
			t.Fatal("inspection returned a different owner or proxy hint", result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("inspection did not complete")
	}
}
