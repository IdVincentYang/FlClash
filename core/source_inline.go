package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

var errSourceForeground = errors.New("configuration structure requires foreground apply")

func sourceInlineCurrentLocked(p *preparedConfig, request *ConfigInputRequest, keys []string) error {
	if request == nil || request.ExpectedConfig == nil || request.Source.Client == "" || request.Replay || !request.Active || request.Init != nil ||
		p == nil || p != appliedConfig || p != pendingConfig || p.inputVersion != 2 || !p.current() || p.cfg == nil ||
		p.manifest.ManagedPolicy != nil || configFact.Phase != "ready" || !configFact.BusinessActive || p.scope.Check() != nil ||
		requestscope.BeginHook == nil || requestscope.OwnerHook == nil || requestscope.OwnerHook().ID != p.receipt.Owner {
		return errSourceSuperseded
	}
	selectMu.Lock()
	checkpointMu.Lock()
	valid := configFenceMatchesLocked(request.ExpectedConfig)
	appRequests.mu.Lock()
	state, expected := appRequests.state, request.ExpectedRun
	valid = valid && sourceTicketValidLocked(request.Source, keys) && p.dataset == appRequests.dataset && appRequests.owner.ID == p.receipt.Owner && appRequests.phase == "ready" &&
		state.Phase == "started" && state.IntentRunning && !state.Paused && state.ProcessEpoch != "" && state.ProcessEpoch == expected.ProcessEpoch &&
		state.IntentRevision == expected.IntentRevision && state.IntentRunning == expected.IntentRunning && state.Paused == expected.Paused &&
		state.ServiceID == expected.ServiceID && state.ProtectGeneration == expected.ProtectGeneration && state.ProtectPhase == expected.ProtectPhase &&
		state.ServiceID == p.receipt.ServiceID && (p.receipt.ProtectGeneration == 0 && state.ProtectPhase == "none" || p.receipt.ProtectGeneration != 0 && state.ProtectGeneration == p.receipt.ProtectGeneration && state.ProtectPhase == "ready")
	appRequests.mu.Unlock()
	checkpointMu.Unlock()
	selectMu.Unlock()
	if !valid {
		return errSourceSuperseded
	}
	if err := checkSourceUses(C.Path.HomeDir(), p.manifest.SourceUses); err != nil {
		return err
	}
	lease, err := requestscope.Begin(p.scope.Context(), requestscope.Spec{Owner: requestscope.Owner{ID: p.receipt.Owner}, Kind: "provider-local", Key: "source-inline", Resource: filepath.Join(C.Path.HomeDir(), "source-acceptance", "live")})
	if err != nil {
		return err
	}
	qualified, real := lease.(*appRequestLease)
	if !real || qualified == nil || qualified.registry != appRequests || qualified.spec.Owner.ID != p.receipt.Owner || qualified.Check() != nil {
		if lease != nil && (!real || qualified != nil) {
			lease.Close()
		}
		return errSourceSuperseded
	}
	lease.Close()
	return nil
}

func sourceInlineShape(raw *config.RawConfig) string {
	copy := *raw
	copy.Proxy, copy.ProxyGroup = nil, nil
	copy.Rule = nil
	return sourceValueHash(copy)
}

