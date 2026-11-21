package main

import (
	"net"
	"net/netip"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/common/buf"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestHostTrafficStore(t *testing.T) {
	store := newHostTrafficStore(2)
	ip := netip.MustParseAddr("192.0.2.4")
	add := func(host string) func(int64, int64) {
		return store.account(&C.Metadata{Host: host, DstIP: ip})
	}
	for i := 0; i < 4097; i++ {
		add(" EXAMPLE.test. ")(1, 2)
	}
	add("example.test")(3, 4)
	add("")(0, 5)
	add("different.test")(7, 0)
	if store.account(&C.Metadata{Type: C.INNER, Host: "internal.test"}) != nil {
		t.Fatal("internal traffic accepted")
	}
	probe := &C.Metadata{Host: "probe.test"}
	pendingProbeRoutes.Store(probe, struct{}{})
	t.Cleanup(func() { pendingProbeRoutes.Delete(probe) })
	if store.account(probe) != nil {
		t.Fatal("route probe accepted")
	}
	want := map[string]hostTrafficRow{
		"host:example.test": {Key: "host:example.test", Upload: 4100, Download: 8198},
		"ip:192.0.2.4":      {Key: "ip:192.0.2.4", Download: 5},
		"other:":            {Key: "other:", Upload: 7},
	}
	for i := 0; i < 2; i++ {
		snapshot := store.snapshot("runtime-a")
		got := make(map[string]hostTrafficRow)
		for _, row := range snapshot.Rows {
			got[row.Key] = row
		}
		if snapshot.RuntimeEpoch != "runtime-a" || !reflect.DeepEqual(got, want) {
			t.Fatalf("unexpected snapshot: %+v", snapshot)
		}
	}
	next := newHostTrafficStore(2).snapshot("runtime-b")
	if next.RuntimeEpoch != "runtime-b" || len(next.Rows) != 0 {
		t.Fatalf("new Core inherited old totals: %+v", next)
	}
	if hostTrafficKey(&C.Metadata{Host: "second.test", DstIP: ip}) == hostTrafficKey(&C.Metadata{Host: "first.test", DstIP: ip}) {
		t.Fatal("different hostnames sharing an IP were merged")
	}
}

type hostTrafficTestTCP struct{ C.Conn }

func (hostTrafficTestTCP) Chains() C.Chain                 { return C.Chain{"DIRECT"} }
func (hostTrafficTestTCP) ProviderChains() C.Chain         { return nil }
func (hostTrafficTestTCP) RemoteDestination() string       { return "" }
func (hostTrafficTestTCP) Read(p []byte) (int, error)      { return len(p), nil }
func (hostTrafficTestTCP) Write(p []byte) (int, error)     { return len(p), nil }
func (hostTrafficTestTCP) ReadBuffer(b *buf.Buffer) error  { _, err := b.WriteString("xx"); return err }
func (hostTrafficTestTCP) WriteBuffer(b *buf.Buffer) error { b.Release(); return nil }
func (hostTrafficTestTCP) Close() error                    { return nil }

type hostTrafficTestUDP struct{ C.PacketConn }

func (hostTrafficTestUDP) Chains() C.Chain                          { return C.Chain{"proxy"} }
func (hostTrafficTestUDP) ProviderChains() C.Chain                  { return nil }
func (hostTrafficTestUDP) RemoteDestination() string                { return "" }
func (hostTrafficTestUDP) ReadFrom(p []byte) (int, net.Addr, error) { return len(p), nil, nil }
func (hostTrafficTestUDP) WaitReadFrom() ([]byte, func(), net.Addr, error) {
	return []byte("abc"), nil, nil, nil
}
func (hostTrafficTestUDP) WriteTo(p []byte, _ net.Addr) (int, error) { return len(p), nil }
func (hostTrafficTestUDP) Close() error                              { return nil }

func TestHostTrafficCountsTrackerBytesWithoutSnapshots(t *testing.T) {
	store := newHostTrafficStore(4)
	account, notify := statistic.DefaultTrafficAccount, statistic.DefaultRequestNotify
	statistic.DefaultTrafficAccount, statistic.DefaultRequestNotify = store.account, nil
	t.Cleanup(func() {
		statistic.DefaultTrafficAccount, statistic.DefaultRequestNotify = account, notify
	})
	manager := &statistic.Manager{}
	tcp := statistic.NewTCPTracker(hostTrafficTestTCP{}, manager, &C.Metadata{Host: "same.test"}, nil, 1, 2, true)
	_, _ = tcp.Write([]byte("abc"))
	_, _ = tcp.Read(make([]byte, 4))
	read := buf.NewSize(4)
	_ = tcp.ReadBuffer(read)
	read.Release()
	_ = tcp.WriteBuffer(buf.As([]byte("12345")))
	_, downloads := tcp.UnwrapReader()
	downloads[0](6)
	_, uploads := tcp.UnwrapWriter()
	uploads[0](7)
	_ = tcp.Close()

	udp := statistic.NewUDPTracker(hostTrafficTestUDP{}, manager, &C.Metadata{Host: "SAME.TEST."}, nil, 0, 0, true)
	_, _ = udp.WriteTo([]byte("12"), nil)
	_, _, _ = udp.ReadFrom(make([]byte, 4))
	_, _, _, _ = udp.WaitReadFrom()
	_ = udp.Close()
	internal := statistic.NewUDPTracker(hostTrafficTestUDP{}, manager, &C.Metadata{Host: "skip.test"}, nil, 20, 20, false)
	_, _ = internal.WriteTo([]byte("12"), nil)
	_ = internal.Close()
	manager.ResetStatistic()
	if manager.Get(tcp.ID()) != nil || manager.Get(udp.ID()) != nil {
		t.Fatal("fixture did not remove closed connections")
	}
	want := []hostTrafficRow{{Key: "host:same.test", Upload: 18, Download: 21}}
	if got := store.snapshot("runtime-a").Rows; !reflect.DeepEqual(got, want) {
		t.Fatalf("byte paths counted incorrectly: got %+v, want %+v", got, want)
	}
}
