package main

import (
	"context"
	"errors"
	"io"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/component/geodata"
	mh "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/updater"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestAppRequestGeoBatchRejectsParentBeforeCleanup(t *testing.T) {
	r := revisionRegistry(t)
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	oldMode := tunnel.Mode()
	tunnel.SetMode(tunnel.Direct)
	defer tunnel.SetMode(oldMode)
	home, mode := C.Path.HomeDir(), geodata.GeodataMode()
	C.SetHomeDir(t.TempDir())
	geodata.SetGeodataMode(false)
	defer C.SetHomeDir(home)
	defer geodata.SetGeodataMode(mode)
	for path, fixture := range map[string]string{C.Path.MMDB(): "../assets/data/GEOIP.metadb", C.Path.ASN(): "../assets/data/ASN.mmdb"} {
		data, err := os.ReadFile(fixture)
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := geodata.InitGeoIP(); err != nil {
		t.Fatal(err)
	}
	if err := geodata.InitASN(); err != nil {
		t.Fatal(err)
	}
	var requests atomic.Int32
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		requests.Add(1)
		_, _ = io.WriteString(w, "unexpected old batch")
	}))
	defer origin.Close()
	mmdb, asn := geodata.MmdbUrl(), geodata.ASNUrl()
	geodata.SetMmdbUrl(origin.URL + "/mmdb")
	geodata.SetASNUrl(origin.URL + "/asn")
	defer geodata.SetMmdbUrl(mmdb)
	defer geodata.SetASNUrl(asn)

	begin := requestscope.BeginHook
	waiting, release := make(chan context.Context, 2), make(chan struct{})
	requestscope.BeginHook = func(ctx context.Context, spec requestscope.Spec) (requestscope.Lease, error) {
		if spec.Kind == "geo" {
			waiting <- ctx
			<-release
		}
		return begin(ctx, spec)
	}
	defer func() { requestscope.BeginHook = begin }()
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	done := make(chan error, 1)
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		done <- updater.UpdateGeoDatabases()
	}()
	defer func() {
		unblock()
		r.flushCleanup()
		select {
		case <-finished:
		case <-time.After(2 * time.Second):
			t.Error("Geo batch did not finish during cleanup")
		}
	}()
	var parent requestscope.Lease
	for i := 0; i < 2; i++ {
		select {
		case ctx := <-waiting:
			if inherited := requestscope.FromContext(ctx); inherited == nil || parent != nil && inherited != parent {
				t.Fatal("actual Geo resources did not inherit one batch parent")
			} else {
				parent = inherited
			}
		case <-time.After(2 * time.Second):
			t.Fatal("actual Geo batch did not reach both child registrations")
		}
	}
	owner := r.currentOwner()
	state := r.state
	state.Revision++
	state.NetworkRevision++
	if !r.publishPrepared(state) || parent.Context().Err() != nil || r.currentOwner() != owner || !r.state.IntentRunning || r.state.Phase != "started" {
		t.Fatal("fixture did not isolate the prepared-before-cancel native revision window")
	}
	r.mu.Lock()
	operations := maps.Clone(r.operations)
	r.mu.Unlock()
	unblock()
	select {
	case err := <-done:
		if !errors.Is(err, requestscope.ErrCancelled) {
			t.Fatal("old batch children borrowed the new native revision", err, "target requests", requests.Load())
		}
	case <-time.After(2 * time.Second):
		t.Fatal("rejected batch did not finish")
	}
	r.mu.Lock()
	unchanged := reflect.DeepEqual(operations, r.operations) && len(r.leases) == 0 && len(r.latest) == 0
	r.mu.Unlock()
	if requests.Load() != 0 || !unchanged {
		t.Fatal("rejected old batch performed IO or mutated registry before cleanup", requests.Load(), unchanged)
	}
}

func TestAppRequestOldParentCannotReplaceNewGeoChild(t *testing.T) {
	for _, invalidation := range []string{"closed", "cancelled", "context", "prepared", "granted"} {
		t.Run(invalidation, func(t *testing.T) {
			r := revisionRegistry(t)
			oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
			tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
			defer tunnel.UpdateProxies(oldProxies, oldProviders)
			oldMode := tunnel.Mode()
			tunnel.SetMode(tunnel.Direct)
			defer tunnel.SetMode(oldMode)
			parent, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "geo-batch", Key: "geo-batch"})
			if err != nil {
				t.Fatal(err)
			}
			defer parent.Close()
			parentContext := parent.Context()
			switch invalidation {
			case "closed":
				cleanup := parent.(*appRequestLease).prepareClose()
				defer cleanup()
			case "cancelled":
				parent.Close()
			case "context":
				ctx, cancel := context.WithCancel(parentContext)
				cancel()
				parentContext = ctx
			case "prepared":
				state := r.state
				state.Revision++
				state.NetworkRevision++
				r.publishPrepared(state)
				defer r.flushCleanup()
			case "granted":
				receipt, err := parent.GrantCommit()
				if err != nil {
					t.Fatal(err)
				}
				defer receipt.Complete()
			}
			entered, release := make(chan struct{}), make(chan struct{})
			var once sync.Once
			unblock := func() { once.Do(func() { close(release) }) }
			origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				close(entered)
				select {
				case <-release:
					_, _ = io.WriteString(w, "new child completed")
				case <-req.Context().Done():
				}
			}))
			defer origin.Close()
			defer unblock()
			spec := requestscope.Spec{Owner: r.currentOwner(), Kind: "geo", Key: "geo:ASN", URL: origin.URL, Proxy: "DIRECT"}
			newer, err := r.begin(context.Background(), spec)
			if err != nil {
				t.Fatal(err)
			}
			defer newer.Close()
			done := make(chan error, 1)
			go func() {
				response, err := mh.HttpRequest(newer.Context(), origin.URL, "GET", nil, nil, mh.WithScope(newer))
				if err == nil {
					var body []byte
					body, err = io.ReadAll(response.Body)
					response.Body.Close()
					if err == nil && string(body) != "new child completed" {
						err = errors.New("new child response was incomplete")
					}
				}
				done <- err
			}()
			select {
			case <-entered:
			case <-time.After(2 * time.Second):
				t.Fatal("new actual HTTP did not start")
			}
			current := newer.(*appRequestLease)
			r.mu.Lock()
			operations, count := maps.Clone(r.operations), len(r.leases)
			r.mu.Unlock()
			rejected, err := r.begin(parentContext, spec)
			if rejected != nil {
				rejected.Close()
			}
			if !errors.Is(err, requestscope.ErrCancelled) {
				t.Fatal("invalid old parent registered a child", err)
			}
			r.mu.Lock()
			unchanged := reflect.DeepEqual(operations, r.operations) && len(r.leases) == count && r.latest["geo:geo:ASN"] == current && r.leases[current.id] == current && len(current.closers) != 0
			r.mu.Unlock()
			if !unchanged || newer.Check() != nil {
				t.Fatal("rejected parent advanced operations, replaced latest, or closed the newer socket")
			}
			unblock()
			select {
			case err := <-done:
				if err != nil {
					t.Fatal("new same-key HTTP was interrupted", err)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("new same-key HTTP did not finish")
			}
		})
	}
}
