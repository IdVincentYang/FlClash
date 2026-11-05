package main

import (
	"encoding/base64"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

type sourceProviderRuntime struct {
	status         atomic.Pointer[string]
	viewPath       atomic.Pointer[string]
	closeOnce      sync.Once
	parent         *preparedConfig
	plan           sourceProviderPlan
	material       SourceProviderMaterial
	proxy          *sourceProxyProvider
	rule           *sourceRuleProvider
	retiredProxies [][]C.Proxy
	retiredBytes   int
	once           sync.Once
}

type sourceProxyProvider struct {
	*provider.ProxySetProvider
	runtime *sourceProviderRuntime
	entry   *providerInitial
}

func (p *sourceProxyProvider) Initial() error {
	if p.entry != nil {
		return p.entry.Initial()
	}
	return p.ProxySetProvider.Initial()
}
func (p *sourceProxyProvider) Update() error                      { return p.runtime.update(nil) }
func (p *sourceProxyProvider) VehicleType() P.VehicleType         { return p.runtime.vehicleType() }
func (p *sourceProxyProvider) underlyingProvider() P.Provider     { return p.ProxySetProvider }
func (p *sourceProxyProvider) sourceSideUpdate(body []byte) error { return p.runtime.update(body) }
func (p *sourceProxyProvider) sourceExternalProvider() *ExternalProvider {
	path := p.runtime.sourceViewPath()
	return &ExternalProvider{Name: p.Name(), Type: p.Type().String(), VehicleType: p.VehicleType().String(), Count: p.Count(), UpdateAt: p.UpdatedAt(), Path: path, SubscriptionInfo: p.GetSubscriptionInfo(), SourceKey: p.runtime.plan.Key, SourceStatus: p.runtime.sourceStatus()}
}
func (p *sourceProxyProvider) Close() error {
	p.runtime.closeOnce.Do(func() {
		p.runtime.parent.sourceSerial.Lock()
		defer p.runtime.parent.sourceSerial.Unlock()
		_ = p.ProxySetProvider.Close()
		for _, generation := range append(p.runtime.retiredProxies, p.Proxies()) {
			for _, proxy := range generation {
				_ = proxy.Close()
			}
		}
		p.runtime.retiredProxies = nil
	})
	return nil
}

func (r *sourceProviderRuntime) vehicleType() P.VehicleType {
	if r.plan.Mapping["type"] == "http" {
		return P.HTTP
	}
	return P.File
}

func prepareSourceProviders(p *preparedConfig) error {
	if p.manifest.Version != 2 || len(p.manifest.ProviderMaterials) == 0 {
		return nil
	}
	if requestscope.BeginHook == nil || requestscope.OwnerHook == nil || requestscope.OwnerHook().ID != p.receipt.Owner {
		return errSourceSuperseded
	}
	var root SourceUse
	for _, use := range p.manifest.SourceUses {
		if use.Kind == "config" {
			root = use
		}
	}
	plans, err := acceptedSourceProviderPlans(C.Path.HomeDir(), root, p.manifest.YAMLSHA256)
	if err != nil {
		return err
	}
	p.sourceProviders = map[string]*sourceProviderRuntime{}
	for _, material := range p.manifest.ProviderMaterials {
		var plan sourceProviderPlan
		for _, candidate := range plans {
			if candidate.Key == material.Use.Key {
				plan = candidate
				break
			}
		}
		if plan.Key == "" {
			return errSourceReview
		}
		for _, use := range p.manifest.SourceUses {
			if use.Kind == "config" {
				plan.Context = use
			}
		}
		plan.ContextMaterialHash = p.manifest.YAMLSHA256
		lease, err := requestscope.Begin(p.scope.Context(), requestscope.Spec{Owner: requestscope.Owner{ID: p.receipt.Owner}, Kind: "provider-local", Key: "source-prepare:" + plan.Key, Resource: sourceProviderCache(C.Path.HomeDir(), p.receipt.Owner, material)})
		if err != nil {
			return err
		}
		qualified, valid := lease.(*appRequestLease)
		if !valid || qualified == nil || qualified.registry != appRequests || qualified.Check() != nil {
			if lease != nil && (!valid || qualified != nil) {
				lease.Close()
			}
			return errSourceSuperseded
		}
		lease.Close()
		p.sourceProviders[plan.Key] = &sourceProviderRuntime{parent: p, plan: plan, material: material}
	}
	return projectSourceProviderFiles(C.Path.HomeDir(), p)
}

func sourcePreparationAllowedLocked(registry *appRequestRegistry, spec requestscope.Spec) bool {
	p := pendingConfig
	if spec.Kind != "provider-local" || spec.Proxy != "" || spec.Owner.ID == 0 || spec.Owner != registry.owner || p == nil || p.receipt.Owner != spec.Owner.ID || p.manifest.Version != 2 || !p.current() || p.scope.Context().Err() != nil {
		return false
	}
	root := filepath.Join(C.Path.HomeDir(), "source-acceptance", "live", strconv.FormatUint(spec.Owner.ID, 10))
	relative, err := filepath.Rel(root, spec.Resource)
	return err == nil && relative != "." && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && (spec.URL == "" || strings.HasPrefix(spec.URL, "file://") || strings.HasPrefix(spec.URL, "source-accepted://"))
}

func installSourceProviders(p *preparedConfig) error {
	for _, r := range p.sourceProviders {
		path := sourceObjectPath(C.Path.HomeDir(), r.material.MaterialHash)
		r.viewPath.Store(&path)
		if r.plan.Kind == "provider-proxy" {
			original, valid := p.cfg.Providers[r.plan.Name].(*provider.ProxySetProvider)
			if !valid {
				return errSourceReview
			}
			wrapper := &sourceProxyProvider{ProxySetProvider: original, runtime: r}
			if p.stage != nil {
				wrapper.entry = p.stage.add(original)
			}
			r.proxy = wrapper
			p.cfg.Providers[r.plan.Name] = wrapper
		} else {
			format, _ := r.plan.Mapping["format"].(string)
			behavior, _ := r.plan.Mapping["behavior"].(string)
			reserved := map[string]bool{}
			for name := range p.cfg.RuleProviders {
				reserved[name] = true
			}
			g, err := prepareSourceRuleGeneration(p.scope.Context(), C.Path.HomeDir(), r.material.MaterialHash, format, behavior, r.material.Use, reserved)
			if err != nil {
				return err
			}
			if original, valid := p.cfg.RuleProviders[r.plan.Name].(io.Closer); valid {
				_ = original.Close()
			}
			r.rule = newSourceRuleProvider(p.scope.Context(), r.plan.Name, r.vehicleType(), g, func() error { return r.update(nil) })
			r.rule.sideUpdate = r.update
			r.rule.external = func() *ExternalProvider {
				path := r.sourceViewPath()
				return &ExternalProvider{Name: r.rule.Name(), Type: r.rule.Type().String(), VehicleType: r.rule.VehicleType().String(), Count: r.rule.Count(), UpdateAt: r.rule.current.Load().loaded, Path: path, SourceKey: r.plan.Key, SourceStatus: r.sourceStatus()}
			}
			p.cfg.RuleProviders[r.plan.Name] = r.rule
		}
	}
	return nil
}

func sourceProviderCurrentLocked(r *sourceProviderRuntime) error {
	p := r.parent
	if requestscope.BeginHook == nil || requestscope.OwnerHook == nil || requestscope.OwnerHook().ID != p.receipt.Owner {
		return errSourceSuperseded
	}
	if appliedConfig != p || !p.current() || configFact.Phase != "ready" || !p.eligible && p.sourceRecovery == nil || p.scope.Check() != nil {
		return errSourceSuperseded
	}
	if _, err := pendingForReceipt(p.receipt); err != nil {
		return err
	}
	lease, err := requestscope.Begin(p.scope.Context(), requestscope.Spec{Owner: requestscope.Owner{ID: p.receipt.Owner}, Kind: "provider-local", Key: "source-qualification:" + r.plan.Key, Resource: sourceProviderCache(C.Path.HomeDir(), p.receipt.Owner, r.material)})
	if err != nil {
		return err
	}
	qualified, valid := lease.(*appRequestLease)
	if !valid || qualified == nil || qualified.registry != appRequests || qualified.spec.Owner.ID != p.receipt.Owner || qualified.Check() != nil {
		if lease != nil && (!valid || qualified != nil) {
			lease.Close()
		}
		return errSourceSuperseded
	}
	lease.Close()
	if r.rule != nil && tunnel.RuleProvidersSnapshot()[r.plan.Name] != r.rule || r.proxy != nil && tunnel.ProvidersSnapshot()[r.plan.Name] != r.proxy {
		return errSourceSuperseded
	}
	return nil
}

func (r *sourceProviderRuntime) read() ([]byte, error) {
	ctx := r.parent.scope.Context()
	proxy, _ := r.plan.Mapping["proxy"].(string)
	kind := "provider"
	if r.plan.Mapping["type"] == "file" {
		kind = "provider-local"
	}
	url, _ := r.plan.Mapping["url"].(string)
	lease, err := requestscope.Begin(ctx, requestscope.Spec{Owner: requestscope.Owner{ID: r.parent.receipt.Owner}, Kind: kind, Key: "source-refresh:" + r.plan.Key, URL: url, Proxy: proxy, Trigger: "automatic"})
	if err != nil {
		return nil, err
	}
	qualified, valid := lease.(*appRequestLease)
	if !valid || qualified == nil || qualified.registry != appRequests || qualified.Check() != nil {
		if lease != nil && (!valid || qualified != nil) {
			lease.Close()
		}
		return nil, errSourceSuperseded
	}
	defer lease.Close()
	var body []byte
	if kind == "provider-local" {
		path, _ := r.plan.Mapping["path"].(string)
		path = C.Path.Resolve(path)
		if !C.Path.IsSafePath(path) {
			return nil, errSourceReview
		}
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		body, err = io.ReadAll(io.LimitReader(f, sourceCandidateMax+1))
		_ = f.Close()
		if err != nil {
			return nil, err
		}
	} else {
		header, err := sourceProviderHeaders(r.plan.Mapping)
		if err != nil {
			return nil, err
		}
		vehicle := resource.NewHTTPVehicle(url, "", proxy, header, 30*time.Second, sourceCandidateMax+1)
		previous, err := readSourceObject(C.Path.HomeDir(), r.material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return nil, err
		}
		previousHash := utils.MakeHash(previous)
		response, err := vehicle.ScopedRead(ctx, previousHash, lease)
		if err != nil {
			return nil, err
		}
		body = response.Bytes
		if body == nil && response.Hash.Equal(previousHash) {
			body = previous
		}
	}
	if len(body) == 0 || len(body) > sourceCandidateMax {
		return nil, errSourceBudget
	}
	if lease.Check() != nil {
		return nil, errSourceSuperseded
	}
	return body, nil
}

func (r *sourceProviderRuntime) sourceStatus() string {
	if status := r.status.Load(); status != nil {
		return *status
	}
	return ""
}
func (r *sourceProviderRuntime) sourceViewPath() string {
	if path := r.viewPath.Load(); path != nil {
		return *path
	}
	return ""
}

func (r *sourceProviderRuntime) update(body []byte) error { return r.updateQualified(body, nil) }

func (r *sourceProviderRuntime) updateQualified(body []byte, fenceRequest *sourceAcceptanceRequest) (failure error) {
	p := r.parent
	p.sourceSerial.Lock()
	defer p.sourceSerial.Unlock()
	defer func() {
		status := ""
		switch {
		case errors.Is(failure, errSourceReview):
			status = "reviewRequired"
		case errors.Is(failure, errSourceBudget):
			status = "budget"
		case p.sourceRecovery != nil:
			status = "recovery"
		}
		r.status.Store(&status)
	}()
	if !configMu.TryLock() {
		return errSourceSuperseded
	}
	err := sourceProviderCurrentLocked(r)
	if err == nil && fenceRequest != nil && !sourceProviderRequestCurrent(*fenceRequest) {
		err = errSourceSuperseded
	}
	if err == nil && p.sourceRecovery != nil {
		err = persistSourceMaterialLocked(p)
		configMu.Unlock()
		return err
	}
	configMu.Unlock()
	if err != nil {
		return err
	}
	if body == nil {
		body, err = r.read()
		if err != nil {
			return err
		}
	}
	if !configMu.TryLock() {
		return errSourceSuperseded
	}
	defer configMu.Unlock()
	if err := sourceProviderCurrentLocked(r); err != nil {
		return err
	}
	if fenceRequest != nil && !sourceProviderRequestCurrent(*fenceRequest) {
		return errSourceSuperseded
	}
	if inputHash(body) == r.material.MaterialHash {
		return nil
	}
	if err := pendingSourceMaterialBlocksReplay(C.Path.HomeDir()); err != nil {
		return err
	}
	origin, err := r.reviewOrigin(body)
	if err != nil {
		return err
	}
	request := sourceAcceptanceRequest{Action: "review", Key: r.plan.Key, Kind: r.plan.Kind, Identity: r.plan.Declaration, Settings: sourceValueHash(r.plan.Mapping)}
	request.Provider, request.Parent, request.ProviderName = r.plan.Mapping, &r.plan.Parent, r.plan.Name
	request.Use, request.MaterialHash = &r.plan.Context, r.plan.ContextMaterialHash
	if r.plan.Kind == "provider-rule" {
		request.BodyBase64 = base64.StdEncoding.EncodeToString(body)
		request.Format, _ = r.plan.Mapping["format"].(string)
		request.Behavior, _ = r.plan.Mapping["behavior"].(string)
	} else {
		request.BodyBase64 = base64.StdEncoding.EncodeToString(body)
	}
	accepted, err := sourceAcceptance(C.Path.HomeDir(), request)
	if err != nil {
		return err
	}
	if accepted.Status != "accepted" || accepted.Use == nil {
		return errSourceReview
	}
	return r.adoptLocked(body, *accepted.Use, accepted.MaterialHash, origin)
}

func (r *sourceProviderRuntime) start() {
	r.once.Do(func() {
		interval, _ := r.plan.Mapping["interval"].(int)
		if r.plan.Mapping["type"] == "file" {
			interval = 1
		}
		if interval <= 0 {
			return
		}
		go func() {
			ticker := time.NewTicker(time.Duration(interval) * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-r.parent.scope.Context().Done():
					return
				case <-ticker.C:
					_ = r.update(nil)
				}
			}
		}()
	})
}
