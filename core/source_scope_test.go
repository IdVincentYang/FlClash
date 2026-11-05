package main

import (
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestSourceWithdrawalPreservesAutomaticStopButRevokesUse(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	configTestHome(t)
	defer settleMessageBatcher()
	home := C.Path.HomeDir()
	input := writeTestInput(t, configTestYAML(configTestPort(t)))
	applyTestInput(t, input)
	p := appliedConfig
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	grant := permissions.Grants["script:9"]
	request := sourceAcceptanceRequest{Action: "withdraw", Key: "script:9", Kind: "script", Incarnation: grant.Incarnation, Revision: grant.Revision}
	if _, err := sourceAcceptance(home, request); err != nil {
		t.Fatal(err)
	}
	configMu.Lock()
	err = reconcileSourceScopesLocked(home)
	configMu.Unlock()
	if err != nil || p.scope.Check() != nil || !p.eligible {
		t.Fatalf("stopping future maintenance revoked accepted use: %v", err)
	}
	request.StopUse = true
	request.Revision++
	if _, err := sourceAcceptance(home, request); err != nil {
		t.Fatal(err)
	}
	configMu.Lock()
	err = reconcileSourceScopesLocked(home)
	configMu.Unlock()
	if err != nil || p.scope.Check() == nil || p.eligible || configFact.BusinessActive || configFact.ReplayEligible {
		t.Fatalf("revocation retained business/replay use: %v %+v", err, configFact)
	}
	if _, err := replayConfigInput(&InitParams{HomeDir: home}); err == nil {
		t.Fatal("revoked checkpoint remained replayable")
	}
	if _, err := sourceAcceptance(home, request); err == nil {
		t.Fatal("late withdrawal reused an obsolete revision")
	}
}
