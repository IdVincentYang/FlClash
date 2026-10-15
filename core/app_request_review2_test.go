package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/geodata"
	mh "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/component/updater"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

func TestAppRequestURLTestProviderReplacementCancelsWithoutWatch(t *testing.T) {
	for _, health := range []bool{false, true} {
		t.Run(strconv.FormatBool(health), func(t *testing.T) {
			r := revisionRegistry(t)
			entered, closed := make(chan struct{}), make(chan struct{})
			origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { close(entered); <-req.Context().Done(); close(closed) }))
			defer origin.Close()
			hop := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if req.Method != "CONNECT" || req.Host != origin.Listener.Addr().String() {
					http.Error(w, "blocked", 403)
					return
				}
				remote, err := net.Dial("tcp", origin.Listener.Addr().String())
				if err != nil {
					return
				}
				conn, _, err := w.(http.Hijacker).Hijack()
				if err != nil {
					remote.Close()
					return
				}
				_, _ = io.WriteString(conn, "HTTP/1.1 200 Connection established\r\n\r\n")
				go func() { defer conn.Close(); defer remote.Close(); _, _ = io.Copy(remote, conn) }()
				_, _ = io.Copy(conn, remote)
				conn.Close()
				remote.Close()
			}))
			defer hop.Close()
			_, portText, _ := net.SplitHostPort(hop.Listener.Addr().String())
			owner := r.currentOwner()
			parser := func(data []byte) ([]C.Proxy, error) {
				port, err := strconv.Atoi(string(data))
				if err != nil {
					return nil, err
				}
				node, err := adapter.ParseProxy(map[string]any{"name": "same provider node", "type": "http", "server": "127.0.0.1", "port": port}, adapter.WithProviderName("replacement provider"), adapter.WithRequestOwner(owner))
				if err != nil {
					return nil, err
				}
				return []C.Proxy{node}, nil
			}
			path := filepath.Join(t.TempDir(), "nodes")
			os.WriteFile(path, []byte(portText), 0600)
			hc := provider.NewHealthCheck(nil, origin.URL, 5000, 0, true, nil)
			pd, err := provider.NewProxySetProvider("replacement provider", 0, nil, parser, resource.NewHTTPVehicle("http://127.0.0.1:1/provider", path, "DIRECT", nil, time.Second, 0), hc)
			if err != nil {
				t.Fatal(err)
			}
			defer pd.Close()
			if err = pd.Initial(); err != nil {
				t.Fatal(err)
			}
			oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
			tunnel.UpdateProxies(nil, map[string]P.ProxyProvider{pd.Name(): pd})
			defer tunnel.UpdateProxies(oldProxies, oldProviders)
			stopRouteWatch()
			node := pd.Proxies()[0]
			before, _ := node.MarshalJSON()
			oldHook := adapter.UrlTestHook
			var hooks atomic.Int32
			adapter.UrlTestHook = func(string, string, uint16) { hooks.Add(1) }
			defer func() { adapter.UrlTestHook = oldHook }()
			done := make(chan struct{})
			go func() {
				defer close(done)
				if health {
					pd.HealthCheck()
				} else {
					_, _ = node.URLTest(context.Background(), origin.URL, nil)
				}
			}()
			select {
			case <-entered:
			case <-time.After(2 * time.Second):
				t.Fatal("actual URLTest did not reach origin")
			}
			if _, _, err = pd.SideUpdate([]byte("1")); err != nil {
				t.Fatal(err)
			}
			select {
			case <-closed:
			case <-time.After(time.Second):
				t.Fatal("background provider update did not close old URLTest")
			}
			select {
			case <-done:
			case <-time.After(time.Second):
				t.Fatal("old URLTest remained running")
			}
			if _, err := node.URLTest(context.Background(), origin.URL, nil); err == nil {
				t.Fatal("old node started after same-owner replacement")
			}
			after, _ := node.MarshalJSON()
			if string(before) != string(after) || hooks.Load() != 0 {
				t.Fatal("replaced URLTest published late history/alive/extra/hook")
			}
		})
	}
}

