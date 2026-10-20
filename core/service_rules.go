package main

import (
	"encoding/json"
	"net/url"
	"regexp"
	"strings"

	"github.com/metacubex/http"
)

const (
	youtubePremiumURL  = "https://www.youtube.com/premium?hl=en"
	chatGPTIOSURL      = "https://ios.chat.openai.com/"
	chatGPTTraceURL    = "https://chat.openai.com/cdn-cgi/trace"
	chatGPTWebURL      = "https://api.openai.com/compliance/cookie_requirements"
	claudeTraceURL     = "https://claude.ai/cdn-cgi/trace"
	geminiURL          = "https://gemini.google.com"
	netflixCDNURL      = "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=5"
	netflixTitleOneURL = "https://www.netflix.com/title/81280792"
	netflixTitleTwoURL = "https://www.netflix.com/title/70143836"
	netflixRegionURL   = "https://www.netflix.com/title/80018499"
	disneyDeviceURL    = "https://disney.api.edge.bamgrid.com/devices"
	disneyTokenURL     = "https://disney.api.edge.bamgrid.com/token"
	disneySessionURL   = "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql"
	primeVideoURL      = "https://www.primevideo.com"
	spotifyURL         = "https://www.spotify.com/api/content/v1/country-selector?platform=web&format=json"
	tikTokURL          = "https://www.tiktok.com/"
	bilibiliURL        = "https://api.bilibili.com/pgc/player/web/playurl?avid=18281381&cid=29892777&qn=0&type=&otype=json&ep_id=183799&fourk=1&fnver=0&fnval=16&module=bangumi"
)

// disneyAuthHeader is the public browser client token Disney+ hands to any web
// visitor; the device and token calls below are rejected without it.
const disneyAuthHeader = "Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84"

var (
	youTubeRegionPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)id=["']country-code["'][^>]*>\s*([A-Za-z]{2,3})\s*<`),
		regexp.MustCompile(`"GL"\s*:\s*"([A-Za-z]{2})"`),
		regexp.MustCompile(`"countryCode"\s*:\s*"([A-Za-z]{2})"`),
		regexp.MustCompile(`"country_code"\s*:\s*"([A-Za-z]{2})"`),
	}
	tikTokRegionPattern = regexp.MustCompile(`"webapp\.app-context"\s*:\s*\{[^{}]*?"region"\s*:\s*"([^"]*)"`)
	primeRegionPattern  = regexp.MustCompile(`"currentTerritory":"([^"]+)"`)
	geminiRegionMarker  = `,2,1,200,"`
)

func firstSubmatch(pattern *regexp.Regexp, body string) string {
	match := pattern.FindStringSubmatch(body)
	if len(match) < 2 {
		return ""
	}
	return match[1]
}

func checkClaude(env serviceEnv) ServiceCheckItem {
	result := env.get(claudeTraceURL, serviceSmallMaxBody)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	region := normalizeRegion(traceValue(result.Body, "loc"))
	if region == "" {
		item.Status = serviceFailed
		return item
	}
	item.Region = region
	item.Status = "observed"
	return item
}

func checkGemini(env serviceEnv) ServiceCheckItem {
	result := env.scan(geminiURL, func(tail string) bool { return geminiRegion(tail) != "" })
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	item.Region = geminiRegion(result.Body)
	item.Status = serviceFailed
	if item.Region != "" {
		item.Status = "observed"
	}
	return item
}

func geminiRegion(body string) string {
	index := strings.Index(body, geminiRegionMarker)
	if index < 0 {
		return ""
	}
	start := index + len(geminiRegionMarker)
	if start+3 >= len(body) || body[start+3] != '"' {
		return ""
	}
	code := body[start : start+3]
	if !isAsciiUpper(code) {
		return ""
	}
	return normalizeRegion(code)
}

