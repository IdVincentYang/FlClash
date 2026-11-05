package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	RP "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

type sourceRuleTestTunnel struct {
	rules   map[string]P.RuleProvider
	updates *utils.Callback[P.RuleProvider]
}

func (f *sourceRuleTestTunnel) Providers() map[string]P.ProxyProvider               { return nil }
func (f *sourceRuleTestTunnel) RuleProviders() map[string]P.RuleProvider            { return f.rules }
func (f *sourceRuleTestTunnel) RuleUpdateCallback() *utils.Callback[P.RuleProvider] { return f.updates }

func sourceRuleRegistryFixture(t *testing.T) (*appRequestRegistry, string) {
	t.Helper()
	r, _ := appRequestFixture(t)
	old, begin, owner, resourceHook := appRequests, requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook
	appRequests = r
	requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook = r.begin, r.currentOwner, r.lockResource
	t.Cleanup(func() {
		appRequests = old
		requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook = begin, owner, resourceHook
	})
	current := r.newOwner()
	r.setPhase(current, "inner")
	return r, t.TempDir()
}

func sourceRuleAcceptedFixture(t *testing.T, home, body string) (string, SourceUse) {
	t.Helper()
	summary, err := summarizeSourceRuleContent([]byte(body), "text", "domain")
	if err != nil {
		t.Fatal(err)
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		t.Fatal(err)
	}
	var revision uint64
	if grant := permissions.Grants["profile:7"]; grant != nil {
		revision = grant.Revision
	}
	use, err := acceptSourceRevision(home, "profile:7", inputHash([]byte("controlled fixture")), summary.Digest, "source", "", false, revision, "provider-rule")
	if err != nil {
		t.Fatal(err)
	}
	digest, err := sealSourceObject(home, []byte(body), sourceCandidateMax)
	if err != nil {
		t.Fatal(err)
	}
	return digest, use
}

func TestSourceRuleGenerationUsesRealLeaseAndPublishesStableWrapper(t *testing.T) {
	_, home := sourceRuleRegistryFixture(t)
	fixture := &sourceRuleTestTunnel{rules: map[string]P.RuleProvider{}, updates: utils.NewCallback[P.RuleProvider]()}
	RP.SetTunnel(fixture)
	t.Cleanup(func() { RP.SetTunnel(tunnel.Tunnel) })
	updated := make(chan P.RuleProvider, 8)
	listener := fixture.updates.Register(func(p P.RuleProvider) { updated <- p })
	defer listener.Close()
	prepare := func(body string) *sourceRuleGeneration {
		digest, use := sourceRuleAcceptedFixture(t, home, body)
		g, err := prepareSourceRuleGeneration(context.Background(), home, digest, "text", "domain", use, nil)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(g.close)
		return g
	}
	first := prepare("old.invalid\n")
	wrapper := newSourceRuleProvider(context.Background(), "public-rules", P.HTTP, first, nil)
	t.Cleanup(func() { _ = wrapper.Close() })
	fixture.rules[wrapper.Name()] = wrapper
	second := prepare("new.invalid\nextra.invalid\n")
	if first.provider.Name() == second.provider.Name() || first.provider.Name() == wrapper.Name() {
		t.Fatal("private generation reused a public/provider identity")
	}
	if reflect.TypeOf(wrapper.Strategy()) != reflect.TypeOf(first.provider.Strategy()) {
		t.Fatal("wrapper obscured the original Strategy type")
	}
	consumer, err := RP.NewRuleSet(wrapper.Name(), "REJECT", false, true)
	if err != nil {
		t.Fatal(err)
	}
	if !consumer.MatchDomain("old.invalid") || consumer.MatchDomain("new.invalid") {
		t.Fatal("unpublished generation leaked into a shared RuleSet consumer")
	}
	select {
	case p := <-updated:
		t.Fatalf("private preparation emitted update for %s", p.Name())
	case <-time.After(25 * time.Millisecond):
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	wrapper.matched = func(g *sourceRuleGeneration, _ *C.Metadata, matched bool) {
		once.Do(func() {
			if g != first || !matched {
				t.Error("match attributed to another generation")
			}
			close(entered)
			<-release
		})
	}
	matched := make(chan bool, 1)
	go func() { matched <- consumer.MatchDomain("old.invalid") }()
	<-entered
	if err := wrapper.publish(second); err != nil {
		t.Fatal(err)
	}
	close(release)
	if !<-matched {
		t.Fatal("in-flight match changed generation")
	}
	if !consumer.MatchDomain("new.invalid") || consumer.MatchDomain("old.invalid") || wrapper.Count() != 2 {
		t.Fatal("stable RuleSet consumer did not see the published generation")
	}
	if !first.provider.Match(&C.Metadata{Host: "old.invalid"}, C.RuleMatchHelper{}) {
		t.Fatal("publishing closed a still-pinned old generation")
	}
	fixture.updates.Emit(wrapper)
	select {
	case p := <-updated:
		if p != wrapper || p.Count() != 2 {
			t.Fatal("public callback exposed a private/old provider")
		}
	case <-time.After(time.Second):
		t.Fatal("published callback was not delivered")
	}
}

type sourceRuleNoopLease struct{ requestscope.Lease }

func (*sourceRuleNoopLease) Close() {}

func TestSourceRuleGenerationRejectsMissingOrForeignAuthorityBeforeFactory(t *testing.T) {
	r, home := sourceRuleRegistryFixture(t)
	digest, use := sourceRuleAcceptedFixture(t, home, "fixture.invalid\n")
	for name, begin := range map[string]func(context.Context, requestscope.Spec) (requestscope.Lease, error){
		"missing":   nil,
		"nil lease": func(context.Context, requestscope.Spec) (requestscope.Lease, error) { return nil, nil },
		"noop lease": func(context.Context, requestscope.Spec) (requestscope.Lease, error) {
			return &sourceRuleNoopLease{}, nil
		},
		"typed nil": func(context.Context, requestscope.Spec) (requestscope.Lease, error) {
			return (*appRequestLease)(nil), nil
		},
		"denied": func(context.Context, requestscope.Spec) (requestscope.Lease, error) {
			return nil, requestscope.ErrBlocked
		},
	} {
		t.Run(name, func(t *testing.T) {
			requestscope.BeginHook = begin
			if g, err := prepareSourceRuleGeneration(context.Background(), home, digest, "text", "domain", use, nil); err == nil || g != nil {
				t.Fatal("unqualified authority reached a private factory")
			}
			if _, err := os.Stat(filepath.Join(home, "source-acceptance", "live")); !os.IsNotExist(err) {
				t.Fatal("rejected authority created a live cache", err)
			}
		})
	}
	requestscope.BeginHook = r.begin
	r.setPhase(r.currentOwner(), "retired")
	if _, err := prepareSourceRuleGeneration(context.Background(), home, digest, "text", "domain", use, nil); !errors.Is(err, requestscope.ErrBlocked) {
		t.Fatal("retired owner prepared a generation", err)
	}
}