func sourceInlineIntermediate(home string, p *preparedConfig, manifest ConfigManifest) (ConfigManifest, []sourceProviderPlan, []SourceProviderMaterial, error) {
	var root SourceUse
	for _, use := range manifest.SourceUses {
		if use.Kind == "config" {
			root = use
		}
	}
	plans, err := acceptedSourceProviderPlans(home, root, manifest.YAMLSHA256)
	if err != nil || len(plans) != len(p.sourceProviders) {
		return manifest, nil, nil, errSourceReview
	}
	updates := []SourceProviderMaterial{}
	materials := slices.Clone(manifest.ProviderMaterials)
	for i, next := range materials {
		r := p.sourceProviders[next.Use.Key]
		if r == nil || r.plan.Declaration != next.Declaration || r.plan.Kind != next.Kind || r.plan.Name != next.Name {
			return manifest, nil, nil, errSourceForeground
		}
		if r.material.MaterialHash != next.MaterialHash {
			updates = append(updates, next)
			next.MaterialHash, next.Use, next.Origin = r.material.MaterialHash, r.material.Use, r.material.Origin
			materials[i] = next
		}
	}
	derived, err := bindSourceProviderMaterials(home, root, manifest.YAMLSHA256, materials)
	if err != nil {
		return manifest, nil, nil, errSourceForeground
	}
	manifest.ProviderMaterials = materials
	manifest.SourceUses, err = sourceCompositionUses(home, derived)
	if err != nil {
		return manifest, nil, nil, err
	}
	for i := range plans {
		plans[i].Context = derived
	}
	return manifest, plans, updates, nil
}

func adoptSourceInlineRequest(request *ConfigInputRequest) ConfigApplyResult {
	configMu.Lock()
	p := appliedConfig
	configMu.Unlock()
	if p == nil || request == nil {
		return ConfigApplyResult{Status: "superseded"}
	}
	p.sourceSerial.Lock()
	if !configMu.TryLock() {
		p.sourceSerial.Unlock()
		return ConfigApplyResult{Status: "superseded"}
	}
	var updates []SourceProviderMaterial
	var err error
	result := func() ConfigApplyResult {
		defer configMu.Unlock()
		defer p.sourceSerial.Unlock()
		updates, err = adoptSourceInlineLocked(p, request)
		result := configResult("applied", p.receipt, err)
		if err != nil {
			result.Status = "deferred"
			result.RequiresFullApply = errors.Is(err, errSourceForeground)
			if errors.Is(err, errSourceSuperseded) {
				result.Status = "superseded"
			}
		}
		return result
	}()
	if err != nil {
		return result
	}
	for _, update := range updates {
		body, readErr := readSourceObject(C.Path.HomeDir(), update.MaterialHash, sourceCandidateMax)
		if readErr == nil {
			readErr = p.sourceProviders[update.Use.Key].update(body)
		}
		if readErr != nil {
			err = readErr
			break
		}
	}
	configMu.Lock()
	defer configMu.Unlock()
	result = configResult("applied", p.receipt, err)
	if appliedConfig != p || !p.current() || p.scope.Check() != nil {
		result.Status = "superseded"
	} else if err != nil {
		result.Status = "deferred"
	}
	return result
}

