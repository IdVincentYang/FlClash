package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	P "github.com/metacubex/mihomo/constant/provider"
	authStore "github.com/metacubex/mihomo/listener/auth"
	proxyHTTP "github.com/metacubex/mihomo/listener/http"
	"github.com/metacubex/mihomo/listener/inner"
	"github.com/metacubex/mihomo/tunnel"
)

type AppRequestState struct {
	ProcessEpoch       string `json:"processEpoch"`
	Revision           uint64 `json:"revision"`
	IntentRevision     uint64 `json:"intentRevision"`
	IntentRunning      bool   `json:"intentRunning"`
	Paused             bool   `json:"paused"`
	Source             string `json:"source"`
	Phase              string `json:"phase"`
	Reason             string `json:"reason"`
	ServiceID          string `json:"serviceId"`
	NetworkRevision    uint64 `json:"networkRevision"`
	NetworkSourceEpoch string `json:"networkSourceEpoch"`
	DefaultNetworkKind string `json:"defaultNetworkKind"`
	DefaultNetworkID   string `json:"defaultNetworkId"`
	DirectNetworkID    string `json:"directNetworkId"`
	ProtectGeneration  uint64 `json:"protectGeneration"`
	ProtectPhase       string `json:"protectPhase"`
}

type appRequestRegistry struct {
	mu              sync.Mutex
	state           AppRequestState
	owner           requestscope.Owner
	phase           string
	configToken     uint64
	next            uint64
	leases          map[string]*appRequestLease
	latest          map[string]*appRequestLease
	locks           map[string]chan struct{}
	changed         chan struct{}
	namespace       string
	socketGate      func(string, AppRequestState, int) error
	privateMu       sync.Mutex
	privateListener net.Listener
	privateConns    map[net.Conn]struct{}
	routeBusy       int
	pendingCleanups []func()
	client          string
	clientReady     bool
	dataset         uint64
	sources         map[string]uint64
	operations      map[string]uint64
	permits         map[string]requestscope.Spec
	commits         map[string]*appRequestReceipt
	dataReaders     map[string]struct{}
	bootstrap       *bootstrapResource
}

type bootstrapResource struct {
	Name, URL, Path string
	Owner           requestscope.Owner
}

type appRequestLease struct {
	registry                         *appRequestRegistry
	id, user, password, originalUser string
	spec                             requestscope.Spec
	state                            AppRequestState
	ctx                              context.Context
	cancel                           context.CancelFunc
	granted, closed                  bool
	closers                          map[io.Closer]struct{}
	choiceMu                         sync.Mutex
	fixedProxy                       C.Proxy
	routePicks                       map[string]string
	routeProviders                   map[string]uint32
	routeProviderRefs                map[string]P.ProxyProvider
	routeRules                       map[string]any
	routeProxies                     map[string]C.Proxy
	routeEpoch                       uint64
}

type appRequestReceipt struct {
	registry   *appRequestRegistry
	id, client string
	once       sync.Once
}

func (receipt *appRequestReceipt) Complete() {
	receipt.once.Do(func() {
		r := receipt.registry
		r.mu.Lock()
		delete(r.commits, receipt.id)
		r.changedLocked()
		r.mu.Unlock()
	})
}
func (receipt *appRequestReceipt) Fail(error) { receipt.Complete() }

var appRequests = newAppRequestRegistry()
var appDirectProxy = adapter.NewProxy(outbound.NewDirect())

func randomRequestToken() (string, error) {
	var bytes [24]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", errors.New("request entropy unavailable")
	}
	return hex.EncodeToString(bytes[:]), nil
}

func newAppRequestRegistry() *appRequestRegistry {
	namespace, _ := randomRequestToken()
	return &appRequestRegistry{leases: map[string]*appRequestLease{}, latest: map[string]*appRequestLease{}, locks: map[string]chan struct{}{}, changed: make(chan struct{}), namespace: namespace,
		sources: map[string]uint64{}, operations: map[string]uint64{}, permits: map[string]requestscope.Spec{}, commits: map[string]*appRequestReceipt{}}
}

func installAppRequests() {
	if !features.Android {
		return
	}
	requestscope.BeginHook = appRequests.begin
	requestscope.ProxyHook = appRequests.bindProxy
	requestscope.OwnerHook = appRequests.currentOwner
	requestscope.OwnerActiveHook = appRequests.ownerActive
	requestscope.PhaseHook = appRequests.setPhase
	requestscope.ReadyHook = appRequests.waitReady
	requestscope.BootstrapHook = appRequests.needBootstrap
	requestscope.ResourceHook = appRequests.lockResource
}

func (r *appRequestRegistry) changedLocked() {
	close(r.changed)
	r.changed = make(chan struct{})
}

func (r *appRequestRegistry) currentOwner() requestscope.Owner {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.owner
}

func (r *appRequestRegistry) invalidateLocked() []func() {
	r.permits = map[string]requestscope.Spec{}
	var cleanups []func()
	for _, lease := range r.leases {
		lease.closed = true
		cancel := lease.cancel
		cleanups = append(cleanups, cancel)
		for conn := range lease.closers {
			conn := conn
			cleanups = append(cleanups, func() { _ = conn.Close() })
		}
	}
	r.leases = map[string]*appRequestLease{}
	r.latest = map[string]*appRequestLease{}
	r.changedLocked()
	return cleanups
}

func finishRequestCleanup(cleanups []func()) {
	for _, cleanup := range cleanups {
		cleanup()
	}
}

func (r *appRequestRegistry) publish(state AppRequestState) bool {
	applied := r.publishPrepared(state)
	r.flushCleanup()
	return applied
}

