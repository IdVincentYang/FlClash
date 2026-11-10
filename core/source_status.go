package main

import (
	"slices"
	"strings"
)

func sourceSubscriptionStatus(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if request.Kind != "profile" || !strings.HasPrefix(request.Key, "profile:") || request.ForceReview || request.Fresh {
		return sourceAcceptanceResult{}, errSourceReview
	}
	result, err := reviewSourceCandidate(home, request)
	if err != nil || result.Status == "reviewRequired" {
		return result, err
	}
	configuration := "config:" + strings.TrimPrefix(request.Key, "profile:")
	for _, candidate := range pendingSourceReviews {
		r := candidate.request
		related := r.Key == request.Key || r.Key == configuration || r.Parent != nil && r.Parent.Key == request.Key || slices.ContainsFunc(r.Uses, func(use SourceUse) bool {
			return use.Key == request.Key && use.Kind == "profile"
		})
		if related && sourceAcceptanceCurrent(r) {
			return sourceAcceptanceResult{Status: "reviewRequired"}, nil
		}
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	grant := permissions.Grants[configuration]
	if grant != nil {
		purpose := grant.Purposes["config"]
		if purpose != nil {
			digests := purpose.Accepted
			if bundle := purpose.ReviewBundle; bundle != nil {
				digests = []string{bundle.Bound.Digest}
			}
			for _, digest := range digests {
				dependencies := purpose.BoundUses[digest]
				root := slices.ContainsFunc(dependencies, func(use SourceUse) bool {
					return use.Kind == "profile" && use.Key == request.Key
				})
				if root && sourceUseAllowed(permissions, sourceUseReceipt(configuration, "config", digest, grant)) {
					return sourceAcceptanceResult{Status: "accepted"}, nil
				}
			}
		}
	}
	return sourceAcceptanceResult{Status: "reviewRequired"}, nil
}
