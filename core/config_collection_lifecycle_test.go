//go:build no_zerotier

package main

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

type collectionTestPause struct {
	entered chan struct{}
	release chan struct{}
	once    sync.Once
	panic   bool
}

var queuedCollectionTestPause atomic.Pointer[collectionTestPause]

func pauseQueuedCollectionForTest() {
	if pause := queuedCollectionTestPause.Swap(nil); pause != nil {
		close(pause.entered)
		<-pause.release
		if pause.panic {
			panic("collection test panic")
		}
	}
}

func holdQueuedCollection(t *testing.T) *collectionTestPause {
	t.Helper()
	pause := &collectionTestPause{entered: make(chan struct{}), release: make(chan struct{})}
	queuedCollectionTestPause.Store(pause)
	t.Cleanup(func() { pause.once.Do(func() { close(pause.release) }) })
	return pause
}

func awaitCollectionEvent(t *testing.T, event <-chan struct{}) {
	t.Helper()
	select {
	case <-event:
	case <-time.After(4 * time.Second):
		t.Fatal("collector event did not arrive")
	}
}

func collectionHome() string {
	configMu.Lock()
	defer configMu.Unlock()
	return C.Path.HomeDir()
}

func collectionInput(t *testing.T) (string, string) {
	t.Helper()
	configMu.Lock()
	home := C.Path.HomeDir()
	yaml := strings.ReplaceAll(configTestYAML(0), "MATCH,DIRECT", "MATCH,collection-pick") +
		"proxy-groups:\n  - {name: collection-pick, type: select, proxies: [DIRECT, REJECT]}\n"
	input := writeLegacyTestInput(t, yaml)
	orphan := filepath.Join(inputDirectory(home), inputHash([]byte("orphan "+input))+".yaml")
	if err := os.WriteFile(orphan, []byte("unused: true\n"), 0o600); err != nil {
		configMu.Unlock()
		t.Fatal(err)
	}
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	configMu.Unlock()
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" {
		t.Fatal(installed)
	}
	if result := activateConfig(installed.Receipt); result.Status != "activated" {
		t.Fatal(result)
	}
	return orphan, filepath.Join(inputDirectory(home), input+".json")
}

func requireCollectionFiles(t *testing.T, orphan, protected string, removed bool) {
	t.Helper()
	_, err := os.Stat(orphan)
	if removed && !os.IsNotExist(err) || !removed && err != nil {
		t.Fatalf("orphan removal=%v, stat=%v", removed, err)
	}
	if _, err := os.Stat(protected); err != nil {
		t.Fatal("live checkpoint input was removed", err)
	}
}

