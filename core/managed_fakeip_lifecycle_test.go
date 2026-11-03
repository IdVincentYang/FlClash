package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/fakeip"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	D "github.com/miekg/dns"
)

func TestManagedFakeIPLifecycleChild(t *testing.T) {
	mode := os.Getenv("FLCLASH_FAKEIP_LIFECYCLE_CHILD")
	if mode == "" {
		t.Skip("isolated lifecycle child")
	}
	home := os.Getenv("FLCLASH_FAKEIP_LIFECYCLE_HOME")
	if home == "" {
		t.Fatal("synthetic cache home required")
	}
	if err := os.MkdirAll(home, 0700); err != nil {
		t.Fatal(err)
	}
	C.SetHomeDir(home)
	var mu sync.Mutex
	var attempts []string
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		mu.Lock()
		attempts = append(attempts, network+":"+address)
		mu.Unlock()
		return fmt.Errorf("lifecycle mechanism experiment prohibits network sockets")
	}
	result := map[string]any{"mode": mode, "home": home, "shutdownCalled": false}
	pool := func(persistent bool, size int, prefix string) *fakeip.Pool {
		p, err := fakeip.New(fakeip.Options{IPNet: netip.MustParsePrefix(prefix), Size: size, Persistence: persistent})
		if err != nil {
			t.Fatal(err)
		}
		return p
	}
	observe := func(p *fakeip.Pool, old, next netip.Addr) {
		host, exists := p.LookBack(old)
		result["issuedA"], result["newB"] = old.String(), next.String()
		result["oldAliasHost"], result["oldAliasExists"] = host, exists
		result["preservesIssuedA"] = exists && host == "a.lifecycle.test"
	}
	const prefix = "198.18.0.0/24"
	switch mode {
	case "executor-memory":
		apply := func() {
			raw, err := config.UnmarshalRawConfig([]byte(`mode: rule
mixed-port: 0
allow-lan: false
external-controller: ''
geo-auto-update: false
find-process-mode: off
ntp: {enable: false}
tun: {enable: false}
profile: {store-fake-ip: false, store-selected: false}
dns:
  enable: true
  listen: ''
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/24
  fake-ip-range6: ''
  fake-ip-filter-mode: blacklist
  fake-ip-filter: []
  use-hosts: false
  use-system-hosts: false
  nameserver: [tcp://127.0.0.1:1]
  default-nameserver: [tcp://127.0.0.1:1]
  fallback: []
rules: ['MATCH,REJECT']
`))
			if err != nil {
				t.Fatal(err)
			}
			cfg, err := config.ParseRawConfig(raw)
			if err != nil {
				t.Fatal(err)
			}
			executor.ApplyConfigStaged(cfg, false)
		}
		query := func(name string) netip.Addr {
			m := new(D.Msg)
			m.SetQuestion(D.Fqdn(name), D.TypeA)
			r, err := resolver.DefaultService.ServeMsg(context.Background(), m)
			if err != nil || len(r.Answer) != 1 {
				t.Fatal("mechanism DNS", r, err)
			}
			a, ok := r.Answer[0].(*D.A)
			if !ok {
				t.Fatal("mechanism expected A answer")
			}
			ip, _ := netip.AddrFromSlice(a.A)
			return ip.Unmap()
		}
		apply()
		a := query("a.lifecycle.test")
		before, exists := resolver.FindHostByIP(a)
		if !exists || before != "a.lifecycle.test" {
			t.Fatal("executor initial identity control", before, exists)
		}
		apply()
		cloned, exists := resolver.FindHostByIP(a)
		result["afterUpdateBeforeB"], result["clonedAExists"] = cloned, exists
		b := query("b.lifecycle.test")
		host, exists := resolver.FindHostByIP(a)
		result["issuedA"], result["newB"] = a.String(), b.String()
		result["oldAliasHost"], result["oldAliasExists"] = host, exists
		result["preservesIssuedA"] = exists && host == "a.lifecycle.test"
		result["mechanismOnly"] = "manual fake-ip config; no managed descriptor or product Apply"
	case "memory-update", "memory-continuous", "same-pool":
		p := pool(false, 1000, prefix)
		a := p.Lookup("a.lifecycle.test")
		if mode == "same-pool" {
			fmt.Println("fakeip-lifecycle-ready: same-pool CloneFrom")
			p.CloneFrom(p)
			t.Fatal("same-pool CloneFrom unexpectedly returned")
		}
		if mode == "memory-update" {
			next := pool(false, 1000, prefix)
			next.CloneFrom(p)
			p = next
		}
		cloned, exists := p.LookBack(a)
		result["beforeB"], result["beforeBExists"] = cloned, exists
		b := p.Lookup("b.lifecycle.test")
		observe(p, a, b)
	case "persistent-update", "persistent-stored-update", "cold-seed", "cold-stored-seed", "cold-recover", "closed-store":
		p := pool(true, 1000, prefix)
		cache := cachefile.Cache()
		if cache.DB == nil || filepath.Dir(cache.DB.Path()) != filepath.Clean(home) {
			t.Fatal("cache is not the owned synthetic DB")
		}
		result["cachePath"] = cache.DB.Path()
		if mode == "cold-recover" {
			a := netip.MustParseAddr("198.18.0.4")
			host, exists := p.LookBack(a)
			result["beforeB"], result["beforeBExists"] = host, exists
			b := p.Lookup("b.lifecycle.test")
			observe(p, a, b)
			break
		}
		a := p.Lookup("a.lifecycle.test")
		if host, exists := p.LookBack(a); !exists || host != "a.lifecycle.test" {
			t.Fatal("persistent successful write/read control", host, exists)
		}
		result["initialWriteReadVerified"] = true
		if mode == "cold-seed" || mode == "cold-stored-seed" {
			if mode == "cold-stored-seed" {
				p.StoreState()
				result["explicitStoreState"] = true
			}
			observe(p, a, a)
			break
		}
		if mode == "closed-store" {
			if err := cache.DB.Close(); err != nil {
				t.Fatal(err)
			}
			result["dbCloseSucceeded"] = true
			b := p.Lookup("b.lifecycle.test")
			_, exists := p.LookBack(b)
			p.StoreState()
			result["returnedAlias"], result["returnedAliasBacked"] = b.String(), exists
			result["lookupHasErrorReturn"], result["storeStateHasErrorReturn"] = false, false
			break
		}
		if mode == "persistent-stored-update" {
			p.StoreState()
			result["explicitStoreState"] = true
		}
		next := pool(true, 1000, prefix)
		next.CloneFrom(p)
		before, exists := next.LookBack(a)
		result["beforeB"], result["beforeBExists"] = before, exists
		b := next.Lookup("b.lifecycle.test")
		observe(next, a, b)
	case "lru-loss":
		p := pool(false, 2, prefix)
		a := p.Lookup("a.lifecycle.test")
		p.Lookup("b.lifecycle.test")
		c := p.Lookup("c.lifecycle.test")
		observe(p, a, c)
		result["memorySize"], result["spaceExhausted"] = 2, false
	case "finite-wrap":
		p := pool(false, 1000, "198.18.0.0/29")
		a := p.Lookup("a.lifecycle.test")
		p.Lookup("b.lifecycle.test")
		p.Lookup("c.lifecycle.test")
		d := p.Lookup("d.lifecycle.test")
		observe(p, a, d)
		result["newName"], result["range"], result["allocationHasErrorReturn"] = "d.lifecycle.test", "198.18.0.0/29", false
	default:
		t.Fatal("unknown lifecycle mode")
	}
	mu.Lock()
	result["networkSocketAttempts"] = append([]string{}, attempts...)
	mu.Unlock()
	data, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	fmt.Println("fakeip-lifecycle-result:" + string(data))
}

