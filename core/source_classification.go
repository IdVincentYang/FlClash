package main

import (
	"encoding/json"
	"errors"
	"maps"
	"net/netip"
	"net/url"
	"slices"
	"strings"

	"github.com/metacubex/mihomo/common/orderedmap"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/component/age"
	RC "github.com/metacubex/mihomo/rules/common"
)

type sourceContentSummary struct {
	Digest       string              `json:"digest"`
	Parts        map[string]string   `json:"parts"`
	NodeShapes   []string            `json:"nodeShapes"`
	NodeNames    []string            `json:"nodeNames"`
	Groups       string              `json:"groups"`
	Rules        []string            `json:"rules"`
	ProxyTargets []string            `json:"proxyTargets"`
	Filtered     bool                `json:"filtered"`
	UnsafeNodes  bool                `json:"unsafeNodes"`
	UnsafeGroups bool                `json:"unsafeGroups"`
	Details      sourceReviewDetails `json:"details"`
}

type sourceReviewDetails struct {
	Protocols     []string `json:"protocols"`
	DNS           []string `json:"dns"`
	Features      []string `json:"features"`
	Nodes         int      `json:"nodes"`
	Rules         int      `json:"rules"`
	DefaultTarget string   `json:"defaultTarget,omitempty"`
	Binary        bool     `json:"binary,omitempty"`
}

type sourceRuleSlot struct {
	Target   string   `json:"target"`
	Domains  []string `json:"domains,omitempty"`
	Prefixes []string `json:"prefixes,omitempty"`
}

type sourceRuleContract struct {
	Prefix  []string         `json:"prefix"`
	Slots   []sourceRuleSlot `json:"slots"`
	Default string           `json:"default"`
}

type sourceContentContract struct {
	Version  int                  `json:"version"`
	Base     sourceContentSummary `json:"base"`
	Rules    *sourceRuleContract  `json:"rules,omitempty"`
	Bindings []SourceUse          `json:"bindings,omitempty"`
}

func sourceValueHash(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return inputHash(encoded)
}

func decodeSourceContent(data []byte) (map[string]any, sourceContentSummary, error) {
	if len(data) == 0 || len(data) > sourceCandidateMax {
		return nil, sourceContentSummary{}, errSourceBudget
	}
	plain, err := age.DecryptBytes(data)
	if err != nil {
		return nil, sourceContentSummary{}, err
	}
	var document map[string]any
	if err := yaml.Unmarshal(plain, &document); err != nil || document == nil {
		return nil, sourceContentSummary{}, errors.New("source must be a YAML or JSON object")
	}
	if err := restoreSourcePolicyOrder(plain, document); err != nil {
		return nil, sourceContentSummary{}, err
	}
	summary, err := summarizeSourceContent(document)
	return document, summary, err
}

