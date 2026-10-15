package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	ntpTime "github.com/metacubex/mihomo/ntp"
	ntpService "github.com/metacubex/mihomo/ntp/ntp"
	S5 "github.com/metacubex/mihomo/transport/socks5"
	"github.com/metacubex/mihomo/tunnel"
)

func revisionRegistry(t *testing.T) *appRequestRegistry {
	t.Helper()
	r, _ := appRequestFixture(t)
	state := r.state
	state.Revision++
	state.IntentRunning, state.Phase, state.Reason = true, "started", "none"
	r.publish(state)
	owner := r.newOwner()
	r.setPhase(owner, "ready")
	appConsumerHooks(t, r)
	old := appRequests
	appRequests = r
	t.Cleanup(func() { appRequests = old })
	r.socketGate = func(string, AppRequestState, int) error { return nil }
	return r
}

func TestAppRequestDartSpec(t *testing.T) {
	raw := os.Getenv("L1_REQUEST_SPEC")
	if raw == "" {
		t.Skip("invoked by the Dart native-spec bridge")
	}
	var input struct {
		State  AppRequestState
		Params appRequestControl
	}
	if err := json.Unmarshal([]byte(raw), &input); err != nil {
		t.Fatal(err)
	}
	r := newAppRequestRegistry()
	defer r.closePrivate()
	r.publish(input.State)
	r.owner = requestscope.Owner{ID: input.Params.Owner}
	r.phase = "ready"
	r.client, r.clientReady, r.dataset = input.Params.Client, true, input.Params.Dataset
	result := r.control(input.Params)
	if failure, ok := result.(map[string]string); ok {
		t.Fatal(failure)
	}
}

func TestAppRequestFallbackSetOwnsURLTestAndRejectsOldProxy(t *testing.T) {
	r := revisionRegistry(t)
	priorHook := adapter.UrlTestHook
	var hookCalls atomic.Int32
	adapter.UrlTestHook = func(url, name string, delay uint16) {
		hookCalls.Add(1)
		if priorHook != nil {
			priorHook(url, name, delay)
		}
	}
	defer func() { adapter.UrlTestHook = priorHook }()
	entered := make(chan struct{})
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if requests.Add(1) == 1 {
			w.WriteHeader(503)
			return
		}
		close(entered)
		<-req.Context().Done()
	}))
	defer server.Close()
	node := adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "owned node"}))
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{node.Name(): node}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	expected, _ := utils.NewUnsignedRanges[uint16]("200")
	if _, err := node.URLTest(context.Background(), server.URL, expected); err != nil {
		t.Fatal(err)
	}
	if node.AliveForTestUrl(server.URL) {
		t.Fatal("fixture did not mark URL unavailable")
	}
	initial := len(node.DelayHistory())
	initialExtra := node.ExtraDelayHistories()
	initialState, _ := node.MarshalJSON()
	initialHooks := hookCalls.Load()
	hc := provider.NewHealthCheck([]C.Proxy{node}, "", 0, 0, false, nil)
	pd, _ := provider.NewCompatibleProvider("fallback source", []C.Proxy{node}, hc)
	defer pd.Close()
	group, _ := outboundgroup.NewFallback(outboundgroup.GroupCommonOption{Name: "fallback", URL: server.URL, ExpectedStatus: "200"}, outboundgroup.FallbackOption{}, node, []P.ProxyProvider{pd})
	tunnel.UpdateProxies(map[string]C.Proxy{node.Name(): node, "fallback": adapter.NewProxy(group)}, nil)
	done := make(chan *ChangeProxyResult, 1)
	go func() { done <- handleChangeProxy(&ChangeProxyParams{GroupName: "fallback", ProxyName: node.Name()}) }()
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		t.Fatal("Fallback.Set did not enter its URLTest")
	}
	state := r.state
	state.Revision++
	state.IntentRunning = false
	state.Phase, state.Reason = "stopped", "userStop"
	r.publish(state)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("revocation did not close the real URLTest")
	}
	if len(node.DelayHistory()) != initial || node.AliveForTestUrl(server.URL) {
		t.Fatal("cancelled fallback wrote history or alive")
	}
	finalState, _ := node.MarshalJSON()
	if !reflect.DeepEqual(initialExtra, node.ExtraDelayHistories()) || string(initialState) != string(finalState) || hookCalls.Load() != initialHooks {
		t.Fatal("cancelled fallback published extra state, alive or hook")
	}
	next := r.newOwner()
	r.setPhase(next, "ready")
	state.Revision++
	state.IntentRunning, state.Phase, state.Reason = true, "started", "none"
	r.publish(state)
	if _, err := node.URLTest(context.Background(), server.URL, expected); err == nil {
		t.Fatal("old proxy borrowed the current owner")
	}
	if requests.Load() != 2 {
		t.Fatal("old proxy sent a request")
	}
	if hookCalls.Load() != initialHooks {
		t.Fatal("retired URLTest published a hook")
	}
}

