package main

import (
	"encoding/json"
	"errors"
	"net"
	"reflect"
	"slices"
	"strings"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/tunnel"
)

type ManagedPolicyDescriptor struct {
	Version          int    `json:"version"`
	PolicySHA256     string `json:"policySha256"`
	MaintenanceProxy string `json:"maintenanceProxy,omitempty"`
}

type ConfigFence struct {
	RuntimeEpoch string `json:"runtimeEpoch"`
	Version      uint64 `json:"version"`
	Owner        uint64 `json:"owner"`
	Token        uint64 `json:"token"`
	InputID      string `json:"inputId"`
	RouteEpoch   uint64 `json:"routeEpoch"`
	PicksVersion uint64 `json:"picksVersion"`
}

var errManagedPolicy = errors.New("managed policy change requires a new configuration input")

type ConfigBuildFailure struct {
	Expected        ConfigFence     `json:"expected"`
	ExpectedRun     AppRequestState `json:"expectedRun"`
	RegisteredToken uint64          `json:"registeredToken"`
}

func failConfigBuild(request *ConfigBuildFailure) ConfigApplyResult {
	configMu.Lock()
	defer configMu.Unlock()
	selectMu.Lock()
	checkpointMu.Lock()
	appRequests.mu.Lock()
	op := latestConfig.Load()
	expectedToken := request.RegisteredToken
	if expectedToken == 0 {
		expectedToken = request.Expected.Token
	}
	valid := request.Expected.RuntimeEpoch == configRuntimeEpoch && request.Expected.Owner == configFact.Owner && request.Expected.Token == configFact.Token && (op == nil && expectedToken == 0 || op != nil && op.token == expectedToken)
	if features.Android {
		state, expected := appRequests.state, request.ExpectedRun
		valid = valid && state.ProcessEpoch == expected.ProcessEpoch && state.IntentRevision == expected.IntentRevision && state.IntentRunning == expected.IntentRunning && state.Paused == expected.Paused
	}
	p := appliedConfig
	qualified := p != nil && p.eligible && configFact.Phase == "ready" && p.dataset == appRequests.dataset && operationRunValidLocked(p.op)
	if qualified {
		for key, revision := range p.sources {
			if appRequests.sources[key] != revision {
				qualified = false
			}
		}
	}
	appRequests.mu.Unlock()
	checkpointMu.Unlock()
	selectMu.Unlock()
	if !valid {
		return configResult("superseded", ConfigReceipt{}, errConfigSuperseded)
	}
	if qualified {
		return configResult("retained", p.receipt, nil)
	}
	if p == nil {
		p = pendingConfig
	}
	if p != nil {
		return blockConfigLocked(p, errors.New("configuration build failed"))
	}
	return configResult("blocked", ConfigReceipt{}, errors.New("configuration build failed"))
}

func managedProviderMutationBlocked() bool {
	configMu.Lock()
	defer configMu.Unlock()
	return pendingConfig != nil && pendingConfig.manifest.ManagedPolicy != nil || appliedConfig != nil && appliedConfig.manifest.ManagedPolicy != nil
}

func configFenceMatchesLocked(expected *ConfigFence) bool {
	if expected == nil {
		return true
	}
	epoch, picks := routeStamp()
	return expected.RuntimeEpoch == configRuntimeEpoch && expected.Version == configFact.Version && expected.Owner == configFact.Owner && expected.Token == configFact.Token && expected.InputID == configFact.InputID && expected.RouteEpoch == epoch && expected.PicksVersion == picks
}

func managedGroup(raw *config.RawConfig, name string) []string {
	for _, group := range raw.ProxyGroup {
		if group["name"] != name {
			continue
		}
		values, ok := group["proxies"].([]any)
		if !ok {
			return nil
		}
		members := make([]string, 0, len(values))
		for _, value := range values {
			member, ok := value.(string)
			if !ok {
				return nil
			}
			members = append(members, member)
		}
		return members
	}
	return nil
}

func isManagedProxy(raw *config.RawConfig, name string) bool {
	for _, proxy := range raw.Proxy {
		if proxy["name"] == name {
			return true
		}
	}
	return false
}