func (r *appRequestRegistry) publishPrepared(state AppRequestState) bool {
	r.mu.Lock()
	if state.ProcessEpoch == "" || state.ProcessEpoch == r.state.ProcessEpoch && state.Revision <= r.state.Revision {
		r.mu.Unlock()
		return false
	}
	previous := r.state
	r.state = state
	protectedBusiness := false
	if prepared := preparedConfigGate.Load(); prepared != nil && prepared.scope == activeBusiness.Load() {
		protectedBusiness = prepared.receipt.ProtectGeneration != 0
	}
	if scope := activeBusiness.Load(); scope != nil && scope.IsActive() &&
		(previous.ProcessEpoch != state.ProcessEpoch || previous.IntentRevision != state.IntentRevision || previous.ServiceID != state.ServiceID || protectedBusiness && previous.ProtectGeneration != state.ProtectGeneration || !state.IntentRunning || state.Paused || state.Phase != "starting" && state.Phase != "started" || protectedBusiness && state.ProtectPhase != "ready") {
		cancel := scope.Invalidate()
		r.pendingCleanups = append(r.pendingCleanups, func() {
			cancel()
			safeGoDetached("retire business", func() { retireOwnedBusiness(scope) })
		})
	}
	r.pendingCleanups = append(r.pendingCleanups, r.invalidateLocked()...)
	r.mu.Unlock()
	return true
}

func (r *appRequestRegistry) flushCleanup() {
	r.mu.Lock()
	cleanups := r.pendingCleanups
	r.pendingCleanups = nil
	exiting := r.state.Reason == "exiting"
	r.mu.Unlock()
	finishRequestCleanup(cleanups)
	if exiting {
		r.closePrivate()
	}
}

func (r *appRequestRegistry) nextConfigOwner() (requestscope.Owner, []func()) {
	r.mu.Lock()
	r.next++
	r.owner = requestscope.Owner{ID: r.next}
	r.phase = "parsing"
	r.bootstrap = nil
	owner := r.owner
	cleanups := r.invalidateLocked()
	r.mu.Unlock()
	return owner, cleanups
}

func (r *appRequestRegistry) newOwner() requestscope.Owner {
	selectMu.Lock()
	checkpointMu.Lock()
	owner, cleanups := r.nextConfigOwner()
	checkpointMu.Unlock()
	selectMu.Unlock()
	finishRequestCleanup(cleanups)
	return owner
}

func (r *appRequestRegistry) setPhase(owner requestscope.Owner, phase string) {
	r.mu.Lock()
	if owner != r.owner || (r.phase == "failed" || r.phase == "retired") && phase != "failed" && phase != "retired" {
		r.mu.Unlock()
		return
	}
	r.phase = phase
	var cleanups []func()
	if phase == "failed" || phase == "retired" {
		cleanups = r.invalidateLocked()
	} else {
		r.changedLocked()
	}
	r.mu.Unlock()
	finishRequestCleanup(cleanups)
}

func (r *appRequestRegistry) allowedLocked(spec requestscope.Spec) bool {
	if r.configToken != 0 && r.phase != "ready" && spec.Owner == r.owner {
		if latest := latestConfig.Load(); latest == nil || latest.token != r.configToken {
			return false
		}
	}

	if spec.Client != "" && (!r.clientReady || spec.Client != r.client || spec.Dataset != r.dataset || spec.SourceRevision != r.sources[spec.Key] || spec.Operation != r.operations[spec.Key]) {
		return false
	}
	if r.routeBusy > 0 || r.state.ProcessEpoch == "" || r.state.Reason == "exiting" || spec.Proxy == "DIRECT" && !directRequestAvailable(r.state) {
		return false
	}
	if spec.Kind == "bootstrap" {
		return spec.Client != "" && spec.Permit != "" && spec.Trigger == "manual" && spec.Proxy == "DIRECT"
	}
	if spec.Kind == "maintenance" && spec.Proxy == "DIRECT" {
		if !r.state.IntentRunning || r.state.Paused || r.state.Phase != "started" {
			return spec.Trigger == "manual" && (r.state.Reason == "initializedIdle" || r.state.Reason == "userStop" || r.state.Reason == "excludedSsid")
		}
	}
	if spec.Owner.ID == 0 || spec.Owner != r.owner || r.phase != "inner" && r.phase != "ready" {
		return false
	}
	if spec.Kind == "provider-local" {
		return true
	}
	if r.state.Paused || !r.state.IntentRunning || r.state.Phase == "failed" || r.state.Phase == "stopping" {
		return false
	}
	if spec.Kind == "provider-initial" || spec.Kind == "provider" && r.phase == "inner" {
		return true
	}
	return r.phase == "ready" && r.state.Phase == "started"
}

