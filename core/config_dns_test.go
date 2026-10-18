package main

import (
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
	D "github.com/miekg/dns"
)

func configDNSAddress(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := l.Addr().String()
	_ = l.Close()
	return address
}

func dnsInput(t *testing.T, address, upstream string) string {
	t.Helper()
	return writeKeptTestInput(t, fmt.Sprintf("mode: rule\nipv6: true\nrules: [\"MATCH,DIRECT\"]\ndns:\n  enable: true\n  listen: %q\n  use-hosts: false\n  use-system-hosts: false\n  nameserver: [\"udp://%s\"]\n  default-nameserver: [\"udp://%s\"]\n", address, upstream, upstream))
}

func dnsExchange(address, network, name string) (*D.Msg, error) {
	client := D.Client{Net: network, Timeout: 200 * time.Millisecond}
	request := new(D.Msg)
	request.SetQuestion(name+".", D.TypeA)
	result, _, err := client.Exchange(request, address)
	return result, err
}

func TestOwnedDNSActivationStopAndPortReuse(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	first := managedDNSServer(t, "udp", nil)
	second := managedDNSServer(t, "udp", nil)
	address := configDNSAddress(t)
	input := dnsInput(t, address, first.address)
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared := prepareConfig(receipt)
	if prepared.Status != "prepared" {
		t.Fatal(prepared)
	}
	installed := installConfig(prepared.Receipt)
	if installed.Status != "installed" {
		t.Fatal(installed)
	}
	old := ordinaryDNS.Load()
	for _, network := range []string{"tcp", "udp"} {
		response, err := dnsExchange(address, network, "before-activation-"+network+".test")
		if err != nil || response.Rcode != D.RcodeServerFailure {
			t.Fatal(network, response, err)
		}
	}
	if first.count() != 0 {
		t.Fatal("unactivated DNS sent a query")
	}
	if activated := activateConfig(installed.Receipt); activated.Status != "activated" {
		t.Fatal(activated)
	}
	for _, network := range []string{"tcp", "udp"} {
		response, err := dnsExchange(address, network, "active-"+network+".test")
		if err != nil || response.Rcode != D.RcodeSuccess {
			t.Fatal(network, response, err)
		}
	}
	if first.count() != 2 {
		t.Fatal("ordinary ingress did not reach its frozen service", first.count())
	}
	handleStopListener()
	for _, network := range []string{"tcp", "udp"} {
		_, _ = dnsExchange(address, network, "after-stop-"+network+".test")
	}
	if first.count() != 2 {
		t.Fatal("stopped DNS accepted a new query", first.count())
	}
	applyTestInput(t, dnsInput(t, address, second.address))
	old.close()
	for _, network := range []string{"tcp", "udp"} {
		response, err := dnsExchange(address, network, "new-owner-"+network+".test")
		if err != nil || response.Rcode != D.RcodeSuccess {
			t.Fatal(network, response, err)
		}
	}
	if first.count() != 2 || second.count() != 2 {
		t.Fatal("old cleanup or DNS service crossed owner", first.count(), second.count())
	}
}

func TestOwnedDNSDisabledListenPreservesLegacyZeroPort(t *testing.T) {
	for _, address := range []string{"", "127.0.0.1:0", ":0", "[::1]:0", "127.0.0.1:", "invalid", "127.0.0.1"} {
		t.Run(address, func(t *testing.T) {
			configTestEnvironment(t)
			C.SetHomeDir(t.TempDir())
			isInit.Store(true)
			upstream := managedDNSServer(t, "udp", nil)
			accepted := applyTestInput(t, dnsInput(t, address, upstream.address))
			if !accepted.Fact.BusinessActive || ordinaryDNS.Load() != nil {
				t.Fatal("disabled DNS listen opened a socket or blocked the config", accepted)
			}
			if currentConfig.DNS.Listen != address || upstream.count() != 0 {
				t.Fatal("disabled listen changed the intended config or sent a query")
			}
		})
	}
}

