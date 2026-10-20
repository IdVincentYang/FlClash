package main

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/http"
)

const (
	// A sweep runs a few checks at a time so it cannot take every probe slot.
	// It therefore runs in waves, and a rule like Disney+ spends several
	// requests in sequence, so the run gets a multiple of the request budget.
	serviceCheckConcurrency  = 4
	serviceSweepBudgetFactor = 6

	// Region markers sit deep inside these pages; endpoints that answer with a
	// few lines get the small cap.
	serviceHtmlMaxBody  = 512 * 1024
	serviceSmallMaxBody = 16 * 1024

	// Gemini's region sits past 800 KiB, Prime Video's at times past 4 MiB.
	serviceScanMaxBody = 8 * 1024 * 1024
)

// Statuses a check reports. Dart maps each to a localized label, so these
// strings are part of the contract and cannot be reworded on one side alone.
const (
	serviceAvailable         = "available"
	serviceUnavailable       = "unavailable"
	serviceRestricted        = "restricted"
	serviceDisallowedIsp     = "disallowed-isp"
	serviceBlocked           = "blocked"
	serviceUnsupportedRegion = "unsupported-region"
	serviceOriginalsOnly     = "originals-only"
	serviceComingSoon        = "coming-soon"
	serviceTimeout           = "timeout"
	serviceFailed            = "failed"
)

// An empty Names selects no services.
type ServiceCheckParams struct {
	ScopeID   string   `json:"scopeId"`
	Purpose   string   `json:"purpose"`
	ProxyName string   `json:"proxy-name"`
	Names     []string `json:"names"`
	Timeout   int64    `json:"timeout"`
}

// runServiceCheck stamps Name; a blank Status means a rule has yet to judge it.
type ServiceCheckItem struct {
	Name         string             `json:"name"`
	Purpose      string             `json:"purpose"`
	Reason       string             `json:"reason,omitempty"`
	HTTPStatus   int                `json:"http-status,omitempty"`
	Elapsed      int64              `json:"elapsed,omitempty"`
	Steps        []ServiceCheckStep `json:"steps,omitempty"`
	Status       string             `json:"status"`
	Region       string             `json:"region,omitempty"`
	Delay        int64              `json:"delay,omitempty"`
	Chains       []string           `json:"chains,omitempty"`
	CheckedAt    int64              `json:"checked-at"`
	CoreEpoch    uint64             `json:"core-epoch"`
	PicksVersion uint64             `json:"picks-version"`
}

var (
	serviceCheckSlots = make(chan struct{}, serviceCheckConcurrency)

	serviceClaimsMu sync.Mutex
	serviceClaims   = map[string]*context.CancelFunc{}
)

type serviceEnv struct {
	ctx       context.Context
	proxyName string
	timeout   time.Duration
	run       *serviceRun
}

func (e serviceEnv) get(url string, maxBody int64) *ProbeResult {
	return e.send(probeRequest{method: http.MethodGet, url: url, maxBody: maxBody})
}

func (e serviceEnv) scan(url string, until func(tail string) bool) *ProbeResult {
	return e.send(probeRequest{method: http.MethodGet, url: url, maxBody: serviceScanMaxBody, until: until})
}

func (e serviceEnv) send(req probeRequest) *ProbeResult {
	if e.run != nil {
		policy, ok := e.run.policy(req)
		if !ok {
			return &ProbeResult{Error: probeErrorFailed, bodyState: "recipient-blocked"}
		}
		req.policy = policy
		if policy.noRedirect {
			req.noRedirect = true
		}
	}
	req.proxyName = e.proxyName
	req.timeout = e.timeout
	headers := map[string]string{"User-Agent": browserUserAgent}
	for name, value := range req.headers {
		headers[name] = value
	}
	req.headers = headers
	first := 0
	if e.run != nil {
		first = len(e.run.steps)
	}
	result := runProbe(e.ctx, req)
	if e.run != nil {
		e.run.finishRead(result, first)
	}
	return result
}

type serviceChecker struct {
	name      string
	url       string
	endpoints []string
	purpose   string
	check     func(serviceEnv) ServiceCheckItem
}