func TestAppRequestOwningServiceStopClosesRealBusinessListener(t *testing.T) {
	r, _ := appRequestFixture(t)
	private, err := r.privateEndpoint()
	if err != nil {
		t.Fatal(err)
	}
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := reservation.Addr().String()
	port := reservation.Addr().(*net.TCPAddr).Port
	_ = reservation.Close()
	listener.SetAllowLan(false)
	listener.SetBindAddress("127.0.0.1")
	listener.ReCreateMixed(port, tunnel.Tunnel)
	isRunning.Store(true)
	defer handleStopListener()
	connect := func(address string) bool {
		conn, err := net.DialTimeout("tcp", address, time.Second)
		if err == nil {
			_ = conn.Close()
		}
		return err == nil
	}
	if !connect(addr) {
		t.Fatal("business listener did not open")
	}
	current := requestTunIdentity{"new service", 2}
	closed := false
	if stopOwnedRequestService(requestTunIdentity{"old service", 1}, current, func() { closed = true }) || closed || !connect(addr) {
		t.Fatal("old service stopped current listener")
	}
	if !stopOwnedRequestService(current, current, func() { closed = true }) || !closed || isRunning.Load() || connect(addr) {
		t.Fatal("owning service did not clean listener")
	}
	if !connect(private) {
		t.Fatal("business stop closed private maintenance channel")
	}
}

type requestTouchProvider struct {
	P.ProxyProvider
	touches int
}

func (p *requestTouchProvider) Touch() { p.touches++; p.ProxyProvider.Touch() }

func TestAppRequestStrictRoundRobinAdvancesPerOperation(t *testing.T) {
	r := revisionRegistry(t)
	nodes := []C.Proxy{}
	for i := 0; i < 2; i++ {
		a, _ := outbound.NewHttp(outbound.HttpOption{Name: fmtName(i), Server: "127.0.0.1", Port: 1})
		nodes = append(nodes, adapter.NewProxy(a))
	}
	hc := provider.NewHealthCheck(nodes, "", 0, 0, false, nil)
	pd, _ := provider.NewCompatibleProvider("round robin source", nodes, hc)
	defer pd.Close()
	touched := &requestTouchProvider{ProxyProvider: pd}
	group, _ := outboundgroup.NewLoadBalance(outboundgroup.GroupCommonOption{Name: "round robin"}, outboundgroup.LoadBalanceOption{Strategy: "round-robin"}, nodes[0], []P.ProxyProvider{touched})
	proxy := adapter.NewProxy(group)
	seen := []string{}
	for i := 0; i < 4; i++ {
		lease, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "request", Key: fmtName(i), Mode: "proxy"})
		if err != nil {
			t.Fatal(err)
		}
		l := lease.(*appRequestLease)
		first, err := l.SelectProxy(proxy, &C.Metadata{})
		if err != nil {
			t.Fatal(err)
		}
		second, err := l.SelectProxy(proxy, &C.Metadata{})
		if err != nil || first != second {
			t.Fatal("same operation changed its terminal")
		}
		seen = append(seen, first.Name())
		lease.Close()
	}
	if seen[0] == seen[1] || seen[0] != seen[2] || seen[1] != seen[3] {
		t.Fatal("new operations did not advance round robin", seen)
	}
	if touched.touches != 4 {
		t.Fatal("lazy provider must be touched once per operation", touched.touches)
	}
}

func TestAppRequestUnchangedConfigPreservesScopeAndSourceChangeRevokes(t *testing.T) {
	r := revisionRegistry(t)
	withCurrentConfig(t, &config.Config{General: &config.General{Mode: tunnel.Mode(), IPv6: !resolver.DisableIPv6}, Controller: &config.Controller{}})
	l, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "maintenance", Trigger: "manual", Key: "same config", Proxy: "DIRECT"})
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	mode, ipv6 := currentConfig.General.Mode, currentConfig.General.IPv6
	authentication := []string{}
	params := &UpdateParams{Mode: &mode, IPv6: &ipv6, Authentication: &authentication, GeoXUrl: map[string]string{"ASN": geodata.ASNUrl()}}
	if err := updateConfig(params); err != nil {
		t.Fatal(err)
	}
	if err := l.Check(); err != nil {
		t.Fatal("unchanged config cancelled Direct", err)
	}
	previous := geodata.ASNUrl()
	defer geodata.SetASNUrl(previous)
	params.GeoXUrl["ASN"] = "http://127.0.0.1/changed-source"
	if err := updateConfig(params); err != nil {
		t.Fatal(err)
	}
	if err := l.Check(); err == nil {
		t.Fatal("source change did not revoke scope")
	}
}
func fmtName(i int) string { return "synthetic-" + strconv.Itoa(i) }

