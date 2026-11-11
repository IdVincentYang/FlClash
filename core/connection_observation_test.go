package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"os"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestConnectionObservationTunnelPreservesCoreCapabilities(t *testing.T) {
	var base observableTunnel = tunnel.Tunnel
	wrapped := connectionObservationTunnel{observableTunnel: base, capture: func(*C.Metadata) {}}
	var _ C.Tunnel = wrapped
	var _ P.Tunnel = wrapped
	var _ requestscope.AppTunnel = wrapped
	var _ proxydialer.Tunnel = wrapped
	if wrapped.NatTable() != base.NatTable() {
		t.Fatal("observation replaced the Core NAT owner")
	}
}

func observationTracker(port int, network C.NetWork) *statistic.TrackerInfo {
	metadata := &C.Metadata{NetWork: network, Type: C.TUN, Host: "controlled.test", SrcIP: netip.MustParseAddr("192.0.2.1"), SrcPort: uint16(port), DstIP: netip.MustParseAddr("192.0.2.2"), DstPort: 8080}
	if network == C.UDP {
		metadata.RawSrcAddr = &net.UDPAddr{IP: net.IPv4(192, 0, 2, 1), Port: port}
		metadata.RawDstAddr = &net.UDPAddr{IP: net.IPv4(192, 0, 2, 2), Port: 8080}
	} else {
		metadata.RawSrcAddr = &net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: port}
		metadata.RawDstAddr = &net.TCPAddr{IP: net.IPv4(192, 0, 2, 2), Port: 8080}
	}
	return &statistic.TrackerInfo{UUID: utils.NewUUIDV4(), Start: time.Now(), Metadata: metadata, Chain: C.Chain{"DIRECT"}, Rule: "Match"}
}

func TestConnectionObservationFreezesIdentityAndConfiguration(t *testing.T) {
	store := newConnectionObservationStore()
	info := observationTracker(20001, C.TCP)
	identity := decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.original"]}`, "androidUid")
	store.remember(info.Metadata, connectionIngress{identity: &identity, capture: connectionCapture{Status: "vpn", ServiceID: "service-a", Generation: 7}})
	store.bind(info, sourceRuleProvenance{AppliedRevision: "old-input"})
	first := store.view(info)
	info.Metadata.Host, info.Metadata.Process, info.Metadata.Uid = "new.test", "test.wrong", 10999
	identity = decodeApplicationIdentity(10999, `{"status":"known","userScope":"current","packages":["test.reinstalled"]}`, "androidUid")
	store.remember(info.Metadata, connectionIngress{identity: &identity, capture: connectionCapture{Status: "vpn", ServiceID: "service-b", Generation: 8}})
	store.bind(info, sourceRuleProvenance{AppliedRevision: "new-input"})
	second := store.view(info)
	if !reflect.DeepEqual(first, second) || second.metadata.Host != "controlled.test" || second.metadata.Process != "test.original" || second.metadata.Uid != 10123 || second.observation.Configuration.InputID != "old-input" || second.observation.Configuration.Mode != "rule" {
		t.Fatalf("current state rewrote old connection: %+v / %+v", second.observation, second.metadata)
	}
	if info.Metadata.Process != "test.wrong" {
		t.Fatal("observation mutated Core routing metadata")
	}
}

func TestConnectionObservationLookupIsOncePerConnectionNotPacketOrSnapshot(t *testing.T) {
	for _, network := range []C.NetWork{C.TCP, C.UDP} {
		t.Run(network.String(), func(t *testing.T) {
			store := newConnectionObservationStore()
			info := observationTracker(21001, network)
			calls := 0
			resolve := func(*C.Metadata) applicationIdentity {
				calls++
				return decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.app"]}`, "androidUid")
			}
			store.remember(info.Metadata, connectionIngress{resolve: resolve})
			if store.view(info).observation.Application.UID != nil || calls != 0 {
				t.Fatal("snapshot performed a late lookup")
			}
			store.bind(info, sourceRuleProvenance{})
			for i := 0; i < 100; i++ {
				packet := observationTracker(21001, network)
				store.remember(packet.Metadata, connectionIngress{resolve: resolve})
				store.view(info)
			}
			if calls != 1 || store.view(info).observation.Application.packageName() != "test.app" || len(store.pending) > 1 {
				t.Fatalf("lookup repeated or pending packets accumulated: calls=%d pending=%d", calls, len(store.pending))
			}
		})
	}
}

