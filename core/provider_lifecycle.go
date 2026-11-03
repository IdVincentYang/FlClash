package main

import (
	"path/filepath"
	"sync"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type coreShutdownWork struct {
	once     sync.Once
	done     chan struct{}
	success  bool
	cleaning bool
}

func guardedInitClash(params *InitParams, sequence uint64) bool {
	if sequence == 0 {
		sequence = methodCallSeq.Add(1)
	}
	configMu.Lock()
	defer configMu.Unlock()
	if coreLifecycleUnavailable(sequence) || stageBusyForInit() {
		return false
	}
	if isInit.Load() {
		return filepath.Clean(params.HomeDir) == filepath.Clean(constant.Path.HomeDir())
	}
	initializeCore(params)
	return !coreLifecycleUnavailable(0)
}

func guardedPhysicalShutdown() bool {
	if !providerStageEnabled {
		return false
	}
	stagedCore.Lock()
	defer stagedCore.Unlock()
	return stagedCore.shutdown != nil && stagedCore.shutdown.cleaning
}

func shutdownGuardedCore(sequence uint64) bool {
	if sequence == 0 {
		sequence = methodCallSeq.Add(1)
	}
	noteCoreLifecycleArrival(&MethodCall{Method: shutdownMethod, seq: sequence})
	stagedCore.Lock()
	if sequence <= stagedCore.closedThrough {
		stagedCore.Unlock()
		return true
	}
	work := stagedCore.shutdown
	stagedCore.Unlock()
	work.once.Do(func() { go work.run() })
	timer := time.NewTimer(providerStageTimeout)
	defer timer.Stop()
	select {
	case <-work.done:
		stagedCore.Lock()
		defer stagedCore.Unlock()
		return work.success
	case <-timer.C:
		return false
	}
}

func (work *coreShutdownWork) run() {
	defer func() {
		if recover() != nil {
			stagedCore.Lock()
			work.cleaning = false
			close(work.done)
			stagedCore.Unlock()
		}
	}()
	configMu.Lock()
	stagedCore.Lock()
	stage := stagedCore.stage
	stagedCore.Unlock()
	if stage != nil {
		stage.retire()
	}
	registry := appRequests
	closers := cancelProviderOwner(registry, registry.currentOwner().ID)
	revokeBusiness()
	preparedConfigGate.Store(nil)
	isRunning.Store(false)
	tunnel.OnSuspend()
	checkpointMu.Lock()
	configFact.BusinessActive, configFact.ReplayEligible = false, false
	configFact.Phase = "retired"
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	configMu.Unlock()
	for _, conn := range closers {
		_ = conn.Close()
	}
	if stage != nil {
		<-stage.done
	}
	configMu.Lock()
	stagedCore.Lock()
	if stagedCore.shutdown != work {
		stagedCore.Unlock()
		configMu.Unlock()
		return
	}
	work.cleaning = true
	stagedCore.Unlock()
	configMu.Unlock()
	registry.closePrivate()
	handleStopLog()
	stopRouteWatch()
	closeGlobalCoreResources()
	handleForceGC()
	configMu.Lock()
	stagedCore.Lock()
	currentConfig, pendingConfig, appliedConfig = nil, nil, nil
	isInit.Store(false)
	work.success, work.cleaning = true, false
	stagedCore.closedThrough = methodCallSeq.Load()
	signalStagedCoreLocked()
	close(work.done)
	stagedCore.Unlock()
	configMu.Unlock()
}