func restoreSourcePolicyOrder(data []byte, document map[string]any) error {
	var ordered struct {
		DNS struct {
			Main  *orderedmap.OrderedMap[string, any] `yaml:"nameserver-policy"`
			Proxy *orderedmap.OrderedMap[string, any] `yaml:"proxy-server-nameserver-policy"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(data, &ordered); err != nil {
		return errors.New("invalid source DNS policy")
	}
	if dns, ok := document["dns"].(map[string]any); ok {
		if ordered.DNS.Main != nil {
			dns["nameserver-policy"] = ordered.DNS.Main
		}
		if ordered.DNS.Proxy != nil {
			dns["proxy-server-nameserver-policy"] = ordered.DNS.Proxy
		}
	}
	return nil
}

func sourceMappings(value any) ([]map[string]any, bool) {
	if value == nil {
		return nil, true
	}
	if mappings, valid := value.([]map[string]any); valid {
		return mappings, true
	}
	values, ok := value.([]any)
	if !ok {
		return nil, false
	}
	result := make([]map[string]any, 0, len(values))
	for _, item := range values {
		mapping, ok := item.(map[string]any)
		if !ok {
			return nil, false
		}
		result = append(result, mapping)
	}
	return result, true
}

func sourceStrings(value any) ([]string, bool) {
	if value == nil {
		return nil, true
	}
	if values, valid := value.([]string); valid {
		return slices.Clone(values), true
	}
	values, ok := value.([]any)
	if !ok {
		return nil, false
	}
	result := make([]string, 0, len(values))
	for _, item := range values {
		text, ok := item.(string)
		if !ok {
			return nil, false
		}
		result = append(result, text)
	}
	return result, true
}

func summarizeSourceContent(document map[string]any) (sourceContentSummary, error) {
	summary := sourceContentSummary{Digest: sourceValueHash(document), Parts: map[string]string{}}
	if summary.Digest == "" {
		return summary, errors.New("source contains unsupported values")
	}
	nodes, ok := sourceMappings(document["proxies"])
	if !ok {
		return summary, errors.New("invalid source proxies")
	}
	nodeNames := map[string]bool{}
	nodeShapes := map[string]string{}
	nodeUDP := map[string]bool{}
	for _, node := range nodes {
		name, _ := node["name"].(string)
		kind, _ := node["type"].(string)
		if name == "" || kind == "" || nodeNames[name] {
			return summary, errors.New("source proxy names and types must be explicit and unique")
		}
		summary.Details.Protocols = append(summary.Details.Protocols, kind)
		for _, field := range []string{"udp", "plugin", "dialer-proxy", "skip-cert-verify", "certificate", "private-key"} {
			if value, present := node[field]; present && value != false && value != "" {
				summary.Details.Features = append(summary.Details.Features, field)
			}
		}
		nodeNames[name] = true
		summary.NodeNames = append(summary.NodeNames, name)
		shape := maps.Clone(node)
		for _, mutable := range []string{"name", "server", "port", "username", "password", "uuid", "alterId", "alter-id"} {
			delete(shape, mutable)
		}
		nodeShapes[name] = sourceValueHash(shape)
		summary.NodeShapes = append(summary.NodeShapes, nodeShapes[name])
		udp, _ := node["udp"].(bool)
		nodeUDP[name] = udp && slices.Contains([]string{"socks5", "ss", "ssr", "vmess", "vless", "trojan"}, strings.ToLower(kind))
		if slices.Contains([]string{"direct", "reject", "reject-drop", "pass", "pass-rule", "compatible", "rematch"}, strings.ToLower(kind)) {
			summary.UnsafeNodes = true
		}
	}
	slices.Sort(summary.NodeShapes)
	summary.NodeShapes = slices.Compact(summary.NodeShapes)
	slices.Sort(summary.NodeNames)
	groups, ok := sourceMappings(document["proxy-groups"])
	if !ok {
		return summary, errors.New("invalid source proxy groups")
	}
	groupByName := map[string]map[string]any{}
	var normalizedGroups []map[string]any
	for _, group := range groups {
		name, _ := group["name"].(string)
		if name == "" || groupByName[name] != nil || nodeNames[name] {
			return summary, errors.New("source group names must be explicit and unique")
		}
		groupByName[name] = group
		copy := maps.Clone(group)
		members, valid := sourceStrings(group["proxies"])
		if !valid {
			return summary, errors.New("invalid source group members")
		}
		for i, member := range members {
			if nodeNames[member] {
				members[i] = "\x00source-node:" + nodeShapes[member]
			}
		}
		copy["proxies"] = slices.Compact(members)
		for _, key := range []string{"filter", "exclude-filter", "exclude-type", "include-all", "include-all-proxies", "include-all-providers"} {
			if value, present := group[key]; present && value != false && value != "" {
				summary.Filtered = true
			}
		}
		normalizedGroups = append(normalizedGroups, copy)
	}
	summary.Groups = sourceValueHash(normalizedGroups)
	var proxyOnly func(string, map[string]bool, bool) bool
	proxyOnly = func(name string, seen map[string]bool, requireUDP bool) bool {
		if seen[name] || slices.Contains([]string{"DIRECT", "REJECT", "REJECT-DROP", "COMPATIBLE", "PASS", "PASS-RULE", "GLOBAL"}, name) {
			return false
		}
		if nodeNames[name] {
			return !summary.UnsafeNodes && (!requireUDP || nodeUDP[name])
		}
		group := groupByName[name]
		if group == nil || group["use"] != nil || summary.Filtered {
			return false
		}
		if value, present := group["disable-udp"]; present && requireUDP {
			if disabled, known := value.(bool); !known || disabled {
				return false
			}
		}
		kind, _ := group["type"].(string)
		if !slices.Contains([]string{"select", "url-test", "fallback", "load-balance"}, kind) {
			return false
		}
		members, valid := sourceStrings(group["proxies"])
		if !valid || len(members) == 0 {
			return false
		}
		seen = maps.Clone(seen)
		seen[name] = true
		for _, member := range members {
			if !proxyOnly(member, seen, requireUDP) {
				return false
			}
		}
		return true
	}
	for name := range nodeNames {
		if proxyOnly(name, map[string]bool{}, true) {
			summary.ProxyTargets = append(summary.ProxyTargets, name)
		}
	}
	for name := range groupByName {
		if proxyOnly(name, map[string]bool{}, true) {
			summary.ProxyTargets = append(summary.ProxyTargets, name)
		}
		if !proxyOnly(name, map[string]bool{}, false) {
			summary.UnsafeGroups = true
		}
	}
	slices.Sort(summary.ProxyTargets)
	rules, ok := sourceStrings(document["rules"])
	if !ok {
		return summary, errors.New("invalid source rules")
	}
	summary.Rules = rules
	summary.Details.Nodes, summary.Details.Rules = len(nodes), len(rules)
	if len(rules) > 0 {
		tp, _, target, _ := RC.ParseRulePayload(rules[len(rules)-1], true)
		if tp == "MATCH" {
			summary.Details.DefaultTarget = target
		}
	}
	for _, field := range []string{"dns", "rules", "listeners", "tunnels", "ntp", "external-controller", "external-controller-tls", "external-controller-unix", "external-controller-pipe"} {
		if _, present := document[field]; present {
			summary.Details.Features = append(summary.Details.Features, field)
		}
	}
	if dns, ok := document["dns"].(map[string]any); ok {
		addServers := func(value any) {
			servers, ok := sourceStrings(value)
			if single, isString := value.(string); isString {
				servers, ok = []string{single}, true
			}
			if !ok {
				return
			}
			for _, server := range servers {
				if len(summary.Details.DNS) >= 64 {
					break
				}
				if !strings.Contains(server, "://") {
					server = "udp://" + server
				}
				parsed, err := url.Parse(server)
				if err == nil && parsed.Host != "" {
					summary.Details.DNS = append(summary.Details.DNS, parsed.Scheme+"://"+parsed.Host)
				}
			}
		}
		for _, field := range []string{"nameserver", "default-nameserver", "fallback", "proxy-server-nameserver", "direct-nameserver"} {
			addServers(dns[field])
		}
		for _, field := range []string{"nameserver-policy", "proxy-server-nameserver-policy"} {
			if policy, ok := dns[field].(*orderedmap.OrderedMap[string, any]); ok {
				for pair := policy.Oldest(); pair != nil; pair = pair.Next() {
					addServers(pair.Value)
				}
			}
		}
	}
	slices.Sort(summary.Details.Protocols)
	summary.Details.Protocols = slices.Compact(summary.Details.Protocols)
	slices.Sort(summary.Details.DNS)
	summary.Details.DNS = slices.Compact(summary.Details.DNS)
	slices.Sort(summary.Details.Features)
	summary.Details.Features = slices.Compact(summary.Details.Features)
	for key, value := range document {
		if !slices.Contains([]string{"proxies", "proxy-groups", "rules"}, key) {
			summary.Parts[key] = sourceValueHash(value)
			if summary.Parts[key] == "" {
				return summary, errors.New("source contains unsupported fields")
			}
		}
	}
	return summary, nil
}

func sourceRuleWithinSlot(line string, slot sourceRuleSlot) bool {
	tp, payload, target, params := RC.ParseRulePayload(line, true)
	if target != slot.Target || target == "" {
		return false
	}
	switch tp {
	case "DOMAIN", "DOMAIN-SUFFIX":
		if len(params) != 0 || payload == "" || strings.ContainsAny(payload, "*+/,\x00\r\n\t ") {
			return false
		}
		if len(slot.Domains) == 0 && len(slot.Prefixes) == 0 {
			return true
		}
		payload = strings.ToLower(strings.TrimSuffix(payload, "."))
		for _, suffix := range slot.Domains {
			suffix = strings.ToLower(strings.TrimSuffix(suffix, "."))
			if suffix != "" && (payload == suffix || strings.HasSuffix(payload, "."+suffix)) {
				return true
			}
		}
	case "IP-CIDR", "IP-CIDR6":
		if len(params) > 1 || len(params) == 1 && params[0] != "no-resolve" {
			return false
		}
		prefix, err := netip.ParsePrefix(payload)
		if err != nil {
			return false
		}
		if len(slot.Domains) == 0 && len(slot.Prefixes) == 0 {
			return true
		}
		for _, raw := range slot.Prefixes {
			allowed, err := netip.ParsePrefix(raw)
			if err == nil && prefix.Addr().BitLen() == allowed.Addr().BitLen() && prefix.Bits() >= allowed.Bits() && allowed.Masked().Contains(prefix.Masked().Addr()) {
				return true
			}
		}
	}
	return false
}

func sourceRuleBlocks(lines []string, contract sourceRuleContract) ([][]string, bool) {
	if len(lines) < len(contract.Prefix)+1 || !slices.Equal(lines[:len(contract.Prefix)], contract.Prefix) || lines[len(lines)-1] != contract.Default || len(contract.Slots) == 0 {
		return nil, false
	}
	tp, _, target, params := RC.ParseRulePayload(contract.Default, true)
	if tp != "MATCH" || target == "" || len(params) != 0 {
		return nil, false
	}
	blocks := make([][]string, len(contract.Slots))
	index := 0
	for _, line := range lines[len(contract.Prefix) : len(lines)-1] {
		for index < len(contract.Slots) && !sourceRuleWithinSlot(line, contract.Slots[index]) {
			index++
		}
		if index == len(contract.Slots) {
			return nil, false
		}
		blocks[index] = append(blocks[index], line)
	}
	return blocks, true
}

func sourceRulesAutomaticallyAllowed(old, next sourceContentSummary, contract *sourceRuleContract) bool {
	if contract == nil {
		return false
	}
	before, ok := sourceRuleBlocks(old.Rules, *contract)
	if !ok {
		return false
	}
	after, ok := sourceRuleBlocks(next.Rules, *contract)
	if !ok {
		return false
	}
	_, _, fallback, _ := RC.ParseRulePayload(contract.Default, true)
	if fallback != "DIRECT" && fallback != "REJECT" && !slices.Contains(next.ProxyTargets, fallback) {
		return false
	}
	for i, slot := range contract.Slots {
		if !slices.Contains(next.ProxyTargets, slot.Target) {
			return false
		}
		if fallback == "DIRECT" || fallback == "REJECT" {
			kept := 0
			for _, line := range after[i] {
				if kept < len(before[i]) && before[i][kept] == line {
					kept++
				}
			}
			if kept != len(before[i]) {
				return false
			}
		}
	}
	return true
}

func classifySourceDelta(contract sourceContentContract, next sourceContentSummary) []string {
	old := contract.Base
	if contract.Version != 1 {
		return []string{"unknown_contract"}
	}
	if old.Digest == next.Digest {
		return nil
	}
	reasons := []string{}
	if next.UnsafeNodes || len(old.NodeNames) > 0 && len(next.NodeNames) == 0 {
		reasons = append(reasons, "proxy_capability_changed")
	}
	for _, shape := range next.NodeShapes {
		if !slices.Contains(old.NodeShapes, shape) {
			reasons = append(reasons, "proxy_capability_changed")
		}
	}
	if old.Groups != next.Groups || (old.Filtered || next.Filtered) && !slices.Equal(old.NodeNames, next.NodeNames) {
		reasons = append(reasons, "group_binding_changed")
	}
	if old.UnsafeGroups || next.UnsafeGroups {
		for _, name := range old.NodeNames {
			if !slices.Contains(next.NodeNames, name) {
				reasons = append(reasons, "group_binding_changed")
				break
			}
		}
	}
	for key := range old.Parts {
		if next.Parts[key] != old.Parts[key] {
			reasons = append(reasons, sourcePartReason(key))
		}
	}
	for key := range next.Parts {
		if _, existed := old.Parts[key]; !existed {
			reasons = append(reasons, sourcePartReason(key))
		}
	}
	if !slices.Equal(old.Rules, next.Rules) && !sourceRulesAutomaticallyAllowed(old, next, contract.Rules) {
		reasons = append(reasons, "ordered_routing_changed")
	}
	slices.Sort(reasons)
	return slices.Compact(reasons)
}

func proposeSourceRuleContract(summary sourceContentSummary) *sourceRuleContract {
	if len(summary.Rules) < 2 {
		return nil
	}
	contract := &sourceRuleContract{Default: summary.Rules[len(summary.Rules)-1]}
	tp, _, fallback, params := RC.ParseRulePayload(contract.Default, true)
	if tp != "MATCH" || fallback == "" || len(params) != 0 || fallback != "DIRECT" && fallback != "REJECT" && !slices.Contains(summary.ProxyTargets, fallback) {
		return nil
	}
	seen := map[string]bool{}
	for _, line := range summary.Rules[:len(summary.Rules)-1] {
		_, _, target, _ := RC.ParseRulePayload(line, true)
		if len(contract.Slots) == 0 && (target == "DIRECT" || target == "REJECT") && sourceRuleWithinSlot(line, sourceRuleSlot{Target: target}) {
			contract.Prefix = append(contract.Prefix, line)
			continue
		}
		if !slices.Contains(summary.ProxyTargets, target) || !sourceRuleWithinSlot(line, sourceRuleSlot{Target: target}) {
			return nil
		}
		if len(contract.Slots) == 0 || contract.Slots[len(contract.Slots)-1].Target != target {
			if seen[target] {
				return nil
			}
			seen[target] = true
			contract.Slots = append(contract.Slots, sourceRuleSlot{Target: target})
		}
	}
	if len(contract.Slots) == 0 || !sourceRulesAutomaticallyAllowed(summary, summary, contract) {
		return nil
	}
	return contract
}

func sourcePartReason(key string) string {
	switch key {
	case "dns":
		return "dns_changed"
	case "mode", "sub-rules", "rule-providers":
		return "routing_changed"
	case "proxy-providers":
		return "provider_source_changed"
	case "listeners", "tunnels", "tun", "external-controller", "external-controller-tls", "external-controller-unix", "external-controller-pipe":
		return "entry_or_control_changed"
	default:
		return "unclassified_effective_field_changed"
	}
}