var serviceCheckers = []serviceChecker{
	{name: "google", url: "https://www.google.com/generate_204"},
	{name: "github", url: "https://github.com/"},
	{name: "youtube", url: "https://www.youtube.com/generate_204", check: checkYouTubePremium, endpoints: []string{youtubePremiumURL}},
	{name: "chatgpt", url: "https://chat.openai.com/", check: checkChatGpt, endpoints: []string{chatGPTIOSURL, chatGPTTraceURL, chatGPTWebURL}},
	{name: "claude", url: "https://claude.ai/", check: checkClaude, endpoints: []string{claudeTraceURL}},
	{name: "gemini", url: "https://gemini.google.com/", check: checkGemini, endpoints: []string{geminiURL}},
	{name: "netflix", url: "https://www.netflix.com/", check: checkNetflix, endpoints: []string{netflixCDNURL, netflixTitleOneURL, netflixTitleTwoURL, netflixRegionURL}},
	{name: "disney-plus", url: "https://www.disneyplus.com/", check: checkDisneyPlus, endpoints: []string{disneyDeviceURL, disneyTokenURL, disneySessionURL}},
	{name: "prime-video", url: "https://www.primevideo.com/", check: checkPrimeVideo, endpoints: []string{primeVideoURL}},
	{name: "spotify", url: "https://www.spotify.com/", check: checkSpotify, endpoints: []string{spotifyURL}},
	{name: "tiktok", url: "https://www.tiktok.com/", check: checkTikTok, endpoints: []string{tikTokURL}},
	{name: "bilibili", url: "https://www.bilibili.com/", check: checkBilibili, endpoints: []string{bilibiliURL}},
}

func handleServiceCheck(params *ServiceCheckParams) []ServiceCheckItem {
	started := time.Now()
	if params.Purpose != "" && params.Purpose != "basic" && params.Purpose != "advanced" {
		return nil
	}
	wanted := selectedCheckers(params.Names)
	for index := range wanted {
		wanted[index].purpose = params.Purpose
		if wanted[index].purpose == "" {
			wanted[index].purpose = "basic"
		}
	}
	items := make([]ServiceCheckItem, len(wanted))
	if len(wanted) == 0 {
		return items
	}

	timeout := min(probeTimeout(params.Timeout), defaultProbeTimeout)
	parent, _, requestErr := requestOperationContext(params.ScopeID, params.ProxyName)
	if requestErr != nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(parent, timeout*serviceSweepBudgetFactor)
	defer cancel()

	// Claimed before queueing, so a check waiting for a slot is cancelled the
	// moment its service is asked again.
	contexts, release := claimServices(ctx, wanted)
	defer release()
	var running sync.WaitGroup
	for index, checker := range wanted {
		granted := acquireSlot(contexts[index], serviceCheckSlots)
		running.Add(1)
		go func(index int, checker serviceChecker) {
			defer running.Done()
			if granted {
				defer func() { <-serviceCheckSlots }()
			}
			items[index] = runServiceCheck(contexts[index], checker, params.ProxyName, timeout, started)
		}(index, checker)
	}
	running.Wait()
	return items
}

// A misbehaving rule must not take the sweep down with it.
func runServiceCheck(ctx context.Context, checker serviceChecker, proxyName string, timeout time.Duration, start time.Time) (item ServiceCheckItem) {
	epoch, picksVersion := routeStamp()
	run := &serviceRun{checker: checker}
	item = ServiceCheckItem{Status: serviceFailed}
	defer func() {
		if recovered := recover(); recovered != nil {
			item = ServiceCheckItem{Status: serviceFailed}
		}
		item.Name = checker.name
		item.Purpose = checker.purpose
		if item.Purpose == "" {
			item.Purpose = "basic"
		}
		item.Steps = run.steps
		item.Elapsed = time.Since(start).Milliseconds()
		if checker.purpose == "advanced" {
			item.Chains = nil
			item.Delay = 0
			item.HTTPStatus = 0
			endEpoch, endPicks := routeStamp()
			if epoch != endEpoch || picksVersion != endPicks || run.changed(epoch, picksVersion) {
				item.Status, item.Reason = serviceFailed, "route-changed"
			}
		}
		if run.reason != "" {
			item.Status, item.Reason = serviceFailed, run.reason
			if run.reason == "timeout" {
				item.Status = serviceTimeout
			}
		}
		if item.Status == "" {
			item.Status = serviceFailed
		}
		item.CheckedAt = time.Now().UnixMilli()
		item.CoreEpoch = epoch
		item.PicksVersion = picksVersion
	}()
	if ctx.Err() != nil {
		return item
	}
	env := serviceEnv{ctx: ctx, proxyName: proxyName, timeout: timeout, run: run}
	if checker.purpose == "advanced" {
		if checker.check == nil {
			item.Reason = "unsupported-purpose"
			return item
		}
		item = checker.check(env)
	} else {
		item = checkReachable(checker.url)(env)
	}
	return item
}

