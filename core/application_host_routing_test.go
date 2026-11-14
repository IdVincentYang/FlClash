package main

import (
	"context"
	"encoding/json"
	"net"
	"net/netip"
	"strconv"
	"testing"

	"github.com/metacubex/mihomo/component/requestscope"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func hostWire(apps []applicationRouteEntry, hosts []applicationHostEntry) *applicationRouteSettings {
	wire := applicationWire(7, 2, apps...)
	canonical := "7\n2\n"
	for _, app := range apps {
		id := "-"
		if app.GroupID != nil {
			id = strconv.FormatInt(*app.GroupID, 10)
		}
		canonical += app.Package + "\x00" + app.Target + "\x00" + id + "\n"
	}
	if len(hosts) != 0 {
		canonical += "host-rules\n"
	}
	for _, host := range hosts {
		canonical += applicationHostCanonical(host) + "\n"
	}
	wire.HostRules, wire.Revision = hosts, inputHash([]byte(canonical))
	return wire
}

func TestApplicationHostPriorityAndIdentity(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	applyTestInput(t, sourceTraceInput(t, "mode: rule\nfind-process-mode: off\ngeo-auto-update: false\nproxies:\n  - {name: app-host, type: socks5, server: 127.0.0.1, port: 19080}\n  - {name: app-default, type: socks5, server: 127.0.0.1, port: 19081}\n  - {name: generic, type: socks5, server: 127.0.0.1, port: 19082}\nrules: ['MATCH,REJECT']\n", nil))
	scope := requestscope.NewBusinessScope(311, func() bool { return true })
	scope.Activate()
	defer scope.Close()
	p := &preparedConfig{scope: scope}
	old := preparedConfigGate.Swap(p)
	defer preparedConfigGate.Store(old)
	generic := applicationHostEntry{ID: "1", Type: "DOMAIN", Content: "example.test", Target: "generic"}
	own := applicationHostEntry{ID: "2", Package: "a", Type: "DOMAIN", Content: "example.test", Target: "app-host"}
	app := applicationRouteEntry{Package: "a", Target: "app-default"}
	for _, network := range []C.NetWork{C.TCP, C.UDP} {
		for _, tc := range []struct {
			name     string
			apps     []applicationRouteEntry
			hosts    []applicationHostEntry
			mode     tunnel.TunnelMode
			packages []string
			want     string
		}{
			{"none", nil, nil, tunnel.Rule, []string{"a"}, ""},
			{"generic", nil, []applicationHostEntry{generic}, tunnel.Rule, []string{"a"}, "generic"},
			{"own", nil, []applicationHostEntry{own}, tunnel.Rule, []string{"a"}, "app-host"},
			{"both", nil, []applicationHostEntry{generic, own}, tunnel.Rule, []string{"a"}, "app-host"},
			{"whole-before-generic", []applicationRouteEntry{app}, []applicationHostEntry{generic}, tunnel.Rule, []string{"a"}, "app-default"},
			{"missing-host-target", nil, []applicationHostEntry{{ID: "2", Package: "a", Type: "DOMAIN", Content: "example.test", Target: "removed"}}, tunnel.Rule, []string{"a"}, "REJECT"},
			{"own-before-whole", []applicationRouteEntry{app}, []applicationHostEntry{generic, own}, tunnel.Rule, []string{"a"}, "app-host"},
			{"direct-generic", nil, []applicationHostEntry{generic}, tunnel.Direct, []string{"a"}, ""},
			{"direct-own", []applicationRouteEntry{app}, []applicationHostEntry{generic, own}, tunnel.Direct, []string{"a"}, "app-host"},
			{"unknown", []applicationRouteEntry{app}, []applicationHostEntry{generic, own}, tunnel.Rule, nil, "generic"},
			{"shared", []applicationRouteEntry{app}, []applicationHostEntry{generic, own}, tunnel.Rule, []string{"a", "b"}, "generic"},
		} {
			t.Run(network.String()+"/"+tc.name, func(t *testing.T) {
				tunnel.SetMode(tc.mode)
				wire := hostWire(tc.apps, tc.hosts)
				if err := validateApplicationRoutes(wire); err != nil {
					t.Fatal(err)
				}
				data, _ := json.Marshal(wire)
				p.manifest = ConfigManifest{ProfileID: wire.ProfileID, AcceptedOverrides: map[string]json.RawMessage{"application-routing": data}}
				publishSourceTraceState(p, "fixture", false)
				metadata := &C.Metadata{NetWork: network, Type: C.TUN, Host: "example.test", DstIP: netip.MustParseAddr("192.0.2.2"), RawSrcAddr: &net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: 42321}, RawDstAddr: &net.TCPAddr{IP: net.IPv4(192, 0, 2, 2), Port: 443}}
				body, _ := json.Marshal(map[string]any{"status": "known", "userScope": "current", "packages": tc.packages})
				identity := decodeApplicationIdentity(10123, string(body), "androidUid")
				connectionObservations.Lock()
				delete(connectionObservations.pending, connectionIngressKey(metadata))
				connectionObservations.Unlock()
				connectionObservations.remember(metadata, connectionIngress{identity: &identity})
				_, target, err := resolveApplicationRoute(context.Background(), scope, metadata)
				if err != nil || target != tc.want {
					t.Fatalf("target=%q want=%q err=%v", target, tc.want, err)
				}
			})
		}
	}
}

