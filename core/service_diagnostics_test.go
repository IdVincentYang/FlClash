package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type diagnosticProxy struct {
	C.Proxy
	address     string
	allowed     map[string]bool
	mu          sync.Mutex
	targets     []string
	fail        bool
	alternating bool
}

type diagnosticAdapter struct{ C.ProxyAdapter }

func (p *diagnosticAdapter) Type() C.AdapterType { return C.Socks5 }
func (p *diagnosticProxy) Adapter() C.ProxyAdapter {
	return &diagnosticAdapter{ProxyAdapter: p.Proxy.Adapter()}
}

func (p *diagnosticProxy) Type() C.AdapterType { return C.Socks5 }

func (p *diagnosticProxy) DialContext(ctx context.Context, m *C.Metadata) (C.Conn, error) {
	p.mu.Lock()
	p.targets = append(p.targets, m.Host)
	fail := p.fail
	alternate := p.alternating
	index := len(p.targets)
	p.mu.Unlock()
	if fail || !p.allowed[m.Host] || m.DstPort != 443 {
		return nil, errors.New("synthetic rejected dial")
	}
	local := &C.Metadata{NetWork: C.TCP}
	if err := local.SetRemoteAddress(p.address); err != nil {
		return nil, err
	}
	conn, err := p.Proxy.DialContext(ctx, local)
	if err != nil {
		return nil, err
	}
	if alternate {
		return &diagnosticConn{Conn: conn, chain: C.Chain{fmt.Sprintf("exit-%d", index)}}, nil
	}
	return conn, nil
}

type diagnosticConn struct {
	C.Conn
	chain C.Chain
}

func (c *diagnosticConn) Chains() C.Chain { return c.chain }

func diagnosticFixture(t *testing.T, handler http.HandlerFunc, trusted bool, certificateNames ...string) *diagnosticProxy {
	t.Helper()
	hosts := map[string]bool{}
	for _, checker := range serviceCheckers {
		for _, raw := range append([]string{checker.url}, checker.endpoints...) {
			parsed, err := url.Parse(raw)
			if err == nil && parsed.Hostname() != "" {
				hosts[parsed.Hostname()] = true
			}
		}
	}
	names := []string{}
	for host := range hosts {
		names = append(names, host)
	}
	if len(certificateNames) > 0 {
		names = slices.Clone(certificateNames)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(71), Subject: pkix.Name{CommonName: "synthetic diagnostic"}, DNSNames: names, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, IsCA: true, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewUnstartedServer(handler)
	server.Config.ErrorLog = log.New(io.Discard, "", 0)
	server.TLS = &tls.Config{Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}, MinVersion: tls.VersionTLS12}
	server.StartTLS()
	t.Cleanup(server.Close)
	if trusted {
		if err := ca.AddCertificate(string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(ca.ResetCertificate)
	proxy := &diagnosticProxy{Proxy: namedProxy("diagnostic-node"), address: server.Listener.Addr().String(), allowed: hosts}
	tunnel.UpdateProxies(map[string]C.Proxy{"diagnostic-node": proxy}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	return proxy
}

func diagnosticCheck(t *testing.T, name, purpose string) ServiceCheckItem {
	t.Helper()
	result := handleServiceCheck(&ServiceCheckParams{Names: []string{name}, Purpose: purpose, ProxyName: "diagnostic-node", Timeout: 1000})
	if len(result) != 1 {
		t.Fatalf("items=%d, want one", len(result))
	}
	return result[0]
}

func TestDiagnosticBasicUsesOneAnonymousHTTPSRequestPerService(t *testing.T) {
	var calls atomic.Int32
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Method != "GET" || r.Header.Get("Cookie") != "" || r.Header.Get("Authorization") != "" || r.ContentLength > 0 {
			t.Errorf("non-basic request: %s", r.Method)
		}
		if r.Host == "www.youtube.com" {
			w.WriteHeader(http.StatusForbidden)
		} else {
			w.WriteHeader(http.StatusNoContent)
		}
	}, true)
	for _, checker := range serviceCheckers {
		t.Run(checker.name, func(t *testing.T) {
			before := calls.Load()
			item := diagnosticCheck(t, checker.name, "basic")
			want := serviceAvailable
			if checker.name == "youtube" {
				want = serviceRestricted
			}
			if item.Status != want || calls.Load() != before+1 || item.Region != "" || len(item.Steps) != 1 || !slices.Equal(item.Chains, []string{"diagnostic-node"}) {
				t.Fatalf("basic=%+v calls=%d", item, calls.Load()-before)
			}
		})
	}
}

func TestDiagnosticBasicClosesWithoutWaitingForBody(t *testing.T) {
	closed := make(chan struct{})
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "10000000")
		w.WriteHeader(http.StatusOK)
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		close(closed)
	}, true)
	item := diagnosticCheck(t, "google", "basic")
	if item.Status != serviceAvailable {
		t.Fatalf("header-only result=%+v", item)
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("response body/connection was not closed")
	}
}

