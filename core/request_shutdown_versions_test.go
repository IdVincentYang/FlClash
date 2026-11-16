//go:build no_zerotier

package main

import (
	"fmt"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func TestRequestGuardedShutdownReleasesConfigurationVersions(t *testing.T) {
	if !stageTestEnvironment(t) {
		return
	}
	r := appRequests
	home := C.Path.HomeDir()
	for cycle := 0; cycle < 4; cycle++ {
		input := writeTestInput(t, configTestYAML(0), fmt.Sprintf("script:%d", 900+cycle))
		applyTestInput(t, input)
		configMu.Lock()
		p := appliedConfig
		same := pendingConfig == p
		configMu.Unlock()
		if p == nil || p.sourcePins == nil || !same {
			t.Fatal("real apply did not acquire the shared pending/applied source holder")
		}
		if !handleShutdown() {
			t.Fatal("real guarded shutdown failed")
		}
		configMu.Lock()
		cleared := pendingConfig == nil && appliedConfig == nil && p.sourcePins == nil
		configMu.Unlock()
		r.mu.Lock()
		pins := 0
		for _, entry := range r.sourceVersions.entries {
			pins += entry.pins
		}
		idle := len(r.leases) == 0 && len(r.commits) == 0 && len(r.completionHolds) == 0
		cold := r.sourceVersions.cold.Len()
		entries := len(r.sourceVersions.entries)
		r.sourceVersions.clearCold()
		r.operationVersions.clearCold()
		empty := len(r.sources) == 0 && len(r.operations) == 0
		r.mu.Unlock()
		if !cleared || !idle || pins != 0 || cold != entries || !empty {
			t.Errorf("shutdown cycle=%d cleared=%v idle=%v pins=%d cold=%d entries=%d empty=%v", cycle, cleared, idle, pins, cold, entries, empty)
		}
		deadline := time.Now().Add(5 * time.Second)
		for inputCollectionQueued.Load() {
			if time.Now().After(deadline) {
				t.Fatal("input collector did not finish before controlled reinitialization")
			}
			time.Sleep(time.Millisecond)
		}
		if !handleInitClash(&InitParams{HomeDir: home}) {
			t.Fatal("real fresh Init failed after physical shutdown")
		}
		if appRequests != r {
			t.Fatal("test reset registry instead of verifying its retained lifecycle")
		}
	}
	if !handleShutdown() {
		t.Fatal("final controlled shutdown failed")
	}
}
