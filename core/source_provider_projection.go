package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/dlclark/regexp2"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/common/structure"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/config"
)

type sourceProxyOverride struct {
	TFO            *bool   `provider:"tfo,omitempty"`
	MPTCP          *bool   `provider:"mptcp,omitempty"`
	UDP            *bool   `provider:"udp,omitempty"`
	UDPOverTCP     *bool   `provider:"udp-over-tcp,omitempty"`
	Up             *string `provider:"up,omitempty"`
	Down           *string `provider:"down,omitempty"`
	DialerProxy    *string `provider:"dialer-proxy,omitempty"`
	SkipCertVerify *bool   `provider:"skip-cert-verify,omitempty"`
	NameCertVerify *string `provider:"name-cert-verify,omitempty"`
	Interface      *string `provider:"interface-name,omitempty"`
	RoutingMark    *int    `provider:"routing-mark,omitempty"`
	IPVersion      *string `provider:"ip-version,omitempty"`
	Prefix         *string `provider:"additional-prefix,omitempty"`
	Suffix         *string `provider:"additional-suffix,omitempty"`
	Names          []struct {
		Pattern *regexp2.Regexp `provider:"pattern"`
		Target  string          `provider:"target"`
	} `provider:"proxy-name,omitempty"`
	Expressions []provider.OverrideExpr `provider:"override-expr,omitempty"`
}

func summarizeSourceProviderProxy(document map[string]any, parent *config.RawConfig) (sourceContentSummary, error) {
	summary, err := summarizeSourceContent(document)
	if err != nil || parent == nil {
		return summary, err
	}
	context := sourceValueHash(struct {
		Groups   []map[string]any    `json:"groups"`
		Rules    []string            `json:"rules"`
		SubRules map[string][]string `json:"subRules"`
	}{parent.ProxyGroup, parent.Rule, parent.SubRules})
	summary.Parts["provider-context"] = context
	summary.Digest = sourceValueHash([]string{summary.Digest, context})
	for _, group := range parent.ProxyGroup {
		for _, field := range []string{"filter", "exclude-filter", "exclude-type", "include-all", "include-all-proxies", "include-all-providers"} {
			if value := group[field]; value != nil && value != false && value != "" {
				summary.Filtered = true
			}
		}
	}
	return summary, nil
}

func (o *sourceProxyOverride) apply(mapping map[string]any) error {
	for key, value := range map[string]*bool{"tfo": o.TFO, "mptcp": o.MPTCP, "udp": o.UDP, "udp-over-tcp": o.UDPOverTCP, "skip-cert-verify": o.SkipCertVerify} {
		if value != nil {
			mapping[key] = *value
		}
	}
	for key, value := range map[string]*string{"up": o.Up, "down": o.Down, "dialer-proxy": o.DialerProxy, "name-cert-verify": o.NameCertVerify, "interface-name": o.Interface, "ip-version": o.IPVersion} {
		if value != nil {
			mapping[key] = *value
		}
	}
	if o.RoutingMark != nil {
		mapping["routing-mark"] = *o.RoutingMark
	}
	for _, rename := range o.Names {
		if rename.Pattern == nil {
			return errSourceReview
		}
		rename.Pattern.MatchTimeout = 250 * time.Millisecond
		name, err := rename.Pattern.Replace(mapping["name"].(string), rename.Target, 0, -1)
		if err != nil {
			return err
		}
		mapping["name"] = name
	}
	if o.Prefix != nil {
		mapping["name"] = fmt.Sprint(*o.Prefix, mapping["name"])
	}
	if o.Suffix != nil {
		mapping["name"] = fmt.Sprint(mapping["name"], *o.Suffix)
	}
	for _, expression := range o.Expressions {
		if err := expression.Apply(mapping); err != nil {
			return err
		}
	}
	return nil
}

// Core exposes its converter and expression evaluator but combines override/filter
// application with outbound factories; mirror only that pure projection here.
func sourceProviderProxyDocument(body []byte, declaration map[string]any) (map[string]any, error) {
	var schema struct {
		Filter   string              `provider:"filter,omitempty"`
		Exclude  string              `provider:"exclude-filter,omitempty"`
		Types    string              `provider:"exclude-type,omitempty"`
		Dialer   string              `provider:"dialer-proxy,omitempty"`
		Secret   string              `provider:"age-secret-key,omitempty"`
		Override sourceProxyOverride `provider:"override,omitempty"`
	}
	decoder := structure.NewDecoder(structure.Option{TagName: "provider", WeaklyTypedInput: true})
	if err := decoder.Decode(declaration, &schema); err != nil {
		return nil, err
	}
	plain, err := age.DecryptBytes(body, schema.Secret)
	if err != nil {
		return nil, err
	}
	var payload provider.ProxySchema
	if err := yaml.Unmarshal(plain, &payload); err != nil {
		payload.Proxies, err = convert.ConvertsV2Ray(plain)
		if err != nil {
			return nil, err
		}
	}
	if payload.Proxies == nil {
		return nil, errSourceReview
	}
	compile := func(input string) ([]*regexp2.Regexp, error) {
		var result []*regexp2.Regexp
		for _, expression := range strings.Split(input, "`") {
			compiled, err := regexp2.Compile(expression, regexp2.None)
			if err != nil {
				return nil, err
			}
			compiled.MatchTimeout = 250 * time.Millisecond
			result = append(result, compiled)
		}
		return result, nil
	}
	filters, err := compile(schema.Filter)
	if err != nil {
		return nil, err
	}
	var excludes []*regexp2.Regexp
	if schema.Exclude != "" {
		excludes, err = compile(schema.Exclude)
		if err != nil {
			return nil, err
		}
	}
	seen := map[string]bool{}
	selected := []any{}
	for _, filter := range filters {
	nodes:
		for _, node := range payload.Proxies {
			if schema.Types != "" {
				kind, valid := node["type"].(string)
				if !valid {
					continue
				}
				for _, excluded := range strings.Split(schema.Types, "|") {
					if strings.EqualFold(kind, excluded) {
						continue nodes
					}
				}
			}
			name, valid := node["name"].(string)
			if !valid {
				continue
			}
			for _, exclude := range excludes {
				matched, err := exclude.MatchString(name)
				if err != nil {
					return nil, err
				}
				if matched {
					continue nodes
				}
			}
			if schema.Filter != "" {
				matched, err := filter.MatchString(name)
				if err != nil {
					return nil, err
				}
				if !matched {
					continue
				}
			}
			if seen[name] {
				continue
			}
			if schema.Dialer != "" {
				node["dialer-proxy"] = schema.Dialer
			}
			if err := schema.Override.apply(node); err != nil {
				return nil, err
			}
			seen[name] = true
			encoded, err := json.Marshal(node)
			if err != nil {
				return nil, err
			}
			var frozen map[string]any
			if err := json.Unmarshal(encoded, &frozen); err != nil {
				return nil, err
			}
			selected = append(selected, frozen)
		}
	}
	if len(selected) == 0 {
		return nil, errSourceReview
	}
	return map[string]any{"proxies": selected}, nil
}