func TestDiagnosticBasicRedirectIsAnObservationWithoutAnotherRecipient(t *testing.T) {
	var calls atomic.Int32
	proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		http.Redirect(w, r, "http://unaccepted.invalid/path", 302)
	}, true)
	item := diagnosticCheck(t, "youtube", "basic")
	if item.Status != "redirected" || item.HTTPStatus != 302 || calls.Load() != 1 || len(proxy.targets) != 1 {
		t.Fatalf("redirect followed or misreported: %+v", item)
	}
}

func TestDiagnosticTLSIdentityAndFailedProxyNeverFallBack(t *testing.T) {
	for _, trusted := range []bool{false, true} {
		t.Run(map[bool]string{false: "untrusted", true: "failed-proxy"}[trusted], func(t *testing.T) {
			var reached atomic.Int32
			proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { reached.Add(1); w.WriteHeader(204) }, false)
			proxy.fail = trusted
			item := diagnosticCheck(t, "google", "basic")
			if item.Status != serviceFailed || reached.Load() != 0 || len(proxy.targets) != 1 {
				t.Fatalf("unexpected fallback/success: %+v reached=%d", item, reached.Load())
			}
		})
	}
}

func TestDiagnosticAdvancedRejectsRedirectRecipientsBeforeSending(t *testing.T) {
	for _, target := range []string{"http://www.spotify.com/final", "https://other.invalid/final", "https://www.spotify.com:444/final", "https://user:password@www.spotify.com/final"} {
		t.Run(target, func(t *testing.T) {
			var calls atomic.Int32
			proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { calls.Add(1); http.Redirect(w, r, target, 302) }, true)
			item := diagnosticCheck(t, "spotify", "advanced")
			if item.Status != serviceFailed || item.Reason != "redirect-blocked" || calls.Load() != 1 || len(proxy.targets) != 1 || len(item.Steps) != 1 {
				t.Fatalf("recipient escaped: %+v", item)
			}
		})
	}
}

func TestDiagnosticAdvancedRedirectLimitAndPerSendSummaries(t *testing.T) {
	var calls atomic.Int32
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		http.Redirect(w, r, "/next?private=synth"+strings.Repeat("x", int(n)), 302)
	}, true)
	item := diagnosticCheck(t, "spotify", "advanced")
	if item.Status != serviceFailed || item.Reason != "redirect-blocked" || calls.Load() != 4 || len(item.Steps) != 4 {
		t.Fatalf("limit=%+v calls=%d", item, calls.Load())
	}
	encoded, _ := json.Marshal(item)
	if strings.Contains(string(encoded), "private") || strings.Contains(string(encoded), "synth") {
		t.Fatal("dynamic redirect query escaped")
	}
	for _, step := range item.Steps {
		if step.HTTPStatus != 302 || !slices.Equal(step.Chains, []string{"diagnostic-node"}) {
			t.Fatalf("step=%+v", step)
		}
	}
}

