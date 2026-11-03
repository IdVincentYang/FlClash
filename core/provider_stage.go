package main

import (
	"context"
	"errors"
	"io"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/config"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub"
	RP "github.com/metacubex/mihomo/rules/provider"
)

var providerStageTimeout = 30 * time.Second
var errCoreLifecycleUnavailable = errors.New("Core cleanup is incomplete; initialization is unavailable")
var errZeroTierUnsupported = errors.New("ZeroTier is not supported on Android")
var errProviderInitialization = errors.New("Provider initialization failed; configuration was blocked")

var stagedCore = struct {
	sync.Mutex
	changed       chan struct{}
	stage         *providerStage
	shutdown      *coreShutdownWork
	closedThrough uint64
}{changed: make(chan struct{})}

func signalStagedCoreLocked() {
	close(stagedCore.changed)
	stagedCore.changed = make(chan struct{})
}

func lifecycleUnavailableLocked(sequence uint64) bool {
	return stagedCore.shutdown != nil && !stagedCore.shutdown.success || sequence != 0 && sequence <= stagedCore.closedThrough
}

func coreLifecycleUnavailable(sequence uint64) bool {
	if !providerStageEnabled {
		return false
	}
	stagedCore.Lock()
	defer stagedCore.Unlock()
	return lifecycleUnavailableLocked(sequence)
}

func noteCoreLifecycleArrival(call *MethodCall) {
	if !providerStageEnabled || call.Method != shutdownMethod {
		return
	}
	stagedCore.Lock()
	defer stagedCore.Unlock()
	if call.seq <= stagedCore.closedThrough {
		return
	}
	if stagedCore.shutdown == nil || stagedCore.shutdown.success {
		stagedCore.shutdown = &coreShutdownWork{done: make(chan struct{})}
		signalStagedCoreLocked()
	}
}

func cancelProviderOwner(registry *appRequestRegistry, owner uint64) []io.Closer {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if registry.owner.ID != owner {
		return nil
	}
	registry.phase = "retired"
	registry.permits = map[string]requestscope.Spec{}
	var closers []io.Closer
	for _, lease := range registry.leases {
		lease.closed = true
		lease.cancel()
		for conn := range lease.closers {
			closers = append(closers, conn)
		}
	}
	registry.leases = map[string]*appRequestLease{}
	registry.latest = map[string]*appRequestLease{}
	registry.changedLocked()
	return closers
}

type providerInitial struct {
	mu       sync.Mutex
	stage    *providerStage
	initial  func() error
	close    func() error
	done     chan struct{}
	state    uint8
	err      error
	ctx      context.Context
	cancel   context.CancelFunc
	stopLink func() bool
}

func (entry *providerInitial) Initial() error {
	entry.mu.Lock()
	if entry.state != 0 {
		entry.mu.Unlock()
		<-entry.done
		return entry.err
	}
	entry.state = 1
	entry.mu.Unlock()
	err := func() (failure error) {
		defer func() {
			if recover() != nil {
				failure = errProviderInitialization
			}
		}()
		return entry.initial()
	}()
	entry.mu.Lock()
	entry.err, entry.state = err, 2
	close(entry.done)
	entry.mu.Unlock()
	if err != nil {
		failure := capabilityError(err)
		if failure != errZeroTierUnsupported {
			failure = errProviderInitialization
		}
		entry.stage.fail(failure)
	}
	entry.stage.initials.Done()
	return err
}

func (entry *providerInitial) seal() {
	entry.mu.Lock()
	defer entry.mu.Unlock()
	entry.cancel()
	if entry.state == 0 {
		entry.state, entry.err = 2, context.Canceled
		close(entry.done)
		entry.stage.initials.Done()
	}
}

type stagedProxyProvider struct {
	*provider.ProxySetProvider
	entry *providerInitial
}

func (p *stagedProxyProvider) Initial() error                  { return p.entry.Initial() }
func (p *stagedProxyProvider) Close() error                    { p.entry.stage.retire(); return nil }
func (p *stagedProxyProvider) RequestContext() context.Context { return p.entry.ctx }
func (p *stagedProxyProvider) underlyingProvider() P.Provider  { return p.ProxySetProvider }

type stagedRuleProvider struct {
	*RP.RuleSetProvider
	entry *providerInitial
}

func (p *stagedRuleProvider) Strategy() any {
	select {
	case <-p.entry.done:
		return p.RuleSetProvider.Strategy()
	default:
		return nil
	}
}

func (p *stagedRuleProvider) Initial() error                  { return p.entry.Initial() }
func (p *stagedRuleProvider) Close() error                    { p.entry.stage.retire(); return nil }
func (p *stagedRuleProvider) RequestContext() context.Context { return p.entry.ctx }
func (p *stagedRuleProvider) underlyingProvider() P.Provider  { return p.RuleSetProvider }

