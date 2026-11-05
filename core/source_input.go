package main

import (
	"cmp"
	"errors"
	"slices"
	"strconv"
	"strings"
)

func canonicalSourceUses(uses []SourceUse) []SourceUse {
	result := slices.Clone(uses)
	slices.SortFunc(result, func(a, b SourceUse) int {
		for _, order := range []int{cmp.Compare(a.Key, b.Key), cmp.Compare(a.Kind, b.Kind), cmp.Compare(a.Incarnation, b.Incarnation), cmp.Compare(a.Epoch, b.Epoch), cmp.Compare(a.PurposeEpoch, b.PurposeEpoch), cmp.Compare(a.Digest, b.Digest)} {
			if order != 0 {
				return order
			}
		}
		return 0
	})
	return slices.Compact(result)
}

func sourceCompositionDigest(content string, uses []SourceUse) string {
	return sourceValueHash(struct {
		Content string      `json:"content"`
		Uses    []SourceUse `json:"uses"`
	}{content, canonicalSourceUses(uses)})
}

func sourceReviewUseDigest(request sourceAcceptanceRequest, summary sourceContentSummary) string {
	if request.Kind == "config" {
		return sourceCompositionDigest(summary.Digest, request.Uses)
	}
	return summary.Digest
}

func validateInputSourceUses(home string, manifest ConfigManifest, body []byte) error {
	if len(manifest.SourceUses) == 0 {
		return errors.New("source acceptance is required; open the frontend to review this configuration")
	}
	document, summary, err := decodeSourceContent(body)
	if err != nil {
		return err
	}
	root := false
	if manifest.ProfileID == nil {
		return errors.New("accepted source input must identify its profile")
	}
	rootKey := "config:" + strconv.FormatInt(*manifest.ProfileID, 10)
	profileKey := "profile:" + strconv.FormatInt(*manifest.ProfileID, 10)
	if !slices.Contains(manifest.Dependencies, profileKey) || !slices.Contains(manifest.Dependencies, "application-config") || !slices.ContainsFunc(manifest.SourceUses, func(use SourceUse) bool { return use.Key == profileKey && use.Kind == "profile" }) {
		return errors.New("final configuration lacks its profile and application source bindings")
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	dependencies := []SourceUse{}
	for _, use := range manifest.SourceUses {
		if use.Kind != "config" {
			dependencies = append(dependencies, use)
		}
	}
	dependencies = canonicalSourceUses(dependencies)
	expectedRootDigest := sourceCompositionDigest(summary.Digest, dependencies)
	for _, use := range manifest.SourceUses {
		if !sourceUseAllowed(permissions, use) {
			return errSourceUseRevoked
		}
		if use.Key == profileKey && use.Kind == "profile" && permissions.Grants[use.Key].Routing == "own" {
			if err := validateOwnRoutingInput(document, profileKey); err != nil {
				return err
			}
		}
		if use.Kind == "config" && use.Key == rootKey && use.Digest == expectedRootDigest {
			if root || !slices.Equal(canonicalSourceUses(permissions.Grants[use.Key].Purposes[use.Kind].BoundUses[use.Digest]), dependencies) {
				return errors.New("configuration source bindings differ from the accepted composition")
			}
			root = true
		} else if use.Kind == "config" {
			return errSourceReview
		}
	}
	if !root {
		return errors.New("final configuration differs from the accepted source composition")
	}
	for _, key := range manifest.Dependencies {
		if !strings.HasPrefix(key, "profile:") && !strings.HasPrefix(key, "script:") && !strings.HasPrefix(key, "clash-provider:") {
			continue
		}
		bound := false
		for _, use := range manifest.SourceUses {
			if use.Key == key && (key != "profile:"+strconv.FormatInt(*manifest.ProfileID, 10) || use.Kind == "profile") {
				bound = true
				break
			}
		}
		if !bound {
			return errors.New("configuration material lacks an accepted source binding")
		}
	}
	return nil
}