func TestConnectionObservationRetainsEarlierRuleLookup(t *testing.T) {
	store := newConnectionObservationStore()
	info := observationTracker(22001, C.TCP)
	calls := 0
	store.remember(info.Metadata, connectionIngress{resolve: func(*C.Metadata) applicationIdentity { calls++; return unknownApplication("lookupFailed") }})
	identity := decodeApplicationIdentity(10123, `{"status":"ambiguous","userScope":"current","packages":["test.a","test.b"]}`, "androidUid")
	store.remember(info.Metadata, connectionIngress{identity: &identity})
	store.bind(info, sourceRuleProvenance{})
	result := store.view(info)
	if calls != 0 || result.observation.Application.Status != "ambiguous" || result.metadata.Process != "" || result.metadata.Uid != 10123 {
		t.Fatal("rule lookup was repeated or shared UID was guessed")
	}
}

func TestConnectionObservationFollowsUDPMetadataCloneWithoutBorrowingOtherPackets(t *testing.T) {
	store := newConnectionObservationStore()
	info := observationTracker(22002, C.UDP)
	identity := decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.app"]}`, "androidUid")
	store.remember(info.Metadata, connectionIngress{identity: &identity, capture: connectionCapture{Status: "vpn", ServiceID: "original-service", Generation: 7}})
	info.Metadata = info.Metadata.Clone()
	if store.captureFor(info.Metadata) == nil {
		t.Fatal("UDP clone lost the captured service identity")
	}
	store.bind(info, sourceRuleProvenance{})
	if store.view(info).observation.Application.packageName() != "test.app" || store.view(info).observation.Capture.ServiceID != "original-service" {
		t.Fatal("Core UDP metadata clone lost its original socket observation")
	}
	next := observationTracker(22002, C.UDP)
	store.bind(next, sourceRuleProvenance{})
	if store.view(next).observation.Application.UID != nil {
		t.Fatal("different UDP packet borrowed a previous socket's owner")
	}
}

func TestConnectionObservationDoesNotLabelConfigurationDuringMutation(t *testing.T) {
	configMu.Lock()
	defer configMu.Unlock()
	if observedConfiguration().Status != "unknown" {
		t.Fatal("in-flight configuration was labeled as installed")
	}
}

func TestConnectionObservationTCPPortReuseDoesNotRetainAnEarlierOwner(t *testing.T) {
	store := newConnectionObservationStore()
	first := observationTracker(22101, C.TCP)
	second := observationTracker(22101, C.TCP)
	old := decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.old"]}`, "androidUid")
	current := decodeApplicationIdentity(10124, `{"status":"known","userScope":"current","packages":["test.new"]}`, "androidUid")
	store.remember(first.Metadata, connectionIngress{identity: &old})
	store.remember(second.Metadata, connectionIngress{identity: &current})
	store.bind(second, sourceRuleProvenance{})
	if store.view(second).observation.Application.packageName() != "test.new" {
		t.Fatal("TCP port reuse kept an old owner")
	}
	store.bind(first, sourceRuleProvenance{})
	if store.view(first).observation.Application.packageName() != "" {
		t.Fatal("late connection borrowed a different socket's identity")
	}
}