func TestDiagnosticAdvancedUsesASharedEightSendBudget(t *testing.T) {
	checker := serviceChecker{name: "budget", purpose: "advanced", endpoints: []string{"https://diagnostic.example.test/start"}}
	previous := serviceCheckers
	serviceCheckers = []serviceChecker{checker}
	t.Cleanup(func() { serviceCheckers = previous })
	var calls atomic.Int32
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.URL.Path == "/start" {
			http.Redirect(w, r, "/final", 302)
			return
		}
		w.WriteHeader(204)
	}, true)
	run := &serviceRun{checker: checker}
	env := serviceEnv{ctx: context.Background(), proxyName: "diagnostic-node", timeout: time.Second, run: run}
	for i := 0; i < 6; i++ {
		env.get(checker.endpoints[0], 0)
	}
	if calls.Load() != 8 || len(run.steps) != 8 || run.reason != "request-limit" {
		t.Fatalf("budget calls=%d steps=%d reason=%s", calls.Load(), len(run.steps), run.reason)
	}
}

func TestDiagnosticDisneyNeverForwardsPostOnAnyRedirect(t *testing.T) {
	for _, code := range []int{301, 302, 303, 307, 308} {
		t.Run(http.StatusText(code), func(t *testing.T) {
			var calls atomic.Int32
			diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				w.Header().Set("Location", "https://disney.api.edge.bamgrid.com/token")
				w.WriteHeader(code)
			}, true)
			item := diagnosticCheck(t, "disney-plus", "advanced")
			if item.Status != serviceFailed || calls.Load() != 1 || len(item.Steps) != 1 {
				t.Fatalf("POST was replayed: %+v calls=%d", item, calls.Load())
			}
		})
	}
}

func TestDiagnosticDisneyStrictThreeStepsAndSecretProjection(t *testing.T) {
	var requests []string
	var requestsMu sync.Mutex
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		requestsMu.Lock()
		requests = append(requests, r.URL.Path)
		requestsMu.Unlock()
		if r.Method != "POST" || r.Header.Get("Cookie") != "" {
			t.Error("unexpected method/cookie")
		}
		switch r.URL.Path {
		case "/devices":
			io.WriteString(w, `{"assertion":"assertion+synthetic"}`)
		case "/token":
			if r.ParseForm() != nil || r.Form.Get("subject_token") != "assertion+synthetic" {
				t.Error("assertion was not form encoded")
			}
			io.WriteString(w, `{"refresh_token":"refresh\\\"synthetic"}`)
		default:
			var payload map[string]any
			if json.NewDecoder(r.Body).Decode(&payload) != nil {
				t.Error("invalid JSON token encoding")
			}
			io.WriteString(w, `{"extensions":{"sdk":{"session":{"location":{"countryCode":"JP"},"inSupportedLocation":true}}}}`)
		}
	}, true)
	item := diagnosticCheck(t, "disney-plus", "advanced")
	requestsMu.Lock()
	defer requestsMu.Unlock()
	if item.Status != "observed" || item.Region != "JP" || len(requests) != 3 || len(item.Steps) != 3 || len(item.Chains) != 0 {
		t.Fatalf("session=%+v requests=%v", item, requests)
	}
	encoded, _ := json.Marshal(item)
	for _, secret := range []string{"assertion+synthetic", "refresh", "Bearer", "sessionId"} {
		if strings.Contains(string(encoded), secret) {
			t.Fatalf("secret %s escaped", secret)
		}
	}
}

func TestDiagnosticBadResponsesNeverBecomePositiveClues(t *testing.T) {
	cases := []struct{ name, body string }{
		{"bilibili", `{}`}, {"bilibili", `{"code":0}`}, {"bilibili", `{"code":0,"data":{"dash":{"video":[{}]}}}`},
		{"disney-plus", `{"assertion":123}`}, {"disney-plus", `{"assertion":""}`},
		{"youtube", `<html>YouTube Premium ad-free</html>`}, {"gemini", `<html>challenge</html>`},
		{"spotify", `{"countryCode":"ZZZ"}`}, {"tiktok", `{"region":"JP"}`}, {"prime-video", `{"currentTerritory":"ZZZ"}`},
	}
	for i, scenario := range cases {
		t.Run(scenario.name+string(rune('A'+i)), func(t *testing.T) {
			diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, scenario.body) }, true)
			item := diagnosticCheck(t, scenario.name, "advanced")
			if item.Status != "failed" {
				t.Fatalf("bad response became a clue: %+v", item)
			}
		})
	}
}