func TestAppRequestUnrelatedPicksKeepFixedNodeAndRelatedPickCancels(t *testing.T) {
	r := revisionRegistry(t)
	nodes := []C.Proxy{}
	for i := 0; i < 2; i++ {
		a, _ := outbound.NewHttp(outbound.HttpOption{Name: fmtName(i), Server: "127.0.0.1", Port: 1})
		nodes = append(nodes, adapter.NewProxy(a))
	}
	makeGroup := func(name string) *adapter.Proxy {
		hc := provider.NewHealthCheck(nodes, "", 0, 0, false, nil)
		pd, _ := provider.NewCompatibleProvider(name+" source", nodes, hc)
		t.Cleanup(func() { _ = pd.Close() })
		g, _ := outboundgroup.NewSelector(outboundgroup.GroupCommonOption{Name: name}, outboundgroup.SelectorOption{}, nodes[0], []P.ProxyProvider{pd})
		return adapter.NewProxy(g)
	}
	group, other := makeGroup("related"), makeGroup("unrelated")
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{group.Name(): group, other.Name(): other, nodes[0].Name(): nodes[0], nodes[1].Name(): nodes[1]}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	create := func(key, proxy string) *appRequestLease {
		l, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "request", Key: key, Proxy: proxy, Mode: "proxy"})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(l.Close)
		return l.(*appRequestLease)
	}
	fixed := create("fixed node", nodes[0].Name())
	_, _ = fixed.SelectProxy(nodes[0], &C.Metadata{})
	dependent := create("group operation", group.Name())
	_, _ = dependent.SelectProxy(group, &C.Metadata{})
	handleChangeProxy(&ChangeProxyParams{GroupName: other.Name(), ProxyName: nodes[1].Name()})
	if fixed.Check() != nil || dependent.Check() != nil {
		t.Fatal("unrelated pick cancelled a fixed operation")
	}
	handleChangeProxy(&ChangeProxyParams{GroupName: group.Name(), ProxyName: nodes[1].Name()})
	if fixed.Check() != nil || dependent.Check() == nil {
		t.Fatal("related pick did not cancel only its dependent operation")
	}
}

func TestAppRequestGeoNotifyBatchDoesNotCancelSibling(t *testing.T) {
	r := revisionRegistry(t)
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	home := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(home)
	mmdb, err := os.ReadFile("../assets/data/GEOIP.metadb")
	if err != nil {
		t.Fatal(err)
	}
	asn, err := os.ReadFile("../assets/data/ASN.mmdb")
	if err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(C.Path.MMDB(), mmdb, 0600)
	_ = os.WriteFile(C.Path.ASN(), asn, 0600)
	if err = geodata.InitGeoIP(); err != nil {
		t.Fatal(err)
	}
	if err = geodata.InitASN(); err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	var completed atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/asn" {
			close(entered)
			select {
			case <-release:
			case <-req.Context().Done():
				return
			}
		}
		_, _ = w.Write(asn)
	}))
	defer server.Close()
	oldMMDB, oldASN := geodata.MmdbUrl(), geodata.ASNUrl()
	geodata.SetMmdbUrl(server.URL + "/mmdb")
	geodata.SetASNUrl(server.URL + "/asn")
	defer geodata.SetMmdbUrl(oldMMDB)
	defer geodata.SetASNUrl(oldASN)
	original := updater.GeoUpdateHook
	updater.GeoUpdateHook = func(name string, updating, skipped bool, err error) {
		original(name, updating, skipped, err)
		if name == "MMDB" && !updating && err == nil {
			completed.Store(true)
		}
	}
	defer func() { updater.GeoUpdateHook = original }()
	done := make(chan error, 1)
	go func() { done <- updater.UpdateGeoDatabases() }()
	select {
	case <-entered:
	case err := <-done:
		t.Fatal("Geo batch failed before entering sibling", err)
	case <-time.After(3 * time.Second):
		t.Fatal("Geo batch did not enter sibling")
	}
	deadline := time.Now().Add(2 * time.Second)
	for !completed.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !completed.Load() {
		close(release)
		t.Fatal("first Geo resource did not finish")
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal("notify=true Geo batch cancelled its sibling", err)
	}
	data, _ := os.ReadFile(C.Path.MMDB())
	if len(data) != len(asn) {
		t.Fatal("first Geo resource did not commit")
	}
	_ = r
}

