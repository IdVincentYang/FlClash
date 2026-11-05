package main

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/metacubex/mihomo/common/orderedmap"
	RC "github.com/metacubex/mihomo/rules/common"
)

func validateOwnRoutingInput(document map[string]any, key string) error {
	for _, field := range []string{"listeners", "tunnels", "sub-rules"} {
		if value := document[field]; value != nil && sourceValueHash(value) != sourceValueHash([]any{}) && sourceValueHash(value) != sourceValueHash(map[string]any{}) {
			return errSourceRoutingDenied
		}
	}
	rules, valid := sourceStrings(document["rules"])
	if !valid || len(rules) == 0 {
		return errSourceRoutingDenied
	}
	for i, line := range rules {
		tp, _, target, _ := RC.ParseRulePayload(line, true)
		if strings.Contains(strings.ToUpper(line), "RULE-SET") && strings.Contains(line, "@source-") {
			return errSourceRoutingDenied
		}
		if tp == "MATCH" {
			if i != len(rules)-1 || target == "" || target == "PASS" || target == "REMATCH" || target == "COMPATIBLE" {
				return errSourceRoutingDenied
			}
		} else if i == len(rules)-1 {
			return errSourceRoutingDenied
		}
	}
	_, err := sourceRoutingProjection(document, key)
	return err
}

func sourceRoutingProjection(document map[string]any, key string) (map[string]any, error) {
	data, err := json.Marshal(document)
	if err != nil {
		return nil, errSourceReview
	}
	var projected map[string]any
	if json.Unmarshal(data, &projected) != nil {
		return nil, errSourceReview
	}
	if err := restoreSourcePolicyOrder(data, projected); err != nil {
		return nil, err
	}
	for _, entry := range []string{"rules", "sub-rules", "listeners", "tunnels"} {
		delete(projected, entry)
	}
	checkNodes := func(value any) error {
		proxies, valid := sourceMappings(value)
		if !valid {
			return errSourceReview
		}
		for _, proxy := range proxies {
			kind, _ := proxy["type"].(string)
			if strings.EqualFold(kind, "rematch") {
				return errSourceRoutingDenied
			}
		}
		return nil
	}
	if err := checkNodes(projected["proxies"]); err != nil {
		return nil, err
	}
	if providers, ok := projected["proxy-providers"].(map[string]any); ok {
		for _, value := range providers {
			if declaration, ok := value.(map[string]any); ok {
				if payload, present := declaration["payload"]; present {
					body, err := json.Marshal(map[string]any{"proxies": payload})
					if err != nil {
						return nil, err
					}
					effective, err := sourceProviderProxyDocument(body, declaration)
					if err != nil {
						return nil, err
					}
					if err := checkNodes(effective["proxies"]); err != nil {
						return nil, err
					}
				}
			}
		}
	}
	if groups, valid := sourceMappings(projected["proxy-groups"]); valid {
		for _, group := range groups {
			members, _ := sourceStrings(group["proxies"])
			for _, member := range members {
				if member == "PASS" || member == "PASS-RULE" || member == "COMPATIBLE" {
					return nil, errSourceRoutingDenied
				}
			}
		}
	}
	providers, _ := projected["rule-providers"].(map[string]any)
	kept := map[string]any{}
	bind := func(name string) (string, error) {
		declaration, exists := providers[name]
		if !exists || name == "" || strings.ContainsAny(name, ":,\x00\r\n\t ") {
			return "", errors.New("independent DNS or sniffer rule set must have an explicit source binding")
		}
		internal := "@source-" + inputHash([]byte(key + "\x00" + name))[:24]
		kept[internal] = declaration
		return internal, nil
	}
	rewriteDomain := func(value string) (string, error) {
		if !strings.HasPrefix(strings.ToLower(value), "rule-set:") {
			return value, nil
		}
		if strings.Count(value, ":") != 1 {
			return "", errSourceReview
		}
		names := strings.Split(value[len("rule-set:"):], ",")
		for i, name := range names {
			bound, err := bind(name)
			if err != nil {
				return "", err
			}
			names[i] = bound
		}
		return "rule-set:" + strings.Join(names, ","), nil
	}
	rewriteList := func(mapping map[string]any, field string, rules bool) error {
		original, exists := mapping[field]
		if !exists {
			return nil
		}
		items, ok := sourceStrings(original)
		if !ok {
			return errSourceReview
		}
		result := make([]any, len(items))
		for i, value := range items {
			var err error
			if rules {
				tp, payload, target, params := RC.ParseRulePayload(value, true)
				if tp == "RULE-SET" {
					payload, err = bind(payload)
					value = strings.Join(append([]string{tp, payload, target}, params...), ",")
				} else if strings.Contains(strings.ToUpper(value), "RULE-SET") {
					return errors.New("nested source rule set references require an explicit independent binding")
				}
			} else {
				value, err = rewriteDomain(value)
			}
			if err != nil {
				return err
			}
			result[i] = value
		}
		mapping[field] = result
		return nil
	}
	if dns, ok := projected["dns"].(map[string]any); ok {
		for _, field := range []string{"nameserver-policy", "proxy-server-nameserver-policy"} {
			if original, exists := dns[field]; exists {
				policy, ok := original.(*orderedmap.OrderedMap[string, any])
				if !ok {
					return nil, errSourceReview
				}
				rewritten := orderedmap.New[string, any]()
				for pair := policy.Oldest(); pair != nil; pair = pair.Next() {
					bound, err := rewriteDomain(pair.Key)
					if err != nil {
						return nil, err
					}
					rewritten.Set(bound, pair.Value)
				}
				dns[field] = rewritten
			}
		}
		rules := dns["fake-ip-filter-mode"] == "rule"
		if err := rewriteList(dns, "fake-ip-filter", rules); err != nil {
			return nil, err
		}
		if filter, ok := dns["fallback-filter"].(map[string]any); ok {
			if err := rewriteList(filter, "domain", false); err != nil {
				return nil, err
			}
		}
	}
	if sniffer, ok := projected["sniffer"].(map[string]any); ok {
		for _, field := range []string{"force-domain", "skip-domain", "skip-src-address", "skip-dst-address"} {
			if err := rewriteList(sniffer, field, false); err != nil {
				return nil, err
			}
		}
	}
	if len(kept) == 0 {
		delete(projected, "rule-providers")
	} else {
		projected["rule-providers"] = kept
	}
	return projected, nil
}