func TestDiagnosticChatGPTKeepsIndependentEndpointObservations(t *testing.T) {
	for _, scenario := range []struct {
		name, iosBody, iosObservation, webBody string
		traceBroken                            bool
	}{
		{"isp-web-unknown", "you may be connected to a disallowed isp", "disallowed-isp", `{}`, false},
		{"blocked-web-unknown", "sorry, you have been blocked", "blocked", `{}`, false},
		{"isp-trace-broken", "you may be connected to a disallowed isp", "disallowed-isp", `{}`, true},
		{"blocked-web-malformed", "sorry, you have been blocked", "blocked", `{`, false},
		{"isp-web-unsupported", "you may be connected to a disallowed isp", "disallowed-isp", `{"error":{"code":"unsupported_country"}}`, false},
		{"blocked-trace-broken-web-unsupported", "sorry, you have been blocked", "blocked", `{"error":{"code":"unsupported_country"}}`, true},
		{"recognized-page-web-unknown", "request is not allowed. please try again later.", "observed", `{}`, false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var calls atomic.Int32
			diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				switch r.Host {
				case "ios.chat.openai.com":
					io.WriteString(w, scenario.iosBody)
				case "chat.openai.com":
					if scenario.traceBroken {
						w.Header().Set("Content-Length", "200")
					}
					io.WriteString(w, "loc=JP\nsynthetic-private-trace\n")
				default:
					io.WriteString(w, scenario.webBody)
				}
			}, true)
			item := diagnosticCheck(t, "chatgpt", "advanced")
			if calls.Load() != 3 || len(item.Steps) != 3 || item.Status == "available" {
				t.Fatalf("independent checks were lost or overstated: %+v calls=%d", item, calls.Load())
			}
			encoded, _ := json.Marshal(item)
			var wire struct {
				Steps []map[string]any `json:"steps"`
			}
			json.Unmarshal(encoded, &wire)
			if wire.Steps[0]["observation"] != scenario.iosObservation {
				t.Fatalf("iOS observation was lost: %s", encoded)
			}
			if scenario.traceBroken {
				if wire.Steps[1]["outcome"] != "read-error" || item.Region != "" {
					t.Fatalf("partial trace became a region: %s", encoded)
				}
			} else if wire.Steps[1]["region"] != "JP" || item.Region != "JP" {
				t.Fatalf("independent trace region was lost: %s", encoded)
			}
			if strings.Contains(scenario.webBody, "unsupported_country") && wire.Steps[2]["observation"] != "unsupported-region" {
				t.Fatalf("Web observation was lost: %s", encoded)
			}
			if strings.Contains(string(encoded), "synthetic-private-trace") {
				t.Fatal("raw body escaped")
			}
		})
	}
}

func TestDiagnosticUnsupportedPurposeAndDuplicateSelection(t *testing.T) {
	proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(204)
	}, true)
	count := func() int {
		proxy.mu.Lock()
		defer proxy.mu.Unlock()
		return len(proxy.targets)
	}
	for _, purpose := range []string{"unknown", "advanced"} {
		handleServiceCheck(&ServiceCheckParams{ProxyName: "diagnostic-node", Names: []string{"google"}, Purpose: purpose})
	}
	if count() != 0 {
		t.Fatal("unsupported purpose sent a request")
	}
	items := handleServiceCheck(&ServiceCheckParams{ProxyName: "diagnostic-node", Names: []string{"google", "google", "unknown"}, Purpose: "basic"})
	if len(items) != 1 || count() != 1 {
		t.Fatalf("duplicate names sent extra work: items=%d dials=%d", len(items), count())
	}
}

func TestDiagnosticRedirectDoesNotStoreOrReplayCookies(t *testing.T) {
	var cookieSeen atomic.Bool
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" || r.Header.Get("Referer") != "" {
			cookieSeen.Store(true)
		}
		if r.URL.Path != "/final" {
			w.Header().Set("Set-Cookie", "session=synthetic-secret; Secure")
			http.Redirect(w, r, "/final", 302)
			return
		}
		io.WriteString(w, `{"countryCode":"JP"}`)
	}, true)
	item := diagnosticCheck(t, "spotify", "advanced")
	if item.Status != "observed" || len(item.Steps) != 2 || cookieSeen.Load() {
		t.Fatalf("redirect cookie behavior: %+v cookie=%v", item, cookieSeen.Load())
	}
}

