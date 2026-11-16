package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"sync"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func modeInputIdle(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for inputCollectionQueued.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if inputCollectionQueued.Load() {
		t.Fatal("previous fixture input collection did not finish")
	}
}

func modeInput(t *testing.T, mode tunnel.TunnelMode, ordinary bool, origin string) string {
	t.Helper()
	modeInputIdle(t)
	target := "REJECT"
	if ordinary {
		target = "DIRECT"
	}
	yaml := fmt.Sprintf("mode: %s\nfind-process-mode: off\ngeo-auto-update: false\ndns: {enable: false}\nntp: {enable: false}\nproxy-groups:\n  - {name: app-choice, type: select, proxies: [DIRECT]}\n  - {name: GLOBAL, type: select, proxies: [DIRECT]}\nrules: ['MATCH,%s']\n", mode, target)
	id := sourceTraceInput(t, yaml, nil)
	if origin == "profile" {
		return id
	}
	path := filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var manifest ConfigManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	entry := &manifest.RuleLedger.Lists["rules"][0]
	entry.Origin, entry.Revision = origin, inputHash([]byte("controlled local rules"))
	data, err = json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	id = inputHash(data)
	if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"), data); err != nil {
		t.Fatal(err)
	}
	return id
}

func modeAppSettings(host bool, target string) *applicationRouteSettings {
	if host {
		return hostWire(nil, []applicationHostEntry{{ID: "1", Package: "test.app", Type: "IP-CIDR", Content: "127.0.0.1/32", Target: target}})
	}
	return hostWire([]applicationRouteEntry{{Package: "test.app", Target: target}}, nil)
}

func modeMetadata(port int, destination uint16) *C.Metadata {
	metadata := observationTracker(port, C.TCP).Metadata
	metadata.Host, metadata.DstIP, metadata.DstPort = "", netip.MustParseAddr("127.0.0.1"), destination
	metadata.RawDstAddr = &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: int(destination)}
	return metadata
}

func modeRemember(metadata *C.Metadata, configuration connectionConfiguration) {
	identity := decodeApplicationIdentity(10123, `{"status":"known","userScope":"current","packages":["test.app"]}`, "androidUid")
	connectionObservations.remember(metadata, connectionIngress{configuration: configuration, identity: &identity})
}

func modeCoreTCP(t *testing.T, metadata *C.Metadata, gate func(*statistic.TrackerInfo), revoked bool) *statistic.TrackerInfo {
	t.Helper()
	client, inbound := net.Pipe()
	entered, frozen := make(chan *statistic.TrackerInfo, 1), make(chan struct{})
	release, done := make(chan struct{}), make(chan struct{})
	var once sync.Once
	previous := statistic.DefaultRequestNotify
	statistic.DefaultRequestNotify = func(tracker statistic.Tracker) {
		info := tracker.Info()
		if info.Metadata != metadata {
			return
		}
		entered <- info
		<-release
		connectionObservations.bind(info, bindSourceTracker(info))
		close(frozen)
	}
	defer func() {
		once.Do(func() { close(release) })
		_ = client.Close()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Error("Core TCP handler was not reclaimed")
		}
		statistic.DefaultRequestNotify = previous
	}()
	scope := appliedConfig.scope
	go func() { defer close(done); tunnel.BindBusiness(scope).HandleTCPConn(inbound, metadata) }()
	_ = client.SetDeadline(time.Now().Add(5 * time.Second))
	probe := make(chan error, 1)
	go func() {
		payload := "mode-r06"
		_, err := io.WriteString(client, payload)
		if err == nil {
			response := make([]byte, len(payload))
			_, err = io.ReadFull(client, response)
			if err == nil && string(response) != payload {
				err = fmt.Errorf("unexpected local echo %q", response)
			}
		}
		probe <- err
	}()
	var info *statistic.TrackerInfo
	select {
	case info = <-entered:
	case err := <-probe:
		t.Fatalf("connection ended before real Tracker join: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("Tracker join gate was not reached")
	}
	if gate != nil {
		gate(info)
	}
	if revoked && scope.Check() == nil {
		t.Error("full ConfigInput replacement did not revoke the old lease")
	}
	once.Do(func() { close(release) })
	select {
	case <-frozen:
	case <-time.After(5 * time.Second):
		t.Fatal("observation was not frozen")
	}
	err := <-probe
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		t.Error("a timeout does not prove lease revocation", err)
	}
	if revoked {
		if err == nil {
			t.Error("revoked connection continued transporting payload")
		}
	} else if err != nil {
		t.Fatal("actual local TCP exit changed", err)
	}
	return info
}

