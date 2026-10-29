package main

import (
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func outboundFixture(t *testing.T, handler http.HandlerFunc, trusted bool, names ...string) *diagnosticProxy {
	t.Helper()
	if len(names) == 0 {
		names = []string{"www.cloudflare.com"}
	}
	proxy := diagnosticFixture(t, handler, trusted, names...)
	proxy.allowed["www.cloudflare.com"] = true
	return proxy
}
func outboundCheck(timeout int64) *OutboundIpResult {
	return handleOutboundIp(&OutboundIpParams{ProxyName: "diagnostic-node", Urls: []string{outboundIPURL}, Timeout: timeout})
}
func TestOutboundIPSingleRecipient(t *testing.T) {
	var calls atomic.Int32
	outboundFixture(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.URL.Path != "/cdn-cgi/trace" || r.URL.RawQuery != "" || r.UserAgent() != browserUserAgent || r.Header.Get("Cookie") != "" || r.Header.Get("Referer") != "" {
			t.Error("unexpected outbound request")
		}
		fmt.Fprint(w, "ip=1.1.1.1\nloc=AU\n")
	}, true)
	result := outboundCheck(1000)
	if result.Error != "" || result.Url != outboundIPURL || calls.Load() != 1 {
		t.Fatalf("result=%+v calls=%d", result, calls.Load())
	}
	for _, urls := range [][]string{nil, {"http://www.cloudflare.com/cdn-cgi/trace"}, {outboundIPURL, outboundIPURL}, {outboundIPURL + "?extra=1"}, {"https://example.invalid/"}} {
		result = handleOutboundIp(&OutboundIpParams{ProxyName: "diagnostic-node", Urls: urls})
		if result.Error != "recipient-blocked" || calls.Load() != 1 {
			t.Fatal("unexpected recipient accepted")
		}
	}
}
func TestOutboundIPRejectsAllRedirects(t *testing.T) {
	for _, status := range []int{301, 302, 303, 307, 308} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			var calls atomic.Int32
			outboundFixture(t, func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				w.Header().Set("Location", "http://another.invalid/trace")
				w.WriteHeader(status)
			}, true)
			if result := outboundCheck(1000); result.Error != "http-failed" || calls.Load() != 1 {
				t.Fatalf("result=%+v calls=%d", result, calls.Load())
			}
		})
	}
}
func TestOutboundIPRequiresCompleteBoundedBody(t *testing.T) {
	for name, body := range map[string]string{"large": "ip=1.1.1.1\nloc=US\n" + strings.Repeat("x", 4096), "invalid": "ip=not-an-ip\nloc=US\n", "private": "ip=::ffff:192.168.1.1\nloc=US\n", "missing": "ip=1.1.1.1\n", "duplicate": "ip=1.1.1.1\nip=8.8.8.8\nloc=US\n"} {
		t.Run(name, func(t *testing.T) {
			outboundFixture(t, func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, body) }, true)
			if result := outboundCheck(1000); result.Error == "" {
				t.Fatal("accepted invalid body")
			}
		})
	}
	t.Run("truncated", func(t *testing.T) {
		outboundFixture(t, func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Length", "200")
			fmt.Fprint(w, "ip=1.1.1.1\nloc=US\n")
		}, true)
		if result := outboundCheck(1000); result.Error == "" {
			t.Fatal("accepted truncated response")
		}
	})
}
func TestOutboundIPLimitCancelsUnfinishedBody(t *testing.T) {
	cancelled := make(chan struct{})
	outboundFixture(t, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ip=1.1.1.1\nloc=US\n"+strings.Repeat("x", 5000))
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		close(cancelled)
	}, true)
	if result := outboundCheck(1000); result.Error != "body-limit" {
		t.Fatalf("result=%+v", result)
	}
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("over-limit body kept its connection")
	}
}

func TestOutboundIPCancelsActualBodyRead(t *testing.T) {
	cancelled := make(chan struct{})
	outboundFixture(t, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ip=1.1.1.1\nloc=US\n")
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		close(cancelled)
	}, true)
	if result := outboundCheck(50); result.Error == "" {
		t.Fatal("partial body accepted")
	}
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("body connection not cancelled")
	}
}
func TestOutboundIPStrictTLSAndFailedProxy(t *testing.T) {
	t.Run("untrusted", func(t *testing.T) {
		outboundFixture(t, func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ip=1.1.1.1\nloc=US\n") }, false)
		if result := outboundCheck(1000); result.Error != "tls-failed" {
			t.Fatalf("result=%+v", result)
		}
	})
	t.Run("wrong-name", func(t *testing.T) {
		outboundFixture(t, func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ip=1.1.1.1\nloc=US\n") }, true, "wrong.invalid")
		if result := outboundCheck(1000); result.Error != "tls-failed" {
			t.Fatalf("result=%+v", result)
		}
	})
	t.Run("failed-proxy", func(t *testing.T) {
		var calls atomic.Int32
		p := outboundFixture(t, func(w http.ResponseWriter, _ *http.Request) { calls.Add(1) }, true)
		p.fail = true
		if result := outboundCheck(1000); result.Error == "" || calls.Load() != 0 {
			t.Fatalf("result=%+v calls=%d", result, calls.Load())
		}
	})
}
func TestPublicIPNormalizationAndTrace(t *testing.T) {
	for _, ip := range []string{"1.1.1.1", "8.8.8.8", "2606:4700:4700::1111", "::ffff:1.1.1.1"} {
		if !publicIPAddress(ip) {
			t.Errorf("rejected %s", ip)
		}
	}
	for _, ip := range []string{"0.1.2.3", "10.0.0.1", "100.64.0.1", "127.0.0.1", "169.254.1.1", "172.31.1.1", "192.168.1.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "240.1.1.1", "::", "::1", "fe80::1", "ff02::1", "fc00::1", "2001:db8::1", "3fff::1", "3fff:0fff:ffff::1", "::ffff:10.0.0.1", "2606:4700::1%en0", "https://1.1.1.1"} {
		if publicIPAddress(ip) {
			t.Errorf("accepted %s", ip)
		}
	}
	if !validOutboundTrace("ip=2606:4700:4700::1111\nloc=US\n") {
		t.Fatal("valid IPv6 trace rejected")
	}
}