func TestAppRequestOldGeoBatchDoesNotInvalidateNewOwner(t *testing.T) { testOldGeoBatch(t, "owner") }
func TestAppRequestGeoBatchKeepsNativeVersion(t *testing.T) {
	for _, change := range []string{"revision", "epoch"} {
		t.Run(change, func(t *testing.T) { testOldGeoBatch(t, change) })
	}
}
func testOldGeoBatch(t *testing.T, change string) {
	r := revisionRegistry(t)
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	oldMode := tunnel.Mode()
	tunnel.SetMode(tunnel.Direct)
	defer tunnel.SetMode(oldMode)
	home := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(home)
	mmdb, _ := os.ReadFile("../assets/data/GEOIP.metadb")
	asn, _ := os.ReadFile("../assets/data/ASN.mmdb")
	os.WriteFile(C.Path.MMDB(), mmdb, 0600)
	os.WriteFile(C.Path.ASN(), asn, 0600)
	if err := geodata.InitGeoIP(); err != nil {
		t.Fatal(err)
	}
	if err := geodata.InitASN(); err != nil {
		t.Fatal(err)
	}
	waiting, ending, release := make(chan struct{}), make(chan struct{}), make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/asn" {
			close(waiting)
			<-req.Context().Done()
			return
		}
		w.Write(asn)
	}))
	defer server.Close()
	oldMMDB, oldASN := geodata.MmdbUrl(), geodata.ASNUrl()
	geodata.SetMmdbUrl(server.URL + "/mmdb")
	geodata.SetASNUrl(server.URL + "/asn")
	defer geodata.SetMmdbUrl(oldMMDB)
	defer geodata.SetASNUrl(oldASN)
	oldHook := updater.GeoUpdateHook
	var first atomic.Bool
	updater.GeoUpdateHook = func(name string, updating, skipped bool, err error) {
		oldHook(name, updating, skipped, err)
		if !updating {
			if name == "MMDB" && err == nil {
				first.Store(true)
			}
			if name == "ASN" {
				close(ending)
				<-release
			}
		}
	}
	defer func() { updater.GeoUpdateHook = oldHook }()
	done := make(chan error, 1)
	go func() { done <- updater.UpdateGeoDatabases() }()
	select {
	case <-waiting:
	case <-time.After(2 * time.Second):
		t.Fatal("old batch did not start sibling")
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		r.mu.Lock()
		live := false
		for _, l := range r.leases {
			if l.spec.Key == "geo:MMDB" {
				live = true
			}
		}
		r.mu.Unlock()
		if first.Load() && !live {
			break
		}
		if time.Now().After(deadline) {
			close(release)
			t.Fatal("first resource did not complete")
		}
		time.Sleep(time.Millisecond)
	}
	owner := r.currentOwner()
	if change == "owner" {
		owner = r.newOwner()
		r.setPhase(owner, "ready")
	} else {
		changeRequestNativeVersion(r, change)
	}
	select {
	case <-ending:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("cancelled batch did not reach end")
	}
	lease, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "request", Key: "new auto", Mode: "auto"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { w.Write([]byte("new")) }))
	defer origin.Close()
	response, err := mh.HttpRequest(lease.Context(), origin.URL, "GET", nil, nil, mh.WithScope(lease))
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	epoch, _ := routeStamp()
	close(release)
	<-done
	if next, _ := routeStamp(); next != epoch || lease.Check() != nil {
		t.Fatal("old batch invalidated the new owner's Auto scope")
	}
	currentGeo, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "geo", Key: "notification gating", Proxy: "DIRECT"})
	if err != nil {
		t.Fatal(err)
	}
	defer currentGeo.Close()
	completion := currentGeo.(*appRequestLease).CompletionVersion()
	updater.GeoUpdatedHook(&completion, map[string]string{"ASN": "http://127.0.0.1/obsolete-source"})
	if next, _ := routeStamp(); next != epoch || lease.Check() != nil {
		t.Fatal("obsolete resource source invalidated new scope")
	}
	updater.GeoUpdatedHook(&completion, nil)
	if next, _ := routeStamp(); next == epoch || lease.Check() == nil {
		t.Fatal("current notification did not invalidate Auto scope")
	}

}

