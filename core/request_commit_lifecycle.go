package main

import (
	"errors"
	"sync/atomic"

	C "github.com/metacubex/mihomo/constant"
)

const frontendCommitLimit = 16

// A registry or JNI reinitialization does not join Dart file/DB writers.
var unknownRequestWriters atomic.Int32
var errRequestWriterUnknown = errors.New("request_restart_required")

func requestWriterError() error {
	if requestNativeFault.Load() || unknownRequestWriters.Load() != 0 {
		return errRequestWriterUnknown
	}
	return nil
}

func (r *appRequestRegistry) frontendCommitCountLocked() int {
	count := 0
	for _, receipt := range r.commits {
		if receipt.client != "" && !receipt.retired {
			count++
		}
	}
	return count
}

func (r *appRequestRegistry) retireFrontendCommitsLocked() bool {
	uncertain := false
	for id, receipt := range r.commits {
		if receipt.client == "" {
			continue
		}
		if !receipt.begun {
			delete(r.commits, id)
			if receipt.releaseVersions != nil {
				receipt.releaseVersions()
				receipt.releaseVersions = nil
			}
			_ = finishSourceMaterialCommit(receipt)
			continue
		}
		uncertain = true
		if !receipt.retired {
			receipt.retired, receipt.failed = true, true
			unknownRequestWriters.Add(1)
		}
	}
	r.changedLocked()
	return uncertain
}

func (r *appRequestRegistry) discardDetachedSourceReviews() {
	registryLock := requestLockScope{mu: &r.mu}
	defer registryLock.finish()

	registryLock.Lock()

	for key, candidate := range pendingSourceReviews {
		if candidate.request.Source.Client == "" || candidate.request.Source.Client != r.client {
			continue
		}
		receiptID := candidate.request.Session
		if candidate.material != nil && candidate.material.receipt != "" {
			receiptID = candidate.material.receipt
		}
		if receipt := r.commits[receiptID]; receipt != nil && receipt.begun {
			continue
		}
		if candidate.material != nil {
			releaseSourceMaterialLease(candidate.material.lease, candidate.request.Source.Client)
		}
		delete(pendingSourceReviews, key)
	}
}

func (r *appRequestRegistry) retireFrontendQualification() {
	checkpointLock := requestLockScope{mu: &checkpointMu}
	defer checkpointLock.finish()

	checkpointLock.Lock()

	_ = ensureRequestRecoveryMarker(C.Path.HomeDir())
	_ = invalidateConfigCheckpointLocked("", true)
	if scope := activeBusiness.Load(); scope != nil {
		cancel := scope.Invalidate()
		cancel()
		safeGoDetached("retire unknown writer business", func() { retireOwnedBusiness(scope) })
	}
}
