package main

import (
	"encoding/base64"

	C "github.com/metacubex/mihomo/constant"
)

func sourceProviderRequestCurrent(request sourceAcceptanceRequest) bool {
	if request.ExpectedConfig == nil || !sourceAcceptanceCurrent(request) {
		return false
	}
	selectMu.Lock()
	checkpointMu.Lock()
	valid := configFenceMatchesLocked(request.ExpectedConfig)
	checkpointMu.Unlock()
	selectMu.Unlock()
	return valid
}

func inspectSourceProviderRequest(request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	p := appliedConfig
	if p == nil {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	r := p.sourceProviders[request.Key]
	if r == nil || r.plan.Name != request.ProviderName || r.plan.Kind != request.Kind {
		return sourceAcceptanceResult{}, errSourceSuperseded
	}
	if err := sourceProviderCurrentLocked(r); err != nil {
		return sourceAcceptanceResult{}, err
	}
	body, err := readSourceObject(C.Path.HomeDir(), r.material.MaterialHash, sourceCandidateMax)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if pending := pendingSourceReviews[request.Key]; pending != nil && pending.request.Identity == r.plan.Declaration && pending.request.Kind == request.Kind {
		body = pending.body
	}
	if r.plan.Origin != nil {
		if pending := pendingSourceReviews[r.plan.Origin.Key]; pending != nil && pending.request.Identity == r.plan.Origin.Identity && pending.request.Kind == request.Kind {
			body = pending.body
		}
	}
	selectMu.Lock()
	checkpointMu.Lock()
	epoch, picks := routeStamp()
	fence := ConfigFence{RuntimeEpoch: configRuntimeEpoch, Version: configFact.Version, Owner: configFact.Owner, Token: configFact.Token, InputID: configFact.InputID, RouteEpoch: epoch, PicksVersion: picks}
	checkpointMu.Unlock()
	selectMu.Unlock()
	return sourceAcceptanceResult{Status: "provider", Providers: []sourceProviderPlan{r.plan}, BodyBase64: base64.StdEncoding.EncodeToString(body), Config: &fence}, nil
}

func adoptSourceProviderRequest(request sourceAcceptanceRequest) error {
	configMu.Lock()
	p := appliedConfig
	if !isInit.Load() || p == nil || !sourceProviderRequestCurrent(request) {
		configMu.Unlock()
		return errSourceSuperseded
	}
	r := p.sourceProviders[request.Key]
	if r == nil || r.plan.Name != request.ProviderName || r.plan.Kind != request.Kind || request.Use == nil || request.Use.Key != r.plan.Key || request.Use.Kind != r.plan.Kind {
		configMu.Unlock()
		return errSourceSuperseded
	}
	body, err := readSourceObject(C.Path.HomeDir(), request.MaterialHash, sourceCandidateMax)
	if err == nil {
		err = checkSourceUses(C.Path.HomeDir(), []SourceUse{*request.Use})
	}
	configMu.Unlock()
	if err != nil {
		return err
	}
	return r.updateQualified(body, &request)
}