type providerStage struct {
	receipt   ConfigReceipt
	scope     *requestscope.BusinessScope
	registry  *appRequestRegistry
	ctx       context.Context
	cancel    context.CancelFunc
	task      chan *config.Config
	setup     chan struct{}
	setupOnce sync.Once
	// ready seals Apply and required Initial completion; it is not activation.
	ready chan struct{}
	// done releases admission only after owned cleanup really returns.
	done        chan struct{}
	failed      chan struct{}
	initials    sync.WaitGroup
	mu          sync.Mutex
	entries     []*providerInitial
	err         error
	retired     bool
	abandoned   bool
	networkDone chan struct{}
	stopScope   func() bool
}

func newProviderStage(p *preparedConfig) *providerStage {
	ctx, cancel := context.WithCancel(p.scope.Context())
	s := &providerStage{receipt: p.receipt, scope: p.scope, registry: appRequests, ctx: ctx, cancel: cancel,
		task: make(chan *config.Config, 1), setup: make(chan struct{}), ready: make(chan struct{}), done: make(chan struct{}), failed: make(chan struct{}), networkDone: make(chan struct{})}
	s.stopScope = context.AfterFunc(p.scope.Context(), s.retire)
	return s
}

func (s *providerStage) fail(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err == nil {
		s.err = err
		close(s.failed)
	}
}

func (s *providerStage) failure() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.err
}

func (s *providerStage) retire() {
	s.mu.Lock()
	if s.retired || s.abandoned {
		s.mu.Unlock()
		return
	}
	s.retired = true
	entries := append([]*providerInitial(nil), s.entries...)
	s.cancel()
	s.mu.Unlock()
	s.scope.Close()
	closers := cancelProviderOwner(s.registry, s.receipt.Owner)
	for _, entry := range entries {
		entry.seal()
	}
	go func() {
		defer close(s.networkDone)
		for _, conn := range closers {
			_ = conn.Close()
		}
	}()
}

// Bootstrap retry keeps the same owner; ordinary retirement must cancel it.
func (s *providerStage) abandon() {
	s.mu.Lock()
	if s.retired {
		s.mu.Unlock()
		return
	}
	s.abandoned = true
	s.stopScope()
	s.cancel()
	s.mu.Unlock()
}

func (s *providerStage) add(original interface {
	P.Provider
	RequestContext() context.Context
	Close() error
}) *providerInitial {
	ctx, cancel := context.WithCancel(original.RequestContext())
	entry := &providerInitial{stage: s, initial: original.Initial, close: original.Close, done: make(chan struct{}), ctx: ctx, cancel: cancel}
	entry.stopLink = context.AfterFunc(s.ctx, cancel)
	s.mu.Lock()
	s.entries = append(s.entries, entry)
	s.initials.Add(1)
	retired := s.retired
	s.mu.Unlock()
	if retired {
		entry.seal()
	}
	return entry
}

func (s *providerStage) wrap(cfg *config.Config) {
	for name, p := range cfg.Providers {
		if original, ok := p.(*provider.ProxySetProvider); ok {
			cfg.Providers[name] = &stagedProxyProvider{original, s.add(original)}
		}
	}
	for name, p := range cfg.RuleProviders {
		if original, ok := p.(*RP.RuleSetProvider); ok {
			cfg.RuleProviders[name] = &stagedRuleProvider{original, s.add(original)}
		}
	}
}

func (s *providerStage) run() {
	defer func() {
		if recover() != nil {
			s.fail(errProviderInitialization)
			return
		}
		stagedCore.Lock()
		if stagedCore.stage == s {
			stagedCore.stage = nil
			signalStagedCoreLocked()
		}
		close(s.done)
		stagedCore.Unlock()
	}()
	<-s.setup
	cfg := <-s.task
	if cfg != nil && s.ctx.Err() == nil {
		func() {
			defer func() {
				if recover() != nil {
					s.fail(errProviderInitialization)
					s.retire()
				}
			}()
			dnsListen := cfg.DNS.Listen
			cfg.DNS.Listen = ""
			defer func() { cfg.DNS.Listen = dnsListen }()
			hub.ApplyConfigStaged(cfg)
		}()
	} else {
		s.mu.Lock()
		entries := append([]*providerInitial(nil), s.entries...)
		s.mu.Unlock()
		for _, entry := range entries {
			entry.seal()
		}
	}
	s.initials.Wait()
	close(s.ready)
	<-s.ctx.Done()
	s.mu.Lock()
	abandoned := s.abandoned
	entries := append([]*providerInitial(nil), s.entries...)
	s.mu.Unlock()
	if !abandoned {
		s.retire()
		<-s.networkDone
	}
	for _, entry := range entries {
		entry.stopLink()
		entry.cancel()
		_ = entry.close()
	}
	if cfg != nil {
		cfg.CloseProviders()
	}
	s.stopScope()
}

func (s *providerStage) start(cfg *config.Config) {
	s.setupOnce.Do(func() { s.task <- cfg; close(s.setup) })
}

func capabilityError(err error) error {
	if !providerStageEnabled || err == nil {
		return err
	}
	leaf := err
	for errors.Unwrap(leaf) != nil {
		leaf = errors.Unwrap(leaf)
	}
	if leaf.Error() == "ZeroTier support is disabled by \"no_zerotier\" build tag" {
		return errZeroTierUnsupported
	}
	return err
}