func adoptSourceInlineLocked(p *preparedConfig, request *ConfigInputRequest) ([]SourceProviderMaterial, error) {
	if err := sourceInlineCurrentLocked(p, request, p.manifest.Dependencies); err != nil {
		return nil, err
	}
	if p.sourceRecovery != nil {
		return nil, persistSourceMaterialLocked(p)
	}
	home := C.Path.HomeDir()
	if err := pendingSourceMaterialBlocksReplay(home); err != nil {
		return nil, err
	}
	if _, err := os.Stat(filepath.Join(home, "request-recovery-required")); !os.IsNotExist(err) {
		return nil, errSourceReview
	}
	manifest, body, next, parsedHash, err := readConfigInput(home, request.InputID)
	if err != nil {
		return nil, err
	}
	if manifest.Version != 2 || manifest.ManagedPolicy != nil || manifest.ProfileID == nil || p.manifest.ProfileID == nil || *manifest.ProfileID != *p.manifest.ProfileID || manifest.TestURL != p.manifest.TestURL {
		return nil, errSourceForeground
	}
	if err := sourceInlineCurrentLocked(p, request, manifest.Dependencies); err != nil {
		return nil, err
	}
	old, _, err := decodeConfigDocument(p.bytes)
	if err != nil {
		return nil, err
	}
	if err := patchConfigInput(old, p.manifest.AcceptedOverrides); err != nil {
		return nil, err
	}
	if sourceInlineShape(old) != sourceInlineShape(next) {
		return nil, errSourceForeground
	}
	graphChanged := sourceValueHash(old.Proxy) != sourceValueHash(next.Proxy) || sourceValueHash(old.ProxyGroup) != sourceValueHash(next.ProxyGroup)
	rulesChanged := !slices.Equal(old.Rule, next.Rule)
	manifest, plans, updates, err := sourceInlineIntermediate(home, p, manifest)
	if err != nil {
		return nil, err
	}
	if graphChanged && (len(updates) != 0 || rulesChanged) || rulesChanged && len(updates) != 0 {
		return nil, errSourceForeground
	}
	if graphChanged || rulesChanged {
		if reason := sourceInlineReaderReason(); reason != "" {
			return nil, fmt.Errorf("%w: %s", errSourceForeground, reason)
		}
		if graphChanged {
			if reason := sourceNodeFactoryRisk(map[string]any{"proxies": next.Proxy}); reason != "" {
				return nil, fmt.Errorf("%w: %s", errSourceForeground, reason)
			}
		}
	}
	if (graphChanged || rulesChanged) && (p.sourceRetiredCount >= sourceRetiredGenerationLimit || p.sourceRetiredBytes+len(p.bytes)+len(body) > sourceMaterialTotal) {
		return nil, fmt.Errorf("%w: %w", errSourceForeground, errSourceBudget)
	}
	var graph *sourceInlineGraph
	var rules []C.Rule
	if rulesChanged {
		rules, err = prepareSourceInlineRules(p, old, next, manifest.RuleLedger)
		if err != nil {
			return nil, err
		}
	}
	if graphChanged {
		recordSourceRawFactories(next)
		graph, err = func() (*sourceInlineGraph, error) {
			selectMu.Lock()
			defer selectMu.Unlock()
			return prepareSourceInlineGraph(p, old, next)
		}()
		if err != nil {
			return nil, err
		}
	}
	published := false
	defer func() {
		if graph != nil && !published {
			graph.close()
		}
	}()
	selectMu.Lock()
	manifest.SelectedMap, err = checkpointSelectionsLocked()
	if graph != nil && err == nil {
		for name, proxy := range graph.proxies {
			if _, valid := proxy.Adapter().(*outboundgroup.Selector); valid {
				if group, valid := proxy.Adapter().(outboundgroup.ProxyGroup); valid {
					manifest.SelectedMap[name] = group.Now()
				}
			}
		}
	}
	selectMu.Unlock()
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(manifest)
	if err != nil {
		return nil, err
	}
	target := inputHash(encoded)
	if target == p.receipt.InputID {
		return updates, acknowledgeSourceInlineLocked(p, request)
	}
	if err := writeConfigManifest(filepath.Join(inputDirectory(home), target+".json"), encoded); err != nil {
		return nil, err
	}
	transaction, err := randomRequestToken()
	if err != nil {
		return nil, err
	}
	pending := sourceMaterialPending{Version: 1, Transaction: transaction, RuntimeEpoch: configRuntimeEpoch, Owner: requestscope.Owner{ID: p.receipt.Owner}, Token: p.receipt.Token, ParentInput: p.receipt.InputID, TargetInput: target, ProviderKey: "inline:" + sourceValueHash(*manifest.ProfileID), MaterialHash: manifest.YAMLSHA256}
	checkpointMu.Lock()
	err = beginSourceMaterialPending(home, pending)
	checkpointMu.Unlock()
	if err != nil {
		return nil, err
	}
	if err := sourceInlineCurrentLocked(p, request, manifest.Dependencies); err != nil {
		checkpointMu.Lock()
		clearErr := clearSourceMaterialPending(home, pending)
		if clearErr != nil {
			p.eligible = false
			configFact.ReplayEligible = false
			configFact.Version = configFactSequence.Add(1)
		}
		checkpointMu.Unlock()
		return nil, err
	}
	selectMu.Lock()
	checkpointMu.Lock()
	publishSourceTraceState(p, p.receipt.InputID, true)
	if graph != nil {
		tunnel.UpdateProxies(graph.proxies, graph.providers)
		config.SetProxyNameList(graph.names)
		p.cfg.Proxies, p.cfg.Providers = graph.proxies, graph.providers
		graph.retired.input, graph.retired.materialHash = p.receipt.InputID, p.manifest.YAMLSHA256
		p.sourceInlineRetired = append(p.sourceInlineRetired, graph.retired)
	}
	if rulesChanged {
		tunnel.UpdateRules(rules, p.cfg.SubRules, p.cfg.RuleProviders)
		p.cfg.Rules = rules
	}
	if graphChanged || rulesChanged {
		p.sourceRetiredCount++
		p.sourceRetiredBytes += len(p.bytes)
		p.sourceRetiredInputs = append(p.sourceRetiredInputs, p.receipt.InputID)
	}
	p.manifest, p.bytes, p.raw = manifest, body, next
	p.receipt.InputID = target
	p.sources = make(map[string]uint64, len(manifest.Dependencies))
	for _, key := range manifest.Dependencies {
		p.sources[key] = request.Source.Sources[key]
	}
	for _, plan := range plans {
		r := p.sourceProviders[plan.Key]
		r.plan.Parent, r.plan.Context, r.plan.ContextMaterialHash = plan.Parent, plan.Context, plan.ContextMaterialHash
		r.plan.Origin = plan.Origin
		for _, material := range manifest.ProviderMaterials {
			if material.Use.Key == plan.Key {
				r.material = material
			}
		}
	}
	p.sourceRecovery, p.eligible = &pending, false
	configFact.InputID, configFact.YAMLSHA256, configFact.ParsedSHA256 = target, manifest.YAMLSHA256, parsedHash
	configFact.ProfileName = manifest.ProfileName
	configFact.MaterialPending, configFact.ReplayEligible = true, false
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	refreshRouteLocked(graph != nil || rulesChanged)
	checkpointMu.Lock()
	publishSourceTraceState(p, target, false)
	checkpointMu.Unlock()
	selectMu.Unlock()
	published = true
	if graph != nil {
		for _, task := range graph.tasks {
			task()
		}
		for _, pd := range graph.ownedProviders {
			_ = pd.Initial()
		}
	}
	err = persistSourceMaterialLocked(p)
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	return updates, err
}

