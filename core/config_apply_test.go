package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"

	"testing"
	"time"

	MHTTP "github.com/metacubex/http"
	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

func TestConfigCandidateReferenceCollection(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	accepted := writeTestInput(t, "mode: rule\nrules: [\"MATCH,DIRECT\"]\n")
	applyTestInput(t, accepted)
	for inputCollectionQueued.Load() {
		time.Sleep(time.Millisecond)
	}
	candidate := writeTestInput(t, "mode: direct\nrules: [\"MATCH,DIRECT\"]\n")
	stale := writeTestInput(t, "mode: global\nrules: [\"MATCH,DIRECT\"]\n")
	rejected := writeTestInput(t, "rules: [\n")
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: rejected})
	if result := prepareConfig(receipt); result.Status != "rejected" {
		t.Fatal(result)
	}
	root := inputDirectory(C.Path.HomeDir())
	marker := candidate + "." + strings.Repeat("a", 24) + ".candidate"
	for name, epoch := range map[string]string{marker: configRuntimeEpoch, stale + "." + strings.Repeat("b", 24) + ".candidate": "previous-process"} {
		manifestBytes, _ := os.ReadFile(filepath.Join(root, strings.Split(name, ".")[0]+".json"))
		var manifest ConfigManifest
		_ = json.Unmarshal(manifestBytes, &manifest)
		data, _ := json.Marshal(inputCandidateMarker{YAMLSHA256: manifest.YAMLSHA256, RuntimeEpoch: epoch})
		if err := atomicConfigFile(filepath.Join(root, name), data); err != nil {
			t.Fatal(err)
		}
	}
	if err := collectConfigInputs(""); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{accepted, candidate} {
		if _, err := os.Stat(filepath.Join(root, id+".json")); err != nil {
			t.Fatal("live reference removed", id, err)
		}
	}
	for _, id := range []string{stale, rejected} {
		if _, err := os.Stat(filepath.Join(root, id+".json")); !os.IsNotExist(err) {
			t.Fatal("unreferenced input retained", id, err)
		}
	}
	if err := collectConfigInputs(marker); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, candidate+".json")); !os.IsNotExist(err) {
		t.Fatal("released candidate retained", err)
	}
}

func TestConfigStagedBindingCannotOpenBeforeActivation(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	loaded := make(chan string, 16)
	previousLoaded := executor.DefaultProviderLoadedHook
	executor.DefaultProviderLoadedHook = func(name string) {
		if previousLoaded != nil {
			previousLoaded(name)
		}
		loaded <- name
	}
	defer func() { executor.DefaultProviderLoadedHook = previousLoaded }()
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		<-release
		io.WriteString(w, "proxies:\n  - name: local\n    type: direct\n")
	}))
	defer provider.Close()
	defer releaseOnce.Do(func() { close(release) })
	input := writeTestInput(t, fmt.Sprintf("mixed-port: %d\nmode: rule\nproxy-providers:\n  local:\n    type: http\n    url: %s\n    path: ./local-provider.yaml\nproxy-groups:\n  - name: pick\n    type: select\n    use: [local]\nrules: [\"MATCH,pick\"]\n", port, provider.URL))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	p := prepareConfig(receipt)
	if p.Status != "prepared" {
		t.Fatal(p)
	}
	assertClosed := func() {
		c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatal("prepared socket was lost", err)
		}
		defer c.Close()
		_ = c.SetDeadline(time.Now().Add(time.Second))
		_, _ = c.Write([]byte{5, 1, 0})
		if _, err := io.ReadFull(c, make([]byte, 2)); err == nil {
			t.Fatal("inactive socket completed a business greeting")
		}
		if isRunning.Load() || tunnel.Status() == tunnel.Running {
			t.Fatal("staged install published Running")
		}
	}
	assertClosed()
	completed := make(chan ConfigApplyResult, 1)
	go func() { completed <- installConfig(p.Receipt) }()
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("real staged provider initialization did not reach barrier")
	}
	assertClosed()
	releaseOnce.Do(func() { close(release) })
	installed := <-completed
	if installed.Status != "installed" {
		t.Fatal(installed)
	}
	seen := make(map[string]bool)
	for len(seen) < len(pendingConfig.cfg.Providers) {
		select {
		case name := <-loaded:
			seen[name] = true
		case <-time.After(3 * time.Second):
			t.Fatal("provider initialization did not finish before fixture cleanup")
		}
	}
	assertClosed()
	mode := tunnel.Direct
	if err := updateConfig(&UpdateParams{Mode: &mode}); err != errConfigNotApplied {
		t.Fatal("hot update revived staged input", err)
	}
	if activateConfig(installed.Receipt).Status != "activated" {
		t.Fatal("activation failed")
	}
}

