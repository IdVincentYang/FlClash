package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	R "github.com/metacubex/mihomo/rules"
	RP "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

const sourceRetiredGenerationLimit = 32

type sourceRuleGeneration struct {
	provider  *RP.RuleSetProvider
	use       SourceUse
	digest    string
	owner     requestscope.Owner
	format    P.RuleFormat
	loaded    time.Time
	cache     string
	size      int
	closeOnce sync.Once
}

func (g *sourceRuleGeneration) close() {
	g.closeOnce.Do(func() {
		_ = g.provider.Close()
		_ = os.Remove(g.cache)
	})
}

func prepareSourceRuleGeneration(ctx context.Context, home, digest, format, behavior string, use SourceUse, reserved map[string]bool) (*sourceRuleGeneration, error) {
	if requestscope.BeginHook == nil || requestscope.OwnerHook == nil || ctx.Err() != nil || use.Kind != "provider-rule" {
		return nil, errSourceReview
	}
	owner := requestscope.OwnerHook()
	if owner.ID == 0 {
		return nil, errSourceSuperseded
	}
	body, err := readSourceObject(home, digest, sourceCandidateMax)
	if err != nil {
		return nil, err
	}
	summary, err := summarizeSourceRuleContent(body, format, behavior)
	if err != nil || summary.Digest != use.Digest {
		return nil, errSourceReview
	}
	if err := checkSourceUses(home, []SourceUse{use}); err != nil {
		return nil, err
	}
	parsedFormat, _ := P.ParseRuleFormat(format)
	parsedBehavior, _ := P.ParseBehavior(behavior)
	var name string
	for attempts := 0; attempts < 8; attempts++ {
		token, err := randomRequestToken()
		if err != nil {
			return nil, err
		}
		name = "@source-rp-" + token
		if !reserved[name] && tunnel.RuleProvidersSnapshot()[name] == nil {
			break
		}
		name = ""
	}
	if name == "" {
		return nil, errSourceBudget
	}
	cache := filepath.Join(home, "source-acceptance", "live", strconv.FormatUint(owner.ID, 10), "rule-candidates", inputHash([]byte(name)))
	lease, err := requestscope.Begin(ctx, requestscope.Spec{Owner: owner, Kind: "provider-local", Trigger: "automatic", Key: "source-rule-candidate:" + name, Resource: cache})
	if err != nil {
		return nil, err
	}
	qualified, valid := lease.(*appRequestLease)
	if !valid || qualified == nil || qualified.registry != appRequests || qualified.spec.Owner != owner || qualified.Check() != nil {
		if lease != nil && (!valid || qualified != nil) {
			lease.Close()
		}
		return nil, errSourceSuperseded
	}
	lease.Close()
	private := RP.NewRuleSetProvider(name, parsedBehavior, parsedFormat, 0, resource.NewFileVehicle(cache), nil, nil, R.ParseRule).(*RP.RuleSetProvider)
	private.SetAfterUpdate(func() {})
	stop := context.AfterFunc(ctx, func() { _ = private.Close() })
	defer stop()
	g := &sourceRuleGeneration{provider: private, use: use, digest: digest, owner: owner, format: parsedFormat, cache: cache, size: len(body)}
	if private.RequestOwner() != owner {
		g.close()
		return nil, errSourceSuperseded
	}
	if _, _, err := private.SideUpdate(body); err != nil {
		g.close()
		return nil, err
	}
	if ctx.Err() != nil || requestscope.OwnerHook() != owner {
		g.close()
		return nil, errSourceSuperseded
	}
	if err := checkSourceUses(home, []SourceUse{use}); err != nil {
		g.close()
		return nil, err
	}
	g.loaded = time.Now()
	return g, nil
}

type sourceRuleProvider struct {
	name        string
	behavior    P.RuleBehavior
	format      P.RuleFormat
	vehicle     P.VehicleType
	owner       requestscope.Owner
	ctx         context.Context
	cancel      context.CancelFunc
	current     atomic.Pointer[sourceRuleGeneration]
	mu          sync.Mutex
	generations []*sourceRuleGeneration
	refresh     func() error
	sideUpdate  func([]byte) error
	external    func() *ExternalProvider
	matched     func(*sourceRuleGeneration, *C.Metadata, bool)
}

