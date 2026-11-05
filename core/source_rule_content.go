package main

import (
	"strings"
	"unicode/utf8"

	P "github.com/metacubex/mihomo/constant/provider"
)

func summarizeSourceRuleContent(body []byte, format, behavior string) (sourceContentSummary, error) {
	if _, err := P.ParseBehavior(behavior); err != nil {
		return sourceContentSummary{}, errSourceReview
	}
	parsedFormat, err := P.ParseRuleFormat(format)
	if err != nil {
		return sourceContentSummary{}, errSourceReview
	}
	if format == "" {
		format = "yaml"
	}
	summary := sourceContentSummary{
		Digest: sourceValueHash([]string{format, behavior, inputHash(body)}),
		Parts: map[string]string{
			"rule-provider-format":  sourceValueHash([]string{format, behavior}),
			"rule-provider-content": inputHash(body),
		},
		Details: sourceReviewDetails{Features: []string{format, behavior}, Binary: parsedFormat == P.MrsRule},
	}
	if parsedFormat == P.MrsRule {
		if behavior == "classical" {
			return sourceContentSummary{}, errSourceReview
		}
		return summary, nil
	}
	if !utf8.Valid(body) {
		return sourceContentSummary{}, errSourceReview
	}
	if parsedFormat == P.YamlRule {
		document, _, err := decodeSourceContent(body)
		if err != nil {
			return sourceContentSummary{}, err
		}
		var valid bool
		summary.Rules, valid = sourceStrings(document["payload"])
		if document["payload"] == nil {
			summary.Rules, valid = sourceStrings(document["rules"])
		}
		if !valid {
			return sourceContentSummary{}, errSourceReview
		}
	} else {
		for _, line := range strings.Split(string(body), "\n") {
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") {
				summary.Rules = append(summary.Rules, line)
			}
		}
	}
	summary.Details.Rules = len(summary.Rules)
	return summary, nil
}
