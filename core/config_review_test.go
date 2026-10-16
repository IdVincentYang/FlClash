package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	MHTTP "github.com/metacubex/http"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/tunnel"
)

type delayedFixedTunnel struct {
	C.Tunnel
	entered, release, done chan struct{}
}

func (d *delayedFixedTunnel) TrackInbound(c net.Conn) (net.Conn, error) {
	return d.Tunnel.(interface {
		TrackInbound(net.Conn) (net.Conn, error)
	}).TrackInbound(c)
}
func (d *delayedFixedTunnel) HandleTCPConn(c net.Conn, m *C.Metadata) {
	close(d.entered)
	<-d.release
	d.Tunnel.HandleTCPConn(c, m)
	close(d.done)
}
func (d *delayedFixedTunnel) HandleUDPPacket(p C.UDPPacket, m *C.Metadata) {
	close(d.entered)
	<-d.release
	d.Tunnel.HandleUDPPacket(p, m)
	close(d.done)
}

func freeConfigPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func TestConfigFixedTunnelKeepsAcceptAndPacketScope(t *testing.T) {
	for _, network := range []string{"tcp", "udp"} {
		t.Run(network, func(t *testing.T) {
			configTestHome(t)
			var arrivals atomic.Int32
			var target string
			if network == "tcp" {
				l, err := net.Listen("tcp", "127.0.0.1:0")
				if err != nil {
					t.Fatal(err)
				}
				defer l.Close()
				target = l.Addr().String()
				go func() {
					for {
						c, err := l.Accept()
						if err != nil {
							return
						}
						arrivals.Add(1)
						c.Close()
					}
				}()
			} else {
				l, err := net.ListenPacket("udp", "127.0.0.1:0")
				if err != nil {
					t.Fatal(err)
				}
				defer l.Close()
				target = l.LocalAddr().String()
				go func() {
					b := make([]byte, 128)
					for {
						_, _, err := l.ReadFrom(b)
						if err != nil {
							return
						}
						arrivals.Add(1)
					}
				}()
			}
			input := writeTestInput(t, "mode: rule\nrules: [\"MATCH,REJECT\"]\n")
			applyTestInput(t, input)
			address := fmt.Sprintf("127.0.0.1:%d", freeConfigPort(t))
			fixed := []LC.Tunnel{{Network: []string{network}, Address: address, Target: target, Proxy: "DIRECT"}}
			if err := listener.PatchTunnelChecked(fixed, tunnel.BindBusiness(activeBusiness.Load())); err != nil {
				t.Fatal(err)
			}
			normal, err := net.DialTimeout(network, address, time.Second)
			if err != nil {
				t.Fatal(err)
			}
			normal.Write([]byte("normal"))
			normal.Close()
			for deadline := time.Now().Add(time.Second); arrivals.Load() != 1; {
				if time.Now().After(deadline) {
					t.Fatal("accepted fixed consumer did not reach target")
				}
				time.Sleep(time.Millisecond)
			}
			_ = listener.PatchTunnelChecked(nil, tunnel.Tunnel)
			arrivals.Store(0)
			blocked := &delayedFixedTunnel{Tunnel: tunnel.BindBusiness(activeBusiness.Load()), entered: make(chan struct{}), release: make(chan struct{}), done: make(chan struct{})}
			var releaseOnce sync.Once
			defer releaseOnce.Do(func() { close(blocked.release) })
			if err := listener.PatchTunnelChecked(fixed, blocked); err != nil {
				t.Fatal(err)
			}
			c, err := net.DialTimeout(network, address, time.Second)
			if err != nil {
				t.Fatal(err)
			}
			defer c.Close()
			c.Write([]byte("old"))
			select {
			case <-blocked.entered:
			case <-time.After(time.Second):
				t.Fatal("fixed ingress did not reach consumer barrier")
			}
			applyTestInput(t, input)
			releaseOnce.Do(func() { close(blocked.release) })
			select {
			case <-blocked.done:
			case <-time.After(time.Second):
				t.Fatal("old fixed ingress did not finish")
			}
			time.Sleep(30 * time.Millisecond)
			if arrivals.Load() != 0 {
				t.Fatal("old fixed target borrowed new activation", arrivals.Load())
			}
		})
	}
}