func TestOwnedDNSInactiveAndPartialBindFailure(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	upstream := managedDNSServer(t, "udp", nil)
	address := configDNSAddress(t)
	input := dnsInput(t, address, upstream.address)
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input})
	prepared := prepareConfig(receipt)
	if result := installConfig(prepared.Receipt); result.Status != "installed" {
		t.Fatal(result)
	}
	if result := activateConfig(prepared.Receipt); result.Status != "installedInactive" {
		t.Fatal(result)
	}
	if ordinaryDNS.Load() != nil {
		t.Fatal("inactive install owns a DNS listener")
	}
	for _, network := range []string{"tcp", "udp"} {
		_, _ = dnsExchange(address, network, "inactive-"+network+".test")
	}
	if upstream.count() != 0 {
		t.Fatal("inactive DNS sent a query")
	}
	occupied, err := net.ListenPacket("udp", address)
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	receipt = registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared = prepareConfig(receipt)
	if result := installConfig(prepared.Receipt); result.Status != "blocked" {
		t.Fatal(result)
	}
	tcp, err := net.Listen("tcp", address)
	if err != nil {
		t.Fatal("failed UDP bind leaked the prepared TCP listener", err)
	}
	_ = tcp.Close()
	if ordinaryDNS.Load() != nil || configStateSnapshot().BusinessActive {
		t.Fatal("failed DNS binding remained active")
	}
}

func TestOwnedDNSFailedReplacementClosesPreviousIngress(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	upstream := managedDNSServer(t, "udp", nil)
	address := configDNSAddress(t)
	applyTestInput(t, dnsInput(t, address, upstream.address))
	input := writeKeptTestInput(t, "mode: rule\nrules: [\"DOMAIN-SUFFIX,missing\"]\n")
	receipt := registerConfigOperation(methodCallSeq.Add(1), ConfigInputRequest{InputID: input, Active: true})
	prepared := prepareConfig(receipt)
	if result := installConfig(prepared.Receipt); result.Status != "blocked" {
		t.Fatal(result)
	}
	for _, network := range []string{"tcp", "udp"} {
		_, _ = dnsExchange(address, network, "failed-replacement-"+network+".test")
	}
	if upstream.count() != 0 || ordinaryDNS.Load() != nil {
		t.Fatal("failed replacement retained a new-query ingress")
	}
}

func TestOwnedDNSSeparatesAdmittedQueryFromNewQueriesAfterStop(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	packet, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	entered, release, ready := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var enteredOnce, releaseOnce sync.Once
	var received atomic.Int32
	upstream := &D.Server{PacketConn: packet, NotifyStartedFunc: func() { close(ready) }, Handler: D.HandlerFunc(func(w D.ResponseWriter, request *D.Msg) {
		received.Add(1)
		enteredOnce.Do(func() { close(entered) })
		<-release
		response := new(D.Msg)
		response.SetReply(request)
		_ = w.WriteMsg(response)
	})}
	go func() { _ = upstream.ActivateAndServe() }()
	<-ready
	t.Cleanup(func() { _ = upstream.Shutdown() })
	defer releaseOnce.Do(func() { close(release) })
	address := configDNSAddress(t)
	applyTestInput(t, dnsInput(t, address, packet.LocalAddr().String()))
	old := ordinaryDNS.Load()
	done := make(chan struct{})
	go func() { _, _ = dnsExchange(address, "tcp", "admitted-before-stop.test"); close(done) }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("pre-stop query was not admitted")
	}
	handleStopListener()
	_, _ = dnsExchange(address, "udp", "unique-after-stop.test")
	if received.Load() != 1 {
		t.Fatal("new post-stop query reached the old service", received.Load())
	}
	next := managedDNSServer(t, "udp", nil)
	applyTestInput(t, dnsInput(t, address, next.address))
	old.close()
	if response, err := dnsExchange(address, "tcp", "unique-new-owner.test"); err != nil || response.Rcode != D.RcodeSuccess {
		t.Fatal(response, err)
	}
	if received.Load() != 1 || next.count() != 1 {
		t.Fatal("old and new DNS admission mixed", received.Load(), next.count())
	}
	releaseOnce.Do(func() { close(release) })
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("old client did not finish")
	}
}