func TestAppRequestNamedNTPUsesSOCKSUDPAndClosesOnRetirement(t *testing.T) {
	for _, retire := range []bool{false, true} {
		t.Run(strconv.FormatBool(retire), func(t *testing.T) {
			r := revisionRegistry(t)
			tcp, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			defer tcp.Close()
			relay, err := net.ListenPacket("udp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			defer relay.Close()
			associationClosed := make(chan struct{})
			go func() {
				conn, err := tcp.Accept()
				if err != nil {
					return
				}
				defer conn.Close()
				buf := make([]byte, 3)
				if _, err = io.ReadFull(conn, buf); err != nil {
					return
				}
				_, _ = conn.Write([]byte{5, 0})
				req := make([]byte, 10)
				if _, err = io.ReadFull(conn, req); err != nil {
					return
				}
				if req[1] != 3 {
					return
				}
				port := relay.LocalAddr().(*net.UDPAddr).Port
				_, _ = conn.Write([]byte{5, 0, 0, 1, 127, 0, 0, 1, byte(port >> 8), byte(port)})
				_, _ = io.Copy(io.Discard, conn)
				close(associationClosed)
			}()
			port := tcp.Addr().(*net.TCPAddr).Port
			a, err := outbound.NewSocks5(outbound.Socks5Option{Name: "synthetic UDP hop", Server: "127.0.0.1", Port: port, UDP: true})
			if err != nil {
				t.Fatal(err)
			}
			proxy := adapter.NewProxy(a)
			oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
			tunnel.UpdateProxies(map[string]C.Proxy{proxy.Name(): proxy}, nil)
			defer tunnel.UpdateProxies(oldProxies, oldProviders)
			ntpService.ReCreateNTPService("127.0.0.1:12345", 1, proxy.Name(), tunnel.Tunnel, false)
			defer ntpService.ReCreateNTPService("", 0, "", tunnel.Tunnel, false)
			_ = relay.SetReadDeadline(time.Now().Add(2 * time.Second))
			packet := make([]byte, 2048)
			n, client, err := relay.ReadFrom(packet)
			if err != nil {
				t.Fatal("named NTP did not use the SOCKS UDP relay", err)
			}
			addr, payload, err := S5.DecodeUDPPacket(packet[:n])
			if err != nil || len(payload) != 48 {
				t.Fatal("invalid NTP UDP packet", err)
			}
			if retire {
				next := r.newOwner()
				r.setPhase(next, "ready")
			}
			response := make([]byte, 48)
			response[0], response[1] = 0x24, 1
			stamp := time.Now().Add(3 * time.Second)
			value := uint64(stamp.Unix()+2208988800)<<32 | uint64(stamp.Nanosecond())*(1<<32)/1000000000
			for _, off := range []int{16, 32, 40} {
				binary.BigEndian.PutUint64(response[off:off+8], value)
			}
			copy(response[24:32], payload[40:48])
			encoded, _ := S5.EncodeUDPPacket(addr, response)
			_, _ = relay.WriteTo(encoded, client)
			if retire {
				select {
				case <-associationClosed:
				case <-time.After(time.Second):
					t.Fatal("retirement did not close UDP association")
				}
				if ntpTime.GetOffset() != 0 {
					t.Fatal("retired named NTP committed offset")
				}
			} else {
				deadline := time.Now().Add(time.Second)
				for ntpTime.GetOffset() == 0 && time.Now().Before(deadline) {
					time.Sleep(time.Millisecond)
				}
				if ntpTime.GetOffset() < 2*time.Second {
					t.Fatal("named UDP NTP did not commit offset")
				}
			}
		})
	}
}

func TestAppRequestNamedNTPMissingProxySendsNoDirectUDP(t *testing.T) {
	r := revisionRegistry(t)
	_ = r
	target, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{}, nil)
	defer tunnel.UpdateProxies(oldProxies, oldProviders)
	ntpService.ReCreateNTPService(target.LocalAddr().String(), 1, "missing synthetic target", tunnel.Tunnel, false)
	defer ntpService.ReCreateNTPService("", 0, "", tunnel.Tunnel, false)
	_ = target.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	if _, _, err := target.ReadFrom(make([]byte, 2048)); err == nil {
		t.Fatal("missing named proxy sent Direct UDP")
	}
	if ntpTime.GetOffset() != 0 {
		t.Fatal("missing named proxy changed offset")
	}
}

func TestAppRequestGrantedCommitDoesNotAuthorizeAnotherDial(t *testing.T) {
	r := revisionRegistry(t)
	lease, err := r.begin(context.Background(), requestscope.Spec{Owner: r.currentOwner(), Kind: "maintenance", Trigger: "manual", Key: "finite commit", Proxy: "DIRECT"})
	if err != nil {
		t.Fatal(err)
	}
	defer lease.Close()
	receipt, err := lease.GrantCommit()
	if err != nil {
		t.Fatal(err)
	}
	defer receipt.Complete()
	conn, err := lease.Dialer().DialContext(context.Background(), "tcp", "127.0.0.1:1")
	if conn != nil {
		_ = conn.Close()
	}
	if !errors.Is(err, requestscope.ErrCancelled) {
		t.Fatal("local commit did not reject network before dialing", err)
	}
}