func (r *appRequestRegistry) begin(parent context.Context, spec requestscope.Spec) (requestscope.Lease, error) {
	id, entropyErr := randomRequestToken()
	if entropyErr != nil {
		return nil, requestscope.ErrBlocked
	}
	if spec.Mode != "" && spec.Mode != "auto" && spec.Mode != "proxy" && spec.Mode != "direct" {
		return nil, requestscope.ErrBlocked
	}
	if spec.Mode == "direct" {
		spec.Proxy = "DIRECT"
	}
	if spec.Mode == "proxy" && spec.Proxy == "" {
		spec.Proxy = "GLOBAL"
	}
	r.mu.Lock()
	if parent.Err() != nil {
		r.mu.Unlock()
		return nil, requestscope.ErrCancelled
	}
	if inherited := requestscope.FromContext(parent); inherited != nil {
		lease, ok := inherited.(*appRequestLease)
		if !ok || lease == nil || lease.registry != r || !lease.validLocked() || lease.granted || lease.ctx.Err() != nil {
			r.mu.Unlock()
			return nil, requestscope.ErrCancelled
		}
	}
	if spec.Client != "" {
		if spec.ExpectedState == nil || spec.ExpectedState.Epoch != r.state.ProcessEpoch || spec.ExpectedState.Revision != r.state.Revision || spec.Owner != r.owner {
			r.mu.Unlock()
			return nil, requestscope.ErrCancelled
		}
		if spec.Operation == 0 {
			r.operations[spec.Key]++
			spec.Operation = r.operations[spec.Key]
		}
		if spec.Kind == "bootstrap" {
			permit, ok := r.permits[spec.Permit]
			delete(r.permits, spec.Permit)
			if !ok || permit.Client != spec.Client || permit.Key != spec.Key || permit.URL != spec.URL || permit.Dataset != spec.Dataset || permit.SourceRevision != spec.SourceRevision || permit.ExpectedState == nil || *permit.ExpectedState != *spec.ExpectedState {
				r.mu.Unlock()
				return nil, requestscope.ErrBlocked
			}
		}
	}
	if r.namespace == "" || !r.allowedLocked(spec) {
		r.mu.Unlock()
		return nil, requestscope.ErrBlocked
	}
	if len(r.leases) >= 128 {
		r.mu.Unlock()
		return nil, requestscope.ErrBlocked
	}
	ctx, cancel := context.WithCancel(parent)
	lease := &appRequestLease{registry: r, id: id, spec: spec, state: r.state, ctx: ctx, cancel: cancel, closers: map[io.Closer]struct{}{}}
	key := spec.Kind + ":" + spec.Key
	if strings.HasPrefix(spec.Kind, "provider") {
		key = "provider:" + spec.Key
	}
	if spec.Client == "" && (spec.Kind == "geo" || spec.Kind == "geo-batch") {
		r.operations["internal:"+key]++
		lease.spec.Operation = r.operations["internal:"+key]
	}
	previous := r.latest[key]
	r.latest[key] = lease
	r.leases[lease.id] = lease
	r.mu.Unlock()
	if previous != nil {
		previous.Close()
	}
	return lease, nil
}

func (r *appRequestRegistry) waitReady(ctx context.Context, owner requestscope.Owner, proxy string) error {
	for {
		r.mu.Lock()
		if owner != r.owner || r.phase == "failed" || r.phase == "retired" {
			r.mu.Unlock()
			return requestscope.ErrCancelled
		}
		ready := r.phase == "ready" && r.state.Phase == "started" && !r.state.Paused && (proxy != "DIRECT" || directRequestAvailable(r.state))
		changed := r.changed
		r.mu.Unlock()
		if ready {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-changed:
		}
	}
}

func (l *appRequestLease) Context() context.Context { return l.withContext(l.ctx) }

func (l *appRequestLease) withContext(ctx context.Context) context.Context {
	ctx = requestscope.WithLease(ctx, l)
	if l.spec.Proxy == "DIRECT" {
		ctx = dialer.WithSocketControl(ctx, l.controlSocket)
	}
	return ctx
}