func TestConfigCheckedListenerFailureAfterStagedInstall(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	occupied, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	mixedPort := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	input := writeTestInput(t, fmt.Sprintf("mixed-port: %d\nport: %d\nmode: rule\nrules: [\"MATCH,DIRECT\"]\n", mixedPort, occupied.Addr().(*net.TCPAddr).Port))
	registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared := prepareConfig(registered)
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	result := installConfig(prepared.Receipt)
	if result.Status != "blocked" || result.Fact.BusinessActive || isRunning.Load() || tunnel.Status() == tunnel.Running {
		t.Fatal("listener failure published business", result)
	}
	if connection, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort), 100*time.Millisecond); err == nil {
		connection.Close()
		t.Fatal("partial mixed listener survived failed install")
	}
	if result := activateConfig(prepared.Receipt); result.Status == "activated" {
		t.Fatal("failed binding was revived")
	}
}

func TestConfigControllerWritesUseAcceptedAuthority(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	probe := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	defer probe.Close()
	input := writeTestInput(t, "mode: rule\nproxy-providers:\n  members:\n    type: inline\n    payload:\n      - {name: first, type: direct}\n      - {name: second, type: direct}\n    health-check:\n      enable: false\n      url: "+probe.URL+"\nproxy-groups:\n  - name: pick\n    type: select\n    proxies: [DIRECT,REJECT]\n  - name: auto\n    type: url-test\n    use: [members]\n    url: "+probe.URL+"\n    lazy: true\nrules: [\"MATCH,pick\"]\n")
	applyTestInput(t, input)
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := reservation.Addr().String()
	api := &MHTTP.Server{Handler: route.NewHandler(false, "", "", route.Cors{})}
	go api.Serve(reservation)
	defer api.Close()
	client := &http.Client{Timeout: 2 * time.Second}
	base := "http://" + address
	for deadline := time.Now().Add(3 * time.Second); ; {
		response, err := client.Get(base + "/configs")
		if err == nil {
			response.Body.Close()
			break
		}
		if time.Now().After(deadline) {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	call := func(method, path, body string, want int) {
		req, _ := http.NewRequest(method, base+path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != want {
			data, _ := io.ReadAll(response.Body)
			t.Fatalf("%s %s: %d %s", method, path, response.StatusCode, data)
		}
	}
	before := configStateSnapshot()
	call("PUT", "/configs", `{"path":"/must-not-read","payload":"rules: ["}`, 409)
	call("PATCH", "/configs", `{"mode":"direct","unsupported":true}`, 409)
	call("PATCH", "/configs", `{"mode":"direct","mixed-port":12345}`, 409)
	call("PATCH", "/rules/disable", `{"0":true}`, 409)
	if after := configStateSnapshot(); before != after || currentConfig.General.Mode != tunnel.Rule {
		t.Fatal("rejected HTTP write had configuration effects", before, after)
	}
	call("PATCH", "/configs", `{"mode":"global","ipv6":true,"unified-delay":true}`, 204)
	call("PUT", "/proxies/pick", `{"name":"REJECT"}`, 204)
	beforeInvalidPick := configStateSnapshot()
	beforeEpoch, beforePicks := routeStamp()
	checkpointMu.Lock()
	beforeInvalidRef, err := readCheckpointLocked(C.Path.HomeDir())
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{`{}`, `{"name":""}`, `{"name":null}`} {
		call("PUT", "/proxies/pick", body, 400)
		if state := configStateSnapshot(); state != beforeInvalidPick {
			t.Fatal("invalid PUT changed actual fact", state)
		}
		if epoch, picks := routeStamp(); epoch != beforeEpoch || picks != beforePicks {
			t.Fatal("invalid PUT changed selection versions")
		}
		selectMu.Lock()
		group, _ := selectableGroup("pick")
		selected := group.Now()
		selectMu.Unlock()
		if selected != "REJECT" {
			t.Fatal("invalid PUT cleared manual selection", selected)
		}
		checkpointMu.Lock()
		afterInvalidRef, err := readCheckpointLocked(C.Path.HomeDir())
		checkpointMu.Unlock()
		if err != nil || afterInvalidRef.Version != beforeInvalidRef.Version || afterInvalidRef.InputID != beforeInvalidRef.InputID || !slices.Equal(afterInvalidRef.Dependencies, beforeInvalidRef.Dependencies) {
			t.Fatal("invalid PUT changed checkpoint reference", afterInvalidRef, err)
		}
	}
	checkpointMu.Lock()
	ref, err := readCheckpointLocked(C.Path.HomeDir())
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, raw, _, err := readConfigInput(C.Path.HomeDir(), ref.InputID)
	if err != nil || raw.Mode != tunnel.Global || !raw.IPv6 || !raw.UnifiedDelay || manifest.SelectedMap["pick"] != "REJECT" {
		t.Fatal("HTTP accepted state not replayable", manifest, raw, err)
	}
	call("PUT", "/proxies/auto", `{"name":"second"}`, 204)
	beforeInvalid := configStateSnapshot()
	call("GET", "/group/auto/delay?timeout=invalid", "", 400)
	if after := configStateSnapshot(); after != beforeInvalid {
		t.Fatal("invalid diagnostic cleared selection")
	}
	call("DELETE", "/proxies/auto", "", 204)
	call("PATCH", "/configs", `{"mode":"rule"}`, 204)
	checkpointMu.Lock()
	clearedRef, err := readCheckpointLocked(C.Path.HomeDir())
	checkpointMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	cleared, _, _, _, err := readConfigInput(C.Path.HomeDir(), clearedRef.InputID)
	if err != nil || cleared.SelectedMap["auto"] != "" {
		t.Fatal("automatic group clear became a forced checkpoint pick", cleared, err)
	}
	call("PUT", "/proxies/auto", `{"name":"second"}`, 204)
	call("GET", "/group/auto/delay?url="+url.QueryEscape(probe.URL)+"&timeout=1000", "", 200)
	call("DELETE", "/proxies/pick", "", 409)
	for _, operation := range []struct{ method, path, body string }{
		{"PATCH", "/configs", `{"mode":"direct"}`},
		{"PUT", "/proxies/pick", `{"name":"REJECT"}`},
	} {
		captured := make(chan struct{})
		original := requestscope.ControllerMutationHook
		var once sync.Once
		requestscope.ControllerMutationHook = func() requestscope.ControllerMutation {
			mutation := original()
			once.Do(func() { close(captured) })
			return mutation
		}
		reader, writer := io.Pipe()
		req, _ := http.NewRequest(operation.method, base+operation.path, reader)
		req.Header.Set("Content-Type", "application/json")
		done := make(chan error, 1)
		go func() {
			response, err := client.Do(req)
			if err == nil {
				response.Body.Close()
				if response.StatusCode != 409 {
					err = fmt.Errorf("stale HTTP write: %d", response.StatusCode)
				}
			}
			done <- err
		}()
		if _, err := writer.Write([]byte("{")); err != nil {
			t.Fatal(err)
		}
		select {
		case <-captured:
		case <-time.After(time.Second):
			t.Fatal("HTTP handler did not capture authority")
		}
		applyTestInput(t, input)
		_, _ = io.WriteString(writer, operation.body[1:])
		writer.Close()
		if err := <-done; err != nil {
			t.Fatal(err)
		}
		requestscope.ControllerMutationHook = original
		if currentConfig.General.Mode != tunnel.Rule {
			t.Fatal("old HTTP request mutated new configuration")
		}
		if group, err := selectableGroup("pick"); err != nil || group.Now() != "DIRECT" {
			t.Fatal("old HTTP request mutated new group", err)
		}
	}

}

func TestConfigFailureBusiness(t *testing.T) {
	for _, failure := range []string{"invalid-yaml", "missing", "empty", "invalid-rule"} {
		t.Run(failure, func(t *testing.T) {
			configTestEnvironment(t)
			C.SetHomeDir(t.TempDir())
			isInit.Store(true)
			isRunning.Store(true)
			defer func() { listener.StopListener(); handleCloseConnections(); isRunning.Store(false) }()
			var tripwire, direct, proxied atomic.Int32
			target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { tripwire.Add(1); io.WriteString(w, "UNACCEPTED DIRECT") }))
			defer target.Close()
			allowed := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { direct.Add(1); io.WriteString(w, "legal Direct") }))
			defer allowed.Close()
			proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "CONNECT" || r.Host != target.Listener.Addr().String() {
					http.Error(w, "unexpected target", 403)
					return
				}
				proxied.Add(1)
				c, b, err := w.(http.Hijacker).Hijack()
				if err != nil {
					return
				}
				defer c.Close()
				c.SetDeadline(time.Now().Add(2 * time.Second))
				io.WriteString(c, "HTTP/1.1 200 Connection established\r\n\r\n")
				if _, err := http.ReadRequest(b.Reader); err != nil {
					return
				}
				io.WriteString(c, "HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nviaProxy")
			}))
			defer proxy.Close()
			port := func(addr string) int {
				_, text, _ := net.SplitHostPort(addr)
				value, _ := strconv.Atoi(text)
				return value
			}
			reservation, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			mixedPort := port(reservation.Addr().String())
			reservation.Close()
			yaml := fmt.Sprintf("mixed-port: %d\nallow-lan: false\nmode: rule\nipv6: false\nfind-process-mode: off\ndns:\n  enable: false\nntp:\n  enable: false\nprofile:\n  store-selected: false\nproxies:\n  - name: acceptedProxy\n    type: http\n    server: 127.0.0.1\n    port: %d\nrules:\n  - DST-PORT,%d,DIRECT\n  - MATCH,acceptedProxy\n", mixedPort, port(proxy.Listener.Addr().String()), port(allowed.Listener.Addr().String()))
			path := filepath.Join(C.Path.HomeDir(), "config.yaml")
			if err := os.WriteFile(path, []byte(yaml), 0600); err != nil {
				t.Fatal(err)
			}
			validInput := writeTestInput(t, yaml)
			applyTestInput(t, validInput)
			open := func() net.Conn {
				c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(mixedPort)), time.Second)
				if err != nil {
					t.Fatal(err)
				}
				c.SetDeadline(time.Now().Add(2 * time.Second))
				c.Write([]byte{5, 1, 0})
				greeting := make([]byte, 2)
				if _, err := io.ReadFull(c, greeting); err != nil || greeting[1] != 0 {
					c.Close()
					t.Fatal("actual mixed SOCKS greeting failed", greeting, err)
				}
				return c
			}
			get := func(c net.Conn, destination string) (string, error) {
				defer c.Close()
				host, _, _ := net.SplitHostPort(destination)
				ip := net.ParseIP(host).To4()
				packet := append([]byte{5, 1, 0, 1}, ip...)
				packet = binary.BigEndian.AppendUint16(packet, uint16(port(destination)))
				if _, err := c.Write(packet); err != nil {
					return "", err
				}
				reply := make([]byte, 10)
				if _, err := io.ReadFull(c, reply); err != nil {
					return "", err
				}
				if reply[1] != 0 {
					return "", fmt.Errorf("SOCKS failure %d", reply[1])
				}
				fmt.Fprintf(c, "GET / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", destination)
				response, err := http.ReadResponse(bufio.NewReader(c), nil)
				if err != nil {
					return "", err
				}
				defer response.Body.Close()
				body, err := io.ReadAll(response.Body)
				return string(body), err
			}
			if body, err := get(open(), target.Listener.Addr().String()); err != nil || body != "viaProxy" {
				t.Fatal("normal accepted proxy", body, err)
			}
			if body, err := get(open(), allowed.Listener.Addr().String()); err != nil || body != "legal Direct" {
				t.Fatal("normal legal Direct", body, err)
			}
			pending := open()
			switch failure {
			case "missing":
				os.Remove(path)
			case "empty":
				os.WriteFile(path, nil, 0600)
			default:
				os.WriteFile(path, []byte("proxies: ["), 0600)
			}
			invalidInput := writeTestInput(t, "proxies: [")
			switch failure {
			case "missing":
				_ = os.Remove(filepath.Join(inputDirectory(C.Path.HomeDir()), invalidInput+".json"))
			case "empty":
				invalidInput = writeTestInput(t, "")
			case "invalid-rule":
				invalidInput = writeTestInput(t, "mode: rule\nrules: [\"MATCH,missing-proxy\"]\n")
			}
			registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: invalidInput, Active: true})
			result := prepareConfig(registered)
			if result.Status == "prepared" {
				result = installConfig(result.Receipt)
			}
			if result.Status != "rejected" && result.Status != "blocked" {
				t.Fatalf("bad input accepted: %+v", result)
			}
			message := result.Message
			body, readErr := get(pending, target.Listener.Addr().String())
			record := map[string]any{"failure": failure, "reported_error": message != "", "listener_ports_after": listener.GetPorts(), "accepted_proxy_connections": proxied.Load(), "legal_direct_requests": direct.Load(), "unaccepted_direct_requests": tripwire.Load(), "pending_connection_body": body, "pending_connection_error": fmt.Sprint(readErr)}
			encoded, _ := json.Marshal(record)
			t.Log(string(encoded))
			if tripwire.Load() != 0 {
				t.Fatal("configuration failure widened a real pending business connection to Direct")
			}
			if failure != "invalid-rule" && (readErr != nil || body != "viaProxy") {
				t.Fatal("rejected input did not retain the real proxy", body, readErr)
			}
			if failure == "invalid-rule" && (body != "" || readErr == nil || tunnel.Status() != tunnel.Suspend) {
				t.Fatal("replacement failure did not block business", body, readErr)
			}
			applyTestInput(t, validInput)
			stale := open()
			applyTestInput(t, validInput)
			if body, err := get(stale, target.Listener.Addr().String()); err == nil || body != "" {
				t.Fatal("old greeting crossed a new activation", body, err)
			}
			if body, err := get(open(), target.Listener.Addr().String()); err != nil || body != "viaProxy" {
				t.Fatal("new activation did not recover", body, err)
			}
			if tripwire.Load() != 0 {
				t.Fatal("unaccepted Direct after recovery")
			}
		})
	}
}