func TestConfigFixedTunnelCheckedBindingAndInactive(t *testing.T) {
	for _, network := range []string{"tcp", "udp"} {
		t.Run(network, func(t *testing.T) {
			configTestHome(t)
			address := fmt.Sprintf("127.0.0.1:%d", freeConfigPort(t))
			var release func()
			if network == "tcp" {
				l, err := net.Listen(network, address)
				if err != nil {
					t.Fatal(err)
				}
				release = func() { l.Close() }
			} else {
				l, err := net.ListenPacket(network, address)
				if err != nil {
					t.Fatal(err)
				}
				release = func() { l.Close() }
			}
			defer release()
			input := writeTestInput(t, fmt.Sprintf("mode: rule\nrules: [\"MATCH,DIRECT\"]\ntunnels:\n - network: [tcp,udp]\n   address: %s\n   target: 127.0.0.1:1\n   proxy: DIRECT\n", address))
			prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true}))
			if prepared.Status != "prepared" {
				t.Fatal(prepared)
			}
			if result := installConfig(prepared.Receipt); result.Status != "blocked" || result.Fact.BusinessActive {
				t.Fatal("fixed binding failure accepted", result)
			}
			release()
			applyTestInput(t, input)
			if !handleStopListener() {
				t.Fatal("stop failed")
			}
			assertFree := func() {
				tcp, err := net.Listen("tcp", address)
				if err != nil {
					t.Fatal("fixed TCP survived", err)
				}
				tcp.Close()
				udp, err := net.ListenPacket("udp", address)
				if err != nil {
					t.Fatal("fixed UDP survived", err)
				}
				udp.Close()
			}
			assertFree()
			inactive := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: false}))
			if inactive.Status != "prepared" {
				t.Fatal(inactive)
			}
			installed := installConfig(inactive.Receipt)
			if installed.Status != "installed" {
				t.Fatal(installed)
			}
			if result := activateConfig(installed.Receipt); result.Status != "installedInactive" {
				t.Fatal(result)
			}
			assertFree()
		})
	}
}

func TestConfigTCPHalfCloseAndRevocation(t *testing.T) {
	configTestHome(t)
	server, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	defer releaseOnce.Do(func() { close(release) })
	var requests atomic.Int32
	go func() {
		for {
			c, err := server.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				c.SetDeadline(time.Now().Add(3 * time.Second))
				body, _ := io.ReadAll(c)
				requests.Add(1)
				if string(body) == "retire" {
					close(entered)
					<-release
				}
				io.WriteString(c, "response-after-eof:"+string(body))
			}(c)
		}
	}()
	port := freeConfigPort(t)
	input := writeTestInput(t, fmt.Sprintf("mixed-port: %d\nmode: rule\nrules: [\"MATCH,DIRECT\"]\n", port))
	applyTestInput(t, input)
	connect := func(payload string) (*net.TCPConn, *bufio.Reader) {
		c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		tcp := c.(*net.TCPConn)
		tcp.SetDeadline(time.Now().Add(3 * time.Second))
		fmt.Fprintf(tcp, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", server.Addr(), server.Addr())
		r := bufio.NewReader(tcp)
		response, err := http.ReadResponse(r, &http.Request{Method: http.MethodConnect})
		if err != nil || response.StatusCode != 200 {
			tcp.Close()
			t.Fatal("CONNECT failed", response, err)
		}
		tcp.Write([]byte(payload))
		if err := tcp.CloseWrite(); err != nil {
			tcp.Close()
			t.Fatal(err)
		}
		return tcp, r
	}
	c, r := connect("complete")
	body, err := io.ReadAll(r)
	c.Close()
	if err != nil || string(body) != "response-after-eof:complete" {
		t.Fatal("half close lost remote response", string(body), err)
	}
	c, r = connect("retire")
	defer c.Close()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("server did not observe client EOF")
	}
	applyTestInput(t, input)
	releaseOnce.Do(func() { close(release) })
	body, _ = io.ReadAll(r)
	if len(body) != 0 {
		t.Fatal("retired relay forwarded old response", string(body))
	}
	if requests.Load() != 2 {
		t.Fatal("unexpected accepted TCP request count", requests.Load())
	}
}

