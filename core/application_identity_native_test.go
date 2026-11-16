package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type nativeUIDFixture struct {
	Name          string          `json:"name"`
	UID           int             `json:"uid"`
	CurrentUser   bool            `json:"currentUser"`
	LookupFails   bool            `json:"lookupFails"`
	ValidCount    int             `json:"validCount"`
	InputPackages []string        `json:"inputPackages"`
	Identity      json.RawMessage `json:"identity"`
}

func nativeUIDFixtures(t *testing.T) ([]nativeUIDFixture, string) {
	t.Helper()
	path := os.Getenv("FLCLASH_UID_IDENTITY_FIXTURE")
	if path == "" {
		path = "testdata/uid_package_identity.json"
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []nativeUIDFixture
	if err := json.Unmarshal(data, &fixtures); err != nil || len(fixtures) != 7 {
		t.Fatalf("native fixture: %v, cases=%d", err, len(fixtures))
	}
	for _, f := range fixtures {
		if len(f.candidates()) != f.ValidCount {
			t.Fatalf("controlled input lost candidates: %s", f.Name)
		}
	}
	hash := sha256.Sum256(data)
	return fixtures, hex.EncodeToString(hash[:])
}

func (f nativeUIDFixture) candidates() []string {
	var names []string
	for _, name := range f.InputPackages {
		if strings.TrimSpace(name) != "" {
			names = append(names, name)
		}
	}
	slices.Sort(names)
	return slices.Compact(names)
}

func (f nativeUIDFixture) qualified() bool {
	return f.UID >= 0 && f.CurrentUser && !f.LookupFails && f.ValidCount > 0 && f.ValidCount <= 64
}

func TestNativeUIDIdentityContract(t *testing.T) {
	fixtures, _ := nativeUIDFixtures(t)
	for _, f := range fixtures {
		t.Run(f.Name, func(t *testing.T) {
			identity := decodeApplicationIdentity(f.UID, string(f.Identity), "androidUid")
			status := "lookupFailed"
			switch {
			case f.UID < 0:
				status = "unknown"
			case !f.CurrentUser:
				status = "otherUser"
			case f.LookupFails || f.ValidCount > 64:
			case f.ValidCount == 0:
				status = "notFound"
			case f.ValidCount == 1:
				status = "known"
			default:
				status = "ambiguous"
			}
			if identity.Status != status {
				t.Errorf("status=%s, want %s; native=%s", identity.Status, status, f.Identity)
			}
			if f.UID < 0 {
				if identity.UID != nil || identity.Method != "unavailable" {
					t.Fatal("negative UID was promoted", identity)
				}
			} else if identity.UID == nil || *identity.UID != uint32(f.UID) || identity.Method != "androidUid" {
				t.Fatal("system UID or method lost", identity)
			}
			if f.qualified() {
				if !slices.Equal(identity.Packages, f.candidates()) || identity.UserScope != "current" {
					t.Fatal("complete candidate set changed", identity)
				}
			} else if len(identity.Packages) != 0 || identity.packageName() != "" {
				t.Fatal("unqualified input exposed candidates", identity)
			}
			if f.qualified() && f.ValidCount == 1 && identity.packageName() != f.candidates()[0] {
				t.Fatal("unique identity was lost", identity)
			}
		})
	}
}

func TestNativeUIDMalformedWireDoesNotGainPolicyIdentity(t *testing.T) {
	fixtures, _ := nativeUIDFixtures(t)
	var source json.RawMessage
	for _, f := range fixtures {
		if f.Name == "unique" {
			source = f.Identity
		}
	}
	for _, fault := range []string{"status", "userScope", "packages", "wrong-type", "duplicate", "empty"} {
		t.Run(fault, func(t *testing.T) {
			var wire map[string]any
			if err := json.Unmarshal(source, &wire); err != nil {
				t.Fatal(err)
			}
			switch fault {
			case "wrong-type":
				wire["packages"] = true
			case "duplicate":
				wire["packages"] = []string{"fixture.app000", "fixture.app000"}
			case "empty":
				wire["packages"] = []string{""}
			default:
				delete(wire, fault)
			}
			data, err := json.Marshal(wire)
			if err != nil {
				t.Fatal(err)
			}
			identity := decodeApplicationIdentity(10123, string(data), "androidUid")
			if identity.Status != "lookupFailed" || len(identity.Packages) != 0 || identity.packageName() != "" {
				t.Fatal("malformed wire became qualified", identity)
			}
		})
	}
}

func uidRoutingWire(f nativeUIDFixture, target, variant string, perHost, generic bool) *applicationRouteSettings {
	other := "DIRECT"
	if target == other {
		other = "REJECT"
	}
	var apps []applicationRouteEntry
	var hosts []applicationHostEntry
	names := f.candidates()
	for i, name := range names {
		if i == len(names)-1 && variant == "missing-last" {
			continue
		}
		selected := target
		if i == len(names)-1 && variant == "conflict-last" {
			selected = other
		}
		if perHost {
			apps = append(apps, applicationRouteEntry{Package: name, Target: other})
			hosts = append(hosts, applicationHostEntry{ID: fmt.Sprintf("%d", 1000+i), Package: name, Type: "IP-CIDR", Content: "127.0.0.1/32", Target: selected})
		} else {
			apps = append(apps, applicationRouteEntry{Package: name, Target: selected})
		}
	}
	if generic {
		hosts = append(hosts, applicationHostEntry{ID: "2000", Type: "IP-CIDR", Content: "127.0.0.1/32", Target: "DIRECT"})
	}
	return hostWire(apps, hosts)
}

func uidEchoServer(t *testing.T) (uint16, func()) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var serving sync.WaitGroup
	closed := make(chan struct{})
	go func() {
		defer close(closed)
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			serving.Add(1)
			go func() { defer serving.Done(); defer conn.Close(); _, _ = io.Copy(conn, conn) }()
		}
	}()
	return uint16(listener.Addr().(*net.TCPAddr).Port), func() { _ = listener.Close(); <-closed; serving.Wait() }
}

