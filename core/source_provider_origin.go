package main

import (
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	C "github.com/metacubex/mihomo/constant"
)

type sourceProviderOrigin struct {
	Key      string      `json:"key"`
	Identity string      `json:"identity"`
	Uses     []SourceUse `json:"uses"`
}

func sourceProviderOriginKey(home, kind string, mapping map[string]any, uses []SourceUse) (string, error) {
	path, _ := mapping["path"].(string)
	if path == "" {
		return "", nil
	}
	if !filepath.IsAbs(path) {
		path = filepath.Join(home, path)
	}
	path = filepath.Clean(path)
	if filepath.Dir(path) == filepath.Join(home, "profiles") {
		id := strings.TrimSuffix(filepath.Base(path), ".yaml")
		if _, err := strconv.ParseInt(id, 10, 64); err != nil || kind != "provider-proxy" || filepath.Base(path) != id+".yaml" {
			return "", errSourceReview
		}
		return "profile:" + id, nil
	}
	directory := "proxies"
	if kind == "provider-rule" {
		directory = "rules"
	}
	if filepath.Dir(path) != filepath.Join(home, "providers", directory) {
		return "", nil
	}
	url, _ := mapping["url"].(string)
	for _, use := range uses {
		if !strings.HasPrefix(use.Key, "clash-provider:") || use.Kind != kind {
			continue
		}
		id := strings.TrimPrefix(use.Key, "clash-provider:")
		hash := md5.Sum([]byte(id + "@" + url))
		if filepath.Base(path) == hex.EncodeToString(hash[:]) {
			return use.Key, nil
		}
	}
	return "", errSourceReview
}

func sourceProviderOriginSummary(body []byte, kind string, mapping map[string]any) (sourceContentSummary, error) {
	if kind == "provider-rule" {
		format, _ := mapping["format"].(string)
		behavior, _ := mapping["behavior"].(string)
		return summarizeSourceRuleContent(body, format, behavior)
	}
	document, err := sourceProviderProxyDocument(body, nil)
	if err != nil {
		return sourceContentSummary{}, err
	}
	return summarizeSourceProviderProxy(document, nil)
}

func validateSourceProviderOrigin(home string, permissions *sourcePermissions, material SourceProviderMaterial, mapping map[string]any, uses []SourceUse, body []byte) error {
	key, err := sourceProviderOriginKey(home, material.Kind, mapping, uses)
	if err != nil {
		return err
	}
	if key == "" {
		if material.Origin != (SourceUse{}) {
			return errSourceReview
		}
		return nil
	}
	if material.Origin.Key != key || material.Origin.Kind != material.Kind || !slices.Contains(uses, material.Origin) || !sourceUseAllowed(permissions, material.Origin) {
		return errSourceReview
	}
	summary, err := sourceProviderOriginSummary(body, material.Kind, mapping)
	if err != nil || summary.Digest != material.Origin.Digest {
		return errSourceReview
	}
	return nil
}

func sourceBindingIdentities(uses []SourceUse) []SourceUse {
	result := []SourceUse{}
	for _, use := range uses {
		if strings.HasPrefix(use.Key, "provider-proxy:") || strings.HasPrefix(use.Key, "provider-rule:") {
			continue
		}
		use.Digest = ""
		result = append(result, use)
	}
	return canonicalSourceUses(result)
}

func sourceCompositionUses(home string, root SourceUse) ([]SourceUse, error) {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return nil, err
	}
	if root.Kind != "config" || !sourceUseAllowed(permissions, root) {
		return nil, errSourceUseRevoked
	}
	uses := slices.Clone(permissions.Grants[root.Key].Purposes[root.Kind].BoundUses[root.Digest])
	return canonicalSourceUses(append(uses, root)), nil
}

func (r *sourceProviderRuntime) reviewOrigin(body []byte) (SourceUse, error) {
	if r.plan.Origin == nil {
		return SourceUse{}, nil
	}
	request := sourceAcceptanceRequest{Action: "review", Key: r.plan.Origin.Key, Kind: r.plan.Kind, Identity: r.plan.Origin.Identity, Settings: sourceValueHash(r.plan.Mapping)}
	request.BodyBase64 = base64.StdEncoding.EncodeToString(body)
	request.Format, _ = r.plan.Mapping["format"].(string)
	request.Behavior, _ = r.plan.Mapping["behavior"].(string)
	accepted, err := sourceAcceptance(C.Path.HomeDir(), request)
	if err != nil {
		return SourceUse{}, err
	}
	if accepted.Status != "accepted" || accepted.Use == nil {
		return SourceUse{}, errSourceReview
	}
	return *accepted.Use, nil
}