func TestConfigConcurrentPickRetainsAcknowledgedHotState(t *testing.T) {
	configTestHome(t)
	var direct atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { direct.Add(1); io.WriteString(w, "direct") }))
	defer target.Close()
	port := freeConfigPort(t)
	input := writeTestInput(t, fmt.Sprintf("mixed-port: %d\nmode: direct\nproxy-groups:\n - name: pick\n   type: select\n   proxies: [DIRECT,REJECT]\nrules: [\"MATCH,pick\"]\n", port))
	applyTestInput(t, input)
	get := func() {
		c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(time.Second))
		fmt.Fprintf(c, "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", target.URL, strings.TrimPrefix(target.URL, "http://"))
		io.ReadAll(c)
	}
	get()
	if direct.Load() != 1 {
		t.Fatal("baseline Direct consumer failed")
	}
	direct.Store(0)
	original := writeConfigManifest
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	writeConfigManifest = func(path string, data []byte) error {
		once.Do(func() { close(entered); <-release })
		return original(path, data)
	}
	defer func() { writeConfigManifest = original }()
	mode := tunnel.Rule
	ipv6 := true
	hotDone := make(chan error, 1)
	go func() { hotDone <- updateConfig(&UpdateParams{Mode: &mode, IPv6: &ipv6}) }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("hot checkpoint did not reach write barrier")
	}
	pickDone := make(chan *ChangeProxyResult, 1)
	go func() { pickDone <- handleChangeProxy(&ChangeProxyParams{GroupName: "pick", ProxyName: "REJECT"}) }()
	for deadline := time.Now().Add(time.Second); ; {
		selectMu.Lock()
		pick, _ := selectableGroup("pick")
		selected := pick.Now()
		selectMu.Unlock()
		if selected == "REJECT" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("concurrent pick did not mutate before persistence")
		}
		time.Sleep(time.Millisecond)
	}
	close(release)
	if err := <-hotDone; err != nil {
		t.Fatal(err)
	}
	if result := <-pickDone; result.Message != "" {
		t.Fatal(result)
	}
	replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, raw, _, err := readConfigInput(C.Path.HomeDir(), replay.InputID)
	if err != nil || raw.Mode != tunnel.Rule || !raw.IPv6 || manifest.SelectedMap["pick"] != "REJECT" {
		t.Fatal("acknowledged hot state lost", manifest, raw, err)
	}
	replay.Active = true
	p := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), replay))
	i := installConfig(p.Receipt)
	if result := activateConfig(i.Receipt); result.Status != "activated" {
		t.Fatal(result)
	}
	get()
	if direct.Load() != 0 {
		t.Fatal("cold replay returned to unaccepted Direct", direct.Load())
	}

}

func TestConfigLocalSourceChangesRevokeReplayUntilFreshApply(t *testing.T) {
	for _, key := range []string{"global-rules", "profile:7"} {
		t.Run(key, func(t *testing.T) {
			configTestHome(t)
			input := writeTestInput(t, configTestYAML(0), "profile:7", "global-rules")
			applyTestInput(t, input)
			appRequests.mu.Lock()
			appRequests.client, appRequests.clientReady = "test", true
			appRequests.mu.Unlock()
			result := appRequests.control(appRequestControl{Action: "invalidate", Client: "test", Key: key})
			if failure, ok := result.(map[string]string); ok && failure["error"] != "" {
				t.Fatal(result)
			}
			if !configStateSnapshot().BusinessActive || configStateSnapshot().ReplayEligible {
				t.Fatal("source change falsified warm state or retained cold authority", configStateSnapshot())
			}
			if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err == nil {
				t.Fatal("removed source remained replayable", key)
			}
			applyTestInput(t, input)
			if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err != nil {
				t.Fatal("fresh application did not restore current source authority", key, err)
			}
		})
	}
}

