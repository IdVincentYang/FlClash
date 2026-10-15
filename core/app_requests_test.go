package main

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	mh "github.com/metacubex/http"
	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/utils"
	mihomoHTTP "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	C "github.com/metacubex/mihomo/constant"
)

func appRequestFixture(t *testing.T) (*appRequestRegistry, *appRequestLease) {
	t.Helper()
	r := newAppRequestRegistry()
	r.publish(AppRequestState{ProcessEpoch: "synthetic", Revision: 1, Reason: "userStop", Phase: "stopped", DefaultNetworkKind: "nonVpn", DirectNetworkID: "synthetic-network", ProtectPhase: "none"})
	lease, err := r.begin(context.Background(), requestscope.Spec{Kind: "maintenance", Trigger: "manual", Proxy: "DIRECT", Mode: "direct", Key: "synthetic-object"})
	if err != nil {
		t.Fatal(err)
	}
	l := lease.(*appRequestLease)
	t.Cleanup(l.Close)
	t.Cleanup(r.closePrivate)
	return r, l
}

func TestAppRequestDataReadExcludesNewFrontendGrant(t *testing.T) {
	r, lease := appRequestFixture(t)
	lease.spec.Client = "synthetic-client"
	r.client, r.clientReady = lease.spec.Client, true
	id, err := r.beginDataRead(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lease.GrantCommit(); !errors.Is(err, errRequestCommitBusy) {
		t.Fatal("read did not exclude a later grant", err)
	}
	r.endDataRead(id)
	receipt, err := lease.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if _, err := r.beginDataRead(ctx); err == nil {
		t.Fatal("read passed a live frontend receipt")
	}
	receipt.Complete()
	id, err = r.beginDataRead(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	r.endDataRead(id)
}

func TestAppRequestProviderRejectsRevokedAndAcceptsNewOwner(t *testing.T) {
	r, _ := appRequestFixture(t)
	state := r.state
	state.IntentRunning, state.Phase = true, "started"
	state.Revision++
	r.publish(state)
	owner := r.newOwner()
	r.setPhase(owner, "ready")
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	begin, current, resourceHook := requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook
	requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook = r.begin, r.currentOwner, r.lockResource
	defer func() {
		requestscope.BeginHook, requestscope.OwnerHook, requestscope.ResourceHook = begin, current, resourceHook
	}()
	entered, release := make(chan struct{}), make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		close(entered)
		select {
		case <-release:
		case <-req.Context().Done():
			return
		}
		w.Header().Set("subscription-userinfo", "candidate")
		_, _ = w.Write([]byte("stale"))
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "provider")
	if err := os.WriteFile(path, []byte("baseline"), 0600); err != nil {
		t.Fatal(err)
	}
	vehicle := resource.NewHTTPVehicle(server.URL, path, "DIRECT", nil, time.Second, 0)
	var metadata atomic.Int32
	vehicle.SetInRead(func(*mh.Response) { metadata.Add(1) })
	fetcher := resource.NewFetcher("synthetic", 0, vehicle, nil, func(buf []byte) (string, error) { return string(buf), nil }, func(string) {})
	defer fetcher.Close()
	done := make(chan error, 1)
	go func() { _, _, err := fetcher.Update(); done <- err }()
	select {
	case <-entered:
	case err := <-done:
		t.Fatal("provider did not connect", err)
	case <-time.After(2 * time.Second):
		t.Fatal("provider did not enter loopback target")
	}
	newOwner := r.newOwner()
	r.setPhase(newOwner, "ready")
	close(release)
	if err := <-done; err == nil {
		t.Fatal("retired download committed")
	}
	if buf, _ := os.ReadFile(path); string(buf) != "baseline" || metadata.Load() != 0 || !fetcher.UpdatedAt().IsZero() {
		t.Fatal("retired provider changed file or metadata")
	}
	if _, _, err := fetcher.SideUpdate([]byte("stale side update")); err == nil {
		t.Fatal("old provider side update survived ownership change")
	}
	next := resource.NewFetcher("synthetic", 0, vehicle, nil, func(buf []byte) (string, error) { return string(buf), nil }, func(string) {})
	defer next.Close()
	if _, _, err := next.SideUpdate([]byte("current")); err != nil {
		t.Fatal(err)
	}
	if buf, _ := os.ReadFile(path); string(buf) != "current" {
		t.Fatal("new owner could not commit")
	}
}

func TestAppRequestURLTestCancellationPreservesHistory(t *testing.T) {
	r, lease := appRequestFixture(t)
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	entered := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { close(entered); <-req.Context().Done() }))
	defer server.Close()
	proxy := adapter.NewProxy(outbound.NewDirect())
	ctx := requestscope.WithLease(lease.Context(), lease)
	done := make(chan error, 1)
	go func() { _, err := proxy.URLTest(ctx, server.URL, nil); done <- err }()
	<-entered
	state := r.state
	state.Revision++
	r.publish(state)
	if err := <-done; err == nil {
		t.Fatal("revocation did not cancel the URL test")
	}
	if len(proxy.DelayHistory()) != 0 || len(proxy.DelayHistoryForTestUrl(server.URL)) != 0 {
		t.Fatal("cancellation entered dead-node history")
	}
}

