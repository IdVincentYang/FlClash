package main

import (
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	proxyhttp "github.com/metacubex/mihomo/listener/http"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type delayedObservationTunnel struct {
	businessIngressTunnel
	handle func(net.Conn, *C.Metadata)
}

func (t delayedObservationTunnel) HandleTCPConn(conn net.Conn, metadata *C.Metadata) {
	t.handle(conn, metadata)
}

func TestLocalProxyIdentitySurvivesClientClosingBeforeTrackerJoin(t *testing.T) {
	checkpointMu.Lock()
	previous := configFact
	configFact = ConfigFact{InputID: "local-proxy-input", Phase: "ready", BusinessActive: true}
	checkpointMu.Unlock()
	t.Cleanup(func() {
		checkpointMu.Lock()
		configFact = previous
		checkpointMu.Unlock()
	})
	for _, method := range []string{"GET http://controlled.test/ HTTP/1.1\r\nHost: controlled.test\r\n\r\n", "CONNECT controlled.test:443 HTTP/1.1\r\nHost: controlled.test:443\r\n\r\n"} {
		t.Run(method[:3], func(t *testing.T) {
			store := newConnectionObservationStore()
			scope := requestscope.NewBusinessScope(1, nil)
			scope.Activate()
			t.Cleanup(scope.Close)
			var closed atomic.Bool
			var calls atomic.Int32
			entered := make(chan *C.Metadata, 1)
			release := make(chan struct{})
			result := make(chan observedConnection, 1)
			base := delayedObservationTunnel{
				businessIngressTunnel: tunnel.BindBusiness(scope).(businessIngressTunnel),
				handle: func(conn net.Conn, metadata *C.Metadata) {
					defer conn.Close()
					entered <- metadata
					select {
					case <-release:
					case <-time.After(5 * time.Second):
						return
					}
					info := &statistic.TrackerInfo{UUID: utils.NewUUIDV4(), Metadata: metadata}
					store.bind(info, sourceRuleProvenance{})
					result <- store.view(info)
				},
			}
			wrapped := localProxyObservationTunnel{
				businessIngressTunnel: base,
				capture: func(metadata *C.Metadata) {
					if !isLoopbackProxyConnection(metadata) {
						return
					}
					store.rememberResolved(metadata, connectionIngress{
						capture: connectionCapture{Status: "localProxy", ServiceID: "original", Generation: 1},
						resolve: func(*C.Metadata) applicationIdentity {
							calls.Add(1)
							if closed.Load() {
								return decodeApplicationIdentity(0, `{"status":"notFound","userScope":"current","packages":[]}`, "androidUid")
							}
							return decodeApplicationIdentity(10150, `{"status":"known","userScope":"current","packages":["test.browser"]}`, "androidUid")
						},
					})
				},
			}
			listener, err := proxyhttp.NewWithAuthenticate("127.0.0.1:0", wrapped, false, inbound.WithInName("TEST"))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = listener.Close() })
			client, err := net.DialTimeout("tcp", listener.Address(), time.Second)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = client.Close() })
			_ = client.SetDeadline(time.Now().Add(5 * time.Second))
			if _, err := io.WriteString(client, method); err != nil {
				t.Fatal(err)
			}
			var metadata *C.Metadata
			select {
			case metadata = <-entered:
			case <-time.After(3 * time.Second):
				t.Fatal("proxy request did not reach the business tunnel")
			}
			if metadata.RawSrcAddr.String() != client.LocalAddr().String() || metadata.RawDstAddr.String() != client.RemoteAddr().String() || calls.Load() != 1 {
				t.Fatal("identity was not captured from the original live client socket")
			}
			_ = client.Close()
			closed.Store(true)
			late := decodeApplicationIdentity(0, `{"status":"notFound","userScope":"current","packages":[]}`, "androidUid")
			store.remember(metadata, connectionIngress{identity: &late})
			close(release)
			select {
			case observed := <-result:
				if observed.observation.Application.packageName() != "test.browser" || observed.metadata.Uid != 10150 || observed.observation.Capture.Status != "localProxy" || calls.Load() != 1 {
					t.Fatalf("closed client lost its ingress identity: %+v", observed.observation)
				}
				if observed.observation.Configuration.Status != "known" || observed.observation.Configuration.InputID != "local-proxy-input" {
					t.Fatalf("local proxy lost its ingress configuration without rule provenance: %+v", observed.observation.Configuration)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("delayed tracker did not finish")
			}
		})
	}
}

func TestObservedBusinessTunnelPreservesScopeAdmissionAndRevocation(t *testing.T) {
	scope := requestscope.NewBusinessScope(2, nil)
	defer scope.Close()
	wrapped := bindObservedBusiness(scope)
	tracked, ok := wrapped.(businessIngressTunnel)
	if !ok || tracked.NatTable() != tunnel.Tunnel.NatTable() {
		t.Fatal("observation replaced the business tunnel's capabilities")
	}
	for _, active := range []bool{false, true, false} {
		if active {
			scope.Activate()
		}
		left, right := net.Pipe()
		guarded, err := requestscope.AcceptBusinessConn(wrapped, left)
		if active {
			if err != nil || guarded == left {
				t.Fatal("active scope was not tracked by its original owner")
			}
			scope.Close()
			if _, err := guarded.Write([]byte("blocked")); err == nil {
				t.Fatal("observation bypassed business revocation")
			}
		} else if err == nil {
			t.Fatal("inactive scope admitted an inbound connection")
		}
		_ = left.Close()
		_ = right.Close()
	}
}

func TestLocalProxyObservationKeepsUncertainAndRootIdentities(t *testing.T) {
	for _, original := range []applicationIdentity{
		unknownApplication("unknown"),
		decodeApplicationIdentity(0, `{"status":"notFound","userScope":"current","packages":[]}`, "androidUid"),
		decodeApplicationIdentity(10123, `{"status":"ambiguous","userScope":"current","packages":["test.a","test.b"]}`, "androidUid"),
	} {
		t.Run(original.Status, func(t *testing.T) {
			store := newConnectionObservationStore()
			info := observationTracker(22201, C.TCP)
			store.rememberResolved(info.Metadata, connectionIngress{resolve: func(*C.Metadata) applicationIdentity { return original }})
			later := decodeApplicationIdentity(10150, `{"status":"known","userScope":"current","packages":["test.browser"]}`, "androidUid")
			store.remember(info.Metadata, connectionIngress{identity: &later})
			store.bind(info, sourceRuleProvenance{})
			observed := store.view(info).observation.Application
			if observed.Status != original.Status || observed.packageName() != "" || original.UID != nil && (observed.UID == nil || *observed.UID != *original.UID) {
				t.Fatal("ingress identity was guessed or a real root UID was discarded")
			}
		})
	}
}