func underlyingProvider(p P.Provider) P.Provider {
	if wrapped, ok := p.(interface{ underlyingProvider() P.Provider }); ok {
		return wrapped.underlyingProvider()
	}
	return p
}

func waitProviderSignal(s *providerStage, deadline time.Time) error {
	timer := time.NewTimer(time.Until(deadline))
	defer timer.Stop()
	for {
		s.registry.mu.Lock()
		changed := s.registry.changed
		s.registry.mu.Unlock()
		configMu.Lock()
		_, err := pendingForReceipt(s.receipt)
		unavailable := coreLifecycleUnavailable(0)
		configMu.Unlock()
		if err != nil || unavailable {
			return errConfigSuperseded
		}
		select {
		case <-s.ready:
			return s.failure()
		case <-s.failed:
			return s.failure()
		case <-s.ctx.Done():
			return context.Canceled
		case <-changed:
		case <-timer.C:
			return errors.New("Provider initialization timed out; configuration was blocked")
		}
	}
}

func reserveProviderStage(p *preparedConfig, deadline time.Time) (*providerStage, error) {
	timer := time.NewTimer(time.Until(deadline))
	defer timer.Stop()
	for {
		stagedCore.Lock()
		if lifecycleUnavailableLocked(p.receipt.Token) {
			stagedCore.Unlock()
			return nil, errCoreLifecycleUnavailable
		}
		if stagedCore.stage == nil {
			s := newProviderStage(p)
			stagedCore.stage = s
			stagedCore.Unlock()
			go s.run()
			return s, nil
		}
		old, changed := stagedCore.stage, stagedCore.changed
		if old.scope == p.scope && old.ctx.Err() == nil {
			stagedCore.Unlock()
			return old, nil
		}
		stagedCore.Unlock()
		old.retire()
		select {
		case <-changed:
		case <-p.scope.Context().Done():
			return nil, context.Canceled
		case <-timer.C:
			return nil, errCoreLifecycleUnavailable
		}
	}
}

func installGuardedConfig(receipt ConfigReceipt) ConfigApplyResult {
	deadline := time.Now().Add(providerStageTimeout)
	configMu.Lock()
	p, err := pendingForReceipt(receipt)
	if err != nil {
		result := supersededConfigResult(receipt, err)
		configMu.Unlock()
		return result
	}
	if p.stage != nil {
		s := p.stage
		configMu.Unlock()
		return finishGuardedInstall(p, s, deadline)
	}
	configMu.Unlock()
	s, err := reserveProviderStage(p, deadline)
	configMu.Lock()
	defer configMu.Unlock()
	if err != nil {
		return blockConfigLocked(p, err)
	}
	if p.stage != nil {
		configMu.Unlock()
		result := finishGuardedInstall(p, p.stage, deadline)
		configMu.Lock()
		return result
	}
	defer func() { s.start(nil) }()
	if _, err = pendingForReceipt(receipt); err != nil || coreLifecycleUnavailable(0) {
		s.retire()
		return supersededConfigResult(receipt, errConfigSuperseded)
	}
	p.stage = s
	prepared, result := prepareInstallLocked(receipt)
	if result != nil {
		if result.Status == "bootstrapRequired" {
			s.abandon()
			p.stage = nil
		} else {
			s.retire()
		}
		return *result
	}
	s.wrap(prepared.cfg)
	s.start(prepared.cfg)
	configMu.Unlock()
	resultValue := finishGuardedInstall(p, s, deadline)
	configMu.Lock()
	return resultValue
}

func finishGuardedInstall(p *preparedConfig, s *providerStage, deadline time.Time) ConfigApplyResult {
	err := waitProviderSignal(s, deadline)
	configMu.Lock()
	defer configMu.Unlock()
	if pendingConfig != p || !p.current() {
		s.retire()
		return configResult("superseded", s.receipt, errConfigSuperseded)
	}
	if err != nil || time.Now().After(deadline) || coreLifecycleUnavailable(0) || s.ctx.Err() != nil {
		if err == nil {
			err = errCoreLifecycleUnavailable
		}
		return blockConfigLocked(p, capabilityError(err))
	}
	if _, err = pendingForReceipt(s.receipt); err != nil {
		return supersededConfigResult(s.receipt, err)
	}
	if configFact.Phase == "installed" || configFact.Phase == "ready" {
		return configResult("installed", s.receipt, nil)
	}
	return finishInstallLocked(p)
}

func stageReady(p *preparedConfig) bool {
	if !providerStageEnabled {
		return true
	}
	if p.stage == nil || p.stage.ctx.Err() != nil || p.stage.failure() != nil || coreLifecycleUnavailable(0) {
		return false
	}
	select {
	case <-p.stage.ready:
		return true
	default:
		return false
	}
}

func stageBusyForInit() bool {
	stagedCore.Lock()
	defer stagedCore.Unlock()
	if lifecycleUnavailableLocked(0) {
		return true
	}
	if stagedCore.stage == nil {
		return false
	}
	select {
	case <-stagedCore.stage.ready:
		return stagedCore.stage.ctx.Err() != nil
	default:
		return true
	}
}
