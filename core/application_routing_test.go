package main

import (
	"context"
	"encoding/json"
	"net"
	"net/netip"
	"strconv"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
)

func applicationWire(profile int64, version uint64, entries ...applicationRouteEntry) *applicationRouteSettings {
	canonical := strconv.FormatInt(profile, 10) + "\n" + strconv.FormatUint(version, 10) + "\n"
	for _, entry := range entries {
		group := "-"
		if entry.GroupID != nil {
			group = strconv.FormatInt(*entry.GroupID, 10)
		}
		canonical += entry.Package + "\x00" + entry.Target + "\x00" + group + "\n"
	}
	return &applicationRouteSettings{ProfileID: &profile, Version: version, Revision: inputHash([]byte(canonical)), Rules: entries}
}

func TestApplicationWireAndIdentityBoundary(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	applyTestInput(t, sourceTraceInput(t, "mode: direct\nfind-process-mode: off\ngeo-auto-update: false\nrules: ['MATCH,DIRECT']\n", nil))
	wire := applicationWire(7, 2, applicationRouteEntry{Package: "a", Target: "DIRECT"}, applicationRouteEntry{Package: "b", Target: "REJECT"})
	if err := validateApplicationRoutes(wire); err != nil || wire.Revision != "d887c05e010a90e8d43773632359c9bc1b29e24a0cded86d265ffd66c31ed219" {
		t.Fatal(wire, err)
	}
	tampered := *wire
	tampered.Rules = append([]applicationRouteEntry(nil), wire.Rules...)
	tampered.Rules[0].Target = "REJECT"
	if validateApplicationRoutes(&tampered) == nil {
		t.Fatal("accepted tampered policy")
	}
	for _, entries := range [][]applicationRouteEntry{
		{{Package: "b", Target: "DIRECT"}, {Package: "a", Target: "DIRECT"}},
		{{Package: "a", Target: "DIRECT"}, {Package: "a", Target: "REJECT"}},
		{{Package: "a\n", Target: "DIRECT"}},
	} {
		if validateApplicationRoutes(applicationWire(7, 3, entries...)) == nil {
			t.Fatal("accepted invalid entries", entries)
		}
	}
	wire = applicationWire(7, 2, applicationRouteEntry{Package: "a", Target: "DIRECT"}, applicationRouteEntry{Package: "b", Target: "REJECT"}, applicationRouteEntry{Package: "c", Target: "missing-node"})
	scope := requestscope.NewBusinessScope(310, func() bool { return true })
	scope.Activate()
	defer scope.Close()
	p := &preparedConfig{scope: scope}
	data, _ := json.Marshal(wire)
	p.manifest = ConfigManifest{ProfileID: wire.ProfileID, AcceptedOverrides: map[string]json.RawMessage{"application-routing": data}}
	publishSourceTraceState(p, "fixture", false)
	old := preparedConfigGate.Swap(p)
	defer preparedConfigGate.Store(old)
	for _, network := range []C.NetWork{C.TCP, C.UDP} {
		metadata := &C.Metadata{NetWork: network, Type: C.TUN, SrcIP: netip.MustParseAddr("192.0.2.1"), SrcPort: 42321, DstIP: netip.MustParseAddr("192.0.2.2"), DstPort: 443}
		for _, tc := range []struct {
			status, user string
			packages     []string
			want         string
		}{
			{"known", "current", []string{"a"}, "DIRECT"},
			{"known", "current", []string{"b"}, "REJECT"},
			{"known", "current", []string{"c"}, "REJECT"},
			{"unknown", "current", nil, ""},
			{"known", "other", []string{"a"}, ""},
			{"ambiguous", "current", []string{"a", "b"}, ""},
			{"ambiguous", "current", []string{"a", "unconfigured"}, ""},
		} {
			body, _ := json.Marshal(map[string]any{"status": tc.status, "userScope": tc.user, "packages": tc.packages})
			identity := decodeApplicationIdentity(10123, string(body), "androidUid")
			metadata.RawSrcAddr = &net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: 42321}
			metadata.RawDstAddr = &net.TCPAddr{IP: net.IPv4(192, 0, 2, 2), Port: 443}
			connectionObservations.Lock()
			delete(connectionObservations.pending, connectionIngressKey(metadata))
			connectionObservations.Unlock()
			connectionObservations.remember(metadata, connectionIngress{identity: &identity})
			_, target, err := resolveApplicationRoute(context.Background(), scope, metadata)
			if err != nil || target != tc.want {
				t.Fatalf("%s %+v: %q %v", network, tc, target, err)
			}
		}
		metadata.Type = C.INNER
		if _, target, _ := resolveApplicationRoute(context.Background(), scope, metadata); target != "" {
			t.Fatal("internal request acquired app policy")
		}
	}
}

func TestApplicationHotUpdateReplaysAndRejectsForeignOrOlderSettings(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	id := sourceTraceInput(t, "mode: direct\nfind-process-mode: off\ngeo-auto-update: false\nrules: ['MATCH,REJECT']\n", nil)
	applyTestInput(t, id)
	wire := applicationWire(7, 2, applicationRouteEntry{Package: "a", Target: "DIRECT"})
	if err := updateConfig(&UpdateParams{ApplicationRouting: wire}); err != nil {
		t.Fatal(err)
	}
	if fact := configStateSnapshot(); fact.ApplicationRoutingRevision != wire.Revision || fact.ApplicationRoutingRules["a"] != applicationRuleKeys(*wire)["a"] {
		t.Fatal("not adopted", fact)
	}
	older := applicationWire(7, 1, applicationRouteEntry{Package: "a", Target: "REJECT"})
	if err := updateConfig(&UpdateParams{ApplicationRouting: older}); err != nil {
		t.Fatal(err)
	}
	if configStateSnapshot().ApplicationRoutingRevision != wire.Revision {
		t.Fatal("stale write replaced current policy")
	}
	foreign := applicationWire(8, 3, applicationRouteEntry{Package: "a", Target: "REJECT"})
	if updateConfig(&UpdateParams{ApplicationRouting: foreign}) == nil {
		t.Fatal("foreign subscription adopted")
	}
	ref, err := readCheckpointLocked(C.Path.HomeDir())
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, _, _, err := readConfigInput(C.Path.HomeDir(), ref.InputID)
	if err != nil {
		t.Fatal(err)
	}
	revision, routes := applicationRoutesFor(manifest)
	if revision != wire.Revision || routes["a"].target != "DIRECT" {
		t.Fatal("checkpoint lost app policy", revision, routes)
	}
}

func TestApplicationPolicyIsOwnedIndependentlyOfManagedSourceRules(t *testing.T) {
	f := newManagedFixture(t)
	accepted := applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	wire := applicationWire(7, 3, applicationRouteEntry{Package: "app", Target: "DIRECT"})
	if err := updateConfig(&UpdateParams{ApplicationRouting: wire}); err != nil {
		t.Fatal(err)
	}
	if fact := configStateSnapshot(); fact.ApplicationRoutingRevision != wire.Revision || fact.PolicySHA256 != accepted.Fact.PolicySHA256 {
		t.Fatal(fact)
	}
	replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, _, _, err := readConfigInput(C.Path.HomeDir(), replay.InputID)
	if err != nil || manifest.ManagedPolicy == nil {
		t.Fatal(manifest, err)
	}
	revision, routes := applicationRoutesFor(manifest)
	if revision != wire.Revision || routes["app"].target != "DIRECT" {
		t.Fatal("managed checkpoint lost trusted app policy")
	}
}