func configTestEnvironment(t *testing.T) {
	t.Helper()
	previousHome := C.Path.HomeDir()
	previousPending, previousApplied, previousFact := pendingConfig, appliedConfig, configFact
	previousOperation := latestConfig.Load()
	previousRunning, previousInit := isRunning.Load(), isInit.Load()
	previousConfig := currentConfig
	old := appRequests
	appRequests = newAppRequestRegistry()
	ownerHook, phaseHook := requestscope.OwnerHook, requestscope.PhaseHook
	requestscope.OwnerHook = appRequests.currentOwner
	requestscope.PhaseHook = appRequests.setPhase
	pendingConfig, appliedConfig = nil, nil
	currentConfig = nil
	configFact = ConfigFact{}
	revokeBusiness()
	t.Cleanup(func() {
		deadline := time.Now().Add(12 * time.Second)
		for inputCollectionQueued.Load() && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		configMu.Lock()
		defer configMu.Unlock()
		checkpointMu.Lock()
		defer checkpointMu.Unlock()
		revokeBusiness()
		stopBusinessListeners()
		if currentConfig != nil {
			currentConfig.CloseProviders()
		}
		pendingConfig, appliedConfig, configFact, currentConfig = previousPending, previousApplied, previousFact, previousConfig
		latestConfig.Store(previousOperation)
		preparedConfigGate.Store(nil)
		requestscope.OwnerHook, requestscope.PhaseHook = ownerHook, phaseHook
		appRequests = old
		isRunning.Store(previousRunning)
		isInit.Store(previousInit)
		C.SetHomeDir(previousHome)
	})
}

