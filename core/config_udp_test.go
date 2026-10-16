package main

import (
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
)

func TestConfigUDPProxyDirectAndLateResponse(t *testing.T) {
	configTestEnvironment(t)
	C.SetHomeDir(t.TempDir())
	isInit.Store(true)
	proxy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	relay, err := net.ListenPacket("udp", proxy.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()
	direct, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer direct.Close()
	var proxyCount, directCount atomic.Int32
	var controls sync.Map
	defer controls.Range(func(key, value any) bool { key.(net.Conn).Close(); return true })
	go func() {
		for {
			conn, err := proxy.Accept()
			if err != nil {
				return
			}
			controls.Store(conn, true)
			go func() {
				defer conn.Close()
				defer controls.Delete(conn)
				if _, _, _, err := socks5.ServerHandshake(conn, nil); err == nil {
					_, _ = io.Copy(io.Discard, conn)
				}
			}()
		}
	}()
	go func() {
		b := make([]byte, 2048)
		for {
			n, addr, err := direct.ReadFrom(b)
			if err != nil {
				return
			}
			directCount.Add(1)
			_, _ = direct.WriteTo(append([]byte("direct:"), b[:n]...), addr)
		}
	}()
	lateEntered, lateRelease, lateDone := make(chan struct{}), make(chan struct{}), make(chan struct{})
	defer func() {
		select {
		case <-lateRelease:
		default:
			close(lateRelease)
		}
	}()
	go func() {
		b := make([]byte, 2048)
		for {
			n, client, err := relay.ReadFrom(b)
			if err != nil {
				return
			}
			addr, payload, err := socks5.DecodeUDPPacket(b[:n])
			if err != nil {
				continue
			}
			proxyCount.Add(1)
			if string(payload) == "late" {
				close(lateEntered)
				<-lateRelease
			}
			response, _ := socks5.EncodeUDPPacket(addr, append([]byte("proxy:"), payload...))
			_, _ = relay.WriteTo(response, client)
			if string(payload) == "late" {
				close(lateDone)
			}
		}
	}()
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	mixedPort := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	input := writeTestInput(t, fmt.Sprintf("mixed-port: %d\nmode: rule\nfind-process-mode: off\nproxies:\n  - name: acceptedUDP\n    type: socks5\n    server: 127.0.0.1\n    port: %d\n    udp: true\nrules:\n  - DST-PORT,%d,DIRECT\n  - MATCH,acceptedUDP\n", mixedPort, proxy.Addr().(*net.TCPAddr).Port, direct.LocalAddr().(*net.UDPAddr).Port))
	applyTestInput(t, input)
	open := func() (net.Conn, net.Conn) {
		control, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		control.SetDeadline(time.Now().Add(2 * time.Second))
		addr, err := socks5.ClientHandshake(control, socks5.ParseAddr("0.0.0.0:0"), socks5.CmdUDPAssociate, nil)
		if err != nil {
			control.Close()
			t.Fatal(err)
		}
		if addr.UDPAddr() == nil {
			t.Fatal("missing actual UDP binding")
		}
		packet, err := net.Dial("udp", fmt.Sprintf("127.0.0.1:%d", mixedPort))
		if err != nil {
			control.Close()
			t.Fatal(err)
		}
		return control, packet
	}
	control, packet := open()
	defer control.Close()
	defer packet.Close()
	send := func(packet net.Conn, target, payload string) {
		data, err := socks5.EncodeUDPPacket(socks5.ParseAddr(target), []byte(payload))
		if err != nil {
			t.Fatal(err)
		}
		packet.SetDeadline(time.Now().Add(2 * time.Second))
		if _, err := packet.Write(data); err != nil {
			t.Fatal(err)
		}
	}
	read := func(packet net.Conn) (string, error) {
		b := make([]byte, 2048)
		n, err := packet.Read(b)
		if err != nil {
			return "", err
		}
		_, payload, err := socks5.DecodeUDPPacket(b[:n])
		return string(payload), err
	}
	send(packet, "127.0.0.1:1", "normal")
	if body, err := read(packet); err != nil || body != "proxy:normal" {
		t.Fatal("UDP proxy failed", body, err)
	}
	// A distinct client source creates the Direct NAT binding independently.
	directControl, directPacket := open()
	defer directControl.Close()
	defer directPacket.Close()
	send(directPacket, direct.LocalAddr().String(), "normal")
	if body, err := read(directPacket); err != nil || body != "direct:normal" {
		t.Fatal("legal UDP Direct failed", body, err)
	}
	send(packet, "127.0.0.1:1", "late")
	select {
	case <-lateEntered:
	case <-time.After(2 * time.Second):
		t.Fatal("proxy did not receive old UDP action")
	}
	applyTestInput(t, input)
	close(lateRelease)
	select {
	case <-lateDone:
	case <-time.After(time.Second):
		t.Fatal("old proxy response did not finish")
	}
	packet.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	if body, err := read(packet); err == nil {
		t.Fatal("old response crossed activation", body)
	}
	newControl, newPacket := open()
	defer newControl.Close()
	defer newPacket.Close()
	send(newPacket, "127.0.0.1:1", "recovered")
	if body, err := read(newPacket); err != nil || body != "proxy:recovered" {
		t.Fatal("UDP activation did not recover", body, err)
	}
	if proxyCount.Load() != 3 || directCount.Load() != 1 {
		t.Fatal("unexpected receiver counts", proxyCount.Load(), directCount.Load())
	}
	t.Logf("actual UDP proxy=%d legal Direct=%d late response delivered=0", proxyCount.Load(), directCount.Load())
}