func (l *appRequestLease) controlSocket(ctx context.Context, network, address string, raw syscall.RawConn) error {
	if err := l.Check(); err != nil {
		return err
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	l.registry.mu.Lock()
	gate := l.registry.socketGate
	l.registry.mu.Unlock()
	if gate == nil {
		return requestscope.ErrBlocked
	}
	var gateErr error
	if err := raw.Control(func(fd uintptr) { gateErr = gate(l.id, l.state, int(fd)) }); err != nil {
		return err
	}
	if gateErr != nil {
		return gateErr
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return l.Check()
}

func (l *appRequestLease) CompletionVersion() requestscope.Completion {
	return requestscope.Completion{Spec: l.spec, State: requestscope.StateVersion{Epoch: l.state.ProcessEpoch, Revision: l.state.Revision}}
}

func (r *appRequestRegistry) completionCurrentLocked(completion requestscope.Completion) bool {
	spec := completion.Spec
	if completion.State.Epoch != r.state.ProcessEpoch || completion.State.Revision != r.state.Revision || spec.Owner.ID == 0 || spec.Owner != r.owner || (r.phase != "ready" && r.phase != "inner") || !r.allowedLocked(spec) {
		return false
	}
	if spec.Client != "" {
		return true
	}
	key := spec.Kind + ":" + spec.Key
	if strings.HasPrefix(spec.Kind, "provider") {
		key = "provider:" + spec.Key
	}
	return spec.Operation != 0 && r.operations["internal:"+key] == spec.Operation
}

func (l *appRequestLease) ProxyName() string { return l.spec.Proxy }

func (l *appRequestLease) FixedProxy() (C.Proxy, bool) {
	if l.spec.Proxy == "DIRECT" {
		return appDirectProxy, true
	}
	return nil, false
}

func (l *appRequestLease) SelectProxy(proxy C.Proxy, metadata *C.Metadata) (C.Proxy, error) {
	selectMu.Lock()
	defer selectMu.Unlock()
	l.choiceMu.Lock()
	defer l.choiceMu.Unlock()
	if err := l.Check(); err != nil {
		return nil, err
	}
	if l.fixedProxy != nil {
		return l.fixedProxy, nil
	}
	strict := l.spec.Mode == "proxy"
	if proxy == appDirectProxy && l.spec.Proxy == "DIRECT" && !strict {
		return proxy, nil
	}
	original := proxy
	if l.routePicks == nil {
		l.routePicks, l.routeProviders, l.routeProxies = map[string]string{}, map[string]uint32{}, map[string]C.Proxy{}
		l.routeProviderRefs = map[string]P.ProxyProvider{}
		l.routeRules = readRuleSets()
		l.routeEpoch, _ = routeStamp()
	}
	seen := map[C.Proxy]bool{}
	for proxy != nil && !seen[proxy] {
		seen[proxy] = true
		if name := proxy.ProxyInfo().ProviderName; name != "" {
			pd := tunnel.ProvidersSnapshot()[name]
			if pd == nil {
				cleanup := l.prepareClose()
				go cleanup()
				return nil, requestscope.ErrCancelled
			}
			version := pd.Version()
			found := false
			for _, node := range pd.Proxies() {
				if node == proxy {
					found = true
					break
				}
			}
			if !found || pd.Version() != version {
				cleanup := l.prepareClose()
				go cleanup()
				return nil, requestscope.ErrCancelled
			}
			l.routeProviders[name], l.routeProviderRefs[name] = version, pd
		} else if published := lookupProxy(proxy.Name()); published != nil || l.spec.Kind == "urltest" || l.spec.Kind == "health" {
			l.routeProxies[proxy.Name()] = proxy
			if published != proxy {
				return nil, requestscope.ErrCancelled
			}
		}
		if group, ok := proxy.Adapter().(outboundgroup.ProxyGroup); ok {
			for _, provider := range group.Providers() {
				l.routeProviders[provider.Name()] = provider.Version()
				l.routeProviderRefs[provider.Name()] = provider
			}
		}
		if strict {
			if _, direct := proxy.Adapter().(*outbound.Direct); direct {
				return nil, requestscope.ErrBlocked
			}
		}
		switch proxy.Type() {
		case C.Selector, C.URLTest, C.Fallback, C.LoadBalance:
			next := proxy.Unwrap(metadata, strict)
			if _, pickable := proxy.Adapter().(pickableGroup); pickable && next != nil {
				l.routePicks[proxy.Name()] = next.Name()
			}
			proxy = next
		default:
			if !strict {
				return original, l.Check()
			}
			switch proxy.Type() {
			case C.Shadowsocks, C.ShadowsocksR, C.Snell, C.Socks5, C.Http, C.Vmess, C.Vless, C.Trojan, C.Hysteria, C.Hysteria2, C.WireGuard, C.Tuic, C.Ssh, C.Mieru, C.AnyTLS, C.Sudoku, C.Masque, C.TrustTunnel, C.ShadowQuic, C.OpenVPN:
				l.fixedProxy = proxy
				return proxy, l.Check()
			default:
				return nil, requestscope.ErrBlocked
			}
		}
	}
	return nil, requestscope.ErrBlocked
}

func (l *appRequestLease) routeCurrentLocked() bool {
	l.choiceMu.Lock()
	defer l.choiceMu.Unlock()
	if l.routePicks == nil {
		return true
	}
	for name, pick := range l.routePicks {
		proxy := lookupProxy(name)
		if proxy == nil {
			return false
		}
		group, ok := proxy.Adapter().(pickableGroup)
		if !ok || group.Now() != pick {
			return false
		}
	}
	providers := tunnel.ProvidersSnapshot()
	for name, version := range l.routeProviders {
		pd := l.routeProviderRefs[name]
		if pd.VehicleType() != P.Compatible && providers[name] != pd {
			return false
		}
		if pd.Version() != version {
			return false
		}
	}
	for name, proxy := range l.routeProxies {
		if lookupProxy(name) != proxy {
			return false
		}
	}
	if l.spec.Proxy == "" {
		epoch, _ := routeStamp()
		if epoch != l.routeEpoch || !maps.Equal(l.routeRules, readRuleSets()) {
			return false
		}
	}
	return true
}

func (l *appRequestLease) current() bool {
	selectMu.Lock()
	defer selectMu.Unlock()
	return l.routeCurrentLocked() && l.Check() == nil
}

func (l *appRequestLease) Dialer() C.Dialer { return appRequestDialer{lease: l} }

func (l *appRequestLease) validLocked() bool {
	return !l.closed && l.registry.leases[l.id] == l && l.state.ProcessEpoch == l.registry.state.ProcessEpoch && l.state.Revision == l.registry.state.Revision && l.registry.allowedLocked(l.spec)
}

func (l *appRequestLease) Check() error {
	l.registry.mu.Lock()
	valid := l.validLocked()
	l.registry.mu.Unlock()
	if !valid || l.ctx.Err() != nil {
		return requestscope.ErrCancelled
	}
	return nil
}

func (l *appRequestLease) checkNetwork() error {
	l.registry.mu.Lock()
	valid := l.validLocked() && !l.granted
	l.registry.mu.Unlock()
	if !valid || l.ctx.Err() != nil {
		return requestscope.ErrCancelled
	}
	return nil
}

func (l *appRequestLease) trackCloser(conn io.Closer) error {
	l.registry.mu.Lock()
	valid := l.validLocked()
	if valid {
		l.closers[conn] = struct{}{}
	}
	l.registry.mu.Unlock()
	if !valid {
		_ = conn.Close()
		return requestscope.ErrCancelled
	}
	return nil
}
func (l *appRequestLease) TrackConn(conn net.Conn) error { return l.trackCloser(conn) }

func (l *appRequestLease) LockCommit(ctx context.Context) (func(), error) {
	if err := l.Check(); err != nil {
		return nil, err
	}
	key := l.spec.Resource
	if key == "" {
		key = l.spec.Key
	}
	return l.registry.lockResource(ctx, key)
}

func (r *appRequestRegistry) lockResource(ctx context.Context, key string) (func(), error) {
	r.mu.Lock()
	lock := r.locks[key]
	if lock == nil {
		lock = make(chan struct{}, 1)
		r.locks[key] = lock
	}
	r.mu.Unlock()
	select {
	case lock <- struct{}{}:
		return func() { <-lock }, nil
	case <-ctx.Done():
		return nil, requestscope.ErrCancelled
	}
}

func (r *appRequestRegistry) needBootstrap(name, url, path string) error {
	r.mu.Lock()
	if r.phase == "parsing" {
		r.bootstrap = &bootstrapResource{Name: name, URL: url, Path: path, Owner: r.owner}
	}
	r.mu.Unlock()
	return requestscope.ErrBootstrap
}

func (l *appRequestLease) CheckTarget(url string) error {
	if l.spec.URL != url {
		return requestscope.ErrCancelled
	}
	return l.Check()
}

func (l *appRequestLease) GrantCommit() (requestscope.Receipt, error) {
	selectMu.Lock()
	defer selectMu.Unlock()
	if !l.routeCurrentLocked() {
		return nil, requestscope.ErrCancelled
	}
	l.registry.mu.Lock()
	defer l.registry.mu.Unlock()
	if !l.validLocked() || l.granted {
		return nil, requestscope.ErrCancelled
	}
	if l.spec.Client != "" && len(l.registry.dataReaders) != 0 {
		return nil, errRequestCommitBusy
	}
	l.granted = true
	receipt := &appRequestReceipt{registry: l.registry, id: l.id, client: l.spec.Client}
	l.registry.commits[l.id] = receipt
	return receipt, nil
}

func (l *appRequestLease) Close() { l.prepareClose()() }

func (l *appRequestLease) prepareClose() func() {
	r := l.registry
	r.mu.Lock()
	if l.closed {
		r.mu.Unlock()
		return func() {}
	}
	l.closed = true
	delete(r.leases, l.id)
	key := l.spec.Kind + ":" + l.spec.Key
	if strings.HasPrefix(l.spec.Kind, "provider") {
		key = "provider:" + l.spec.Key
	}
	if r.latest[key] == l {
		delete(r.latest, key)
	}
	closers := l.closers
	l.closers = nil
	r.mu.Unlock()
	return func() {
		l.cancel()
		for conn := range closers {
			_ = conn.Close()
		}
	}
}

func (r *appRequestRegistry) bindProxy(conn net.Conn, user, password string) (requestscope.ProxyBinding, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !strings.HasPrefix(user, "flclash-request-") {
		return requestscope.ProxyBinding{}, false, nil
	}
	host, _, err := net.SplitHostPort(conn.RemoteAddr().String())
	addr, parseErr := netip.ParseAddr(host)
	if err != nil || parseErr != nil || !addr.IsLoopback() {
		return requestscope.ProxyBinding{}, true, requestscope.ErrBlocked
	}
	for _, lease := range r.leases {
		if lease.user == user && lease.password == password && lease.validLocked() && !lease.granted {
			return requestscope.ProxyBinding{Lease: lease, User: lease.originalUser}, true, nil
		}
	}
	return requestscope.ProxyBinding{}, true, requestscope.ErrCancelled
}

type appRequestControl struct {
	ConfigInput                                                                      *ConfigInputRequest
	Action, ID, Kind, Trigger, Key, Proxy, User, Password, Mode, URL, Client, Permit string
	Owner, Dataset, SourceRevision, Operation                                        uint64
	ExpectedState                                                                    *requestscope.StateVersion
	State                                                                            AppRequestState
}

func handleRequestControl(data string) string {
	var params appRequestControl
	if json.Unmarshal([]byte(data), &params) != nil {
		return `{"error":"invalid_request_control"}`
	}
	result := appRequests.control(params)
	bytes, _ := json.Marshal(result)
	return string(bytes)
}

func (r *appRequestRegistry) control(params appRequestControl) any {
	if params.Action == "registerConfigInput" {
		if params.ConfigInput == nil || !validInputID(params.ConfigInput.InputID) {
			return map[string]string{"error": "invalid_config_input"}
		}
		return registerConfigOperation(methodCallSeq.Add(1), *params.ConfigInput)
	}
	if params.Action == "attach" || params.Action == "invalidate" || params.Action == "invalidateDataset" {
		checkpointMu.Lock()
		defer checkpointMu.Unlock()
	}

	failure := func(code string) any { return map[string]string{"error": code} }
	proxyConfigured := false
	if params.Action == "inspect" {
		for _, proxy := range tunnel.AllProxies() {
			switch proxy.Type() {
			case C.Direct, C.Reject, C.Compatible, C.Pass, C.Selector, C.URLTest, C.Fallback, C.LoadBalance:
			default:
				proxyConfigured = true
			}
		}
	}
	switch params.Action {
	case "publish":
		return map[string]any{"applied": r.publishPrepared(params.State)}
	case "block":
		r.mu.Lock()
		state := r.state
		r.mu.Unlock()
		state.Revision++
		state.Phase, state.Reason = "failed", "vpnRevoked"
		return map[string]bool{"ok": r.publishPrepared(state)}
	case "waitData":
		return map[string]bool{"ok": waitRequestDataCommit() == nil}
	case "readData":
		id, err := beginRequestDataRead()
		if err != nil {
			return failure("request_commit_busy")
		}
		return map[string]string{"id": id}
	case "endRead":
		r.endDataRead(params.ID)
		return map[string]bool{"ok": true}
	case "flush":
		r.flushCleanup()
		return map[string]bool{"ok": true}
	case "engineDetach":
		r.detachFrontend()
		return map[string]bool{"ok": true}
	case "attach":
		r.detachFrontend()
		client, err := randomRequestToken()
		if err != nil {
			return failure("request_blocked")
		}
		r.mu.Lock()
		r.client, r.clientReady = client, false
		r.dataset++
		var old []*appRequestLease
		for _, lease := range r.leases {
			if lease.spec.Client != "" {
				old = append(old, lease)
			}
		}
		r.mu.Unlock()
		for _, lease := range old {
			lease.Close()
		}
		return map[string]any{"client": client}
	case "inspect", "ready", "invalidate", "invalidateDataset", "detach", "permit":
		r.mu.Lock()
		if params.Client == "" || params.Client != r.client {
			r.mu.Unlock()
			return failure("request_cancelled")
		}
		var old []*appRequestLease
		switch params.Action {
		case "ready":
			for _, receipt := range r.commits {
				if receipt.client != "" && receipt.client != params.Client {
					r.mu.Unlock()
					return map[string]bool{"ready": false}
				}
			}
			r.clientReady = true
		case "detach":
			r.clientReady = false
		case "invalidate":
			r.sources[params.Key]++
		case "invalidateDataset":
			r.dataset++
			r.phase = "retired"
			if scope := activeBusiness.Load(); scope != nil {
				cancel := scope.Invalidate()
				r.pendingCleanups = append(r.pendingCleanups, func() { cancel(); safeGoDetached("retire dataset business", func() { retireOwnedBusiness(scope) }) })
			}
		case "permit":
			if !r.clientReady || params.ExpectedState == nil || params.ExpectedState.Epoch != r.state.ProcessEpoch || params.ExpectedState.Revision != r.state.Revision || params.Dataset != r.dataset || params.SourceRevision != r.sources[params.Key] || params.URL == "" || len(r.permits) >= 32 {
				r.mu.Unlock()
				return failure("request_cancelled")
			}
			permit, err := randomRequestToken()
			if err != nil {
				r.mu.Unlock()
				return failure("request_blocked")
			}
			r.permits[permit] = requestscope.Spec{Client: params.Client, Key: params.Key, URL: params.URL, Dataset: params.Dataset, SourceRevision: params.SourceRevision, ExpectedState: params.ExpectedState}
			r.mu.Unlock()
			return map[string]string{"permit": permit}
		}
		if params.Action == "invalidate" || params.Action == "invalidateDataset" || params.Action == "detach" {
			r.permits = map[string]requestscope.Spec{}
			for _, lease := range r.leases {
				if params.Action == "invalidateDataset" || lease.spec.Client == params.Client && (params.Action == "detach" || lease.spec.Key == params.Key) {
					old = append(old, lease)
				}
			}
		}
		if params.Action == "invalidate" || params.Action == "invalidateDataset" {
			r.mu.Unlock()
			err := invalidateConfigCheckpointLocked(params.Key, params.Action == "invalidateDataset")
			r.mu.Lock()
			if err != nil {
				r.mu.Unlock()
				return failure("request_commit_recovery_required")
			}
		}
		commits := len(r.commits)
		if r.commits[params.ID] != nil {
			commits--
		}
		result := map[string]any{"state": r.state, "owner": r.owner.ID, "phase": r.phase, "dataset": r.dataset, "sourceRevision": r.sources[params.Key], "operation": r.operations[params.Key], "commits": commits, "bootstrap": r.bootstrap, "hasProxy": proxyConfigured}
		r.mu.Unlock()
		for _, lease := range old {
			lease.Close()
		}
		r.flushCleanup()
		return result
	case "begin":
		if params.Mode != "direct" && params.Proxy != "DIRECT" {
			if auth := authStore.Default.Authenticator(); auth != nil && !auth.Verify(params.User, params.Password) {
				return failure("proxy_authentication_required")
			}
		}
		r.mu.Lock()
		if params.Client == "" || params.Client != r.client || !r.clientReady || params.Dataset != r.dataset || params.SourceRevision != r.sources[params.Key] || params.Owner != r.owner.ID {
			r.mu.Unlock()
			return failure("request_cancelled")
		}
		r.operations[params.Key]++
		params.Operation = r.operations[params.Key]
		var old []*appRequestLease
		for _, lease := range r.leases {
			if lease.spec.Client == params.Client && lease.spec.Key == params.Key {
				old = append(old, lease)
			}
		}
		r.mu.Unlock()
		for _, lease := range old {
			lease.Close()
		}
		lease, err := r.begin(context.Background(), requestscope.Spec{Owner: requestscope.Owner{ID: params.Owner}, Kind: params.Kind, Trigger: params.Trigger, Key: params.Key, Proxy: params.Proxy, Mode: params.Mode, URL: params.URL, Client: params.Client, Dataset: params.Dataset, SourceRevision: params.SourceRevision, Operation: params.Operation, ExpectedState: params.ExpectedState, Permit: params.Permit})
		if err != nil {
			return failure("request_blocked")
		}
		l := lease.(*appRequestLease)
		endpoint, err := r.privateEndpoint()
		if err != nil {
			l.Close()
			return failure("request_channel_unavailable")
		}
		password, err := randomRequestToken()
		if err != nil {
			l.Close()
			return failure("request_blocked")
		}
		r.mu.Lock()
		l.user, l.password, l.originalUser = "flclash-request-"+r.namespace+"-"+l.id, password, params.User
		r.mu.Unlock()
		return map[string]any{"id": l.id, "user": l.user, "password": l.password, "owner": params.Owner, "endpoint": endpoint, "dataset": params.Dataset, "sourceRevision": params.SourceRevision, "operation": params.Operation}
	case "lock":
		id, err := randomRequestToken()
		if err != nil {
			return failure("request_blocked")
		}
		r.mu.Lock()
		if params.Client == "" || params.Client != r.client {
			r.mu.Unlock()
			return failure("request_cancelled")
		}
		if len(r.dataReaders) != 0 {
			r.mu.Unlock()
			return failure("request_commit_busy")
		}
		for _, receipt := range r.commits {
			if receipt.client != "" && receipt.client != params.Client {
				r.mu.Unlock()
				return failure("request_commit_recovery_required")
			}
		}
		r.commits[id] = &appRequestReceipt{registry: r, id: id, client: params.Client}
		r.mu.Unlock()
		return map[string]string{"id": id}

	case "complete":
		r.mu.Lock()
		receipt := r.commits[params.ID]
		r.mu.Unlock()
		if receipt == nil || receipt.client != params.Client {
			return failure("request_cancelled")
		}
		receipt.Complete()
		return map[string]bool{"ok": true}
	case "cancel", "grant", "check":
		r.mu.Lock()
		lease := r.leases[params.ID]
		r.mu.Unlock()
		if lease == nil || lease.spec.Client != params.Client {
			return failure("request_cancelled")
		}
		if params.Action == "cancel" {
			lease.Close()
			return map[string]bool{"ok": true}
		}
		if params.Action == "grant" {
			_, err := lease.GrantCommit()
			if errors.Is(err, errRequestCommitBusy) {
				return failure("request_commit_busy")
			}
			return map[string]bool{"ok": err == nil}
		}
		return map[string]bool{"ok": lease.current()}
	}
	return failure("invalid_request_control")
}

type appRequestDialer struct{ lease *appRequestLease }

func (d appRequestDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	l := d.lease
	ctx = l.withContext(ctx)
	if err := l.checkNetwork(); err != nil {
		return nil, err
	}
	if l.spec.Proxy == "DIRECT" {
		conn, err := dialer.DialContext(ctx, network, address)
		if err != nil {
			return nil, err
		}
		return requestscope.Track(ctx, conn, l)
	}
	if strings.HasPrefix(network, "udp") {
		proxy := lookupProxy(l.spec.Proxy)
		if proxy == nil {
			return nil, requestscope.ErrBlocked
		}
		metadata := &C.Metadata{NetWork: C.UDP, Type: C.INNER}
		if err := metadata.SetRemoteAddress(address); err != nil {
			return nil, err
		}
		selected, err := l.SelectProxy(proxy, metadata)
		if err != nil {
			return nil, err
		}
		if err = l.BeforeDial(metadata); err != nil {
			return nil, err
		}
		conn, err := proxydialer.New(selected, true).DialContext(ctx, network, address)
		if err != nil {
			return nil, err
		}
		if reader, ok := conn.(interface {
			WaitRead() ([]byte, func(), error)
		}); ok {
			conn = &appRequestPacketStream{Conn: conn, read: reader.WaitRead}
		}
		return requestscope.Track(ctx, conn, l)
	}
	conn, err := inner.HandleTcpWithScope(ctx, tunnel.Tunnel, address, l.spec.Proxy, l)
	if err != nil {
		return nil, err
	}
	return requestscope.Track(ctx, conn, l)
}

type appRequestPacketStream struct {
	net.Conn
	read func() ([]byte, func(), error)
}

func (conn *appRequestPacketStream) Read(buffer []byte) (int, error) {
	data, release, err := conn.read()
	if release != nil {
		defer release()
	}
	return copy(buffer, data), err
}

func (d appRequestDialer) ListenPacket(ctx context.Context, network, address string, rAddr netip.AddrPort) (net.PacketConn, error) {
	l := d.lease
	ctx = l.withContext(ctx)
	if err := l.checkNetwork(); err != nil {
		return nil, err
	}
	var chosen C.Dialer = dialer.NewDialer()
	if l.spec.Proxy != "" && l.spec.Proxy != "DIRECT" {
		chosen = proxydialer.NewByName(l.spec.Proxy, tunnel.Tunnel)
	}
	conn, err := chosen.ListenPacket(ctx, network, address, rAddr)
	if err != nil {
		return nil, err
	}
	if err = l.trackCloser(conn); err != nil {
		return nil, err
	}
	context.AfterFunc(ctx, func() { _ = conn.Close() })
	return conn, nil
}

func requestLease(id string) (requestscope.Lease, error) {
	if requestscope.BeginHook == nil {
		return nil, nil
	}
	appRequests.mu.Lock()
	lease := appRequests.leases[id]
	appRequests.mu.Unlock()
	if lease == nil {
		return nil, requestscope.ErrBlocked
	}
	return lease, lease.Check()
}

func requestOperationContext(id, proxy string) (context.Context, requestscope.Lease, error) {
	lease, err := requestLease(id)
	if err != nil {
		return nil, nil, err
	}
	if lease == nil {
		return context.Background(), nil, nil
	}
	l := lease.(*appRequestLease)
	if l.spec.Proxy != proxy {
		return nil, nil, requestscope.ErrBlocked
	}
	return requestscope.WithLease(lease.Context(), lease), lease, nil
}

func invalidateAppRequestRoutesLocked() {
	if requestscope.BeginHook == nil {
		return
	}
	appRequests.mu.Lock()
	leases := make([]*appRequestLease, 0, len(appRequests.leases))
	for _, lease := range appRequests.leases {
		if !lease.granted {
			leases = append(leases, lease)
		}
	}
	appRequests.mu.Unlock()
	for _, lease := range leases {
		if !lease.routeCurrentLocked() {
			cleanup := lease.prepareClose()
			go cleanup()
		}
	}
}

func invalidateAppRequestGroup(name string) {
	if requestscope.BeginHook == nil {
		return
	}
	appRequests.mu.Lock()
	leases := make([]*appRequestLease, 0, len(appRequests.leases))
	for _, lease := range appRequests.leases {
		if !lease.granted {
			leases = append(leases, lease)
		}
	}
	appRequests.mu.Unlock()
	for _, lease := range leases {
		lease.choiceMu.Lock()
		_, selected := lease.routePicks[name]
		relevant := selected || lease.spec.Proxy == name
		lease.choiceMu.Unlock()
		if relevant {
			cleanup := lease.prepareClose()
			go cleanup()
		}
	}
}

func (r *appRequestRegistry) privateEndpoint() (string, error) {
	r.privateMu.Lock()
	defer r.privateMu.Unlock()
	r.mu.Lock()
	exiting := r.state.Reason == "exiting"
	r.mu.Unlock()
	if exiting {
		return "", requestscope.ErrBlocked
	}
	if r.privateListener != nil {
		return r.privateListener.Addr().String(), nil
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	r.privateListener = listener
	r.privateConns = map[net.Conn]struct{}{}
	go func() {
		slots := make(chan struct{}, 64)
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			r.privateMu.Lock()
			if r.privateListener != listener {
				r.privateMu.Unlock()
				_ = conn.Close()
				return
			}
			r.privateConns[conn] = struct{}{}
			r.privateMu.Unlock()
			select {
			case slots <- struct{}{}:
			default:
				r.privateMu.Lock()
				delete(r.privateConns, conn)
				r.privateMu.Unlock()
				_ = conn.Close()
				continue
			}
			go func() {
				defer func() {
					_ = conn.Close()
					r.privateMu.Lock()
					delete(r.privateConns, conn)
					r.privateMu.Unlock()
					<-slots
				}()
				proxyHTTP.HandleScopedConn(conn, tunnel.Tunnel, authStore.Nil)
			}()
		}
	}()
	return listener.Addr().String(), nil
}

func (r *appRequestRegistry) closePrivate() {
	r.privateMu.Lock()
	listener := r.privateListener
	r.privateListener = nil
	conns := r.privateConns
	r.privateConns = nil
	r.privateMu.Unlock()
	if listener != nil {
		_ = listener.Close()
	}
	for conn := range conns {
		_ = conn.Close()
	}
}

func beginAppRouteMutation() func() {
	if requestscope.BeginHook == nil {
		return func() {}
	}
	appRequests.mu.Lock()
	appRequests.routeBusy++
	cleanups := appRequests.invalidateLocked()
	appRequests.mu.Unlock()
	go finishRequestCleanup(cleanups)
	return func() {
		appRequests.mu.Lock()
		appRequests.routeBusy--
		appRequests.changedLocked()
		appRequests.mu.Unlock()
	}
}

func (l *appRequestLease) BeforeDial(metadata *C.Metadata) error {
	if err := l.checkNetwork(); err != nil {
		return err
	}
	if l.spec.Kind == "bootstrap" {
		target, err := url.Parse(l.spec.URL)
		if err != nil {
			return requestscope.ErrBlocked
		}
		port := target.Port()
		if port == "" {
			if target.Scheme == "https" {
				port = "443"
			} else if target.Scheme == "http" {
				port = "80"
			}
		}
		if !strings.EqualFold(target.Hostname(), metadata.String()) {
			host := metadata.Host
			if host == "" && metadata.DstIP.IsValid() {
				host = metadata.DstIP.String()
			}
			if !strings.EqualFold(target.Hostname(), host) {
				return requestscope.ErrBlocked
			}
		}
		if port != fmt.Sprint(metadata.DstPort) {
			return requestscope.ErrBlocked
		}
	}
	selectMu.Lock()
	defer selectMu.Unlock()
	if !l.routeCurrentLocked() {
		return requestscope.ErrCancelled
	}
	return l.Check()
}

func directRequestAvailable(state AppRequestState) bool {
	if state.DirectNetworkID == "" || state.ProtectPhase == "starting" || state.ProtectPhase == "retiring" {
		return false
	}
	return state.DefaultNetworkKind == "nonVpn" || state.DefaultNetworkKind == "vpn" && state.ProtectPhase == "ready"
}

func (r *appRequestRegistry) waitFrontendCommits(ctx context.Context) error {
	if requestscope.BeginHook == nil {
		return nil
	}
	for {
		r.mu.Lock()
		busy := false
		for _, receipt := range r.commits {
			if receipt.client != "" {
				busy = true
				break
			}
		}
		changed := r.changed
		r.mu.Unlock()
		if !busy {
			return nil
		}
		select {
		case <-ctx.Done():
			return requestscope.ErrBlocked
		case <-changed:
		}
	}
}

func waitRequestDataCommit() error {
	id, err := beginRequestDataRead()
	if err == nil {
		appRequests.endDataRead(id)
	}
	return err
}

var errRequestCommitBusy = errors.New("request_commit_busy")

func (r *appRequestRegistry) beginDataRead(ctx context.Context) (string, error) {
	id, err := randomRequestToken()
	if err != nil {
		return "", err
	}
	for {
		r.mu.Lock()
		busy := false
		for _, receipt := range r.commits {
			if receipt.client != "" {
				busy = true
				break
			}
		}
		if !busy {
			if r.dataReaders == nil {
				r.dataReaders = make(map[string]struct{})
			}
			r.dataReaders[id] = struct{}{}
			r.mu.Unlock()
			return id, nil
		}
		changed := r.changed
		r.mu.Unlock()
		select {
		case <-ctx.Done():
			return "", requestscope.ErrBlocked
		case <-changed:
		}
	}
}

func (r *appRequestRegistry) endDataRead(id string) {
	r.mu.Lock()
	delete(r.dataReaders, id)
	r.changedLocked()
	r.mu.Unlock()
}

func beginRequestDataRead() (string, error) {
	if requestscope.BeginHook == nil {
		return "", nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	id, err := appRequests.beginDataRead(ctx)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(filepath.Join(C.Path.HomeDir(), "request-recovery-required")); err == nil {
		appRequests.endDataRead(id)
		return "", requestscope.ErrBlocked
	}
	return id, nil
}

func (l *appRequestLease) CheckURL(target string) error {
	if l.spec.Kind == "bootstrap" {
		origin, err := url.Parse(l.spec.URL)
		if err != nil {
			return requestscope.ErrBlocked
		}
		next, err := url.Parse(target)
		if err != nil || !strings.EqualFold(origin.Scheme, next.Scheme) || !strings.EqualFold(origin.Host, next.Host) {
			return requestscope.ErrBlocked
		}
	}
	return l.checkNetwork()
}

func (r *appRequestRegistry) ownerActive(owner requestscope.Owner) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return owner.ID != 0 && owner == r.owner && (r.phase == "inner" || r.phase == "ready")
}

func (r *appRequestRegistry) detachFrontend() {
	r.mu.Lock()
	r.clientReady = false
	uncertain := false
	for _, receipt := range r.commits {
		if receipt.client != "" {
			uncertain = true
			break
		}
	}
	var cleanups []func()
	var leases []*appRequestLease
	if uncertain {
		r.phase = "retired"
		cleanups = r.invalidateLocked()
	} else {
		for _, lease := range r.leases {
			if lease.spec.Client != "" {
				leases = append(leases, lease)
			}
		}
	}
	r.mu.Unlock()
	finishRequestCleanup(cleanups)
	for _, lease := range leases {
		lease.Close()
	}
}
