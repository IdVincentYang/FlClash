package main

import (
	"context"
	"net/netip"
	"strings"
	"time"

	"github.com/metacubex/http"
)

const (
	outboundIPURL     = "https://www.cloudflare.com/cdn-cgi/trace"
	outboundIpMaxBody = 4096
	browserUserAgent  = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

type OutboundIpParams struct {
	ScopeID   string   `json:"scopeId"`
	ProxyName string   `json:"proxy-name"`
	Urls      []string `json:"urls"`
	Timeout   int64    `json:"timeout"`
}

type OutboundIpResult struct {
	Url          string   `json:"url"`
	Body         string   `json:"body"`
	Delay        int64    `json:"delay"`
	Chains       []string `json:"chains"`
	Error        string   `json:"error,omitempty"`
	CoreEpoch    uint64   `json:"core-epoch"`
	PicksVersion uint64   `json:"picks-version"`
}

func handleOutboundIp(params *OutboundIpParams) *OutboundIpResult {
	epoch, picks := routeStamp()
	failure := func(code string) *OutboundIpResult {
		return &OutboundIpResult{Error: code, CoreEpoch: epoch, PicksVersion: picks}
	}
	if len(params.Urls) != 1 || params.Urls[0] != outboundIPURL {
		return failure("recipient-blocked")
	}
	parent, _, err := requestOperationContext(params.ScopeID, params.ProxyName)
	if err != nil {
		return failure("cancelled")
	}
	timeout := time.Duration(params.Timeout) * time.Millisecond
	if timeout <= 0 || timeout > 6*time.Second {
		timeout = 6 * time.Second
	}
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	result := runProbe(ctx, probeRequest{method: http.MethodGet, url: outboundIPURL, proxyName: params.ProxyName, headers: map[string]string{"User-Agent": browserUserAgent}, timeout: timeout, maxBody: outboundIpMaxBody, noRedirect: true, completeBody: true})
	if result == nil {
		return failure("timeout")
	}
	if ctx.Err() != nil {
		return failure(serviceErrorReason(ctx.Err()))
	}
	if result.Error != "" {
		return failure(result.Error)
	}
	if result.StatusCode == 429 {
		return failure("rate-limited")
	}
	if result.StatusCode != http.StatusOK {
		return failure("http-failed")
	}
	if result.bodyState != "complete" {
		return failure(result.bodyState)
	}
	if !validOutboundTrace(result.Body) {
		return failure("invalid-response")
	}
	if ctx.Err() != nil {
		return failure("cancelled")
	}
	return &OutboundIpResult{Url: outboundIPURL, Body: result.Body, Delay: result.Delay, Chains: result.Chains, CoreEpoch: result.CoreEpoch, PicksVersion: result.PicksVersion}
}

var nonPublicIPPrefixes = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"), netip.MustParsePrefix("100.64.0.0/10"),
	netip.MustParsePrefix("192.0.0.0/24"), netip.MustParsePrefix("192.0.2.0/24"),
	netip.MustParsePrefix("192.88.99.0/24"), netip.MustParsePrefix("198.18.0.0/15"),
	netip.MustParsePrefix("198.51.100.0/24"), netip.MustParsePrefix("203.0.113.0/24"),
	netip.MustParsePrefix("240.0.0.0/4"), netip.MustParsePrefix("2001::/23"),
	netip.MustParsePrefix("2001:db8::/32"),
	netip.MustParsePrefix("3fff::/20"),
}

func publicIPAddress(raw string) bool {
	addr, err := netip.ParseAddr(raw)
	if err != nil || addr.Zone() != "" {
		return false
	}
	addr = addr.Unmap()
	if !addr.IsGlobalUnicast() || addr.IsPrivate() || addr.IsLoopback() || addr.IsLinkLocalUnicast() {
		return false
	}
	if addr.Is6() && !netip.MustParsePrefix("2000::/3").Contains(addr) {
		return false
	}
	for _, prefix := range nonPublicIPPrefixes {
		if prefix.Contains(addr) {
			return false
		}
	}
	return true
}

func validOutboundTrace(body string) bool {
	fields := map[string]string{}
	for _, line := range strings.Split(body, "\n") {
		key, value, ok := strings.Cut(strings.TrimSuffix(line, "\r"), "=")
		if !ok {
			continue
		}
		if _, exists := fields[key]; exists {
			return false
		}
		fields[key] = value
	}
	country := fields["loc"]
	return publicIPAddress(fields["ip"]) && len(country) == 2 && country[0] >= 'A' && country[0] <= 'Z' && country[1] >= 'A' && country[1] <= 'Z'
}