func checkChatGpt(env serviceEnv) ServiceCheckItem {
	observe := func(status, region string) {
		if env.run != nil && len(env.run.steps) > 0 {
			step := &env.run.steps[len(env.run.steps)-1]
			step.Observation, step.Region = status, region
		}
	}
	item := ServiceCheckItem{Status: serviceFailed, Reason: "unrecognized"}
	ios := env.get(chatGPTIOSURL, serviceSmallMaxBody)
	if answered(itemFrom(ios), ios) {
		status := chatGptIosStatus(ios)
		if status == serviceAvailable {
			status = "observed"
		}
		observe(status, "")
	}
	trace := env.get(chatGPTTraceURL, serviceSmallMaxBody)
	if answered(itemFrom(trace), trace) {
		status := serviceFailed
		if trace.StatusCode == http.StatusOK {
			item.Region = normalizeRegion(traceValue(trace.Body, "loc"))
			if item.Region != "" {
				status = "observed"
			}
		}
		observe(status, item.Region)
	}
	web := env.get(chatGPTWebURL, serviceSmallMaxBody)
	if !answered(itemFrom(web), web) {
		return item
	}
	var payload struct {
		Error *struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if json.Unmarshal([]byte(web.Body), &payload) != nil {
		observe(serviceFailed, "")
		return item
	}
	if payload.Error != nil && payload.Error.Code == "unsupported_country" {
		item.Status = serviceUnsupportedRegion
		item.Reason = ""
		observe(serviceUnsupportedRegion, "")
		return item
	}
	observe(serviceFailed, "")
	return item
}

func chatGptIosStatus(result *ProbeResult) string {
	switch {
	case bodyContains(result, "you may be connected to a disallowed isp"):
		return serviceDisallowedIsp
	case bodyContains(result, "sorry, you have been blocked"):
		return serviceBlocked
	case bodyContains(result, "request is not allowed. please try again later."):
		return serviceAvailable
	default:
		return serviceFailed
	}
}

func checkYouTubePremium(env serviceEnv) ServiceCheckItem {
	result := env.get(youtubePremiumURL, serviceHtmlMaxBody)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	for _, pattern := range youTubeRegionPatterns {
		if code := firstSubmatch(pattern, result.Body); code != "" {
			item.Region = normalizeRegion(code)
			break
		}
	}
	switch {
	case bodyContains(result,
		"youtube premium is not available in your country",
		"premium is not available in your country",
		"premium is not available in your region"):
		item.Status = serviceUnsupportedRegion
	case result.StatusCode == http.StatusOK && (item.Region != "" || bodyContains(result, `"browseid":"spunlimited"`)):
		item.Status = "observed"
	default:
		item.Status = serviceFailed
	}
	return item
}

func checkSpotify(env serviceEnv) ServiceCheckItem {
	result := env.get(
		spotifyURL,
		serviceSmallMaxBody,
	)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	var payload struct {
		CountryCode string `json:"countryCode"`
	}
	if result.StatusCode != http.StatusOK || json.Unmarshal([]byte(result.Body), &payload) != nil {
		item.Status = serviceFailed
		return item
	}
	item.Region = normalizeRegion(payload.CountryCode)
	if item.Region == "" {
		item.Status = serviceFailed
	} else {
		item.Status = "observed"
	}

	return item
}

// TikTok is not behind Cloudflare: /cdn-cgi/trace redirects to a 404 page.
func checkTikTok(env serviceEnv) ServiceCheckItem {
	result := env.scan(tikTokURL, tikTokRegionPattern.MatchString)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	item.Status = tikTokStatus(result)
	item.Region = tikTokRegion(result.Body)
	return item
}

func tikTokStatus(result *ProbeResult) string {
	switch {
	case result.StatusCode == http.StatusForbidden ||
		result.StatusCode == http.StatusUnavailableForLegalReasons:
		return serviceRestricted
	case result.StatusCode < 200 || result.StatusCode >= 300:
		return serviceFailed
	case bodyContains(result, "not available in your region", "tiktok is not available"):
		return serviceUnsupportedRegion
	default:
		if tikTokRegion(result.Body) != "" {
			return "observed"
		}
		return serviceFailed
	}
}

// The page names its serving cluster "region" too ("EU-TTP2"); the visitor's
// country is the one in the web app's context.
func tikTokRegion(body string) string {
	return normalizeRegion(firstSubmatch(tikTokRegionPattern, body))
}

func checkBilibili(env serviceEnv) ServiceCheckItem {
	const url = bilibiliURL
	result := env.get(url, serviceSmallMaxBody)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	var payload struct {
		Code *int `json:"code"`
		Data *struct {
			Durl []struct {
				URL string `json:"url"`
			} `json:"durl"`
			Dash *struct {
				Video []struct {
					BaseURL      string `json:"baseUrl"`
					BaseURLSnake string `json:"base_url"`
				} `json:"video"`
			} `json:"dash"`
		} `json:"data"`
	}
	if result.StatusCode != http.StatusOK || json.Unmarshal([]byte(result.Body), &payload) != nil || payload.Code == nil {
		item.Status = serviceFailed
		return item
	}
	switch *payload.Code {
	case 0:
		item.Status = serviceFailed
		if payload.Data != nil {
			for _, entry := range payload.Data.Durl {
				if serviceMediaURL(entry.URL) {
					item.Status = "observed"
				}
			}
			if payload.Data.Dash != nil {
				for _, entry := range payload.Data.Dash.Video {
					if serviceMediaURL(entry.BaseURL) || serviceMediaURL(entry.BaseURLSnake) {
						item.Status = "observed"
					}
				}
			}
		}
	case -10403:
		item.Status = serviceUnsupportedRegion
	default:
		item.Status = serviceFailed
	}

	return item
}

func checkPrimeVideo(env serviceEnv) ServiceCheckItem {
	result := env.scan(primeVideoURL, func(tail string) bool {
		return strings.Contains(tail, `"isServiceRestricted":true`) || primeRegionPattern.MatchString(tail)
	})
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	if strings.Contains(result.Body, `"isServiceRestricted":true`) {
		item.Status = serviceUnsupportedRegion
		return item
	}
	region := firstSubmatch(primeRegionPattern, result.Body)
	if region == "" {
		item.Status = serviceFailed
		return item
	}
	item.Region = normalizeRegion(region)
	if item.Region == "" {
		item.Status = serviceFailed
		return item
	}
	item.Status = "observed"
	return item
}

func checkNetflix(env serviceEnv) ServiceCheckItem {
	if item := netflixFromCdn(env); item.Status == "observed" {
		return item
	}

	first := env.get(netflixTitleOneURL, 0)
	firstItem := itemFrom(first)
	if !answered(firstItem, first) {
		return firstItem
	}
	second := env.get(netflixTitleTwoURL, 0)
	secondItem := itemFrom(second)
	if !answered(secondItem, second) {
		return secondItem
	}

	item := firstItem
	item.Status = serviceFailed
	if first.StatusCode == http.StatusOK || first.StatusCode == http.StatusNotFound || second.StatusCode == http.StatusOK || second.StatusCode == http.StatusNotFound {
		item.Reason = "catalog-hint"
		item.Region = netflixRegion(env)
	}

	return item
}

// netflixRegion reads the country out of the redirect Netflix would send a
// visitor to, so the redirect must not be followed.
func netflixRegion(env serviceEnv) string {
	result := env.send(probeRequest{
		method:     http.MethodGet,
		url:        netflixRegionURL,
		noRedirect: true,
	})
	if result == nil || result.Error != "" || result.header == nil {
		return ""
	}
	origin, _ := url.Parse(netflixRegionURL)
	location, err := url.Parse(result.header.Get("Location"))
	if err != nil {
		return ""
	}
	location = origin.ResolveReference(location)
	if !serviceHTTPS(location) || !strings.EqualFold(location.Hostname(), origin.Hostname()) {
		return ""
	}
	segments := strings.Split(strings.Trim(location.Path, "/"), "/")
	return normalizeRegion(strings.Split(segments[0], "-")[0])
}

func netflixFromCdn(env serviceEnv) ServiceCheckItem {
	const url = netflixCDNURL
	result := env.get(url, serviceSmallMaxBody)
	item := itemFrom(result)
	if !answered(item, result) {
		return item
	}
	if result.StatusCode < 200 || result.StatusCode >= 300 {
		item.Status = serviceRestricted
		return item
	}
	var payload struct {
		Targets []struct {
			Location struct {
				Country string `json:"country"`
			} `json:"location"`
		} `json:"targets"`
	}
	if err := json.Unmarshal([]byte(result.Body), &payload); result.StatusCode != http.StatusOK || err != nil || len(payload.Targets) == 0 {
		item.Status = serviceFailed
		return item
	}
	item.Region = normalizeRegion(payload.Targets[0].Location.Country)
	item.Status = serviceFailed
	if item.Region != "" {
		item.Status = "observed"
	}
	return item
}

func checkDisneyPlus(env serviceEnv) ServiceCheckItem {
	post := func(target string, payload []byte, contentType string) *ProbeResult {
		return env.send(probeRequest{method: http.MethodPost, url: target, headers: map[string]string{"Authorization": disneyAuthHeader, "Content-Type": contentType}, body: payload, maxBody: serviceSmallMaxBody})
	}
	device := post(disneyDeviceURL, []byte(`{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}`), "application/json")
	item := itemFrom(device)
	if !answered(item, device) {
		return item
	}
	var registration struct {
		Assertion string `json:"assertion"`
	}
	if device.StatusCode != http.StatusOK && device.StatusCode != http.StatusCreated || json.Unmarshal([]byte(device.Body), &registration) != nil || !serviceToken(registration.Assertion) {
		item.Status = serviceFailed
		return item
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:token-exchange"}, "latitude": {"0"}, "longitude": {"0"}, "platform": {"browser"}, "subject_token": {registration.Assertion}, "subject_token_type": {"urn:bamtech:params:oauth:token-type:device"}}
	token := post(disneyTokenURL, []byte(form.Encode()), "application/x-www-form-urlencoded")
	item = itemFrom(token)
	if !answered(item, token) {
		return item
	}
	var exchange struct {
		RefreshToken string `json:"refresh_token"`
	}
	if token.StatusCode != http.StatusOK || json.Unmarshal([]byte(token.Body), &exchange) != nil || !serviceToken(exchange.RefreshToken) {
		item.Status = serviceFailed
		return item
	}
	payload, err := json.Marshal(map[string]any{"query": "mutation refreshToken($input: RefreshTokenInput!) { refreshToken(refreshToken: $input) { activeSession { sessionId } } }", "variables": map[string]any{"input": map[string]string{"refreshToken": exchange.RefreshToken}}})
	if err != nil {
		item.Status = serviceFailed
		return item
	}
	session := post(disneySessionURL, payload, "application/json")
	item = itemFrom(session)
	if !answered(item, session) {
		return item
	}
	var result struct {
		Errors     []json.RawMessage `json:"errors"`
		Extensions *struct {
			SDK *struct {
				Session *struct {
					Location *struct {
						CountryCode string `json:"countryCode"`
					} `json:"location"`
					InSupportedLocation *bool `json:"inSupportedLocation"`
				} `json:"session"`
			} `json:"sdk"`
		} `json:"extensions"`
	}
	if session.StatusCode != http.StatusOK || json.Unmarshal([]byte(session.Body), &result) != nil || len(result.Errors) > 0 || result.Extensions == nil || result.Extensions.SDK == nil || result.Extensions.SDK.Session == nil {
		item.Status = serviceFailed
		return item
	}
	active := result.Extensions.SDK.Session
	if active.Location == nil || active.InSupportedLocation == nil {
		item.Status = serviceFailed
		return item
	}
	item.Region = normalizeRegion(active.Location.CountryCode)
	if item.Region == "" {
		item.Status = serviceFailed
		return item
	}
	item.Status = "observed"
	if !*active.InSupportedLocation {
		item.Status = serviceUnsupportedRegion
	}
	return item
}

func serviceToken(value string) bool {
	return value != "" && len(value) <= 8192 && !strings.ContainsAny(value, "\r\n\x00")
}

func serviceMediaURL(value string) bool {
	parsed, err := url.Parse(value)
	return err == nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Hostname() != "" && parsed.User == nil
}
