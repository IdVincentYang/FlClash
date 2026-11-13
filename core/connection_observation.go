package main

import (
	"net"
	"slices"
	"sync"
	"time"

	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

const connectionObservationLimit = 4096
const connectionIngressLimit = 2048

type connectionCapture struct {
	Status     string `json:"status"`
	ServiceID  string `json:"serviceId,omitempty"`
	Generation uint64 `json:"generation,omitempty"`
}

type connectionConfiguration struct {
	Status       string  `json:"status"`
	InputID      string  `json:"inputId,omitempty"`
	Mode         string  `json:"mode,omitempty"`
	RouteEpoch   *uint64 `json:"routeEpoch,omitempty"`
	PicksVersion *uint64 `json:"picksVersion,omitempty"`
}

type connectionObservation struct {
	Version       int                     `json:"version"`
	RuntimeEpoch  string                  `json:"runtimeEpoch,omitempty"`
	Application   applicationIdentity     `json:"application"`
	Capture       connectionCapture       `json:"capture"`
	Configuration connectionConfiguration `json:"configuration"`
}

type connectionIngress struct {
	metadata      *C.Metadata
	capture       connectionCapture
	configuration connectionConfiguration
	identity      *applicationIdentity
	resolve       func(*C.Metadata) applicationIdentity
	time          time.Time
}

type observedConnection struct {
	observation connectionObservation
	metadata    *C.Metadata
}

type connectionObservationStore struct {
	sync.Mutex
	pending map[string]connectionIngress
	frozen  map[string]observedConnection
	order   [connectionObservationLimit]string
	next    int
	sweepAt time.Time
}

func newConnectionObservationStore() *connectionObservationStore {
	return &connectionObservationStore{pending: map[string]connectionIngress{}, frozen: map[string]observedConnection{}}
}

var connectionObservations = newConnectionObservationStore()

func isLoopbackProxyConnection(metadata *C.Metadata) bool {
	if metadata == nil || metadata.NetWork != C.TCP || (metadata.Type != C.HTTP && metadata.Type != C.HTTPS) {
		return false
	}
	source, sourceOK := metadata.RawSrcAddr.(*net.TCPAddr)
	target, targetOK := metadata.RawDstAddr.(*net.TCPAddr)
	return sourceOK && targetOK && source != nil && target != nil && source.IP.IsLoopback() && target.IP.IsLoopback() && source.Port > 0 && target.Port > 0
}

func sameConnectionIngress(left, right *C.Metadata) bool {
	if left == right {
		return true
	}
	if left == nil || right == nil || left.NetWork != C.UDP || right.NetWork != C.UDP || left.Type != right.Type {
		return false
	}
	source, sourceOK := left.RawSrcAddr.(*net.UDPAddr)
	target, targetOK := left.RawDstAddr.(*net.UDPAddr)
	return sourceOK && targetOK && source == right.RawSrcAddr && target == right.RawDstAddr
}

func (s *connectionObservationStore) hasPending(metadata *C.Metadata) bool {
	key := connectionIngressKey(metadata)
	s.Lock()
	defer s.Unlock()
	entry, exists := s.pending[key]
	return exists && time.Since(entry.time) < time.Minute && (metadata.NetWork == C.UDP || sameConnectionIngress(entry.metadata, metadata))
}

func (s *connectionObservationStore) captureFor(metadata *C.Metadata) *connectionCapture {
	s.Lock()
	defer s.Unlock()
	entry, exists := s.pending[connectionIngressKey(metadata)]
	if !exists || !sameConnectionIngress(entry.metadata, metadata) || entry.capture.Status != "vpn" {
		return nil
	}
	capture := entry.capture
	return &capture
}

func connectionIngressKey(metadata *C.Metadata) string {
	if metadata.RawSrcAddr == nil || metadata.RawDstAddr == nil {
		return ""
	}
	return metadata.NetWork.String() + ":" + metadata.RawSrcAddr.String() + ">" + metadata.RawDstAddr.String()
}

func (s *connectionObservationStore) remember(metadata *C.Metadata, ingress connectionIngress) {
	key := connectionIngressKey(metadata)
	if key == "" {
		return
	}
	s.Lock()
	defer s.Unlock()
	if previous, exists := s.pending[key]; exists && time.Since(previous.time) < time.Minute && (metadata.NetWork == C.UDP || sameConnectionIngress(previous.metadata, metadata)) {
		if sameConnectionIngress(previous.metadata, metadata) && previous.identity == nil && ingress.identity != nil {
			previous.identity = ingress.identity
			s.pending[key] = previous
		}
		return
	}
	if len(s.pending) >= connectionIngressLimit {
		if time.Now().Before(s.sweepAt) {
			return
		}
		s.sweepAt = time.Now().Add(time.Second)
		for key, entry := range s.pending {
			if time.Since(entry.time) >= time.Minute {
				delete(s.pending, key)
			}
		}
		if len(s.pending) >= connectionIngressLimit {
			return
		}
	}
	ingress.metadata, ingress.time = metadata, time.Now()
	s.pending[key] = ingress
}

func (s *connectionObservationStore) rememberResolved(metadata *C.Metadata, ingress connectionIngress) {
	if ingress.resolve == nil {
		return
	}
	identity := ingress.resolve(metadata)
	ingress.identity, ingress.resolve = &identity, nil
	s.remember(metadata, ingress)
}

func observedConfiguration() connectionConfiguration {
	if !configMu.TryLock() {
		return connectionConfiguration{Status: "unknown"}
	}
	defer configMu.Unlock()
	epoch, picks := routeStamp()
	checkpointMu.Lock()
	fact := configFact
	checkpointMu.Unlock()
	afterEpoch, afterPicks := routeStamp()
	if !fact.BusinessActive || fact.Phase != "ready" || fact.InputID == "" || epoch != afterEpoch || picks != afterPicks {
		return connectionConfiguration{Status: "unknown"}
	}
	return connectionConfiguration{Status: "known", InputID: fact.InputID, Mode: tunnel.Mode().String(), RouteEpoch: &epoch, PicksVersion: &picks}
}

func unknownConnectionObservation() connectionObservation {
	return connectionObservation{Version: 1, Application: unknownApplication("notObserved"), Capture: connectionCapture{Status: "unknown"}, Configuration: connectionConfiguration{Status: "unknown"}}
}

func (s *connectionObservationStore) bind(info *statistic.TrackerInfo, provenance sourceRuleProvenance) {
	id := info.UUID.String()
	s.Lock()
	if _, exists := s.frozen[id]; exists {
		s.Unlock()
		return
	}
	key := connectionIngressKey(info.Metadata)
	ingress, exists := s.pending[key]
	if exists && sameConnectionIngress(ingress.metadata, info.Metadata) {
		delete(s.pending, key)
	} else {
		ingress = connectionIngress{}
	}
	s.Unlock()
	if ingress.metadata == nil {
		ingress = localProxyConnectionIngress(info.Metadata)
	}

	observation := unknownConnectionObservation()
	observation.RuntimeEpoch = configRuntimeEpoch
	if ingress.identity != nil {
		observation.Application = *ingress.identity
	} else if ingress.resolve != nil {
		observation.Application = ingress.resolve(info.Metadata)
	}
	if ingress.capture.Status != "" {
		observation.Capture = ingress.capture
	}
	current := observedConfiguration()
	before := ingress.configuration
	if before.Status == "known" && current.Status == "known" && before.InputID == current.InputID && before.Mode == current.Mode && *before.RouteEpoch == *current.RouteEpoch && *before.PicksVersion == *current.PicksVersion {
		observation.Configuration = before
	}
	if provenance.AppliedRevision != "" && observation.Configuration.InputID != provenance.AppliedRevision {
		observation.Configuration = connectionConfiguration{Status: "known", InputID: provenance.AppliedRevision}
	}
	if provenance.AppliedRevision != "" && info.Rule != "" {
		// Global and Direct bypass the rule matcher; this evidence belongs to Rule mode.
		observation.Configuration.Mode = "rule"
	}
	metadata := *info.Metadata
	metadata.SrcGeoIP, metadata.DstGeoIP = slices.Clone(metadata.SrcGeoIP), slices.Clone(metadata.DstGeoIP)
	if observation.Application.UID != nil {
		metadata.Uid = *observation.Application.UID
		metadata.Process = observation.Application.packageName()
	}
	s.Lock()
	defer s.Unlock()
	if _, exists := s.frozen[id]; exists {
		return
	}
	delete(s.frozen, s.order[s.next])
	s.order[s.next] = id
	s.next = (s.next + 1) % len(s.order)
	s.frozen[id] = observedConnection{observation: observation, metadata: &metadata}
}

func (s *connectionObservationStore) view(info *statistic.TrackerInfo) observedConnection {
	s.Lock()
	defer s.Unlock()
	if found, exists := s.frozen[info.UUID.String()]; exists {
		return found
	}
	return observedConnection{observation: unknownConnectionObservation(), metadata: info.Metadata}
}

type observableTunnel interface {
	C.Tunnel
	P.Tunnel
	proxydialer.Tunnel
	requestscope.AppTunnel
}

type connectionObservationTunnel struct {
	observableTunnel
	capture func(*C.Metadata)
}

type businessIngressTunnel interface {
	C.Tunnel
	TrackInbound(net.Conn) (net.Conn, error)
}

type localProxyObservationTunnel struct {
	businessIngressTunnel
	capture func(*C.Metadata)
}

func bindObservedBusiness(scope *requestscope.BusinessScope) C.Tunnel {
	return localProxyObservationTunnel{
		businessIngressTunnel: tunnel.BindBusiness(scope).(businessIngressTunnel),
		capture: func(metadata *C.Metadata) {
			connectionObservations.rememberResolved(metadata, localProxyConnectionIngress(metadata))
		},
	}
}

func (t localProxyObservationTunnel) HandleTCPConn(conn net.Conn, metadata *C.Metadata) {
	t.capture(metadata)
	t.businessIngressTunnel.HandleTCPConn(conn, metadata)
}

func (t connectionObservationTunnel) HandleTCPConn(conn net.Conn, metadata *C.Metadata) {
	t.capture(metadata)
	t.observableTunnel.HandleTCPConn(conn, metadata)
}

func (t connectionObservationTunnel) HandleUDPPacket(packet C.UDPPacket, metadata *C.Metadata) {
	t.capture(metadata)
	t.observableTunnel.HandleUDPPacket(packet, metadata)
}
