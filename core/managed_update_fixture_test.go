package main

import (
	"encoding/json"
	"fmt"
	C "github.com/metacubex/mihomo/constant"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/metacubex/mihomo/component/auth"
)

func managedUpdateMaterial(f *managedFixture, host, phase string) map[string]any {
	node := func(name string, index int) map[string]any {
		user := []string{"a", "b"}[index]
		return map[string]any{"name": name, "type": "socks5", "server": host,
			"port": managedPort(f.proxies[index].address), "udp": false,
			"username": user, "password": "pass-" + user}
	}
	nodes := []any{node("edge", 0)}
	members, group := []any{"edge"}, "pool"
	domains := []any{"DOMAIN-SUFFIX,example.test"}
	if phase != "A" {
		nodes = []any{node("edge", 1), node("new-edge", 1)}
		members = []any{"new-edge"}
		domains = append(domains, "DOMAIN,added.test")
	}
	if phase == "bad" {
		members = []any{"missing"}
	}
	if phase == "rename" {
		group = "renamed-pool"
	}
	return map[string]any{
		"proxies":      nodes,
		"proxy-groups": []any{map[string]any{"name": group, "type": "select", "proxies": members}},
		"rule-providers": map[string]any{
			"domains":   map[string]any{"type": "inline", "behavior": "classical", "payload": domains},
			"addresses": map[string]any{"type": "inline", "behavior": "ipcidr", "payload": []any{"127.0.0.0/8", "::1/128"}},
		},
	}
}

func TestManagedUpdateManualFixture(t *testing.T) {
	if os.Getenv("FLCLASH_MANAGED_UPDATE_FIXTURE") != "1" {
		t.Skip("manual local fixture")
	}
	f := newManagedFixture(t)
	host := "127.0.0.1"
	if os.Getenv("FLCLASH_MANAGED_UPDATE_AVD") == "1" {
		host = "10.0.2.2"
	}
	for index, user := range []string{"a", "b"} {
		f.proxies[index].mu.Lock()
		f.proxies[index].auth = auth.NewAuthenticator([]auth.AuthUser{{User: user, Pass: "pass-" + user}})
		f.proxies[index].mu.Unlock()
	}
	var mu sync.Mutex
	phase := "A"
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/profile":
			mu.Lock()
			current := phase
			mu.Unlock()
			_ = json.NewEncoder(w).Encode(managedUpdateMaterial(f, host, current))
		case strings.HasPrefix(r.URL.Path, "/phase/"):
			next := strings.TrimPrefix(r.URL.Path, "/phase/")
			if next != "A" && next != "B" && next != "bad" && next != "rename" {
				http.Error(w, "invalid synthetic phase", http.StatusBadRequest)
				return
			}
			mu.Lock()
			phase = next
			mu.Unlock()
			_ = json.NewEncoder(w).Encode(map[string]string{"phase": next})
		case r.URL.Path == "/probe":
			name := r.URL.Query().Get("name")
			if name == "" {
				name = "fresh.example.test"
			}
			if !strings.HasSuffix(name, ".example.test") && name != "added.test" {
				http.Error(w, "synthetic domain required", http.StatusBadRequest)
				return
			}
			body, businessErr := f.get(name)
			_, dnsErr := f.query(name)
			_ = json.NewEncoder(w).Encode(map[string]any{"body": body, "businessOK": businessErr == nil, "dnsOK": dnsErr == nil})
		case r.URL.Path == "/status":
			mu.Lock()
			current := phase
			mu.Unlock()
			_ = json.NewEncoder(w).Encode(map[string]any{"phase": current,
				"proxyA": f.proxies[0].count(), "proxyB": f.proxies[1].count(),
				"dnsA": f.servers[0].count(), "dnsB": f.servers[1].count(), "direct": f.direct.Load()})
		default:
			http.NotFound(w, r)
		}
	})
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: handler}
	t.Cleanup(func() { _ = server.Close() })
	info := map[string]any{"fixture": "ouo-local", "httpPort": managedPort(listener.Addr().String()),
		"materialHost": host, "mixedPort": f.mixedPort, "dnsPort": f.dnsPort,
		"dnsA": managedPort(f.servers[0].address), "bootstrapDns": managedPort(f.servers[3].address)}
	data, _ := json.Marshal(info)
	fmt.Println("managed-update-fixture:" + string(data))
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		t.Fatal(err)
	}
}

func TestManagedMaterialsReceiptRejectsUnknownTextAndInvalidIdentity(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	input := managedTestInput(t)
	data, err := os.ReadFile(filepath.Join(inputDirectory(C.Path.HomeDir()), input+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var original map[string]any
	if err := json.Unmarshal(data, &original); err != nil {
		t.Fatal(err)
	}
	for _, fault := range []string{"url", "version", "profile", "digest"} {
		t.Run(fault, func(t *testing.T) {
			receipt := map[string]any{"version": 1, "profileId": 7,
				"originSha256": strings.Repeat("a", 64), "rawSha256": strings.Repeat("b", 64),
				"materialSha256": strings.Repeat("c", 64), "bindingsSha256": strings.Repeat("d", 64)}
			switch fault {
			case "url":
				receipt["url"] = "synthetic forbidden text"
			case "version":
				receipt["version"] = 2
			case "profile":
				receipt["profileId"] = 8
			case "digest":
				receipt["rawSha256"] = "not-a-digest"
			}
			original["managedMaterials"] = receipt
			encoded, _ := json.Marshal(original)
			id := inputHash(encoded)
			if err := atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"), encoded); err != nil {
				t.Fatal(err)
			}
			if _, _, _, _, err := readConfigInput(C.Path.HomeDir(), id); err == nil {
				t.Fatal("invalid receipt accepted")
			} else if fault == "url" && !strings.Contains(err.Error(), "unknown field") || fault != "url" && err.Error() != "invalid managed material receipt" {
				t.Fatal("fixture failed outside the receipt check", err)
			}
		})
	}
}