func newCollectionSentinel(t *testing.T, home string) string {
	t.Helper()
	root := inputDirectory(home)
	if err := os.MkdirAll(root, 0o700); err != nil {
		t.Fatal(err)
	}
	name := filepath.Join(root, inputHash([]byte("new lifetime "+t.Name()))+".yaml")
	if err := os.WriteFile(name, []byte("new: true\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return name
}

func TestInputCollectionRestartCycle(t *testing.T) {
	for _, mode := range []string{"same", "switch"} {
		t.Run(mode, func(t *testing.T) {
			if !stageTestEnvironment(t) {
				return
			}
			homes := []string{collectionHome(), t.TempDir()}
			for cycle := 0; cycle < 8; cycle++ {
				orphan, protected := collectionInput(t)
				if !handleShutdown() {
					t.Fatal("shutdown did not finish")
				}
				if inputCollectionQueued.Load() {
					t.Fatal("shutdown returned before collector queue cleanup")
				}
				requireCollectionFiles(t, orphan, protected, true)
				next := homes[0]
				if mode == "switch" {
					next = homes[(cycle+1)%2]
				}
				sentinel := newCollectionSentinel(t, next)
				if !handleInitClash(&InitParams{HomeDir: next}) {
					t.Fatal("init after finished shutdown failed")
				}
				if _, err := os.Stat(sentinel); err != nil {
					t.Fatal("late old collection touched new lifetime", err)
				}
			}
			if !handleShutdown() {
				t.Fatal("final shutdown")
			}
		})
	}
}

func TestInputCollectionLateShutdown(t *testing.T) {
	for _, source := range []string{"activation", "checkpoint", "selection"} {
		for _, mode := range []string{"same", "switch"} {
			t.Run(source+"/"+mode, func(t *testing.T) {
				if os.Getenv("FLCLASH_COLLECTION_GATE_OVERLAY") != "1" {
					t.Skip("requires the bound test-only collector gate overlay")
				}
				if !stageTestEnvironment(t) {
					return
				}
				providerStageTimeout = 500 * time.Millisecond
				home, next := collectionHome(), collectionHome()
				if mode == "switch" {
					next = t.TempDir()
				}
				var pause *collectionTestPause
				var orphan, protected string
				if source == "activation" {
					pause = holdQueuedCollection(t)
					orphan, protected = collectionInput(t)
				} else {
					_, protected = collectionInput(t)
					for deadline := time.Now().Add(4 * time.Second); inputCollectionQueued.Load(); {
						if time.Now().After(deadline) {
							t.Fatal("initial setup collector did not finish")
						}
						time.Sleep(time.Millisecond)
					}
					pause = holdQueuedCollection(t)
					orphan = newCollectionSentinel(t, home)
					if source == "checkpoint" {
						if err := updateConfig(&UpdateParams{}); err != nil {
							t.Fatal(err)
						}
					} else if result := handleChangeProxy(&ChangeProxyParams{GroupName: "collection-pick", ProxyName: "REJECT"}); result.Message != "" || !result.Changed {
						t.Fatal("selection checkpoint", result)
					}
				}
				awaitCollectionEvent(t, pause.entered)
				var newSentinel string
				if mode == "switch" {
					newSentinel = newCollectionSentinel(t, next)
				}
				configMu.Lock()
				candidate, err := prepareCheckpointCandidate(nil, nil)
				configMu.Unlock()
				if err != nil || candidate == nil {
					t.Fatal("checkpoint candidate", candidate, err)
				}
				if handleShutdown() {
					t.Fatal("shutdown succeeded while owned collector was paused")
				}
				if !isInit.Load() || collectionHome() != home || !inputCollectionQueued.Load() {
					t.Fatal("timeout discarded the old lifecycle or queue")
				}
				if handleInitClash(&InitParams{HomeDir: next}) {
					t.Fatal("unfinished shutdown admitted init")
				}
				configMu.Lock()
				late, err := prepareCheckpointCandidate(nil, nil)
				if err == nil {
					err = publishCheckpointCandidate(candidate)
				}
				configMu.Unlock()
				if err != nil || late != nil || candidate.published {
					t.Fatal("shutdown admitted new or old checkpoint", late, candidate.published, err)
				}
				stagedCore.Lock()
				work := stagedCore.shutdown
				stagedCore.Unlock()
				repeated := make(chan bool, 1)
				sequence := methodCallSeq.Add(1)
				noteCoreLifecycleArrival(&MethodCall{Method: shutdownMethod, seq: sequence})
				go func() { repeated <- shutdownGuardedCore(sequence) }()
				pause.once.Do(func() { close(pause.release) })
				if !<-repeated {
					t.Fatal("repeated shutdown did not finish after release")
				}
				stagedCore.Lock()
				sameWork := stagedCore.shutdown == work
				stagedCore.Unlock()
				if !sameWork || isInit.Load() || inputCollectionQueued.Load() {
					t.Fatal("shutdown replaced its owner or left collection unfinished")
				}
				requireCollectionFiles(t, orphan, protected, true)
				if newSentinel != "" {
					if _, err := os.Stat(newSentinel); err != nil {
						t.Fatal("old task touched new directory", err)
					}
				}
				if !handleInitClash(&InitParams{HomeDir: next}) {
					t.Fatal("new init was not admitted after completion")
				}
				collectionInput(t)
				if !handleShutdown() || inputCollectionQueued.Load() {
					t.Fatal("new lifecycle could not queue and finish its collector")
				}
			})
		}
	}
}

func TestInputCollectionFailureCompletion(t *testing.T) {
	for _, failure := range []string{"qualification", "io", "panic"} {
		t.Run(failure, func(t *testing.T) {
			if os.Getenv("FLCLASH_COLLECTION_GATE_OVERLAY") != "1" {
				t.Skip("requires the bound test-only collector gate overlay")
			}
			if !stageTestEnvironment(t) {
				return
			}
			pause := holdQueuedCollection(t)
			orphan, protected := collectionInput(t)
			awaitCollectionEvent(t, pause.entered)
			switch failure {
			case "qualification":
				requestNativeFault.Store(true)
			case "io":
				name := strings.Repeat("b", 64) + "." + strings.Repeat("c", 24) + ".candidate"
				if err := os.Mkdir(filepath.Join(inputDirectory(collectionHome()), name), 0o700); err != nil {
					t.Fatal(err)
				}
			case "panic":
				pause.panic = true
			}
			pause.once.Do(func() { close(pause.release) })
			if !handleShutdown() || isInit.Load() || inputCollectionQueued.Load() {
				t.Fatal("failed collector did not release completion")
			}
			requireCollectionFiles(t, orphan, protected, false)
		})
	}
}
