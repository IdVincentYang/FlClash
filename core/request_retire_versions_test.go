package main

import (
	"context"
	"fmt"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
)

func TestRequestStageRetirementReleasesOnlyItsOwnVersionHolders(t *testing.T) {
	r := revisionRegistry(t)
	client := keyTestClient(t, r)
	for cycle := 0; cycle < 4; cycle++ {
		owner := r.currentOwner()
		key := fmt.Sprintf("script:retire-%d", cycle)
		lease := completionTestLease(t, r, client, key)
		completionTestHold(t, r, lease)
		receipt, err := lease.GrantCommit()
		if err != nil {
			t.Fatal(err)
		}
		geoKey := fmt.Sprintf("geo:retire-%d", cycle)
		geo, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "geo", Key: geoKey, Proxy: "DIRECT"})
		if err != nil {
			t.Fatal(err)
		}
		p := &preparedConfig{receipt: ConfigReceipt{Owner: owner.ID}, scope: requestscope.NewBusinessScope(uint64(cycle+1), func() bool { return true })}
		stage := newProviderStage(p)
		stage.retire()
		<-stage.networkDone
		r.mu.Lock()
		pins := r.sourceVersions.entries[key].pins
		operationPins := r.operationVersions.entries[key].pins
		geoPins := r.operationVersions.entries["internal:geo:"+geoKey].pins
		retired := len(r.leases) == 0 && len(r.latest) == 0 && len(r.completionHolds) == 0
		r.mu.Unlock()
		if !retired || pins != 1 || operationPins != 1 || geoPins != 0 {
			t.Errorf("retirement kept lease/hold pins or dropped receipt: retired=%v source=%d operation=%d geo=%d", retired, pins, operationPins, geoPins)
		}
		receipt.Complete()
		r.mu.Lock()
		r.sourceVersions.clearCold()
		r.operationVersions.clearCold()
		retained := len(r.sources) + len(r.operations)
		r.mu.Unlock()
		if retained != 0 {
			t.Errorf("retired owner left %d non-evictable version entries", retained)
		}
		newOwner := r.newOwner()
		r.setPhase(newOwner, "ready")
		latest := completionTestLease(t, r, client, key)
		lease.Close()
		geo.Close()
		stage.retire()
		for _, closer := range cancelProviderOwner(r, owner.ID) {
			_ = closer.Close()
		}
		if latest.Check() != nil {
			t.Fatal("old owner or late Close revoked new work")
		}
		r.mu.Lock()
		validPins := r.sourceVersions.entries[key].pins == 1 && r.operationVersions.entries[key].pins == 1
		r.mu.Unlock()
		if !validPins {
			t.Fatal("late cleanup changed the new lease's ownership")
		}
		latest.Close()
	}
}
