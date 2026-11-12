package main

import (
	"encoding/json"
	"slices"
	"strings"

	"github.com/metacubex/mihomo/config"
	RC "github.com/metacubex/mihomo/rules/common"
)

type sourcePartialConfiguration struct {
	Missing         []string `json:"missing"`
	RemovedRules    []string `json:"removedRules"`
	RemovedGroups   []string `json:"removedGroups"`
	RemovedSettings []string `json:"removedSettings"`
	Blocked         []string `json:"blocked"`
	DefaultTarget   string   `json:"defaultTarget"`
}

func previewPartialSourceConfiguration(request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if request.Kind != "profile" || len(request.MissingProviders) == 0 || len(request.MissingProviders) > 256 {
		return sourceAcceptanceResult{}, errSourceReview
	}
	document, _, err := decodeSourceContent([]byte(request.Body))
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	changes := &sourcePartialConfiguration{}
	result := sourceAcceptanceResult{Status: "partial", Partial: changes}
	missingRules, missingProxies := map[string]bool{}, map[string]bool{}
	for _, provider := range request.MissingProviders {
		field := "rule-providers"
		missing := missingRules
		if provider.Kind == "provider-proxy" {
			field, missing = "proxy-providers", missingProxies
		} else if provider.Kind != "provider-rule" {
			return sourceAcceptanceResult{}, errSourceReview
		}
		declarations, ok := document[field].(map[string]any)
		if !ok || declarations[provider.Name] == nil || provider.Name == "" {
			changes.Blocked = append(changes.Blocked, field+":"+provider.Name)
			continue
		}
		changes.Missing = append(changes.Missing, provider.Name)
		missing[provider.Name] = true
		delete(declarations, provider.Name)
	}
	groups, valid := sourceMappings(document["proxy-groups"])
	if !valid {
		return sourceAcceptanceResult{}, errSourceReview
	}
	removed := map[string]bool{}
	inlineNodes, valid := sourceMappings(document["proxies"])
	if !valid {
		return sourceAcceptanceResult{}, errSourceReview
	}
	providers, _ := document["proxy-providers"].(map[string]any)
	known := map[string]bool{"DIRECT": true, "REJECT": true, "REJECT-DROP": true, "PASS": true, "GLOBAL": true, "COMPATIBLE": true}
	for _, name := range request.Names {
		known[name] = true
	}
	for _, node := range inlineNodes {
		known[node["name"].(string)] = true
	}
	for _, group := range groups {
		known[group["name"].(string)] = true
	}
	for changed := true; changed; {
		changed = false
		for _, group := range groups {
			name, _ := group["name"].(string)
			if removed[name] {
				continue
			}
			uses, useOK := sourceStrings(group["use"])
			members, memberOK := sourceStrings(group["proxies"])
			if !useOK || !memberOK {
				return sourceAcceptanceResult{}, errSourceReview
			}
			nextUses := slices.DeleteFunc(slices.Clone(uses), func(name string) bool { return missingProxies[name] })
			nextMembers := slices.DeleteFunc(slices.Clone(members), func(name string) bool { return removed[name] })
			includesProviders := group["include-all"] == true || group["include-all-providers"] == true
			lostIncluded := includesProviders && len(missingProxies) != 0 && len(providers) == 0
			if len(nextUses) == len(uses) && len(nextMembers) == len(members) && !lostIncluded {
				continue
			}
			group["use"], group["proxies"] = nextUses, nextMembers
			for _, field := range []string{"filter", "exclude-filter", "exclude-type"} {
				if value, present := group[field]; present && value != nil && value != "" {
					changes.Blocked = append(changes.Blocked, "proxy-groups:"+name)
				}
			}
			hasIncluded := includesProviders && len(providers) != 0 || (group["include-all"] == true || group["include-all-proxies"] == true) && len(inlineNodes) != 0
			if len(nextUses)+len(nextMembers) == 0 && !hasIncluded {
				removed[name] = true
				changes.RemovedGroups = append(changes.RemovedGroups, name)
				changed = true
			}
		}
	}
	keptGroups := make([]any, 0, len(groups))
	for _, group := range groups {
		if !removed[group["name"].(string)] {
			members, _ := sourceStrings(group["proxies"])
			for _, member := range members {
				if len(missingProxies) != 0 && !known[member] {
					changes.Blocked = append(changes.Blocked, "proxy-groups:"+group["name"].(string))
				}
			}
			keptGroups = append(keptGroups, group)
		}
	}
	document["proxy-groups"] = keptGroups
	if value := document["sub-rules"]; value != nil && sourceValueHash(value) != sourceValueHash(map[string]any{}) {
		changes.Blocked = append(changes.Blocked, "sub-rules")
	}
	rules, valid := sourceStrings(document["rules"])
	if !valid {
		return sourceAcceptanceResult{}, errSourceReview
	}
	keptRules := make([]any, 0, len(rules))
	for index, rule := range rules {
		kind, payload, target, _ := RC.ParseRulePayload(rule, true)
		missing, parseError := partialRuleUsesMissing(kind, payload, missingRules)
		unavailable := removed[target] || missing
		if parseError != nil {
			changes.Blocked = append(changes.Blocked, rule)
		}
		if kind == "MATCH" {
			if index != len(rules)-1 || unavailable || target == "" || len(missingProxies) != 0 && !known[target] || slices.Contains([]string{"PASS", "PASS-RULE", "COMPATIBLE", "REMATCH"}, target) {
				changes.Blocked = append(changes.Blocked, "rules:MATCH")
			} else {
				changes.DefaultTarget = target
			}
		}
		if unavailable {
			changes.RemovedRules = append(changes.RemovedRules, rule)
		} else {
			keptRules = append(keptRules, rule)
		}
	}
	if len(keptRules) == 0 {
		changes.Blocked = append(changes.Blocked, "rules:MATCH")
	} else if kind, _, _, _ := RC.ParseRulePayload(keptRules[len(keptRules)-1].(string), true); kind != "MATCH" {
		changes.Blocked = append(changes.Blocked, "rules:MATCH")
	}
	document["rules"] = keptRules
	if err := omitMissingSourceDNSPolicies(document, missingRules, changes); err != nil {
		return sourceAcceptanceResult{}, err
	}
	for field, value := range document {
		if slices.Contains([]string{"rules", "sub-rules"}, field) {
			continue
		}
		encoded, err := json.Marshal(value)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		var plain any
		if json.Unmarshal(encoded, &plain) != nil {
			return sourceAcceptanceResult{}, errSourceReview
		}
		if partialSourceHasMissingReference(plain, missingRules, removed) {
			changes.Blocked = append(changes.Blocked, field)
		}
	}
	slices.Sort(changes.Blocked)
	changes.Blocked = slices.Compact(changes.Blocked)
	if len(changes.Blocked) != 0 {
		return result, nil
	}
	encoded, err := json.Marshal(document)
	if err != nil || len(encoded) > sourceCandidateMax {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	if _, err := config.UnmarshalRawConfig(encoded); err != nil {
		return sourceAcceptanceResult{}, err
	}
	result.Document = document
	return result, nil
}

func partialSourceHasMissingReference(value any, rules, proxies map[string]bool) bool {
	switch value := value.(type) {
	case string:
		if proxies[value] {
			return true
		}
		if strings.HasPrefix(strings.ToLower(value), "rule-set:") {
			for _, name := range strings.Split(value[len("rule-set:"):], ",") {
				if rules[strings.TrimSpace(name)] {
					return true
				}
			}
		}
		kind, payload, _, _ := RC.ParseRulePayload(value, true)
		if missing, err := partialRuleUsesMissing(kind, payload, rules); missing || err != nil {
			return true
		}
		if strings.Contains(value, "#") {
			for _, part := range strings.Split(strings.SplitN(value, "#", 2)[1], "&") {
				if proxies[part] {
					return true
				}
			}
		}
	case []any:
		for _, item := range value {
			if partialSourceHasMissingReference(item, rules, proxies) {
				return true
			}
		}
	case map[string]any:
		for key, item := range value {
			if partialSourceHasMissingReference(key, rules, proxies) || partialSourceHasMissingReference(item, rules, proxies) {
				return true
			}
		}
	}
	return false
}