func TestAppRequestConcurrentGrantCheckAndUnrelatedSelections(t *testing.T) {
	r := revisionRegistry(t)
	nodes := []C.Proxy{adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "fixed"})), adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "other"}))}
	hc := provider.NewHealthCheck(nodes, "", 0, 0, false, nil)
	pd, _ := provider.NewCompatibleProvider("select source", nodes, hc)
	defer pd.Close()
	g, _ := outboundgroup.NewSelector(outboundgroup.GroupCommonOption{Name: "unrelated"}, outboundgroup.SelectorOption{}, nodes[0], []P.ProxyProvider{pd})
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"fixed": nodes[0], "other": nodes[1], "unrelated": adapter.NewProxy(g)}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { w.Write([]byte("ok")) }))
	defer origin.Close()
	makeLease := func(key string) (*appRequestLease, error) {
		l, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "request", Key: key, Proxy: "fixed", Mode: "auto"})
		if err != nil {
			return nil, err
		}
		response, err := mh.HttpRequest(l.Context(), origin.URL, "GET", nil, nil, mh.WithScope(l))
		if err != nil {
			l.Close()
			return nil, err
		}
		io.Copy(io.Discard, response.Body)
		response.Body.Close()
		return l.(*appRequestLease), nil
	}
	lease, err := makeLease("checks")
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	failures := make(chan error, 4)
	var wg sync.WaitGroup
	wg.Add(3)
	go func() {
		defer wg.Done()
		for i := 0; i < 300; i++ {
			result := r.control(appRequestControl{Action: "check", ID: lease.id}).(map[string]bool)
			if !result["ok"] {
				failures <- fmt.Errorf("unrelated choice invalidated check")
				return
			}
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 60; i++ {
			l, err := makeLease(fmt.Sprint("grant", i))
			if err != nil {
				failures <- err
				return
			}
			receipt, err := l.GrantCommit()
			if err != nil {
				l.Close()
				failures <- err
				return
			}
			receipt.Complete()
			l.Close()
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 300; i++ {
			result := handleChangeProxy(&ChangeProxyParams{GroupName: "unrelated", ProxyName: nodes[i%2].Name()})
			if result.Message != "" {
				failures <- fmt.Errorf("%s", result.Message)
				return
			}
		}
	}()
	wg.Wait()
	close(failures)
	for err := range failures {
		t.Fatal(err)
	}
}

func TestAppRequestSingleGeoNotificationKeepsCapturedOwner(t *testing.T) {
	testSingleGeoNotification(t, "owner")
}
func TestAppRequestSingleGeoNotificationKeepsVersions(t *testing.T) {
	for _, change := range []string{"revision", "epoch", "operation", "current"} {
		t.Run(change, func(t *testing.T) { testSingleGeoNotification(t, change) })
	}
}
func testSingleGeoNotification(t *testing.T, change string) {
	r := revisionRegistry(t)
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	oldMode := tunnel.Mode()
	tunnel.SetMode(tunnel.Direct)
	defer tunnel.SetMode(oldMode)

	home := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(home)
	oldData, _ := os.ReadFile("../assets/data/GEOIP.metadb")
	newData, _ := os.ReadFile("../assets/data/ASN.mmdb")
	if err := os.WriteFile(C.Path.MMDB(), oldData, 0600); err != nil {
		t.Fatal(err)
	}
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) { _, _ = w.Write(newData) }))
	defer origin.Close()
	oldURL := geodata.MmdbUrl()
	geodata.SetMmdbUrl(origin.URL)
	defer geodata.SetMmdbUrl(oldURL)
	lease, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "geo", Key: "single geo", Proxy: "DIRECT", URL: origin.URL})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	notifying, release := make(chan requestscope.Owner, 1), make(chan struct{})
	hook := updater.GeoUpdatedHook
	updater.GeoUpdatedHook = func(completion *requestscope.Completion, sources map[string]string) {
		notifying <- completion.Spec.Owner
		<-release
		hook(completion, sources)
	}
	defer func() { updater.GeoUpdatedHook = hook }()
	done := make(chan error, 1)
	go func() { done <- updater.UpdateGeoResource(lease.Context(), "MMDB", lease) }()
	var oldOwner requestscope.Owner
	select {
	case oldOwner = <-notifying:
	case <-time.After(2 * time.Second):
		t.Fatal("actual single Geo did not reach notification")
	}
	if oldOwner != r.currentOwner() {
		t.Fatal("single Geo lost its request owner")
	}
	owner := r.currentOwner()
	switch change {
	case "owner":
		owner = r.newOwner()
		r.setPhase(owner, "ready")
	case "revision", "epoch":
		changeRequestNativeVersion(r, change)
	case "operation":
		newer, err := r.begin(context.Background(), lease.(*appRequestLease).spec)
		if err != nil {
			t.Fatal(err)
		}
		if err = updater.UpdateGeoResource(newer.Context(), "MMDB", newer); err != nil {
			t.Fatal(err)
		}
		newer.Close()
	}
	next, err := r.begin(context.Background(), requestscope.Spec{Owner: owner, Kind: "request", Key: "new auto after single", Mode: "auto"})
	if err != nil {
		t.Fatal(err)
	}
	defer next.Close()
	response, err := mh.HttpRequest(next.Context(), origin.URL, "GET", nil, nil, mh.WithScope(next))
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	epoch, _ := routeStamp()
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	current, _ := routeStamp()
	if change == "current" {
		if current == epoch || next.Check() == nil {
			t.Fatal("current valid single Geo did not notify")
		}
	} else if current != epoch || next.Check() != nil {
		t.Fatal("old single Geo notified a new lifecycle or operation")
	}
}

func changeRequestNativeVersion(r *appRequestRegistry, change string) {
	state := r.state
	if change == "epoch" {
		state.ProcessEpoch += "-new"
		state.Revision = 1
		r.publish(state)
		return
	}
	state.Revision++
	state.IntentRunning = false
	state.Phase = "stopped"
	state.Reason = "userStop"
	r.publish(state)
	state.Revision++
	state.IntentRunning = true
	state.Phase = "started"
	state.Reason = "none"
	r.publish(state)
}