func newSourceRuleProvider(ctx context.Context, name string, vehicle P.VehicleType, initial *sourceRuleGeneration, refresh func() error) *sourceRuleProvider {
	owned, cancel := context.WithCancel(ctx)
	p := &sourceRuleProvider{name: name, behavior: initial.provider.Behavior(), format: initial.format, vehicle: vehicle,
		owner: initial.owner, ctx: owned, cancel: cancel, generations: []*sourceRuleGeneration{initial}, refresh: refresh}
	p.current.Store(initial)
	return p
}

func (p *sourceRuleProvider) Name() string                     { return p.name }
func (p *sourceRuleProvider) Type() P.ProviderType             { return P.Rule }
func (p *sourceRuleProvider) Behavior() P.RuleBehavior         { return p.behavior }
func (p *sourceRuleProvider) VehicleType() P.VehicleType       { return p.vehicle }
func (p *sourceRuleProvider) RequestContext() context.Context  { return p.ctx }
func (p *sourceRuleProvider) RequestOwner() requestscope.Owner { return p.owner }
func (p *sourceRuleProvider) underlyingProvider() P.Provider   { return p.current.Load().provider }
func (p *sourceRuleProvider) Initial() error {
	if p.ctx.Err() != nil {
		return requestscope.ErrCancelled
	}
	return nil
}
func (p *sourceRuleProvider) Update() error {
	if p.ctx.Err() != nil {
		return requestscope.ErrCancelled
	}
	if p.refresh == nil {
		return errSourceReview
	}
	return p.refresh()
}

func (p *sourceRuleProvider) sourceSideUpdate(body []byte) error {
	if p.sideUpdate == nil {
		return errSourceReview
	}
	return p.sideUpdate(body)
}
func (p *sourceRuleProvider) sourceExternalProvider() *ExternalProvider {
	if p.external != nil {
		return p.external()
	}
	return &ExternalProvider{Name: p.name, Type: p.Type().String(), VehicleType: p.vehicle.String(), Count: p.Count(), UpdateAt: p.current.Load().loaded}
}
func (p *sourceRuleProvider) Count() int    { return p.current.Load().provider.Count() }
func (p *sourceRuleProvider) Strategy() any { return p.current.Load().provider.Strategy() }
func (p *sourceRuleProvider) Match(metadata *C.Metadata, helper C.RuleMatchHelper) bool {
	generation := p.current.Load()
	matched := generation.provider.Match(metadata, helper)
	if p.matched != nil {
		p.matched(generation, metadata, matched)
	}
	return matched
}
func (p *sourceRuleProvider) publish(generation *sourceRuleGeneration) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.ctx.Err() != nil || generation.owner != p.owner {
		return errSourceSuperseded
	}
	if generation.provider.Behavior() != p.behavior || generation.format != p.format {
		return errSourceReview
	}
	if len(p.generations) >= sourceRetiredGenerationLimit+1 {
		return errSourceBudget
	}
	p.generations = append(p.generations, generation)
	p.current.Store(generation)
	return nil
}
func (p *sourceRuleProvider) MarshalJSON() ([]byte, error) {
	generation := p.current.Load()
	return json.Marshal(map[string]any{"name": p.name, "type": P.Rule.String(), "behavior": p.behavior.String(),
		"format": p.format.String(), "vehicleType": p.vehicle.String(), "ruleCount": generation.provider.Count(), "updatedAt": generation.loaded})
}
func (p *sourceRuleProvider) Close() error {
	p.cancel()
	p.mu.Lock()
	generations := p.generations
	p.generations = nil
	p.mu.Unlock()
	for _, generation := range generations {
		generation.close()
	}
	return nil
}

var _ P.RuleProvider = (*sourceRuleProvider)(nil)