func TestManagedFakeIPLifecycleInvestigation(t *testing.T) {
	if os.Getenv("FLCLASH_FAKEIP_LIFECYCLE") != "1" {
		t.Skip("explicit bounded lifecycle investigation")
	}
	out := os.Getenv("FLCLASH_FAKEIP_LIFECYCLE_EVIDENCE")
	if out == "" {
		t.Fatal("new evidence directory required")
	}
	if err := os.Mkdir(out, 0700); err != nil {
		t.Fatal(err)
	}
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	var results []map[string]any
	run := func(mode, home string) map[string]any {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, executable, "-test.run=^TestManagedFakeIPLifecycleChild$", "-test.v", "-test.timeout=20s")
		cmd.Env = append(os.Environ(), "FLCLASH_FAKEIP_LIFECYCLE_CHILD="+mode, "FLCLASH_FAKEIP_LIFECYCLE_HOME="+home)
		var output strings.Builder
		cmd.Stdout, cmd.Stderr = &output, &output
		if err := cmd.Start(); err != nil {
			t.Fatal(err)
		}
		waitErr := cmd.Wait()
		record := map[string]any{"mode": mode, "home": home, "pid": cmd.Process.Pid, "command": cmd.Args,
			"waitCompleted": cmd.ProcessState != nil, "exit": cmd.ProcessState.ExitCode(), "deadline": ctx.Err() != nil}
		scanner := bufio.NewScanner(strings.NewReader(output.String()))
		for scanner.Scan() {
			if line := scanner.Text(); strings.HasPrefix(line, "fakeip-lifecycle-result:") {
				var value map[string]any
				if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "fakeip-lifecycle-result:")), &value); err != nil {
					t.Fatal(err)
				}
				record["result"] = value
			}
		}
		name := fmt.Sprintf("%02d-%s.log", len(results), mode)
		if err := os.WriteFile(filepath.Join(out, name), []byte(output.String()), 0600); err != nil {
			t.Fatal(err)
		}
		record["log"] = name
		results = append(results, record)
		if mode == "same-pool" {
			if ctx.Err() == nil || !strings.Contains(output.String(), "fakeip-lifecycle-ready:") {
				t.Error("same-pool deadlock control was not established", waitErr)
			}
		} else if waitErr != nil || record["result"] == nil {
			t.Error("lifecycle child failed before a mechanism result", mode, waitErr)
		}
		return record
	}
	for _, mode := range []string{"memory-continuous", "memory-update", "executor-memory", "persistent-update", "persistent-stored-update", "same-pool", "lru-loss", "finite-wrap", "closed-store"} {
		run(mode, filepath.Join(out, "cache-"+mode))
	}
	for _, seed := range []string{"cold-seed", "cold-stored-seed"} {
		home := filepath.Join(out, "cache-"+seed)
		run(seed, home)
		run("cold-recover", home)
	}
	data, _ := json.MarshalIndent(results, "", "  ")
	if err := os.WriteFile(filepath.Join(out, "results.json"), append(data, '\n'), 0600); err != nil {
		t.Fatal(err)
	}
	for _, record := range results {
		if value, ok := record["result"].(map[string]any); ok {
			if attempts := value["networkSocketAttempts"].([]any); len(attempts) != 0 {
				t.Error("unexpected Core network socket attempt", record["mode"], attempts)
			}
			if preserves, ok := value["preservesIssuedA"].(bool); ok && !preserves && record["mode"] != "lru-loss" {
				t.Errorf("issued A identity not preserved: %s, host=%s", record["mode"], value["oldAliasHost"])
			}
		}
	}
	t.Log("bounded lifecycle results", out)
}