// The host asks for a service again only once the older answer can no longer
// be used, so a newer check cancels the older one and frees its probe slots.
func claimServices(parent context.Context, checkers []serviceChecker) ([]context.Context, func()) {
	contexts := make([]context.Context, len(checkers))
	claimed := make(map[string]context.Context, len(checkers))
	var releases []func()
	for index, checker := range checkers {
		key := checker.name + ":" + checker.purpose
		ctx, ok := claimed[key]
		if !ok {
			var release func()
			ctx, release = claimService(parent, key)
			claimed[key] = ctx
			releases = append(releases, release)
		}
		contexts[index] = ctx
	}
	return contexts, func() {
		for _, release := range releases {
			release()
		}
	}
}

func claimService(parent context.Context, name string) (context.Context, func()) {
	ctx, cancel := context.WithCancel(parent)
	claim := &cancel
	serviceClaimsMu.Lock()
	if previous := serviceClaims[name]; previous != nil {
		(*previous)()
	}
	serviceClaims[name] = claim
	serviceClaimsMu.Unlock()
	return ctx, func() {
		cancel()
		serviceClaimsMu.Lock()
		if serviceClaims[name] == claim {
			delete(serviceClaims, name)
		}
		serviceClaimsMu.Unlock()
	}
}

func selectedCheckers(names []string) []serviceChecker {
	if len(names) == 0 {
		return nil
	}
	wanted := make([]serviceChecker, 0, len(names))
	seen := map[string]bool{}
	for _, name := range names {
		if seen[name] {
			continue
		}
		seen[name] = true
		for _, checker := range serviceCheckers {
			if checker.name == name {
				wanted = append(wanted, checker)
				break
			}
		}
	}
	return wanted
}

func checkReachable(url string) func(serviceEnv) ServiceCheckItem {
	return func(env serviceEnv) ServiceCheckItem {
		result := env.get(url, 0)
		item := itemFrom(result)
		if item.Status != "" {
			return item
		}
		item.Status = statusFromCode(result.StatusCode)
		switch result.StatusCode {
		case http.StatusMovedPermanently, http.StatusFound, http.StatusSeeOther, http.StatusTemporaryRedirect, http.StatusPermanentRedirect:
			item.Status = "redirected"
		}
		return item
	}
}

func itemFrom(result *ProbeResult) ServiceCheckItem {
	if result == nil {
		return ServiceCheckItem{Status: serviceFailed}
	}
	item := ServiceCheckItem{Delay: result.Delay, Chains: result.Chains, HTTPStatus: result.StatusCode}
	if result.bodyState == "read-error" || result.bodyState == "body-limit" || result.bodyState == "recipient-blocked" {
		item.Status = serviceFailed
		return item
	}
	switch result.Error {
	case "":
	case probeErrorTimeout:
		item.Status = serviceTimeout
		item.Delay = 0
	default:
		item.Status = serviceFailed
		item.Delay = 0
	}
	return item
}

func statusFromCode(code int) string {
	switch {
	case code >= 200 && code < 300:
		return serviceAvailable
	case code == http.StatusUnauthorized,
		code == http.StatusForbidden,
		code == http.StatusTooManyRequests,
		code == http.StatusUnavailableForLegalReasons:
		return serviceRestricted
	default:
		return "http-response"
	}
}

func answered(item ServiceCheckItem, result *ProbeResult) bool {
	if item.Status != "" || result == nil {
		return false
	}
	return result.bodyState == "" || result.bodyState == "complete" || result.bodyState == "marker"
}

func bodyContains(result *ProbeResult, needles ...string) bool {
	body := strings.ToLower(result.Body)
	for _, needle := range needles {
		if strings.Contains(body, needle) {
			return true
		}
	}
	return false
}

func traceValue(body string, key string) string {
	for _, line := range strings.Split(body, "\n") {
		if rest, found := strings.CutPrefix(line, key+"="); found {
			return strings.TrimSpace(rest)
		}
	}
	return ""
}
