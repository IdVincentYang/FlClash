package main

import (
	"encoding/base64"
	"errors"
	"strings"

	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/config"
)

func previewSourceProviderPlans(home, body, key string, origins []SourceUse) ([]sourceProviderPlan, error) {
	if !strings.HasPrefix(key, "profile:") || len(body) > sourceCandidateMax {
		return nil, errSourceReview
	}
	plans, err := sourceProviderPlans([]byte(body), []SourceUse{{Key: key, Kind: "profile"}}, key)
	if err != nil {
		return nil, err
	}
	for i := range plans {
		origin, err := sourceProviderOriginKey(home, plans[i].Kind, plans[i].Mapping, origins)
		if err != nil {
			return nil, err
		}
		if origin != "" {
			plans[i].Origin = &sourceProviderOrigin{Key: origin}
		}
	}
	return plans, nil
}

func previewSourceReview(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if len(request.Preview) > sourceCandidateMax {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	body := []byte(request.Body)
	if request.BodyBase64 != "" {
		if request.Body != "" || len(request.BodyBase64) > base64.StdEncoding.EncodedLen(sourceCandidateMax) {
			return sourceAcceptanceResult{}, errSourceBudget
		}
		var err error
		body, err = base64.StdEncoding.DecodeString(request.BodyBase64)
		if err != nil {
			return sourceAcceptanceResult{}, errSourceReview
		}
	}
	if len(body) == 0 || len(body) > sourceCandidateMax {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	var summary sourceContentSummary
	var document map[string]any
	var err error
	switch request.Kind {
	case "provider-rule":
		summary, err = summarizeSourceRuleContent(body, request.Format, request.Behavior)
	case "provider-proxy":
		document, err = sourceProviderProxyDocument(body, request.Provider)
		var context *config.RawConfig
		if err == nil && request.Preview != "" {
			context, err = config.UnmarshalRawConfig([]byte(request.Preview))
		}
		if err == nil {
			summary, err = summarizeSourceProviderProxy(document, context)
		}
	case "profile", "config":
		document, summary, err = decodeSourceContent(body)
		if err == nil && request.Routing == "own" {
			document, err = sourceRoutingProjection(document, request.Key)
			if err == nil {
				summary, err = summarizeSourceContent(document)
			}
		}
	default:
		err = errors.New("unsupported source review preview")
	}
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	result := sourceAcceptanceResult{Status: "preview", Document: document, Details: &summary.Details, MaterialHash: inputHash(body)}
	if request.Kind == "config" {
		if request.Parent == nil {
			return sourceAcceptanceResult{}, errSourceReview
		}
		encoded, err := yaml.Marshal(document)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		result.Providers, err = previewSourceProviderPlans(home, string(encoded), request.Parent.Key, request.Uses)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
	}
	return result, nil
}