func TestDiagnosticRealConsumerRejectsOversizedAndTruncatedBodies(t *testing.T) {
	for _, scenario := range []string{"oversized", "truncated"} {
		t.Run(scenario, func(t *testing.T) {
			diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
				if scenario == "oversized" {
					io.WriteString(w, strings.Repeat(" ", serviceSmallMaxBody+1)+`{"countryCode":"JP"}`)
				} else {
					w.Header().Set("Content-Length", "200")
					io.WriteString(w, `{"countryCode":"JP"}`)
				}
			}, true)
			item := diagnosticCheck(t, "spotify", "advanced")
			want := "body-limit"
			if scenario == "truncated" {
				want = "read-error"
			}
			if item.Status != "failed" || item.Reason != want || item.Region != "" {
				t.Fatalf("incomplete response became a clue: %+v", item)
			}
		})
	}
}

func TestDiagnosticStrictReadDistinguishesCompletionMarkerLimitAndErrors(t *testing.T) {
	for _, scenario := range []struct {
		name, input string
		limit       int64
		until       func(string) bool
		want        string
	}{
		{"complete", "1234", 4, nil, "complete"}, {"limit", "12345", 4, nil, "body-limit"},
		{"marker", "1234marker5678", 30, func(s string) bool { return strings.Contains(s, "marker") }, "marker"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			_, outcome := readServiceBody(strings.NewReader(scenario.input), scenario.limit, scenario.until)
			if outcome != scenario.want {
				t.Fatalf("outcome=%s", outcome)
			}
		})
	}
	reader := io.MultiReader(strings.NewReader(`{"countryCode":"JP"}`), diagnosticReadError{})
	body, outcome := readServiceBody(reader, 1024, nil)
	if outcome != "read-error" || body != "" {
		t.Fatalf("truncated prefix accepted: %s %s", body, outcome)
	}
}

type diagnosticReadError struct{}

func (diagnosticReadError) Read([]byte) (int, error) { return 0, io.ErrUnexpectedEOF }

func TestDiagnosticScopeCancellationClosesInFlightConnection(t *testing.T) {
	entered := make(chan struct{})
	closed := make(chan struct{})
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { close(entered); <-r.Context().Done(); close(closed) }, true)
	ctx, cancel := context.WithCancel(context.Background())
	checker := serviceCheckers[0]
	checker.purpose = "basic"
	answer := make(chan ServiceCheckItem, 1)
	go func() { answer <- runServiceCheck(ctx, checker, "diagnostic-node", time.Second, time.Now()) }()
	<-entered
	cancel()
	select {
	case item := <-answer:
		if item.Status == serviceAvailable {
			t.Fatal("cancelled request succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("cancel did not release check")
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("cancel did not close connection")
	}
}

func TestDiagnosticRejectsTrustedCertificateForWrongHost(t *testing.T) {
	var reached atomic.Int32
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { reached.Add(1) }, true, "wrong.fixture.invalid")
	item := diagnosticCheck(t, "google", "basic")
	if item.Status != serviceFailed || item.Reason != "tls-failed" || reached.Load() != 0 {
		t.Fatalf("wrong identity accepted: %+v reached=%d", item, reached.Load())
	}
}