func writeTestInput(t *testing.T, yaml string, dependencies ...string) string {
	t.Helper()
	raw := []byte(yaml)
	digest := inputHash(raw)
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), digest+".yaml"), raw); err != nil {
		t.Fatal(err)
	}
	id := int64(7)
	if dependencies == nil {
		dependencies = []string{"profile:7", "script:9"}
	}
	manifest := ConfigManifest{Version: 1, YAMLSHA256: digest, ProfileID: &id, ProfileName: "accepted", Dependencies: dependencies, SelectedMap: map[string]string{}, TestURL: "http://127.0.0.1/"}
	bytes, _ := json.Marshal(manifest)
	input := inputHash(bytes)
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), input+".json"), bytes); err != nil {
		t.Fatal(err)
	}
	return input
}

func applyTestInput(t *testing.T, input string) ConfigApplyResult {
	t.Helper()
	registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared := prepareConfig(registered)
	if prepared.Status != "prepared" {
		t.Fatalf("prepare: %+v", prepared)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" {
		t.Fatalf("install: %+v", installed)
	}
	activated := activateConfig(installed.Receipt)
	if activated.Status != "activated" {
		t.Fatalf("activate: %+v", activated)
	}
	return activated
}

func configTestHome(t *testing.T) {
	t.Helper()
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
}

