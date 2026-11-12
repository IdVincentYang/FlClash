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

func TestPartialSourceKeepsIndependentLogicalRulesAndDisablesWholeDependentRules(t *testing.T) {
	body := `rule-providers:
  missing: {type: http, url: https://example.invalid/missing, behavior: domain, format: text}
  loaded: {type: http, url: https://example.invalid/loaded, behavior: domain, format: text}
rules:
  - AND,((RULE-SET,loaded),(NETWORK,TCP)),DIRECT
  - OR,((RULE-SET,loaded),(NOT,((RULE-SET,missing)))),REJECT
  - NOT,((RULE-SET,missing)),DIRECT
  - AND,((DOMAIN-REGEX,exampleRULE-SET.invalid),(RULE-SET,loaded)),DIRECT
  - MATCH,REJECT
`
	result := partialFixture(t, body, "provider-rule", "missing")
	if result.Document == nil || len(result.Partial.Blocked) != 0 {
		t.Fatal(result)
	}
	rules, _ := sourceStrings(result.Document["rules"])
	if len(rules) != 3 || len(result.Partial.RemovedRules) != 2 || !strings.Contains(rules[0], "RULE-SET,loaded") || !strings.Contains(rules[1], "DOMAIN-REGEX") || rules[2] != "MATCH,REJECT" {
		t.Fatal(rules, result.Partial)
	}
}

func TestPartialSourceRemovesOnlyDNSPoliciesReferencingMissingContent(t *testing.T) {
	body := `rule-providers:
  missing: {type: http, url: https://example.invalid/missing, behavior: domain, format: text}
  loaded: {type: http, url: https://example.invalid/loaded, behavior: domain, format: text}
dns:
  nameserver: [127.0.0.1:9]
  proxy-server-nameserver: [127.0.0.1:10]
  nameserver-policy:
    'before.invalid': 127.0.0.1:11
    'rule-set:missing': 127.0.0.1:12
    'rule-set:loaded': 127.0.0.1:13
    'after.invalid': 127.0.0.1:14
  proxy-server-nameserver-policy:
    'rule-set:missing': 127.0.0.1:15
rules: ['RULE-SET,loaded,DIRECT', 'MATCH,REJECT']
`
	result := partialFixture(t, body, "provider-rule", "missing")
	if result.Document == nil || len(result.Partial.RemovedSettings) != 2 || len(result.Partial.Blocked) != 0 || len(result.Partial.RemovedRules) != 0 {
		t.Fatal(result)
	}
	dns := result.Document["dns"].(map[string]any)
	encoded, _ := json.Marshal(dns)
	if strings.Contains(string(encoded), "rule-set:missing") || !strings.Contains(string(encoded), "rule-set:loaded") || !strings.Contains(string(encoded), "127.0.0.1:9") || dns["proxy-server-nameserver-policy"] != nil {
		t.Fatal(string(encoded))
	}
	positions := []int{}
	for _, key := range []string{"before.invalid", "rule-set:loaded", "after.invalid"} {
		positions = append(positions, strings.Index(string(encoded), key))
	}
	if positions[0] < 0 || positions[0] >= positions[1] || positions[1] >= positions[2] {
		t.Fatal("unaffected DNS policies changed order", string(encoded))
	}
}

func TestPartialSourceKeepsEmptyAndNullDNSPolicies(t *testing.T) {
	for _, policy := range []string{"null", "{}"} {
		body := "rule-providers: {missing: {type: http, url: https://example.invalid/missing, behavior: domain, format: text}}\ndns: {nameserver-policy: " + policy + "}\nrules: ['MATCH,REJECT']\n"
		result := partialFixture(t, body, "provider-rule", "missing")
		if result.Document == nil || len(result.Partial.RemovedSettings) != 0 {
			t.Fatal(result)
		}
		if _, present := result.Document["dns"].(map[string]any)["nameserver-policy"]; !present {
			t.Fatal("unaffected DNS field removed")
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