func acknowledgeSourceInlineLocked(p *preparedConfig, request *ConfigInputRequest) error {
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	appRequests.mu.Lock()
	valid := p.current() && sourceTicketValidLocked(request.Source, p.manifest.Dependencies) && p.dataset == appRequests.dataset
	appRequests.mu.Unlock()
	if !valid || p.scope.Check() != nil {
		return errSourceSuperseded
	}
	unchanged := p.eligible && configFact.ReplayEligible
	for key, revision := range p.sources {
		unchanged = unchanged && request.Source.Sources[key] == revision
	}
	if ref, err := readCheckpointLocked(C.Path.HomeDir()); unchanged && err == nil && ref.InputID == p.receipt.InputID && slices.Equal(ref.Dependencies, p.manifest.Dependencies) {
		return nil
	}
	data, err := json.Marshal(configCheckpoint{Version: 1, InputID: p.receipt.InputID, Dependencies: slices.Clone(p.manifest.Dependencies)})
	if err != nil {
		return err
	}
	if err := writeConfigManifest(filepath.Join(inputDirectory(C.Path.HomeDir()), "checkpoint.json"), data); err != nil {
		p.eligible = false
		configFact.ReplayEligible = false
		configFact.Version = configFactSequence.Add(1)
		return err
	}
	p.sources = make(map[string]uint64, len(p.manifest.Dependencies))
	for _, key := range p.manifest.Dependencies {
		p.sources[key] = request.Source.Sources[key]
	}
	changed := !p.eligible || !configFact.ReplayEligible
	p.eligible, configFact.ReplayEligible = true, true
	if changed {
		configFact.Version = configFactSequence.Add(1)
		sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	}
	return nil
}