func configTestPort(t *testing.T) int {
	t.Helper()
	conn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := conn.Addr().(*net.TCPAddr).Port
	_ = conn.Close()
	return port
}

func configTestYAML(port int) string {
	return fmt.Sprintf("mixed-port: %d\nmode: rule\nfind-process-mode: off\ndns: {enable: false}\nntp: {enable: false}\nprofile: {store-selected: false}\nrules: [\"MATCH,DIRECT\"]\n", port)
}

func TestConfigMixedBindingFailureAndRecovery(t *testing.T) {
	configTestHome(t)
	port := configTestPort(t)
	blockedUDP, err := net.ListenPacket("udp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	if err != nil {
		t.Fatal(err)
	}
	defer blockedUDP.Close()
	input := writeTestInput(t, configTestYAML(port))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	result := prepareConfig(receipt)
	if result.Status != "blocked" || configStateSnapshot().BusinessActive {
		t.Fatalf("partial mixed bind accepted: %+v", result)
	}
	conn, dialErr := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Second)
	if dialErr == nil {
		conn.Close()
		t.Fatal("partial TCP bind was not released")
	}
	if listener.GetPorts().MixedPort != 0 {
		t.Fatal("diagnostic pointer retained a failed mixed binding")
	}
	_ = blockedUDP.Close()
	applyTestInput(t, input)
}

