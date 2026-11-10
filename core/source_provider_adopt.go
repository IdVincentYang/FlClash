package main

import (
	"encoding/json"
	"github.com/metacubex/mihomo/component/requestscope"
	"io"
	"maps"
	"os"
	"path/filepath"
	"slices"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func (r *sourceProviderRuntime) adoptLocked(body []byte, use SourceUse, hash string, origin SourceUse) error {
	p, home := r.parent, C.Path.HomeDir()
	oldBody, err := readSourceObject(home, r.material.MaterialHash, sourceCandidateMax)
	if err != nil {
		return err
	}
	if p.sourceRetiredCount >= sourceRetiredGenerationLimit || p.sourceRetiredBytes+len(oldBody)+len(body) > sourceMaterialTotal {
		return errSourceBudget
	}
	material := r.material
	material.MaterialHash, material.Use, material.Origin = hash, use, origin
	checkpointMu.Lock()
	manifest := p.manifest
	manifest.SelectedMap = maps.Clone(p.manifest.SelectedMap)
	manifest.AcceptedOverrides = maps.Clone(p.manifest.AcceptedOverrides)
	manifest.ProviderMaterials = slices.Clone(p.manifest.ProviderMaterials)
	manifest.SourceUses = slices.Clone(p.manifest.SourceUses)
	parentInput := configFact.InputID
	checkpointMu.Unlock()
	var root SourceUse
	for _, dependency := range manifest.SourceUses {
		if dependency.Kind == "config" {
			root = dependency
		}
	}
	for i, previous := range manifest.ProviderMaterials {
		if previous.Use.Key == use.Key {
			manifest.ProviderMaterials[i] = material
		}
	}
	for i, previous := range manifest.SourceUses {
		if previous == r.material.Use {
			manifest.SourceUses[i] = material.Use
		}
	}
	refresh, err := prepareLocalGroupRefresh(home, p, manifest)
	if err != nil {
		return err
	}
	publishedGraph := false
	defer func() {
		if refresh != nil && !publishedGraph {
			refresh.graph.close()
		}
	}()
	if refresh != nil {
		if p.sourceRetiredBytes+len(oldBody)+len(body)+len(p.bytes)+len(refresh.body) > sourceMaterialTotal {
			return errSourceBudget
		}
		manifest = refresh.manifest
		for _, updated := range manifest.ProviderMaterials {
			if updated.Use.Key == material.Use.Key {
				material = updated
			}
		}
	} else {
		derived, err := bindSourceProviderMaterials(home, root, manifest.YAMLSHA256, manifest.ProviderMaterials)
		if err != nil {
			return err
		}
		manifest.SourceUses, err = sourceCompositionUses(home, derived)
		if err != nil {
			return err
		}
	}
	data, err := json.Marshal(manifest)
	if err != nil {
		return err
	}
	target := inputHash(data)
	if err := writeConfigManifest(filepath.Join(inputDirectory(home), target+".json"), data); err != nil {
		return err
	}
	var generation *sourceRuleGeneration
	if r.rule != nil {
		format, _ := r.plan.Mapping["format"].(string)
		behavior, _ := r.plan.Mapping["behavior"].(string)
		generation, err = prepareSourceRuleGeneration(p.scope.Context(), home, hash, format, behavior, use, nil)
		if err != nil {
			return err
		}
	}
	published := false
	defer func() {
		if generation != nil && !published {
			generation.close()
		}
	}()
	transaction, err := randomRequestToken()
	if err != nil {
		return err
	}
	pending := sourceMaterialPending{Version: 1, Transaction: transaction, RuntimeEpoch: configRuntimeEpoch, Owner: requestscope.Owner{ID: p.receipt.Owner}, Token: p.receipt.Token,
		ParentInput: parentInput, TargetInput: target, ProviderKey: r.plan.Key, MaterialHash: hash}
	checkpointMu.Lock()
	err = beginSourceMaterialPending(home, pending)
	checkpointMu.Unlock()
	if err != nil {
		return err
	}
	defer func() {
		if !published && pendingSourceMaterialBlocksReplay(home) != nil {
			checkpointMu.Lock()
			p.eligible = false
			configFact.ReplayEligible = false
			configFact.Version = configFactSequence.Add(1)
			checkpointMu.Unlock()
			sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
		}
	}()
	previousTrace := p.sourceTrace.Load()
	checkpointMu.Lock()
	publishSourceTraceState(p, parentInput, true)
	checkpointMu.Unlock()
	if r.rule != nil {
		err = r.rule.publish(generation)
	} else {
		previous := slices.Clone(r.proxy.Proxies())
		document, projectionErr := sourceProviderProxyDocument(body, r.plan.Mapping)
		if projectionErr != nil {
			return projectionErr
		}
		recordSourceNodeFactories(document)
		_, _, err = r.proxy.ProxySetProvider.SideUpdate(body)
		if err == nil {
			r.retiredProxies = append(r.retiredProxies, previous)
		}
	}
	if err != nil {
		cache := sourceProviderCache(home, p.receipt.Owner, r.material)
		if r.rule == nil {
			actual, cacheErr := boundedSourceProviderCache(cache)
			if cacheErr != nil || inputHash(actual) != r.material.MaterialHash {
				return err
			}
		}
		checkpointMu.Lock()
		clearErr := clearSourceMaterialPending(home, pending)
		checkpointMu.Unlock()
		if clearErr != nil {
			return clearErr
		}
		p.sourceTrace.Store(previousTrace)
		return err
	}
	published = true
	r.material = material
	path := sourceObjectPath(home, hash)
	r.viewPath.Store(&path)
	p.sourceRetiredCount++
	p.sourceRetiredBytes += len(oldBody)
	checkpointMu.Lock()
	p.sourceRetiredInputs = append(p.sourceRetiredInputs, parentInput)
	if refresh != nil {
		checkpointMu.Unlock()
		selectMu.Lock()
		checkpointMu.Lock()
		tunnel.UpdateProxies(refresh.graph.proxies, refresh.graph.providers)
		config.SetProxyNameList(refresh.graph.names)
		p.cfg.Proxies, p.cfg.Providers = refresh.graph.proxies, refresh.graph.providers
		refresh.graph.retired.input, refresh.graph.retired.materialHash = parentInput, p.manifest.YAMLSHA256
		p.sourceInlineRetired = append(p.sourceInlineRetired, refresh.graph.retired)
		p.sourceRetiredBytes += len(p.bytes)
		p.bytes, p.raw = refresh.body, refresh.raw
		configFact.YAMLSHA256, configFact.ParsedSHA256 = manifest.YAMLSHA256, refresh.parsedHash
		checkpointMu.Unlock()
		refreshRouteLocked(true)
		selectMu.Unlock()
		checkpointMu.Lock()
		publishedGraph = true
	}
	p.manifest = manifest
	p.receipt.InputID = target
	p.sourceRecovery = &pending
	p.eligible = false
	configFact.InputID = target
	configFact.MaterialPending = true
	configFact.ReplayEligible = false
	configFact.Version = configFactSequence.Add(1)
	publishSourceTraceState(p, target, false)
	checkpointMu.Unlock()
	if refresh != nil {
		for _, task := range refresh.graph.tasks {
			task()
		}
		for _, pd := range refresh.graph.ownedProviders {
			_ = pd.Initial()
		}
		var root SourceUse
		for _, use := range manifest.SourceUses {
			if use.Kind == "config" {
				root = use
			}
		}
		plans, err := acceptedSourceProviderPlans(home, root, manifest.YAMLSHA256)
		if err != nil {
			return err
		}
		for _, plan := range plans {
			if runtime := p.sourceProviders[plan.Key]; runtime != nil {
				runtime.plan = plan
				for _, material := range manifest.ProviderMaterials {
					if material.Use.Key == plan.Key {
						runtime.material = material
					}
				}
			}
		}
	}
	err = persistSourceMaterialLocked(p)
	if r.rule != nil {
		// Callback consumers reenter parent state, so notification cannot run under configMu.
		go func() {
			configMu.Lock()
			valid := r.parent == appliedConfig && r.parent.scope.Context().Err() == nil && r.rule.current.Load() == generation
			configMu.Unlock()
			if valid {
				tunnel.Tunnel.RuleUpdateCallback().Emit(r.rule)
			}
		}()
	}
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	return err
}

func boundedSourceProviderCache(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(io.LimitReader(f, sourceCandidateMax+1))
}

func persistSourceMaterialLocked(p *preparedConfig) error {
	pending := p.sourceRecovery
	if pending == nil {
		return nil
	}
	if _, err := os.Stat(filepath.Join(C.Path.HomeDir(), "request-recovery-required")); !os.IsNotExist(err) {
		return errSourceReview
	}
	if appliedConfig != p || !p.current() || configFact.Owner != pending.Owner.ID || p.receipt.Token != pending.Token || p.scope.Check() != nil {
		return errSourceSuperseded
	}
	if err := checkSourceUses(C.Path.HomeDir(), p.manifest.SourceUses); err != nil {
		return err
	}
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	actual, err := readSourceMaterialPending(C.Path.HomeDir())
	data, marshalErr := json.Marshal(p.manifest)
	if marshalErr != nil {
		return marshalErr
	}
	target := inputHash(data)
	next := *pending
	next.TargetInput = target
	if err != nil || actual == nil || *actual != *pending && *actual != next || target != configFact.InputID {
		return errSourceSuperseded
	}
	if next != *pending {
		if err := writeConfigManifest(filepath.Join(inputDirectory(C.Path.HomeDir()), target+".json"), data); err != nil {
			return err
		}
		barrier, err := json.Marshal(next)
		if err != nil {
			return err
		}
		if err := writeSourcePending(sourceMaterialPendingPath(C.Path.HomeDir()), barrier); err != nil {
			return err
		}
		p.sourceRecovery = &next
		pending = &next
	}
	data, err = json.Marshal(configCheckpoint{Version: 1, InputID: pending.TargetInput, Dependencies: slices.Clone(p.manifest.Dependencies)})
	if err != nil {
		return err
	}
	if err := writeConfigManifest(filepath.Join(inputDirectory(C.Path.HomeDir()), "checkpoint.json"), data); err != nil {
		return err
	}
	if err := clearSourceMaterialPending(C.Path.HomeDir(), *pending); err != nil {
		return err
	}
	p.sourceRecovery = nil
	p.receipt.InputID = pending.TargetInput
	p.eligible = true
	configFact.MaterialPending = false
	configFact.ReplayEligible = true
	configFact.Version = configFactSequence.Add(1)
	return nil
}
