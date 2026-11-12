package main

import (
	"strings"

	"github.com/metacubex/mihomo/common/orderedmap"
	C "github.com/metacubex/mihomo/constant"
	RC "github.com/metacubex/mihomo/rules/common"
	"github.com/metacubex/mihomo/rules/logic"
)

func partialRuleUsesMissing(kind, payload string, missing map[string]bool) (bool, error) {
	if len(missing) == 0 || !strings.Contains(strings.ToUpper(kind+","+payload), "RULE-SET") {
		return false, nil
	}
	used, depth := false, 0
	var visit RC.ParseRuleFunc
	visit = func(kind, payload, target string, _ []string, _ map[string][]C.Rule) (C.Rule, error) {
		depth++
		defer func() { depth-- }()
		if depth > 128 {
			return nil, errSourceBudget
		}
		switch kind {
		case "RULE-SET":
			used = used || missing[payload]
		case "AND":
			return logic.NewAND(payload, target, visit)
		case "OR":
			return logic.NewOR(payload, target, visit)
		case "NOT":
			return logic.NewNOT(payload, target, visit)
		case "SUB-RULE":
			return logic.NewSubRule(payload, target, nil, visit)
		}
		// Leaves only drive the native logical parser; this tree is never installed.
		return RC.NewMatch(target), nil
	}
	_, err := visit(kind, payload, "", nil, nil)
	return used, err
}

func omitMissingSourceDNSPolicies(document map[string]any, missing map[string]bool, changes *sourcePartialConfiguration) error {
	dns, ok := document["dns"].(map[string]any)
	if !ok {
		return nil
	}
	for _, field := range []string{"nameserver-policy", "proxy-server-nameserver-policy"} {
		original, exists := dns[field]
		if !exists || original == nil {
			continue
		}
		policy, ok := original.(*orderedmap.OrderedMap[string, any])
		if !ok {
			return errSourceReview
		}
		kept := orderedmap.New[string, any]()
		for pair := policy.Oldest(); pair != nil; pair = pair.Next() {
			if partialSourceHasMissingReference(pair.Key, missing, nil) {
				changes.RemovedSettings = append(changes.RemovedSettings, "dns."+field+"["+pair.Key+"]")
			} else {
				kept.Set(pair.Key, pair.Value)
			}
		}
		if kept.Len() == policy.Len() {
			continue
		}
		if kept.Len() == 0 {
			delete(dns, field)
		} else {
			dns[field] = kept
		}
	}
	return nil
}