func TestConfigPreparedBindingCannotBeReplacedByPort(t *testing.T) {
	configTestHome(t)
	port := configTestPort(t)
	input := writeTestInput(t, configTestYAML(port))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" || prepared.CoreParams.BindingID == 0 {
		t.Fatalf("prepare: %+v", prepared)
	}
	listener.StopListener()
	replacement, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	if err != nil {
		t.Fatal(err)
	}
	defer replacement.Close()
	result := installConfig(prepared.Receipt)
	if result.Status != "blocked" || result.Fact.BusinessActive || tunnel.Status() == tunnel.Running {
		t.Fatalf("lost binding was reused: %+v", result)
	}
}

func TestConfigImmutablePreparedBytesAndLatestReceipt(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: false})
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" {
		t.Fatalf("prepare: %+v", prepared)
	}
	path := filepath.Join(inputDirectory(C.Path.HomeDir()), prepared.Fact.YAMLSHA256+".yaml")
	if err := os.WriteFile(path, []byte("mode: direct\nrules: []\n"), 0600); err != nil {
		t.Fatal(err)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" || currentConfig.General.Mode != tunnel.Rule {
		t.Fatalf("install reread mutable bytes: %+v", installed)
	}
	newest := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: false})
	if newest.Token == receipt.Token {
		t.Fatal("registration token was reused")
	}
	if result := activateConfig(installed.Receipt); result.Status != "superseded" {
		t.Fatalf("late activation: %+v", result)
	}
	if result := prepareConfig(newest); result.Status != "rejected" {
		t.Fatalf("changed object did not fail its digest: %+v", result)
	}
}

