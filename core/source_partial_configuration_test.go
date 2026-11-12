package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func partialFixture(t *testing.T, body, kind, name string) sourceAcceptanceResult {
	t.Helper()
	result, err := previewPartialSourceConfiguration(sourceAcceptanceRequest{
		Kind: "profile", Body: body,
		MissingProviders: []sourceProviderPlan{{Kind: kind, Name: name}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func TestPartialSourceRetainsRulesGroupsDNSAndAvailableDeclarations(t *testing.T) {
	body := `proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 9}]
proxy-groups: [{name: Default, type: select, proxies: [node]}]
rule-providers:
  loaded: {type: http, url: https://example.invalid/loaded, behavior: domain, format: text}
  missing: {type: http, url: https://example.invalid/missing, behavior: domain, format: text}
dns: {enable: true, nameserver: [https://1.1.1.1/dns-query], nameserver-policy: {'b.invalid': 1.1.1.1, 'a.invalid': 8.8.8.8}}
rules: ["DOMAIN,first.invalid,DIRECT", "RULE-SET,missing,DIRECT", "RULE-SET,loaded,Default", "MATCH,Default"]
`
	result := partialFixture(t, body, "provider-rule", "missing")
	if result.Document == nil || len(result.Partial.Blocked) != 0 || result.Partial.DefaultTarget != "Default" {
		t.Fatal(result)
	}
	rules, _ := sourceStrings(result.Document["rules"])
	if strings.Join(rules, ";") != "DOMAIN,first.invalid,DIRECT;RULE-SET,loaded,Default;MATCH,Default" || len(result.Partial.RemovedRules) != 1 {
		t.Fatal(rules, result.Partial)
	}
	if len(result.Document["rule-providers"].(map[string]any)) != 1 || len(result.Document["proxy-groups"].([]any)) != 1 {
		t.Fatal(result.Document)
	}
	encoded, _ := json.Marshal(result.Document["dns"])
	if !strings.Contains(string(encoded), `"b.invalid":"1.1.1.1","a.invalid":"8.8.8.8"`) {
		t.Fatal("DNS policy order changed", string(encoded))
	}
}

func TestPartialSourcePrunesOnlyUnavailableGroupDependencies(t *testing.T) {
	body := `proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 9}]
proxy-providers: {missing: {type: http, url: https://example.invalid/missing}}
proxy-groups:
  - {name: Empty, type: select, use: [missing]}
  - {name: Parent, type: select, proxies: [Empty]}
  - {name: Default, type: select, proxies: [node, Parent]}
rules: ["DOMAIN,a.invalid,Parent", "MATCH,Default"]
`
	result := partialFixture(t, body, "provider-proxy", "missing")
	if result.Document == nil || len(result.Partial.RemovedGroups) != 2 || len(result.Partial.RemovedRules) != 1 {
		t.Fatal(result)
	}
	groups := result.Document["proxy-groups"].([]any)
	if len(groups) != 1 {
		t.Fatal(groups)
	}
	members, _ := sourceStrings(groups[0].(map[string]any)["proxies"])
	if len(members) != 1 || members[0] != "node" {
		t.Fatal(members)
	}
}

func TestPartialSourceBlocksCriticalOrUnprovenDependencies(t *testing.T) {
	for _, test := range []struct{ name, extra, rules string }{
		{"dns", "dns: {nameserver-policy: {'rule-set:missing': 1.1.1.1}}", "MATCH,DIRECT"},
		{"sniffer", "sniffer: {skip-domain: ['rule-set:missing']}", "MATCH,DIRECT"},
		{"nested", "", "NOT,((RULE-SET,missing)),DIRECT"},
		{"sub-rules", "sub-rules: {inner: ['MATCH,DIRECT']}", "MATCH,DIRECT"},
		{"implicit-default", "", "DOMAIN,a.invalid,DIRECT"},
	} {
		t.Run(test.name, func(t *testing.T) {
			body := "rule-providers: {missing: {type: http, url: https://example.invalid/missing, behavior: domain, format: text}}\n" + test.extra + "\nrules: ['" + test.rules + "']\n"
			result := partialFixture(t, body, "provider-rule", "missing")
			if result.Document != nil || len(result.Partial.Blocked) == 0 {
				t.Fatal("critical dependency was silently dropped", result)
			}
		})
	}
	for _, extra := range []string{"", "listeners: [{name: incoming, type: mixed, port: 10001, proxy: Empty}]", "dns: {nameserver: ['https://1.1.1.1/dns-query#Empty']}"} {
		body := "proxy-providers: {missing: {type: http, url: https://example.invalid/missing}}\nproxy-groups: [{name: Empty, type: select, use: [missing]}]\nrules: ['MATCH,Empty']\n" + extra
		result := partialFixture(t, body, "provider-proxy", "missing")
		if result.Document != nil || len(result.Partial.Blocked) == 0 {
			t.Fatal("missing default acquired an implicit DIRECT", result)
		}
	}
}

func TestPartialSourceRejectsForeignMissingDeclarations(t *testing.T) {
	result := partialFixture(t, "rules: ['MATCH,REJECT']\n", "provider-rule", "not-in-source")
	if result.Document != nil || len(result.Partial.Blocked) == 0 {
		t.Fatal(result)
	}
}

func TestPartialSourceCannotIntroduceAnEmptyImplicitExit(t *testing.T) {
	for _, group := range []string{
		"{name: Empty, type: select, include-all: true}",
		"{name: Empty, type: select, use: [missing], proxies: [unknown]}",
		"{name: Empty, type: select, use: [missing], proxies: [node], filter: unavailable}",
	} {
		body := "proxies: [{name: node, type: socks5, server: 127.0.0.1, port: 9}]\nproxy-providers: {missing: {type: http, url: https://example.invalid/missing}}\nproxy-groups: [" + group + "]\nrules: ['MATCH,Empty']\n"
		if strings.Contains(group, "include-all") {
			body = strings.Replace(body, "include-all: true", "include-all-providers: true", 1)
		}
		result := partialFixture(t, body, "provider-proxy", "missing")
		if result.Document != nil || len(result.Partial.Blocked) == 0 {
			t.Fatal(result)
		}
	}
	result := partialFixture(t, "proxy-providers: {missing: {type: http, url: https://example.invalid/missing}}\nrules: ['MATCH,unknown']\n", "provider-proxy", "missing")
	if result.Document != nil || len(result.Partial.Blocked) == 0 {
		t.Fatal(result)
	}
}
