package main

import (
	"bytes"
	"context"
	"crypto/x509"
	"errors"
	"io"
	"net"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/metacubex/http"
)

type ServiceCheckStep struct {
	Endpoint     string   `json:"endpoint"`
	HTTPStatus   int      `json:"http-status,omitempty"`
	Delay        int64    `json:"delay"`
	Chains       []string `json:"chains"`
	Outcome      string   `json:"outcome"`
	Observation  string   `json:"observation,omitempty"`
	Region       string   `json:"region,omitempty"`
	CoreEpoch    uint64   `json:"core-epoch"`
	PicksVersion uint64   `json:"picks-version"`
}

type serviceRun struct {
	checker serviceChecker
	steps   []ServiceCheckStep
	reason  string
}

func (r *serviceRun) policy(req probeRequest) (*serviceProbePolicy, bool) {
	allowed := req.url == r.checker.url && r.checker.purpose != "advanced"
	if r.checker.purpose == "advanced" {
		allowed = slices.Contains(r.checker.endpoints, req.url)
	}
	parsed, err := url.Parse(req.url)
	if !allowed || err != nil || !serviceHTTPS(parsed) {
		r.reason = "recipient-blocked"
		return nil, false
	}
	method := req.method
	if method == "" {
		method = http.MethodGet
	}
	post := r.checker.name == "disney-plus" && r.checker.purpose == "advanced"
	if post && method != http.MethodPost || !post && method != http.MethodGet {
		r.reason = "recipient-blocked"
		return nil, false
	}
	return &serviceProbePolicy{run: r, origin: parsed, label: parsed.Hostname() + parsed.EscapedPath(), noRedirect: post || req.noRedirect || r.checker.purpose != "advanced"}, true
}

func serviceHTTPS(u *url.URL) bool {
	return u != nil && u.Scheme == "https" && u.Hostname() != "" && u.User == nil && (u.Port() == "" || u.Port() == "443") && u.Opaque == ""
}

type serviceProbePolicy struct {
	run        *serviceRun
	origin     *url.URL
	label      string
	noRedirect bool
}

func (p *serviceProbePolicy) redirect(next *http.Request, via []*http.Request) error {
	if p.noRedirect {
		return http.ErrUseLastResponse
	}
	if len(via) > 3 || !serviceHTTPS(next.URL) || !strings.EqualFold(next.URL.Hostname(), p.origin.Hostname()) {
		p.run.reason = "redirect-blocked"
		return errors.New("redirect-blocked")
	}
	return nil
}

type serviceProbeTransport struct {
	base   http.RoundTripper
	policy *serviceProbePolicy
	dialer *probeDialer
}

func (t *serviceProbeTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	p := t.policy
	limit := 8
	if p.run.checker.purpose != "advanced" {
		limit = 1
	}
	if len(p.run.steps) >= limit {
		p.run.reason = "request-limit"
		return nil, errors.New("request-limit")
	}
	if !serviceHTTPS(req.URL) || !strings.EqualFold(req.URL.Hostname(), p.origin.Hostname()) || req.Method != http.MethodGet && req.Method != http.MethodPost {
		p.run.reason = "recipient-blocked"
		return nil, errors.New("recipient-blocked")
	}
	if err := req.Context().Err(); err != nil {
		return nil, err
	}
	req.Header.Del("Cookie")
	req.Header.Del("Referer")
	t.dialer.mu.Lock()
	t.dialer.last = nil
	t.dialer.mu.Unlock()
	epoch, picks := routeStamp()
	endpoint := p.label
	if req.URL.String() != p.origin.String() {
		endpoint = req.URL.Hostname()
	}
	step := ServiceCheckStep{Endpoint: endpoint, Outcome: "headers", Chains: []string{}, CoreEpoch: epoch, PicksVersion: picks}
	start := time.Now()
	response, err := t.base.RoundTrip(req)
	step.Delay = time.Since(start).Milliseconds()
	if route := t.dialer.route(); route != nil {
		step.Chains = append([]string(nil), route.chains...)
	}
	if response != nil {
		step.HTTPStatus = response.StatusCode
	}
	if err != nil {
		step.Outcome = serviceErrorReason(err)
	}
	p.run.steps = append(p.run.steps, step)
	return response, err
}

func serviceErrorReason(err error) string {
	if errors.Is(err, context.Canceled) {
		return "cancelled"
	}
	if probeErrorKind(err) == probeErrorTimeout {
		return "timeout"
	}
	var dns *net.DNSError
	var authority x509.UnknownAuthorityError
	var hostname x509.HostnameError
	var invalid x509.CertificateInvalidError
	if errors.As(err, &dns) {
		return "dns-failed"
	}
	if errors.As(err, &authority) || errors.As(err, &hostname) || errors.As(err, &invalid) {
		return "tls-failed"
	}
	return "connect-failed"
}

func (r *serviceRun) finishRead(result *ProbeResult, first int) {
	if result == nil {
		r.reason = "incomplete"
		return
	}
	if len(r.steps) > first && result.bodyState != "" {
		r.steps[len(r.steps)-1].Outcome = result.bodyState
	}
	if result.Error != "" && r.reason == "" {
		r.reason = "incomplete"
		if len(r.steps) > first {
			outcome := r.steps[len(r.steps)-1].Outcome
			switch outcome {
			case "timeout", "cancelled", "dns-failed", "tls-failed", "connect-failed":
				r.reason = outcome
			}
		}
	}
	switch result.bodyState {
	case "read-error", "body-limit":
		r.reason = result.bodyState
	}
}

func (r *serviceRun) changed(epoch, picks uint64) bool {
	for _, step := range r.steps {
		if step.CoreEpoch != epoch || step.PicksVersion != picks {
			return true
		}
	}
	return false
}

func readServiceBody(body io.Reader, maxBody int64, until func(string) bool) (string, string) {
	var buffer bytes.Buffer
	limited := io.LimitReader(body, maxBody+1)
	chunk := make([]byte, probeScanChunk)
	for {
		n, err := limited.Read(chunk)
		if n > 0 {
			buffer.Write(chunk[:n])
		}
		if err != nil && err != io.EOF {
			return "", "read-error"
		}
		payload := buffer.Bytes()
		if int64(len(payload)) > maxBody {
			return "", "body-limit"
		}
		start := max(0, len(payload)-n-probeScanOverlap)
		if until != nil && until(string(payload[start:])) {
			return string(payload), "marker"
		}
		if err == io.EOF {
			return string(payload), "complete"
		}
		if n == 0 {
			return "", "read-error"
		}
	}
}