func TestConfigLateStopCannotCloseNewActivation(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	applyTestInput(t, input)
	oldStop := methodCallSeq.Add(1)
	current := applyTestInput(t, input)
	if !stopListenerReceived(oldStop) {
		t.Fatal("superseded stop was not acknowledged")
	}
	if fact := configStateSnapshot(); !fact.BusinessActive || fact.Owner != current.Fact.Owner {
		t.Fatal("old stop retired new activation", fact)
	}
	if !stopListenerReceived(methodCallSeq.Add(1)) || configStateSnapshot().BusinessActive {
		t.Fatal("current stop did not retire business")
	}
}

func TestConfigAbortWithLostPrepareReceiptIsStillTokenOwned(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	registered := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input})
	if result := prepareConfig(registered); result.Status != "prepared" {
		t.Fatal(result)
	}
	if result := abortConfig(registered); result.Status != "blocked" || result.Fact.ReplayEligible {
		t.Fatal("lost prepared response prevented owned cleanup", result)
	}
	current := applyTestInput(t, input)
	if result := abortConfig(registered); result.Status != "superseded" {
		t.Fatal("old registration aborted new activation", result)
	}
	if fact := configStateSnapshot(); !fact.BusinessActive || fact.Owner != current.Fact.Owner {
		t.Fatal(fact)
	}
}

func TestConfigCheckpointRevokeOrderingAndHotSnapshot(t *testing.T) {
	for _, order := range []string{"revoke-first", "publish-first"} {
		t.Run(order, func(t *testing.T) {
			configTestHome(t)
			input := writeTestInput(t, configTestYAML(0))
			applyTestInput(t, input)
			appRequests.mu.Lock()
			appRequests.client = "test"
			appRequests.clientReady = true
			appRequests.mu.Unlock()
			owner := appRequests.currentOwner()
			epoch, picks := routeStamp()
			configMu.Lock()
			candidate, err := prepareCheckpointCandidate(nil, nil)
			configMu.Unlock()
			if err != nil || candidate == nil {
				t.Fatal(candidate, err)
			}
			if order == "publish-first" {
				configMu.Lock()
				err = publishCheckpointCandidate(candidate)
				configMu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			}
			result := appRequests.control(appRequestControl{Action: "invalidate", Client: "test", Key: "script:9"})
			if failure, ok := result.(map[string]string); ok && failure["error"] != "" {
				t.Fatal(result)
			}
			afterEpoch, afterPicks := routeStamp()
			if owner != appRequests.currentOwner() || epoch != afterEpoch || picks != afterPicks {
				t.Fatal("source-only revoke unexpectedly changed Owner or route")
			}
			if order == "revoke-first" {
				configMu.Lock()
				err = publishCheckpointCandidate(candidate)
				configMu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			}
			checkpointMu.Lock()
			_, err = readCheckpointLocked(C.Path.HomeDir())
			checkpointMu.Unlock()
			if err == nil {
				t.Fatal("old snapshot revived the revoked reference")
			}
			mode := tunnel.Direct
			if err = updateConfig(&UpdateParams{Mode: &mode}); err != nil {
				t.Fatal(err)
			}
			if appliedConfig.eligible || appliedConfig.sources["script:9"] != 0 {
				t.Fatal("hot update recaptured source permission")
			}
			if _, err = replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err == nil {
				t.Fatal("hot snapshot renewed revoked replay permission")
			}
			if !configStateSnapshot().BusinessActive {
				t.Fatal("replay revocation falsified still-active business")
			}
		})
	}
}

