package main

import (
	"net/http"
	"strings"
	"testing"
)

func TestNormalizeRegion(t *testing.T) {
	cases := map[string]string{
		"US":    "US",
		"jp":    "JP",
		"CHN":   "CN",
		"usa":   "US",
		"HKG":   "HK",
		"ZZZ":   "",
		"C":     "",
		"CNAAA": "",
		"":      "",
		"1A":    "",
	}
	for input, want := range cases {
		if got := normalizeRegion(input); got != want {
			t.Errorf("normalizeRegion(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestDiagnosticRegionHintsDoNotApplyStaticAvailabilityBlacklists(t *testing.T) {
	for _, scenario := range []struct{ name, body, want string }{
		{"claude", "loc=CN\n", "CN"},
		{"gemini", geminiRegionMarker + `HKG"`, "HK"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(scenario.body)) }, true)
			item := diagnosticCheck(t, scenario.name, "advanced")
			if item.Status != "observed" || item.Region != scenario.want {
				t.Fatalf("region hint=%+v", item)
			}
		})
	}
}

// The iOS endpoint turns API clients away even where ChatGPT works, so that
// refusal is the success signal and anything else is not.
func TestChatGptIosStatus(t *testing.T) {
	cases := map[string]string{
		"Request is not allowed. Please try again later.": serviceAvailable,
		"You may be connected to a disallowed ISP":        serviceDisallowedIsp,
		"Sorry, you have been blocked":                    serviceBlocked,
		"<html>something else entirely</html>":            serviceFailed,
		"":                                                serviceFailed,
	}
	for body, want := range cases {
		if got := chatGptIosStatus(&ProbeResult{Body: body}); got != want {
			t.Errorf("chatGptIosStatus(%q) = %q, want %q", body, got, want)
		}
	}
}

func TestTikTokStatus(t *testing.T) {
	cases := []struct {
		code int
		body string
		want string
	}{
		{http.StatusOK, `{"webapp.app-context":{"region":"JP"}}`, "observed"},
		{http.StatusForbidden, "", serviceRestricted},
		{http.StatusUnavailableForLegalReasons, "", serviceRestricted},
		{http.StatusOK, "Access Denied", serviceFailed},
		{http.StatusOK, "TikTok is not available in your region", serviceUnsupportedRegion},
		{http.StatusInternalServerError, "", serviceFailed},
	}
	for _, testCase := range cases {
		got := tikTokStatus(&ProbeResult{StatusCode: testCase.code, Body: testCase.body})
		if got != testCase.want {
			t.Errorf("tikTokStatus(%d, %q) = %q, want %q", testCase.code, testCase.body, got, testCase.want)
		}
	}
}

func TestTikTokRegionReadsTheAppContext(t *testing.T) {
	const cluster = `{"idc":"no1a","vdc":"no1a","region":"EU-TTP2","vregion":"EU-TTP2"}`
	page := cluster + `{"__DEFAULT_SCOPE__":{"webapp.app-context":{"language":"en","region":"GB","appId":1233}}}`
	if got := tikTokRegion(page); got != "GB" {
		t.Errorf("region = %q, want the visitor's country rather than the serving cluster", got)
	}
	if got := tikTokRegion(cluster); got != "" {
		t.Errorf("region = %q, want empty without the app context", got)
	}
	if got := tikTokRegion(`{"webapp.app-context":{"region":"zh-Hant-TW"}}`); got != "" {
		t.Errorf("region = %q, want a locale left unread rather than its language", got)
	}
}

func TestSpotifyRegionRequiresStructuredResponse(t *testing.T) {
	diagnosticFixture(t, func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(`{"countryCode":"SE"}`)) }, true)
	item := diagnosticCheck(t, "spotify", "advanced")
	if item.Status != "observed" || item.Region != "SE" {
		t.Fatalf("country=%+v", item)
	}
}

func TestYouTubeRegionPatterns(t *testing.T) {
	bodies := map[string]string{
		`<span id="country-code"> GB </span>`: "GB",
		`{"GL":"JP","other":1}`:               "JP",
		`{"countryCode":"KR"}`:                "KR",
		`{"country_code":"BR"}`:               "BR",
	}
	for body, want := range bodies {
		var got string
		for _, pattern := range youTubeRegionPatterns {
			if code := firstSubmatch(pattern, body); code != "" {
				got = normalizeRegion(code)
				break
			}
		}
		if got != want {
			t.Errorf("region from %q = %q, want %q", body, got, want)
		}
	}
}

func TestServiceTokenBoundsAndPrimeMarker(t *testing.T) {
	for _, value := range []string{"", "line\nbreak", "zero\x00value", strings.Repeat("x", 8193)} {
		if serviceToken(value) {
			t.Fatal("invalid token accepted")
		}
	}
	if !serviceToken("synthetic+token") {
		t.Fatal("valid token rejected")
	}
	if got := firstSubmatch(primeRegionPattern, `{"currentTerritory":"NL"}`); got != "NL" {
		t.Fatalf("territory=%q", got)
	}
}

func TestGeminiRequiresACompleteKnownRegionMarker(t *testing.T) {
	for _, body := range []string{geminiRegionMarker + "CHN", geminiRegionMarker + `ZZZ"`, geminiRegionMarker + `cnx"`} {
		if got := geminiRegion(body); got != "" {
			t.Fatalf("invalid marker=%q", got)
		}
	}
	if got := geminiRegion(geminiRegionMarker + `CHN"`); got != "CN" {
		t.Fatalf("region=%q", got)
	}
}