func TestConfigControllerRejectsEmptyManualPick(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, "mode: rule\nproxy-groups:\n - name: pick\n   type: select\n   proxies: [DIRECT,REJECT]\nrules: [\"MATCH,pick\"]\n")
	applyTestInput(t, input)
	endpoint, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &MHTTP.Server{Handler: route.NewHandler(false, "", "", route.Cors{})}
	go server.Serve(endpoint)
	defer server.Close()
	call := func(body string, want int) {
		r, _ := http.NewRequest(http.MethodPut, "http://"+endpoint.Addr().String()+"/proxies/pick", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		response, err := (&http.Client{Timeout: time.Second}).Do(r)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != want {
			t.Fatal("unexpected PUT status", body, response.StatusCode)
		}
	}
	call(`{"name":"REJECT"}`, http.StatusNoContent)
	before := configStateSnapshot()
	epoch, picks := routeStamp()
	checkpointMu.Lock()
	ref, err := readCheckpointLocked(C.Path.HomeDir())
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{`{}`, `{"name":""}`, `{"name":null}`} {
		call(body, http.StatusBadRequest)
		selectMu.Lock()
		group, _ := selectableGroup("pick")
		selected := group.Now()
		selectMu.Unlock()
		checkpointMu.Lock()
		afterRef, err := readCheckpointLocked(C.Path.HomeDir())
		checkpointMu.Unlock()
		afterEpoch, afterPicks := routeStamp()
		if selected != "REJECT" || configStateSnapshot() != before || epoch != afterEpoch || picks != afterPicks || err != nil || ref.InputID != afterRef.InputID {
			t.Fatal("invalid manual PUT changed actual selection, fact, route or checkpoint", body, afterRef, err)
		}
	}
}

func TestConfigFixedTunnelSlashProxyLifecycle(t *testing.T) {
	configTestHome(t)
	inputFor := func(yaml string) string {
		configMu.Lock()
		defer configMu.Unlock()
		id := writeTestInput(t, yaml)
		marker, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: inputHash([]byte(yaml)), RuntimeEpoch: configRuntimeEpoch})
		if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".000000000000000000000000.candidate"), marker); err != nil {
			t.Fatal(err)
		}
		return id
	}
	tcp, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer tcp.Close()
	udp, err := net.ListenPacket("udp", tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer udp.Close()
	accepted := make(chan string, 4)
	go func() {
		for {
			c, err := tcp.Accept()
			if err != nil {
				return
			}
			accepted <- "tcp"
			c.Close()
		}
	}()
	go func() {
		b := make([]byte, 32)
		for {
			if _, _, err := udp.ReadFrom(b); err != nil {
				return
			}
			accepted <- "udp"
		}
	}()
	address := fmt.Sprintf("127.0.0.1:%d", freeConfigPort(t))
	base := "mode: rule\nproxies:\n - {name: node/a, type: direct}\nrules: [\"MATCH,REJECT\"]\n"
	fixed := fmt.Sprintf("tunnels:\n - network: [tcp,udp]\n   address: %s\n   target: %s\n   proxy: node/a\n", address, tcp.Addr())
	input := inputFor(base + fixed)
	applyTestInput(t, input)
	for _, network := range []string{"tcp", "udp"} {
		c, err := net.DialTimeout(network, address, time.Second)
		if err != nil {
			t.Fatal(err)
		}
		c.Write([]byte("accepted"))
		c.Close()
		select {
		case got := <-accepted:
			if got != network {
				t.Fatal(got)
			}
		case <-time.After(time.Second):
			t.Fatal("fixed consumer failed", network)
		}
	}
	assertFree := func() {
		t.Helper()
		tcp, err := net.Listen("tcp", address)
		if err != nil {
			t.Fatal(err)
		}
		tcp.Close()
		udp, err := net.ListenPacket("udp", address)
		if err != nil {
			t.Fatal(err)
		}
		udp.Close()
	}
	if !handleStopListener() {
		t.Fatal("stop failed")
	}
	assertFree()
	applyTestInput(t, input)
	applyTestInput(t, inputFor(base))
	assertFree()
	occupied, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	failing := inputFor(base + fixed + fmt.Sprintf(" - network: [tcp]\n   address: %s\n   target: %s\n   proxy: node/a\n", occupied.Addr(), tcp.Addr()))
	prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: failing, Active: true}))
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	if result := installConfig(prepared.Receipt); result.Status != "blocked" {
		t.Fatal(result)
	}
	assertFree()
	applyTestInput(t, input)
	if !handleStopListener() {
		t.Fatal("retry stop failed")
	}
	assertFree()
}