func TestApplicationHostValidationAndIPMatching(t *testing.T) {
	for _, tc := range []struct{ kind, content, host, ip string }{
		{"DOMAIN", "example.test", "example.test", "192.0.2.2"},
		{"IP-CIDR", "192.0.2.2/32", "", "192.0.2.2"},
		{"IP-CIDR6", "2001:db8::2/128", "", "2001:db8::2"},
	} {
		entry := applicationHostEntry{ID: "1", Type: tc.kind, Content: tc.content, Target: "DIRECT"}
		wire := hostWire(nil, []applicationHostEntry{entry})
		if err := validateApplicationRoutes(wire); err != nil {
			t.Fatal(err)
		}
		data, _ := json.Marshal(wire)
		routes := applicationHostRoutesFor(ConfigManifest{AcceptedOverrides: map[string]json.RawMessage{"application-routing": data}})
		metadata := &C.Metadata{Host: tc.host, DstIP: netip.MustParseAddr(tc.ip)}
		if _, ok := matchApplicationHost(routes[""], metadata); !ok {
			t.Fatal("exact host did not match", tc)
		}
		metadata.Host, metadata.DstIP = "other.test", netip.MustParseAddr("192.0.2.3")
		if _, ok := matchApplicationHost(routes[""], metadata); ok {
			t.Fatal("host match widened", tc)
		}
		entry.Content = "http://invalid.test/"
		if validateApplicationRoutes(hostWire(nil, []applicationHostEntry{entry})) == nil {
			t.Fatal("invalid host accepted")
		}
	}
}

func BenchmarkApplicationHostIndex(b *testing.B) {
	routes := map[string]applicationRoute{}
	for i := 1; i <= 1000; i++ {
		host := applicationHostEntry{ID: strconv.Itoa(i), Type: "DOMAIN", Content: strconv.Itoa(i) + ".example.test", Target: "DIRECT"}
		data, _ := json.Marshal(hostWire(nil, []applicationHostEntry{host}))
		for key, route := range applicationHostRoutesFor(ConfigManifest{AcceptedOverrides: map[string]json.RawMessage{"application-routing": data}})[""] {
			routes[key] = route
		}
	}
	metadata := &C.Metadata{Host: "1000.example.test"}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, ok := matchApplicationHost(routes, metadata); !ok {
			b.Fatal("missing")
		}
	}
}

func TestApplicationHostWireAndManagedReplay(t *testing.T) {
	wire := hostWire([]applicationRouteEntry{{Package: "a", Target: "DIRECT"}}, []applicationHostEntry{
		{ID: "1", Type: "DOMAIN", Content: "example.test", Target: "DIRECT"},
		{ID: "2", Package: "a", Type: "DOMAIN", Content: "example.test", Target: "REJECT"},
	})
	if wire.Revision != "2cfcf3ac9ffec14b8ef87980aa48477a6755d01e5a9237f78a46308060ce7f7a" || validateApplicationRoutes(wire) != nil {
		t.Fatal("Dart/Go canonical mismatch", wire)
	}
	tampered := *wire
	tampered.HostRules = append([]applicationHostEntry(nil), wire.HostRules...)
	tampered.HostRules[0].Target = "REJECT"
	if validateApplicationRoutes(&tampered) == nil {
		t.Fatal("tampered host accepted")
	}
	duplicated := hostWire(nil, []applicationHostEntry{{ID: "1", Type: "DOMAIN", Content: "example.test", Target: "DIRECT"}, {ID: "2", Type: "DOMAIN", Content: "EXAMPLE.TEST.", Target: "REJECT"}})
	if validateApplicationRoutes(duplicated) == nil {
		t.Fatal("duplicate scope accepted")
	}
	f := newManagedFixture(t)
	accepted := applyManagedInput(t, compiledManagedInput(t, f, "fc-managed-group-a"))
	if err := updateConfig(&UpdateParams{ApplicationRouting: wire}); err != nil {
		t.Fatal(err)
	}
	fact := configStateSnapshot()
	if fact.ApplicationRoutingRules["@host:2"] == "" || fact.PolicySHA256 != accepted.Fact.PolicySHA256 {
		t.Fatal("host not adopted independently", fact)
	}
	replay, err := replayConfigInput(&InitParams{HomeDir: C.Path.HomeDir()})
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, _, _, err := readConfigInput(C.Path.HomeDir(), replay.InputID)
	if err != nil || manifest.ManagedPolicy == nil {
		t.Fatal(err)
	}
	routes := applicationHostRoutesFor(manifest)
	if route, ok := matchApplicationHost(routes["a"], &C.Metadata{Host: "EXAMPLE.TEST."}); !ok || route.target != "REJECT" {
		t.Fatal("lost persisted host", routes)
	}
	removed := applicationWire(7, 3)
	if err := updateConfig(&UpdateParams{ApplicationRouting: removed}); err != nil {
		t.Fatal(err)
	}
	if len(configStateSnapshot().ApplicationRoutingRules) != 0 {
		t.Fatal("deleted host still adopted")
	}
	checkpoint, err := readCheckpointLocked(C.Path.HomeDir())
	if err != nil {
		t.Fatal(err)
	}
	manifest, _, _, _, err = readConfigInput(C.Path.HomeDir(), checkpoint.InputID)
	if err != nil || len(applicationHostRoutesFor(manifest)) != 0 {
		t.Fatal("deleted host replayed", err)
	}
}
