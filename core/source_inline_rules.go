package main

import (
	"slices"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	R "github.com/metacubex/mihomo/rules"
	RC "github.com/metacubex/mihomo/rules/common"
	RW "github.com/metacubex/mihomo/rules/wrapper"
)

func prepareSourceInlineRules(p *preparedConfig, old, next *config.RawConfig, ledger *SourceRuleLedger) ([]C.Rule, error) {
	if len(old.SubRules) != 0 || len(next.SubRules) != 0 || len(p.cfg.RuleProviders) != 0 {
		return nil, errSourceForeground
	}
	summary := func(raw *config.RawConfig) (sourceContentSummary, error) {
		return summarizeSourceContent(map[string]any{"proxies": raw.Proxy, "proxy-groups": raw.ProxyGroup, "rules": raw.Rule})
	}
	before, err := summary(old)
	if err != nil {
		return nil, err
	}
	after, err := summary(next)
	if err != nil {
		return nil, err
	}
	contract := proposeSourceRuleContract(before)
	if !sourceRulesAutomaticallyAllowed(before, after, contract) {
		return nil, errSourceForeground
	}
	targets := []string{}
	for _, slot := range contract.Slots {
		targets = append(targets, slot.Target)
	}
	_, _, fallback, _ := RC.ParseRulePayload(contract.Default, true)
	if !slices.Contains([]string{"DIRECT", "REJECT"}, fallback) {
		targets = append(targets, fallback)
	}
	for _, target := range targets {
		proxy := p.cfg.Proxies[target]
		if proxy == nil || !proxy.SupportUDP() {
			return nil, errSourceForeground
		}
	}
	rules := make([]C.Rule, 0, len(next.Rule))
	for _, line := range next.Rule {
		kind, payload, target, params := RC.ParseRulePayload(line, true)
		if p.cfg.Proxies[target] == nil || !slices.Contains([]string{"DOMAIN", "DOMAIN-SUFFIX", "IP-CIDR", "IP-CIDR6", "MATCH"}, kind) {
			return nil, errSourceForeground
		}
		rule, err := R.ParseRule(kind, payload, target, params, nil)
		if err != nil {
			return nil, err
		}
		rules = append(rules, RW.NewRuleWrapper(rule))
	}
	return sourceTracedRules(p, rules, ledger), nil
}