func TestConnectionObservationBoundsRetentionAndNeverRebuildsEvictedFacts(t *testing.T) {
	store := newConnectionObservationStore()
	first := observationTracker(23001, C.TCP)
	store.bind(first, sourceRuleProvenance{AppliedRevision: "original"})
	for i := 0; i < connectionObservationLimit+10; i++ {
		store.bind(observationTracker(23002+i, C.TCP), sourceRuleProvenance{})
	}
	if len(store.frozen) != connectionObservationLimit || store.view(first).observation.Configuration.InputID != "" || store.view(first).observation.RuntimeEpoch != "" {
		t.Fatal("retention exceeded limit or reconstructed missing historical facts")
	}
	for i := 0; i < connectionIngressLimit+10; i++ {
		store.remember(observationTracker(30000+i, C.UDP).Metadata, connectionIngress{})
	}
	if len(store.pending) != connectionIngressLimit {
		t.Fatalf("unbounded ingress: %d", len(store.pending))
	}
	for key, entry := range store.pending {
		entry.time = time.Now().Add(-2 * time.Minute)
		store.pending[key] = entry
	}
	store.sweepAt = time.Time{}
	store.remember(observationTracker(40000, C.UDP).Metadata, connectionIngress{})
	if len(store.pending) != 1 {
		t.Fatal("expired ingress prevented subsequent observations")
	}
}

func TestConnectionObservationConcurrentJoinAndSnapshot(t *testing.T) {
	store := newConnectionObservationStore()
	infos := make([]*statistic.TrackerInfo, 64)
	for i := range infos {
		infos[i] = observationTracker(41000+i, C.TCP)
		identity := decodeApplicationIdentity(10123+i, fmt.Sprintf(`{"status":"known","userScope":"current","packages":["test.app%d"]}`, i), "androidUid")
		store.remember(infos[i].Metadata, connectionIngress{identity: &identity})
	}
	var group sync.WaitGroup
	for _, info := range infos {
		group.Add(1)
		go func(info *statistic.TrackerInfo) {
			defer group.Done()
			store.bind(info, sourceRuleProvenance{})
		}(info)
	}
	for round := 0; round < 10; round++ {
		for i, info := range infos {
			observed := store.view(info).observation.Application
			if observed.UID != nil && *observed.UID != uint32(10123+i) {
				t.Error("concurrent snapshot borrowed another connection's UID")
			}
		}
	}
	group.Wait()
	for i, info := range infos {
		if store.view(info).observation.Application.packageName() != fmt.Sprintf("test.app%d", i) {
			t.Error("concurrent join lost its application identity")
		}
	}
}

func TestConnectionObservationJSONPreservesUIDAndLegacyFields(t *testing.T) {
	store := newConnectionObservationStore()
	info := observationTracker(25001, C.UDP)
	identity := decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.app"]}`, "androidUid")
	store.remember(info.Metadata, connectionIngress{identity: &identity})
	store.bind(info, sourceRuleProvenance{})
	observed := store.view(info)
	data, err := json.Marshal(sourceTrackerView{TrackerInfo: info, Metadata: observed.metadata, Observation: observed.observation})
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	metadata := result["metadata"].(map[string]any)
	if metadata["process"] != "test.app" || metadata["uid"] != float64(10123) || result["rule"] != "Match" || result["id"] != info.UUID.String() || result["observation"].(map[string]any)["version"] != float64(1) {
		t.Fatalf("connection wire contract changed: %s", data)
	}
	if path := os.Getenv("FLCLASH_CONNECTION_OBSERVATION_FIXTURE"); path != "" {
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func BenchmarkConnectionObservation(b *testing.B) {
	for _, network := range []C.NetWork{C.TCP, C.UDP} {
		b.Run(fmt.Sprint(network), func(b *testing.B) {
			store := newConnectionObservationStore()
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				info := observationTracker(20000+i%40000, network)
				store.remember(info.Metadata, connectionIngress{})
				store.bind(info, sourceRuleProvenance{})
				store.view(info)
			}
		})
	}
}