func uidTCPResult(t *testing.T, scope *requestscope.BusinessScope, metadata *C.Metadata) bool {
	t.Helper()
	client, inbound := net.Pipe()
	defer client.Close()
	done := make(chan struct{})
	go func() { defer close(done); tunnel.BindBusiness(scope).HandleTCPConn(inbound, metadata) }()
	_ = client.SetDeadline(time.Now().Add(3 * time.Second))
	probe := []byte("uid-r05")
	_, err := client.Write(probe)
	echoed := false
	if err == nil {
		response := make([]byte, len(probe))
		_, err = io.ReadFull(client, response)
		echoed = err == nil && bytes.Equal(response, probe)
		if err == nil && !echoed {
			t.Error("local TCP reply was not the probe")
		}
	}
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		t.Error("timeout is not evidence of REJECT", err)
	}
	_ = client.Close()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Error("Core TCP handler was not reclaimed")
	}
	return echoed
}

func TestNativeUIDRoutingAndLocalTCPFallback(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	applyTestInput(t, sourceTraceInput(t, "mode: rule\nfind-process-mode: off\ngeo-auto-update: false\nrules: ['MATCH,REJECT']\n", nil))
	fixtures, hash := nativeUIDFixtures(t)
	port, closeServer := uidEchoServer(t)
	defer closeServer()
	var report []map[string]any
	sourcePort := 43000
	metadataFor := func(network C.NetWork) *C.Metadata {
		sourcePort++
		metadata := observationTracker(sourcePort, network).Metadata
		metadata.Host, metadata.DstIP, metadata.DstPort = "", netip.MustParseAddr("127.0.0.1"), port
		return metadata
	}
	defer func() {
		if path := os.Getenv("FLCLASH_UID_MATRIX_RESULTS"); path != "" {
			body, err := json.MarshalIndent(map[string]any{"fixtureSha256": hash, "cases": report}, "", "  ")
			if err != nil {
				t.Error(err)
				return
			}
			if err := os.WriteFile(path, body, 0600); err != nil {
				t.Error(err)
			}
		}
	}()
	for _, setup := range []struct {
		name          string
		mode          tunnel.TunnelMode
		generic       bool
		app, fallback string
	}{
		{"direct", tunnel.Direct, false, "REJECT", "DIRECT"},
		{"rule-subscription", tunnel.Rule, false, "DIRECT", "REJECT"},
		{"rule-generic-host", tunnel.Rule, true, "REJECT", "DIRECT"},
	} {
		for _, perHost := range []bool{false, true} {
			for _, f := range fixtures {
				variants := []string{"uniform"}
				if f.ValidCount >= 2 {
					variants = append(variants, "missing-last", "conflict-last")
				}
				for _, variant := range variants {
					name := fmt.Sprintf("%s/host=%t/%s/%s", setup.name, perHost, f.Name, variant)
					passed := t.Run(name, func(t *testing.T) {
						tunnel.SetMode(setup.mode)
						wire := uidRoutingWire(f, setup.app, variant, perHost, setup.generic)
						if err := validateApplicationRoutes(wire); err != nil {
							t.Fatal(err)
						}
						scope := requestscope.NewBusinessScope(4100, func() bool { return true })
						scope.Activate()
						defer scope.Close()
						data, err := json.Marshal(wire)
						if err != nil {
							t.Fatal(err)
						}
						p := &preparedConfig{scope: scope, manifest: ConfigManifest{ProfileID: wire.ProfileID, AcceptedOverrides: map[string]json.RawMessage{"application-routing": data}}}
						publishSourceTraceState(p, "uid-fixture", false)
						old := preparedConfigGate.Swap(p)
						defer preparedConfigGate.Store(old)
						identity := decodeApplicationIdentity(f.UID, string(f.Identity), "androidUid")
						want := setup.fallback
						qualified := f.qualified() && variant == "uniform"
						if qualified {
							want = setup.app
						}
						for _, network := range []C.NetWork{C.TCP, C.UDP} {
							metadata := metadataFor(network)
							connectionObservations.remember(metadata, connectionIngress{identity: &identity})
							_, target, err := resolveApplicationRoute(context.Background(), scope, metadata)
							wantOverride := ""
							if qualified || setup.generic {
								wantOverride = want
							}
							if err != nil || target != wantOverride {
								t.Errorf("%s override=%q want=%q error=%v identity=%+v", network, target, wantOverride, err, identity)
							}
						}
						metadata := metadataFor(C.TCP)
						connectionObservations.remember(metadata, connectionIngress{identity: &identity})
						if allowed := uidTCPResult(t, scope, metadata); allowed != (want == "DIRECT") {
							t.Errorf("actual local TCP allowed=%t, want %s", allowed, want)
						}
					})
					report = append(report, map[string]any{"case": name, "passed": passed})
				}
			}
		}
	}
}