func TestDiagnosticNativeScopeRetirementCancelsTheActualConsumer(t *testing.T) {
	entered, closed := make(chan struct{}), make(chan struct{})
	proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { close(entered); <-r.Context().Done(); close(closed) }, true)
	registry, _ := appRequestFixture(t)
	state := registry.state
	state.Revision++
	state.IntentRunning = true
	state.Phase = "started"
	registry.publish(state)
	owner := registry.newOwner()
	registry.setPhase(owner, "ready")
	registry.socketGate = func(string, AppRequestState, int) error { return nil }
	appConsumerHooks(t, registry)
	previous := appRequests
	appRequests = registry
	t.Cleanup(func() { appRequests = previous })
	lease, err := registry.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "maintenance", Trigger: "manual", Mode: "proxy", Proxy: "diagnostic-node", Key: "service:google:basic"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	params := &ServiceCheckParams{ScopeID: lease.(*appRequestLease).id, Names: []string{"google"}, Purpose: "basic", ProxyName: "diagnostic-node", Timeout: 1000}
	done := make(chan []ServiceCheckItem, 1)
	go func() { done <- handleServiceCheck(params) }()
	select {
	case <-entered:
	case items := <-done:
		t.Fatalf("scoped request ended before reaching loopback: %+v", items)
	case <-time.After(time.Second):
		t.Fatal("scoped request did not reach loopback")
	}
	state.Revision++
	state.IntentRunning = false
	state.Phase = "stopped"
	state.Reason = "userStop"
	registry.publish(state)
	select {
	case items := <-done:
		if len(items) != 1 || items[0].Status == serviceAvailable {
			t.Fatalf("retired result=%+v", items)
		}
	case <-time.After(time.Second):
		t.Fatal("retirement did not stop consumer")
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("scope did not close actual socket")
	}
	if got := handleServiceCheck(params); len(got) != 0 {
		t.Fatalf("retired scope reused: %+v", got)
	}
	proxy.mu.Lock()
	defer proxy.mu.Unlock()
	if len(proxy.targets) != 1 {
		t.Fatalf("unexpected successor/fallback: %v", proxy.targets)
	}
}

func TestDiagnosticMultiStepKeepsAllActualExitsAndNoAggregateLatency(t *testing.T) {
	proxy := diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/devices":
			io.WriteString(w, `{"assertion":"synthetic"}`)
		case "/token":
			io.WriteString(w, `{"refresh_token":"synthetic"}`)
		default:
			io.WriteString(w, `{"extensions":{"sdk":{"session":{"location":{"countryCode":"JP"},"inSupportedLocation":true}}}}`)
		}
	}, true)
	proxy.alternating = true
	item := diagnosticCheck(t, "disney-plus", "advanced")
	if item.Status != "observed" || len(item.Steps) != 3 || len(item.Chains) != 0 || item.Delay != 0 || item.HTTPStatus != 0 {
		t.Fatalf("aggregate=%+v", item)
	}
	for index, step := range item.Steps {
		if !slices.Equal(step.Chains, []string{fmt.Sprintf("exit-%d", index+1)}) {
			t.Fatalf("step route=%+v", step)
		}
	}
}

func TestDiagnosticVersionChangeCannotBecomeAnAdvancedConclusion(t *testing.T) {
	clearRoute()
	t.Cleanup(clearRoute)
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) {
		currentRoute.mu.Lock()
		currentRoute.picksVersion++
		currentRoute.mu.Unlock()
		io.WriteString(w, `{"countryCode":"JP"}`)
	}, true)
	item := diagnosticCheck(t, "spotify", "advanced")
	if item.Status != serviceFailed || item.Reason != "route-changed" || len(item.Chains) != 0 {
		t.Fatalf("mixed version accepted: %+v", item)
	}
}

func TestDiagnosticTotalElapsedIncludesServiceQueue(t *testing.T) {
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, `{"countryCode":"JP"}`) }, true)
	for i := 0; i < serviceCheckConcurrency; i++ {
		serviceCheckSlots <- struct{}{}
	}
	var once sync.Once
	free := func() {
		once.Do(func() {
			for i := 0; i < serviceCheckConcurrency; i++ {
				<-serviceCheckSlots
			}
		})
	}
	t.Cleanup(free)
	done := make(chan ServiceCheckItem, 1)
	go func() { done <- diagnosticCheck(t, "spotify", "advanced") }()
	waitForClaim(t, "spotify")
	<-time.After(40 * time.Millisecond)
	free()
	item := <-done
	if item.Status != "observed" || item.Elapsed < 35 || item.Delay != 0 {
		t.Fatalf("service queue omitted: %+v", item)
	}
}