func TestAppRequestDirectSocketGateRefusesConnect(t *testing.T) {
	var received atomic.Int32
	var connected atomic.Int32
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { received.Add(1); _, _ = w.Write([]byte("synthetic")) }))
	server.Config.ConnState = func(_ net.Conn, state http.ConnState) {
		if state == http.StateNew {
			connected.Add(1)
		}
	}
	server.Start()
	defer server.Close()
	for _, scenario := range []string{"missing", "refused", "version-changed"} {
		t.Run(scenario, func(t *testing.T) {
			r, lease := appRequestFixture(t)
			var entered atomic.Int32
			if scenario != "missing" {
				r.socketGate = func(id string, state AppRequestState, fd int) error {
					entered.Add(1)
					if fd < 0 || id != lease.id {
						t.Error("invalid socket identity")
					}
					if scenario == "version-changed" {
						state.Revision++
						r.publish(state)
						return nil
					}
					return requestscope.ErrBlocked
				}
			}
			response, err := mihomoHTTP.HttpRequest(lease.Context(), server.URL, "GET", nil, nil, mihomoHTTP.WithScope(lease))
			if response != nil {
				_ = response.Body.Close()
			}
			if err == nil {
				t.Fatal("unavailable socket gate allowed the request")
			}
			if scenario != "missing" && entered.Load() == 0 {
				t.Fatal("actual socket control was not entered")
			}
			if connected.Load() != 0 {
				t.Fatal("target accepted a forbidden connection")
			}
			if received.Load() != 0 {
				t.Fatal("target received a forbidden request")
			}
		})
	}
}

func TestAppRequestResponseCloseKeepsReceiptAndRevocationRejectsMetadata(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("subscription-userinfo", "synthetic")
		_, _ = w.Write([]byte("synthetic payload"))
	}))
	defer server.Close()
	r, lease := appRequestFixture(t)
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	vehicle := resource.NewHTTPVehicle(server.URL, filepath.Join(t.TempDir(), "provider"), "DIRECT", nil, time.Second, 0)
	var metadataWritten bool
	vehicle.SetInRead(func(*mh.Response) { metadataWritten = true })
	result, err := vehicle.ScopedRead(lease.Context(), utils.HashType{}, lease)
	if err != nil {
		t.Fatal(err)
	}
	if err = lease.Check(); err != nil {
		t.Fatal("response closure released the lease", err)
	}
	if result.Hash.IsValid() == false {
		t.Fatal("response hash missing")
	}
	state := r.state
	state.Revision++
	r.publish(state)
	if err = requestscope.Commit(lease, result.CommitMetadata); !errors.Is(err, requestscope.ErrCancelled) {
		t.Fatal("revoked metadata was committed", err)
	}
	if metadataWritten {
		t.Fatal("revoked subscription metadata was written")
	}
}

func TestAppRequestGrantBeforeRevocationCompletesLocalReceipt(t *testing.T) {
	r, lease := appRequestFixture(t)
	receipt, err := lease.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	state := r.state
	state.Revision++
	r.publish(state)
	receipt.Complete()
	if _, err = lease.GrantCommit(); !errors.Is(err, requestscope.ErrCancelled) {
		t.Fatal("revoked scope got another grant")
	}
}

func TestAppRequestStrictRejectsDirectSemantics(t *testing.T) {
	r, lease := appRequestFixture(t)
	owner := r.newOwner()
	r.setPhase(owner, "ready")
	r.publish(AppRequestState{ProcessEpoch: "synthetic", Revision: 2, IntentRunning: true, Phase: "started"})
	created, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "request", Mode: "proxy", Key: "strict-object"})
	if err != nil {
		t.Fatal(err)
	}
	lease = created.(*appRequestLease)
	defer lease.Close()
	for _, proxy := range []C.Proxy{
		adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "arbitrary-name"})),
		adapter.NewProxy(outbound.NewCompatible()),
	} {
		if _, err := lease.SelectProxy(proxy, &C.Metadata{}); !errors.Is(err, requestscope.ErrBlocked) {
			t.Fatal("strict mode accepted actual direct adapter", err)
		}
	}
}