func TestConfigReplayUsesAcknowledgedHotParametersAndPicks(t *testing.T) {
	configTestHome(t)
	input := writeTestInput(t, configTestYAML(0))
	applyTestInput(t, input)
	mode, ipv6, concurrent, unified, interval := tunnel.Global, true, true, true, 7
	if err := updateConfig(&UpdateParams{Mode: &mode, IPv6: &ipv6, TCPConcurrent: &concurrent, UnifiedDelay: &unified, GeoUpdateInterval: &interval}); err != nil {
		t.Fatal(err)
	}
	if result := handleChangeProxy(&ChangeProxyParams{GroupName: "GLOBAL", ProxyName: "REJECT"}); result.Message != "" {
		t.Fatal(result.Message)
	}
	replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
	if err != nil {
		t.Fatal(err)
	}
	_, _, raw, _, err := readConfigInput(C.Path.HomeDir(), replay.InputID)
	if err != nil {
		t.Fatal(err)
	}
	if raw.Mode != mode || raw.IPv6 != ipv6 || raw.TCPConcurrent != concurrent || raw.UnifiedDelay != unified || raw.GeoUpdateInterval != interval {
		t.Fatalf("hot replay mismatch: %+v", raw)
	}
	replay.Active = true
	prepared := prepareConfig(registerConfigOperation(methodCallSeq.Add(1), replay))
	if prepared.Status != "prepared" {
		t.Fatalf("replay prepare: %+v", prepared)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" {
		t.Fatalf("replay install: %+v", installed)
	}
	activated := activateConfig(installed.Receipt)
	if activated.Status != "activated" {
		t.Fatalf("replay activate: %+v", activated)
	}
	picks, _ := readPicks()
	if picks["GLOBAL"] != "REJECT" || currentConfig.General.Mode != mode {
		t.Fatal("actual hot selections were not replayed", picks)
	}
}

func TestConfigCheckpointDetachAndDatasetReplacement(t *testing.T) {
	configTestHome(t)
	applyTestInput(t, writeTestInput(t, configTestYAML(0)))
	appRequests.control(appRequestControl{Action: "engineDetach"})
	if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err != nil {
		t.Fatal("engine detach revoked the source", err)
	}
	attached := appRequests.control(appRequestControl{Action: "attach"}).(map[string]any)
	client := attached["client"].(string)
	appRequests.control(appRequestControl{Action: "ready", Client: client})
	if result := appRequests.control(appRequestControl{Action: "invalidateDataset", Client: client}); result == nil {
		t.Fatal("dataset replacement returned no result")
	}
	if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err == nil {
		t.Fatal("dataset replacement retained a replayable reference")
	}
}

func TestConfigCheckpointWriteFailureRequiresRecovery(t *testing.T) {
	configTestHome(t)
	applyTestInput(t, writeTestInput(t, configTestYAML(0)))
	configMu.Lock()
	candidate, err := prepareCheckpointCandidate(nil, nil)
	configMu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(inputDirectory(C.Path.HomeDir()), "checkpoint.json")
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	configMu.Lock()
	err = publishCheckpointCandidate(candidate)
	configMu.Unlock()
	if err == nil {
		t.Fatal("failed reference persistence reported success")
	}
	if _, err := os.Stat(filepath.Join(C.Path.HomeDir(), "request-recovery-required")); err != nil {
		t.Fatal("incomplete commit did not block recovery", err)
	}
	if _, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()}); err == nil {
		t.Fatal("incomplete checkpoint allowed cold replay")
	}
}
