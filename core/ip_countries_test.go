package main

import (
	"encoding/json"
	"os"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestLookupIPCountriesIsLocalAndOptional(t *testing.T) {
	previous := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(previous)
	if got := handleLookupIPCountries([]string{"8.8.8.8"}); len(got) != 0 {
		t.Fatalf("missing database returned countries: %v", got)
	}
	if err := os.WriteFile(C.Path.MMDB(), []byte("invalid database"), 0600); err != nil {
		t.Fatal(err)
	}
	if got := handleLookupIPCountries([]string{"8.8.8.8"}); len(got) != 0 {
		t.Fatalf("invalid database returned countries: %v", got)
	}
	data, err := os.ReadFile("../assets/data/GEOIP.metadb")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(C.Path.MMDB(), data, 0600); err != nil {
		t.Fatal(err)
	}
	got := handleLookupIPCountries([]string{"8.8.8.8", "114.114.114.114", "127.0.0.1", "192.168.1.1", "example.test", "203.0.113.1"})
	if len(got) != 2 || got["8.8.8.8"] != "US" || got["114.114.114.114"] != "CN" {
		t.Fatalf("unexpected countries: %v", got)
	}
	var reply struct {
		Result map[string]string `json:"result"`
		Error  any               `json:"error"`
	}
	if err := json.Unmarshal(businessRPC(t, lookupIpCountriesMethod, `["8.8.8.8"]`), &reply); err != nil || reply.Error != nil || reply.Result["8.8.8.8"] != "US" {
		t.Fatalf("country RPC response: %+v / %v", reply, err)
	}
	if got = handleLookupIPCountries(make([]string, 129)); len(got) != 0 {
		t.Fatalf("oversized batch accepted: %v", got)
	}
}

func TestLookupIPCountriesPreservesTerritories(t *testing.T) {
	previous := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	defer C.SetHomeDir(previous)
	data, err := os.ReadFile("../assets/data/GEOIP.metadb")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(C.Path.MMDB(), data, 0600); err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{"8.210.0.1": "HK", "34.92.0.1": "HK", "202.175.1.1": "MO", "168.95.1.1": "TW"}
	ips := make([]string, 0, len(cases))
	for ip := range cases {
		ips = append(ips, ip)
	}
	actual := handleLookupIPCountries(ips)
	for ip, expected := range cases {
		if actual[ip] != expected {
			t.Fatalf("region for %s = %q, want %s", ip, actual[ip], expected)
		}
	}
}

func TestCountryMMDBRecordFormats(t *testing.T) {
	for _, value := range []any{"us", []any{"us"}, []any{"us", "google"}, map[string]any{"country": map[string]any{"iso_code": "us"}}} {
		if got := countryFromMMDB(value); got != "US" {
			t.Fatalf("record %v returned %q", value, got)
		}
	}
	for _, value := range []any{nil, []any{"us", "cn"}, map[string]any{"registered_country": map[string]any{"iso_code": "us"}}} {
		if got := countryFromMMDB(value); got != "" {
			t.Fatalf("ambiguous or absent country accepted: %v / %q", value, got)
		}
	}
}
