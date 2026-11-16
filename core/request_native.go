package main

import (
	"sync"
	"sync/atomic"
)

var requestNativeFault atomic.Bool

// A local scope tracks only this invocation's lock; panic veto precedes unlock.
type requestLockScope struct {
	mu   sync.Locker
	held bool
}

func (s *requestLockScope) Lock()   { s.mu.Lock(); s.held = true }
func (s *requestLockScope) Unlock() { s.held = false; s.mu.Unlock() }

func (s *requestLockScope) finish() {
	failure := recover()
	if failure != nil {
		requestNativeFault.Store(true)
	}
	if s.held {
		s.Unlock()
	}
	if failure != nil {
		panic(failure)
	}
}

func requestFaultCleanup(action string) bool {
	switch action {
	case "cancel", "endRead", "releaseCompletion", "complete", "detach", "engineDetach", "block", "flush", "markRecovery":
		return true
	}
	return false
}
