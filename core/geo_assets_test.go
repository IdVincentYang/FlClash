package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/component/geodata"
	_ "github.com/metacubex/mihomo/component/geodata/memconservative"
	"github.com/metacubex/mihomo/component/geodata/router"
	_ "github.com/metacubex/mihomo/component/geodata/standard"
	"github.com/metacubex/mihomo/component/mmdb"
	C "github.com/metacubex/mihomo/constant"
	"github.com/oschwald/maxminddb-golang"
	"google.golang.org/protobuf/proto"
)

func geoMMDBRole(data []byte, role string) error {
	r, err := maxminddb.FromBytes(data)
	if err != nil {
		return err
	}
	defer r.Close()
	expected := "Meta-geoip0"
	if role == "ASN" {
		expected = "GeoLite2-ASN"
	}
	if r.Metadata.DatabaseType != expected {
		return fmt.Errorf("%s requires %s, got %s", role, expected, r.Metadata.DatabaseType)
	}
	return nil
}

func TestGeoBaselineReaders(t *testing.T) {
	if os.Getenv("FLCLASH_GEO_PROBE_CHILD") != "1" {
		command := exec.Command(os.Args[0], "-test.run=^TestGeoBaselineReaders$", "-test.v")
		command.Env = append(os.Environ(), "FLCLASH_GEO_PROBE_CHILD=1")
		output, err := command.CombinedOutput()
		t.Log(string(output))
		if err != nil {
			t.Fatal(err)
		}
		return
	}
	dir := os.Getenv("FLCLASH_GEO_ASSET_DIR")
	if dir == "" {
		dir = "../assets/data"
	}
	home := t.TempDir()
	files := map[string][]byte{}
	for _, name := range []string{"GEOIP.metadb", "ASN.mmdb", "GEOIP.dat", "GEOSITE.dat"} {
		body, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		files[name] = body
		if err := os.WriteFile(filepath.Join(home, name), body, 0600); err != nil {
			t.Fatal(err)
		}
	}
	C.SetHomeDir(home)
	alias := filepath.Join(home, "Country.mmdb")
	if err := os.WriteFile(alias, files["GEOIP.metadb"], 0600); err != nil {
		t.Fatal(err)
	}
	if C.Path.MMDB() != alias {
		t.Fatal("Core compatibility-name selection changed")
	}
	if err := os.Remove(alias); err != nil {
		t.Fatal(err)
	}
	canonicalSite := filepath.Join(home, "GEOSITE.dat")
	foldedSite := filepath.Join(home, "Geoſite.dat")
	if err := os.Rename(canonicalSite, foldedSite); err != nil {
		t.Fatal(err)
	}
	if C.Path.GeoSite() != foldedSite {
		t.Fatal("Core Unicode compatibility-name selection changed")
	}
	if err := os.Rename(foldedSite, canonicalSite); err != nil {
		t.Fatal(err)
	}
	if C.Path.GeoSite() != canonicalSite {
		t.Fatal("Core canonical GeoSite selection changed")
	}
	for role, name := range map[string]string{"MMDB": "GEOIP.metadb", "ASN": "ASN.mmdb"} {
		if err := geoMMDBRole(files[name], role); err != nil {
			t.Fatal(err)
		}
		other := "ASN.mmdb"
		if role == "ASN" {
			other = "GEOIP.metadb"
		}
		if err := geoMMDBRole(files[other], role); err == nil {
			t.Fatalf("wrong semantic role accepted: %s", role)
		}
		if err := geoMMDBRole(files[name][:100], role); err == nil {
			t.Fatalf("truncated %s accepted", role)
		}
	}
	observations := map[string]any{}
	reader := mmdb.IPInstance()
	defer reader.Close()
	observations["MMDB.metadata"] = reader.Metadata
	for ip, want := range map[string]string{"8.8.8.8": "us", "114.114.114.114": "cn"} {
		codes := reader.LookupCode(net.ParseIP(ip))
		observations["MMDB."+ip] = codes
		found := false
		for _, code := range codes {
			found = found || code == want
		}
		if !found {
			t.Fatalf("country fixture %s: %v, want %s", ip, codes, want)
		}
	}
	asn := mmdb.ASNInstance()
	defer asn.Close()
	observations["ASN.metadata"] = asn.Metadata
	for ip, want := range map[string]string{"8.8.8.8": "15169", "1.1.1.1": "13335"} {
		number, organization := asn.LookupASN(net.ParseIP(ip))
		observations["ASN."+ip] = []string{number, organization}
		if number != want || organization == "" {
			t.Fatalf("ASN fixture %s: %s %s, want %s with organization", ip, number, organization, want)
		}
	}
	loader, err := geodata.GetGeoDataLoader("standard")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := loader.LoadIPByPath("missing.dat", "cn"); err == nil {
		t.Fatal("missing GEOIP accepted")
	}
	if _, err := loader.LoadSiteByPath("missing.dat", "cn"); err == nil {
		t.Fatal("missing GEOSITE accepted")
	}
	for code, sample := range map[string]string{"cn": "114.114.114.114", "us": "8.8.8.8", "private": "127.0.0.1"} {
		entries, err := loader.LoadIPByBytes(files["GEOIP.dat"], code)
		if err != nil || len(entries) == 0 {
			t.Fatalf("GEOIP %s: %v", code, err)
		}
		matcher, err := router.NewGeoIPMatcher(entries)
		if err != nil || !matcher.Match(netip.MustParseAddr(sample)) {
			t.Fatalf("GEOIP %s sample: %v", code, err)
		}
		if code == "cn" && matcher.Match(netip.MustParseAddr("8.8.8.8")) {
			t.Fatal("GEOIP cn unexpectedly matches negative fixture")
		}
		observations["GEOIP."+code] = len(entries)
	}
	for code, sample := range map[string]string{"cn": "baidu.com", "google": "google.com"} {
		entries, err := loader.LoadSiteByBytes(files["GEOSITE.dat"], code)
		if err != nil || len(entries) == 0 {
			t.Fatalf("GEOSITE %s: %v", code, err)
		}
		matcher, err := router.NewSuccinctMatcherGroup(entries)
		if err != nil || !matcher.ApplyDomain(sample) || matcher.ApplyDomain("not-a-real-host.invalid") {
			t.Fatalf("GEOSITE %s positive/negative fixtures: %v", code, err)
		}
		observations["GEOSITE."+code] = len(entries)
	}
	if _, err := loader.LoadIPByBytes([]byte{0xff}, "cn"); err == nil {
		t.Fatal("invalid protobuf GEOIP accepted")
	}
	if _, err := loader.LoadSiteByBytes([]byte{0xff}, "cn"); err == nil {
		t.Fatal("invalid protobuf GEOSITE accepted")
	}
	compact, err := geodata.GetGeoDataLoader("memconservative")
	if err != nil {
		t.Fatal(err)
	}
	compactIPs, err := compact.LoadIPByPath("GEOIP.dat", "cn")
	if err != nil {
		t.Fatal(err)
	}
	compactIPMatcher, err := router.NewGeoIPMatcher(compactIPs)
	if err != nil || !compactIPMatcher.Match(netip.MustParseAddr("114.114.114.114")) || compactIPMatcher.Match(netip.MustParseAddr("8.8.8.8")) {
		t.Fatalf("default loader country positive/negative: %v", err)
	}
	compactSites, err := compact.LoadSiteByPath("GEOSITE.dat", "google")
	if err != nil {
		t.Fatal(err)
	}
	compactSiteMatcher, err := router.NewSuccinctMatcherGroup(compactSites)
	if err != nil || !compactSiteMatcher.ApplyDomain("google.com") || compactSiteMatcher.ApplyDomain("not-a-real-host.invalid") {
		t.Fatalf("default loader domain positive/negative: %v", err)
	}
	observations["memconservative.cn"] = len(compactIPs)
	observations["memconservative.google"] = len(compactSites)
	var ips router.GeoIPList
	var sites router.GeoSiteList
	if err := proto.Unmarshal(files["GEOIP.dat"], &ips); err != nil {
		t.Fatal(err)
	}
	if err := proto.Unmarshal(files["GEOSITE.dat"], &sites); err != nil {
		t.Fatal(err)
	}
	ipCount, siteCount := 0, 0
	for _, entry := range ips.Entry {
		ipCount += len(entry.Cidr)
	}
	for _, entry := range sites.Entry {
		siteCount += len(entry.Domain)
	}
	observations["GEOIP.totals"] = []int{len(ips.Entry), ipCount}
	observations["GEOSITE.totals"] = []int{len(sites.Entry), siteCount}
	data, err := json.MarshalIndent(observations, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if path := os.Getenv("FLCLASH_GEO_OBSERVATION"); path != "" {
		if err := os.WriteFile(path, append(data, '\n'), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