func TestConnectionModeRealTrackerAndTransitions(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	port, closeServer := uidEchoServer(t)
	defer closeServer()
	var records []map[string]any
	for i, tc := range []struct {
		name, origin, wantMode  string
		mode                    tunnel.TunnelMode
		host, ordinary, noStamp bool
		changes                 []tunnel.TunnelMode
		replace                 bool
	}{
		{name: "direct-app", mode: tunnel.Direct, wantMode: "direct"},
		{name: "direct-host", mode: tunnel.Direct, host: true, wantMode: "direct"},
		{name: "rule-app", mode: tunnel.Rule, wantMode: "rule"},
		{name: "rule-host", mode: tunnel.Rule, host: true, wantMode: "rule"},
		{name: "ordinary-profile", mode: tunnel.Rule, ordinary: true, origin: "profile", noStamp: true, wantMode: "rule"},
		{name: "ordinary-local-origin", mode: tunnel.Rule, ordinary: true, origin: "application-rules", noStamp: true, wantMode: "rule"},
		{name: "ordinary-unknown-author", mode: tunnel.Rule, ordinary: true, noStamp: true, wantMode: "rule"},
		{name: "global-bypass", mode: tunnel.Global, wantMode: "global"},
		{name: "app-without-entry-stamp", mode: tunnel.Direct, noStamp: true},
		{name: "direct-to-rule", mode: tunnel.Direct, changes: []tunnel.TunnelMode{tunnel.Rule}},
		{name: "host-direct-to-rule", mode: tunnel.Direct, host: true, changes: []tunnel.TunnelMode{tunnel.Rule}},
		{name: "direct-round-trip", mode: tunnel.Direct, changes: []tunnel.TunnelMode{tunnel.Rule, tunnel.Direct}},
		{name: "ordinary-late-mode", mode: tunnel.Rule, ordinary: true, origin: "application-rules", changes: []tunnel.TunnelMode{tunnel.Direct}, wantMode: "rule"},
		{name: "input-replacement", mode: tunnel.Direct, replace: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			applyTestInput(t, modeInput(t, tc.mode, tc.ordinary, tc.origin))
			if !tc.ordinary {
				target := "app-choice"
				if tc.mode == tunnel.Global {
					target = "REJECT"
				}
				if err := updateConfig(&UpdateParams{ApplicationRouting: modeAppSettings(tc.host, target)}); err != nil {
					t.Fatal(err)
				}
			}
			modeInputIdle(t)
			before := observedConfiguration()
			if before.Status != "known" || before.Mode != tc.mode.String() {
				t.Fatal("initial production configuration is not observable", before)
			}
			metadata := modeMetadata(46000+i, port)
			stamp := before
			if tc.noStamp {
				stamp = connectionConfiguration{Status: "unknown"}
			}
			modeRemember(metadata, stamp)
			matchedIndex, modeAtJoin := -1, ""
			info := modeCoreTCP(t, metadata, func(info *statistic.TrackerInfo) {
				modeAtJoin = tunnel.Mode().String()
				if modeAtJoin != tc.mode.String() {
					t.Fatal("mode changed before the real join gate", modeAtJoin)
				}
				sourceRuleTraces.Lock()
				frame := sourceRuleTraces.pending[metadata]
				if frame != nil {
					matchedIndex = frame.index
				}
				sourceRuleTraces.Unlock()
				if tc.mode != tunnel.Global && (frame == nil || frame.state == nil || frame.state.input != before.InputID || (matchedIndex >= 0) != tc.ordinary) {
					t.Fatal("join gate has no matching production trace", frame)
				}
				if tc.mode == tunnel.Global && frame != nil {
					t.Fatal("Global did not bypass the hook and matcher")
				}
				if !slices.Contains(info.Chain, "DIRECT") || slices.Contains(info.Chain, "app-choice") != (!tc.ordinary && tc.mode != tunnel.Global) {
					t.Fatal("real selected chain differs", info.Chain)
				}
				if tc.mode == tunnel.Global && info.Rule != "" || tc.mode != tunnel.Global && info.Rule == "" {
					t.Fatal("actual App/matcher/Global branch differs", info.Rule)
				}
				for _, mode := range tc.changes {
					if err := updateConfig(&UpdateParams{Mode: &mode}); err != nil {
						t.Fatal(err)
					}
				}
				if tc.replace {
					applyTestInput(t, modeInput(t, tunnel.Rule, true, "profile"))
				}
				if epoch, _ := routeStamp(); len(tc.changes) != 0 && epoch <= *before.RouteEpoch {
					t.Fatal("legal mode update did not advance its epoch")
				}
			}, tc.replace)
			view := sourceTrackerViewOf(info)
			configuration := view.Observation.Configuration
			if configuration.Status != "known" || configuration.InputID != before.InputID || configuration.Mode != tc.wantMode {
				t.Errorf("configuration=%+v want input=%s mode=%q provenance=%+v", configuration, before.InputID, tc.wantMode, view.Provenance)
			}
			partial := tc.noStamp || len(tc.changes) != 0 || tc.replace
			if partial && (configuration.RouteEpoch != nil || configuration.PicksVersion != nil) {
				t.Error("partial proof invented route versions", configuration)
			}
			data, err := json.Marshal(view)
			if err != nil {
				t.Fatal(err)
			}
			records = append(records, map[string]any{"case": tc.name, "expectedMode": tc.wantMode, "modeAtJoin": modeAtJoin, "matchingIndex": matchedIndex, "transportRevoked": tc.replace, "connection": json.RawMessage(data)})
			mode := tunnel.Global
			if err := updateConfig(&UpdateParams{Mode: &mode}); err != nil {
				t.Fatal(err)
			}
			connectionObservations.bind(info, sourceRuleProvenance{AppliedRevision: "unrelated-new-input"})
			if next := sourceTrackerViewOf(info); !reflect.DeepEqual(next.Observation, view.Observation) {
				t.Error("frozen observation changed", next.Observation)
			}
		})
	}
	if path := os.Getenv("FLCLASH_CONNECTION_MODE_FIXTURE"); path != "" {
		data, err := json.MarshalIndent(records, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func TestConnectionModePartialEvidenceBoundaries(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	for _, ordinary := range []bool{false, true} {
		mode := tunnel.Direct
		if ordinary {
			mode = tunnel.Rule
		}
		applyTestInput(t, modeInput(t, mode, ordinary, "application-rules"))
		if !ordinary {
			if err := updateConfig(&UpdateParams{ApplicationRouting: modeAppSettings(false, "DIRECT")}); err != nil {
				t.Fatal(err)
			}
		}
		for i, fault := range []string{"input", "mode", "routeEpoch", "picksVersion", "lock", "missing", "expired", "payload", "chain"} {
			t.Run(fmt.Sprintf("ordinary=%t/%s", ordinary, fault), func(t *testing.T) {
				info := observationTracker(47000+i, C.TCP)
				info.Metadata.Host, info.Metadata.DstIP = "", netip.MustParseAddr("127.0.0.1")
				modeInputIdle(t)
				before := observedConfiguration()
				if before.Status != "known" {
					t.Fatal("boundary fixture has no initial configuration", before)
				}
				originalInput := before.InputID
				switch fault {
				case "input":
					before.InputID = "unrelated-entry-input"
				case "mode":
					before.Mode = "global"
				case "routeEpoch":
					x := *before.RouteEpoch + 1
					before.RouteEpoch = &x
				case "picksVersion":
					x := *before.PicksVersion + 1
					before.PicksVersion = &x
				case "missing", "expired", "payload", "chain":
					before = connectionConfiguration{Status: "unknown"}
				}
				modeRemember(info.Metadata, before)
				var rule C.Rule
				if ordinary {
					rule = appliedConfig.cfg.Rules[0]
					if matched, target := rule.Match(info.Metadata, C.RuleMatchHelper{}); !matched || target != "DIRECT" {
						t.Fatal("ordinary matcher fixture did not match")
					}
				} else {
					var err error
					rule, _, err = resolveApplicationRoute(context.Background(), appliedConfig.scope, info.Metadata)
					if err != nil || rule == nil {
						t.Fatal("App hook fixture did not match", err)
					}
				}
				info.Rule, info.RulePayload = rule.RuleType().String(), rule.Payload()
				sourceRuleTraces.Lock()
				switch fault {
				case "missing":
					delete(sourceRuleTraces.pending, info.Metadata)
				case "expired":
					sourceRuleTraces.pending[info.Metadata].time = time.Now().Add(-2 * time.Minute)
				case "payload":
					info.RulePayload = "not-the-actual-payload"
				case "chain":
					info.Chain = C.Chain{"REJECT"}
				}
				sourceRuleTraces.Unlock()
				provenance := bindSourceTracker(info)
				if fault == "lock" {
					configMu.Lock()
				}
				connectionObservations.bind(info, provenance)
				if fault == "lock" {
					configMu.Unlock()
				}
				configuration := connectionObservations.view(info).observation.Configuration
				if slices.Contains([]string{"missing", "expired", "payload", "chain"}, fault) {
					if configuration.Status != "unknown" || configuration.InputID != "" || configuration.Mode != "" {
						t.Error("missing proof acquired current configuration", configuration)
					}
				} else {
					wantMode := ""
					if ordinary {
						wantMode = "rule"
					}
					if configuration.Status != "known" || configuration.InputID != originalInput || configuration.Mode != wantMode {
						t.Errorf("partial configuration=%+v want mode=%q", configuration, wantMode)
					}
				}
				if configuration.RouteEpoch != nil || configuration.PicksVersion != nil {
					t.Error("partial proof inherited route versions", configuration)
				}
			})
		}
	}
}