func validateManagedInput(manifest ConfigManifest, raw *config.RawConfig) error {
	d := manifest.ManagedPolicy
	if d == nil {
		return nil
	}
	if d.Version != 1 || !validInputID(d.PolicySHA256) || !slices.Contains(manifest.Dependencies, "application-config") {
		return errManagedPolicy
	}
	if raw.Mode != tunnel.Rule || !raw.IPv6 || raw.FindProcessMode != process.FindProcessOff || raw.AllowLan || raw.BindAddress != "127.0.0.1" || raw.MixedPort <= 0 || raw.Port != 0 || raw.SocksPort != 0 || raw.RedirPort != 0 || raw.TProxyPort != 0 || len(raw.Listeners) != 0 || len(raw.Tunnels) != 0 || raw.ShadowSocksConfig != "" || raw.VmessConfig != "" || raw.TuicServer.Enable || raw.ExternalController != "" || raw.ExternalControllerTLS != "" || raw.ExternalControllerUnix != "" || raw.ExternalControllerPipe != "" || raw.ExternalUI != "" || raw.GeoAutoUpdate || raw.NTP.Enable || raw.IPTables.Enable || raw.Sniffer.Enable || len(raw.Hosts) != 0 || raw.Profile.StoreSelected || raw.Profile.StoreFakeIP || len(raw.ProxyProvider) != 0 || len(raw.SkipAuthPrefixes) != 0 {
		return errManagedPolicy
	}
	if !raw.DNS.Enable || raw.DNS.RespectRules || raw.DNS.PreferH3 || raw.DNS.UseHosts || raw.DNS.UseSystemHosts || !raw.DNS.IPv6 || !raw.DNS.DirectNameServerFollowPolicy || len(raw.DNS.Fallback) != 0 {
		return errManagedPolicy
	}
	if raw.DNS.EnhancedMode != C.DNSMapping || raw.DNS.FallbackFilter.GeoIP || len(raw.DNS.FallbackFilter.GeoSite) != 0 || len(raw.DNS.FallbackFilter.IPCIDR) != 0 || len(raw.DNS.FallbackFilter.Domain) != 0 {
		return errManagedPolicy
	}
	if raw.DNS.Listen != "" {
		host, _, err := net.SplitHostPort(raw.DNS.Listen)
		if err != nil || host != "127.0.0.1" {
			return errManagedPolicy
		}
	}
	seen := make(map[string]bool)
	for _, proxy := range raw.Proxy {
		for key := range proxy {
			if !slices.Contains([]string{"name", "type", "server", "port", "udp", "username", "password"}, key) {
				return errManagedPolicy
			}
		}
		name, ok := proxy["name"].(string)
		if !ok || !strings.HasPrefix(name, "fc-managed-proxy-") || seen[name] || proxy["type"] != "socks5" {
			return errManagedPolicy
		}
		seen[name] = true
	}
	for _, group := range raw.ProxyGroup {
		name, ok := group["name"].(string)
		if !ok || !strings.HasPrefix(name, "fc-managed-group-") || seen[name] || group["type"] != "select" || len(group) != 3 {
			return errManagedPolicy
		}
		seen[name] = true
		members := managedGroup(raw, name)
		if len(members) == 0 {
			return errManagedPolicy
		}
		for _, member := range members {
			if !isManagedProxy(raw, member) {
				return errManagedPolicy
			}
		}
	}
	for _, provider := range raw.RuleProvider {
		if provider["type"] != "inline" || provider["behavior"] != "classical" || len(provider) != 3 || provider["payload"] == nil {
			return errManagedPolicy
		}
	}
	if d.MaintenanceProxy != "" && !isManagedProxy(raw, d.MaintenanceProxy) && len(managedGroup(raw, d.MaintenanceProxy)) == 0 {
		return errManagedPolicy
	}
	for group, member := range manifest.SelectedMap {
		if !slices.Contains(managedGroup(raw, group), member) {
			return errManagedPolicy
		}
	}
	for key := range manifest.AcceptedOverrides {
		if !managedHotKey(key) {
			return errManagedPolicy
		}
	}
	return nil
}

func managedHotKey(key string) bool {
	return key == "log-level" || key == "tcp-concurrent" || key == "unified-delay"
}

func validateManagedUpdate(p *preparedConfig, params *UpdateParams) error {
	if p == nil || p.manifest.ManagedPolicy == nil {
		return nil
	}
	projected := *p.raw
	data, err := json.Marshal(params)
	if err != nil {
		return err
	}
	var values map[string]json.RawMessage
	if err = json.Unmarshal(data, &values); err != nil {
		return err
	}
	for key, value := range values {
		if string(value) == "null" || managedHotKey(key) {
			delete(values, key)
		}
	}
	if err = patchConfigInput(&projected, values); err != nil {
		return err
	}
	if !reflect.DeepEqual(projected, *p.raw) {
		return errManagedPolicy
	}
	return nil
}

func managedCheckpointPicks(p *preparedConfig, picks map[string]string) (map[string]string, error) {
	if p.manifest.ManagedPolicy == nil {
		return picks, nil
	}
	result := make(map[string]string)
	for _, group := range p.raw.ProxyGroup {
		name := group["name"].(string)
		value := picks[name]
		if !slices.Contains(managedGroup(p.raw, name), value) {
			return nil, errManagedPolicy
		}
		result[name] = value
	}
	return result, nil
}
