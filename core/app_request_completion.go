package main

import "github.com/metacubex/mihomo/component/requestscope"

const requestCompletionLimit = 128

type appRequestCompletionHold struct {
	spec    requestscope.Spec
	state   AppRequestState
	release func()
}

func (r *appRequestRegistry) sourceVersionLocked(key string) uint64 {
	if key == "" {
		return 0
	}
	value := r.sourceVersions.ensure(key)
	r.revokeExhaustedVersionsLocked()
	return value
}

func (r *appRequestRegistry) operationVersionLocked(key string) uint64 {
	if key == "" {
		return 0
	}
	value := r.operationVersions.ensure(key)
	r.revokeExhaustedVersionsLocked()
	return value
}

func (r *appRequestRegistry) revokeExhaustedVersionsLocked() {
	if !r.versionsRevoked && (r.sourceVersions.exhausted || r.operationVersions.exhausted) {
		r.versionsRevoked = true
		r.sourceVersions.exhausted, r.operationVersions.exhausted = true, true
		r.pendingCleanups = append(r.pendingCleanups, r.invalidateLocked()...)
	}
}

func (r *appRequestRegistry) advanceSourceVersionLocked(key string) uint64 {
	value := r.sourceVersions.advance(key, false)
	r.revokeExhaustedVersionsLocked()
	return value
}

func (r *appRequestRegistry) advanceOperationVersionLocked(key string) uint64 {
	value := r.operationVersions.advance(key, true)
	r.revokeExhaustedVersionsLocked()
	return value
}

func (r *appRequestRegistry) retainSpecVersionsLocked(spec requestscope.Spec) func() {
	var releases []func()
	if spec.Client != "" {
		_, release := r.sourceVersions.retain(spec.Key)
		releases = append(releases, release)
		_, release = r.operationVersions.retain(spec.Key)
		releases = append(releases, release)
	} else if spec.Kind == "geo" || spec.Kind == "geo-batch" {
		_, release := r.operationVersions.retain("internal:" + spec.Kind + ":" + spec.Key)
		releases = append(releases, release)
	}
	return func() {
		for _, release := range releases {
			release()
		}
	}
}

func (r *appRequestRegistry) retainSourceSnapshotLocked(sources map[string]uint64) func() {
	for key, version := range sources {
		if !r.sourceVersions.matches(key, version) {
			return nil
		}
	}
	var releases []func()
	for key := range sources {
		_, release := r.sourceVersions.retain(key)
		releases = append(releases, release)
	}
	return func() {
		for _, release := range releases {
			release()
		}
	}
}

func (p *preparedConfig) releaseSourceVersions() {
	if p == nil {
		return
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	if p.sourcePins != nil {
		p.sourcePins()
		p.sourcePins = nil
	}
}

func (r *appRequestRegistry) pruneCompletionHoldsLocked() {
	for id, hold := range r.completionHolds {
		spec := hold.spec
		source := r.sourceVersions.get(spec.Key)
		next, hasNext := requestVersionSuccessor(spec.SourceRevision)
		valid := r.clientReady && spec.Client == r.client && spec.Dataset == r.dataset && spec.Owner == r.owner &&
			hold.state.ProcessEpoch == r.state.ProcessEpoch && hold.state.Revision == r.state.Revision &&
			r.phase != "failed" && r.phase != "retired" && r.operationVersions.matches(spec.Key, spec.Operation) &&
			(source == spec.SourceRevision || hasNext && source == next)
		if !valid {
			hold.release()
			delete(r.completionHolds, id)
		}
	}
}

func (r *appRequestRegistry) controlCompletion(params appRequestControl) any {
	if params.Action == "releaseCompletion" {
		r.mu.Lock()
		defer r.mu.Unlock()
		if hold := r.completionHolds[params.ID]; hold != nil {
			if params.Client == "" || hold.spec.Client != params.Client {
				return map[string]string{"error": "request_cancelled"}
			}
			hold.release()
			delete(r.completionHolds, params.ID)
		}
		return map[string]bool{"ok": true}
	}
	id, err := randomRequestToken()
	if err != nil {
		return map[string]string{"error": "request_blocked"}
	}
	selectMu.Lock()
	defer selectMu.Unlock()
	r.mu.Lock()
	lease := r.leases[params.ID]
	r.mu.Unlock()
	if lease == nil || !lease.routeCurrentLocked() {
		return map[string]string{"error": "request_cancelled"}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if params.Client == "" || lease.spec.Client != params.Client || !lease.validLocked() || lease.granted || lease.ctx.Err() != nil {
		return map[string]string{"error": "request_cancelled"}
	}
	r.pruneCompletionHoldsLocked()
	if len(r.completionHolds) >= requestCompletionLimit {
		return map[string]string{"error": "request_blocked"}
	}
	r.completionHolds[id] = &appRequestCompletionHold{spec: lease.spec, state: lease.state, release: r.retainSpecVersionsLocked(lease.spec)}
	return map[string]string{"id": id}
}