func TestAppRequestPrivateListenerRequiresScopeAndWorksWhileStopped(t *testing.T) {
	var received atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
		if r.Header.Get("Proxy-Authorization") != "" {
			t.Error("proxy capability reached origin")
		}
		_, _ = w.Write([]byte("synthetic"))
	}))
	defer server.Close()
	r, lease := appRequestFixture(t)
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	lease.user, lease.password = "flclash-request-synthetic", "synthetic-capability"
	previous := requestscope.ProxyHook
	requestscope.ProxyHook = r.bindProxy
	defer func() { requestscope.ProxyHook = previous }()
	endpoint, err := r.privateEndpoint()
	if err != nil {
		t.Fatal(err)
	}
	proxyURL, _ := url.Parse("http://" + endpoint)
	for _, authenticated := range []bool{false, true} {
		if authenticated {
			proxyURL.User = url.UserPassword(lease.user, lease.password)
		}
		transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
		client := &http.Client{Transport: transport, Timeout: 2 * time.Second}
		response, err := client.Get(server.URL)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = io.Copy(io.Discard, response.Body)
		_ = response.Body.Close()
		transport.CloseIdleConnections()
		if !authenticated && response.StatusCode != http.StatusForbidden {
			t.Fatal("private listener accepted an anonymous request")
		}
		if authenticated && response.StatusCode != http.StatusOK {
			t.Fatal("scoped stopped-state direct request failed", response.StatusCode)
		}
	}
	if received.Load() != 1 {
		t.Fatal("unexpected target request count", received.Load())
	}
}

func TestAppRequestFrontendGenerationsAndReceiptDrain(t *testing.T) {
	r, _ := appRequestFixture(t)
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: client})
	params := appRequestControl{Action: "begin", Client: client, Dataset: r.dataset, Key: "profile:synthetic", Kind: "maintenance", Trigger: "manual", Mode: "direct", Proxy: "DIRECT", ExpectedState: &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}}
	first := r.control(params).(map[string]any)
	id := first["id"].(string)
	lease := r.leases[id]
	receipt, err := lease.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	r.control(appRequestControl{Action: "invalidate", Client: client, Key: params.Key})
	if lease.Check() == nil {
		t.Fatal("source change retained old scope")
	}
	if result := r.control(params); result.(map[string]string)["error"] != "request_cancelled" {
		t.Fatal("stale source revision was accepted")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	previous := requestscope.BeginHook
	requestscope.BeginHook = r.begin
	defer func() { requestscope.BeginHook = previous }()
	if r.waitFrontendCommits(ctx) == nil {
		t.Fatal("reload did not wait for the granted local segment")
	}
	receipt.Complete()
	if err := r.waitFrontendCommits(context.Background()); err != nil {
		t.Fatal(err)
	}
	params.SourceRevision++
	second := r.control(params).(map[string]any)
	secondID := second["id"].(string)
	newClient := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	if newClient == client || r.leases[secondID] != nil {
		t.Fatal("reattach retained old frontend capabilities")
	}
}

func TestAppRequestBootstrapPermitIsSingleUseAndVersionBound(t *testing.T) {
	r, _ := appRequestFixture(t)
	client := r.control(appRequestControl{Action: "attach"}).(map[string]any)["client"].(string)
	r.control(appRequestControl{Action: "ready", Client: client})
	version := &requestscope.StateVersion{Epoch: r.state.ProcessEpoch, Revision: r.state.Revision}
	params := appRequestControl{Action: "permit", Client: client, Dataset: r.dataset, Key: "geo:MMDB", URL: "http://127.0.0.1:1234/synthetic", ExpectedState: version}
	permit := r.control(params).(map[string]string)["permit"]
	params.Action, params.Kind, params.Trigger, params.Mode, params.Proxy, params.Permit = "begin", "bootstrap", "manual", "direct", "DIRECT", permit
	created := r.control(params).(map[string]any)
	lease := r.leases[created["id"].(string)]
	if err := lease.CheckURL("http://127.0.0.1:1234/same-origin"); err != nil {
		t.Fatal(err)
	}
	if lease.CheckURL("http://127.0.0.1:1235/other-origin") == nil {
		t.Fatal("bootstrap accepted a different origin")
	}
	if result := r.control(params); result.(map[string]string)["error"] == "" {
		t.Fatal("bootstrap permit was reused")
	}
	params.Action, params.Permit = "permit", ""
	permit = r.control(params).(map[string]string)["permit"]
	state := r.state
	state.Revision++
	r.publish(state)
	params.Action, params.Permit = "begin", permit
	if result := r.control(params); result.(map[string]string)["error"] == "" {
		t.Fatal("native revocation retained the bootstrap permit")
	}
}
