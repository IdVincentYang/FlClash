package main

import (
	b "bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"reflect"
	"runtime"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	authStore "github.com/metacubex/mihomo/listener/auth"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

const (
	delayTestConcurrency    = 50
	defaultTestURL          = "https://www.gstatic.com/generate_204"
	defaultDelayTestTimeout = 5 * time.Second
)

var (
	configMu      sync.Mutex
	currentConfig *config.Config

	// selectMu serialises proxy-group selection writes. mihomo's Selector.Set
	// writes s.selected with no lock of its own, so something has to; configMu
	// used to, which made a tap on a node wait out a whole config apply,
	// provider downloads included, for a write that touches one field.
	// patchSelectGroup takes it under configMu, fixing the order as
	// configMu -> selectMu.
	selectMu sync.Mutex

	isInit     atomic.Bool
	isRunning  atomic.Bool
	sdkVersion atomic.Int32
	testURL    atomic.Pointer[string]

	delayTestSlots = make(chan struct{}, delayTestConcurrency)

	debugStderr = os.Getenv("FLCLASH_CORE_DEBUG") != ""
)

var (
	errConfigNotApplied    = errors.New("config is not applied")
	errNotExternalProvider = errors.New("not external provider")
)

func externalProviders() map[string]cp.Provider {
	eps := make(map[string]cp.Provider)
	for n, p := range tunnel.ProvidersSnapshot() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	for n, p := range tunnel.RuleProvidersSnapshot() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	return eps
}

func lookupExternalProvider(name string) (cp.Provider, bool) {
	if p, exist := tunnel.RuleProvidersSnapshot()[name]; exist && p.VehicleType() != cp.Compatible {
		return p, true
	}
	if p, exist := tunnel.ProvidersSnapshot()[name]; exist && p.VehicleType() != cp.Compatible {
		return p, true
	}
	return nil, false
}

func toExternalProvider(p cp.Provider) (*ExternalProvider, error) {
	switch typed := p.(type) {
	case *provider.ProxySetProvider:
		return &ExternalProvider{
			Name:             typed.Name(),
			Type:             typed.Type().String(),
			VehicleType:      typed.VehicleType().String(),
			Count:            typed.Count(),
			UpdateAt:         typed.UpdatedAt(),
			Path:             typed.Vehicle().Path(),
			SubscriptionInfo: typed.GetSubscriptionInfo(),
		}, nil
	case *rp.RuleSetProvider:
		return &ExternalProvider{
			Name:        typed.Name(),
			Type:        typed.Type().String(),
			VehicleType: typed.VehicleType().String(),
			Count:       typed.Count(),
			UpdateAt:    typed.UpdatedAt(),
			Path:        typed.Vehicle().Path(),
		}, nil
	default:
		return nil, errNotExternalProvider
	}
}

func sideUpdateExternalProvider(p cp.Provider, data []byte) error {
	switch typed := p.(type) {
	case *provider.ProxySetProvider:
		_, _, err := typed.SideUpdate(data)
		return err
	case *rp.RuleSetProvider:
		_, _, err := typed.SideUpdate(data)
		return err
	default:
		return errNotExternalProvider
	}
}

func updateListenersChecked(cfg *config.Config, target constant.Tunnel, mixed *listener.MixedBinding) error {
	general := cfg.General
	if err := mixed.Validate(); err != nil {
		return err
	}
	listener.SetAllowLan(general.AllowLan)
	listener.SetBindAddress(general.BindAddress)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)
	if err := listener.PatchInboundListenersChecked(cfg.Listeners, target, true); err != nil {
		return err
	}
	for _, item := range []struct {
		port   int
		create func(int, constant.Tunnel) error
	}{
		{general.Port, listener.ReCreateHTTPChecked},
		{general.SocksPort, listener.ReCreateSocksChecked},
		{general.RedirPort, listener.ReCreateRedirChecked},
		{general.TProxyPort, listener.ReCreateTProxyChecked},
	} {
		if err := item.create(item.port, target); err != nil {
			return err
		}
	}
	if general.MixedPort != 0 && mixed == nil {
		return errors.New("mixed listener was not prepared")
	}
	if err := listener.ReCreateShadowSocksChecked(general.ShadowSocksConfig, target); err != nil {
		return err
	}
	if err := listener.ReCreateVmessChecked(general.VmessConfig, target); err != nil {
		return err
	}
	if err := listener.ReCreateTuicChecked(general.TuicServer, target); err != nil {
		return err
	}
	if !features.Android {
		if err := listener.ReCreateTunChecked(general.Tun, target); err != nil {
			return err
		}
	}
	if err := listener.PatchTunnelChecked(cfg.Tunnels, target); err != nil {
		return err
	}
	return mixed.Validate()
}

func stopBusinessListeners() {
	listener.StopListener()
	listener.PatchInboundListeners(nil, tunnel.Tunnel, true)
	_ = listener.PatchTunnelChecked(nil, tunnel.Tunnel)
}

func patchSelectGroup(mapping map[string]string) {
	selectMu.Lock()
	defer selectMu.Unlock()
	for name, proxy := range tunnel.AllProxies() {
		outbound, ok := proxy.(*adapter.Proxy)
		if !ok {
			continue
		}

		selector, ok := outbound.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			continue
		}

		selected, exist := mapping[name]
		if !exist {
			continue
		}

		selector.ForceSet(selected)
	}
}

func defaultSetupParams() *SetupParams {
	return &SetupParams{
		TestURL:     defaultTestURL,
		SelectedMap: map[string]string{},
	}
}

func setTestURL(url string) {
	if url == "" {
		return
	}
	constant.DefaultTestURL = url
	testURL.Store(&url)
}

func currentTestURL() string {
	if url := testURL.Load(); url != nil && *url != "" {
		return *url
	}
	return defaultTestURL
}

func acquireDelayTestSlot(ctx context.Context) bool {
	select {
	case delayTestSlots <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

func releaseDelayTestSlot() {
	<-delayTestSlots
}

func routeConfig(cfg *config.Config) *route.Config {
	controller := cfg.Controller
	routeCfg := &route.Config{
		Addr:        controller.ExternalController,
		TLSAddr:     controller.ExternalControllerTLS,
		UnixAddr:    controller.ExternalControllerUnix,
		PipeAddr:    controller.ExternalControllerPipe,
		RoutingMark: controller.ExternalControllerRoutingMark,
		Secret:      controller.Secret,
		DohServer:   controller.ExternalDohServer,
		IsDebug:     cfg.General.LogLevel == log.DEBUG,
		Cors: route.Cors{
			AllowOrigins:        controller.Cors.AllowOrigins,
			AllowPrivateNetwork: controller.Cors.AllowPrivateNetwork,
		},
	}
	if cfg.TLS != nil {
		routeCfg.Certificate = cfg.TLS.Certificate
		routeCfg.PrivateKey = cfg.TLS.PrivateKey
		routeCfg.ClientAuthType = cfg.TLS.ClientAuthType
		routeCfg.ClientAuthCert = cfg.TLS.ClientAuthCert
		routeCfg.EchKey = cfg.TLS.EchKey
	}
	return routeCfg
}

func patchTun(target *LC.Tun, params *tunSchema) {
	target.Enable = params.Enable
	if params.AutoRoute != nil {
		target.AutoRoute = *params.AutoRoute
	}
	if params.Device != nil {
		target.Device = *params.Device
	}
	if params.RouteAddress != nil {
		target.RouteAddress = *params.RouteAddress
	}
	if params.DNSHijack != nil {
		target.DNSHijack = *params.DNSHijack
	}
	if params.Stack != nil {
		target.Stack = *params.Stack
	}
}

func updateConfig(params *UpdateParams) error {
	return updateConfigOwned(params, nil)
}

func updateConfigOwned(params *UpdateParams, expected *controllerConfigMutation) error {
	configMu.Lock()
	defer configMu.Unlock()
	if expected != nil && !expected.valid() {
		return errConfigSuperseded
	}
	if currentConfig == nil || pendingConfig != nil && configFact.Phase != "ready" {
		return errConfigNotApplied
	}

	general := currentConfig.General
	tunChanged := false
	if params.Tun != nil {
		projected := general.Tun
		patchTun(&projected, params.Tun)
		tunChanged = !reflect.DeepEqual(projected, general.Tun)
	}
	if params.MixedPort != nil && *params.MixedPort != general.MixedPort || params.AllowLan != nil && *params.AllowLan != general.AllowLan || params.Authentication != nil && !slices.Equal(*params.Authentication, general.Authentication) || tunChanged || params.ExternalController != nil && *params.ExternalController != currentConfig.Controller.ExternalController {
		return errors.New("configuration_reapply_required")
	}
	selectMu.Lock()
	checkpointMu.Lock()
	locked := true
	defer func() {
		if locked {
			checkpointMu.Unlock()
			selectMu.Unlock()
		}
	}()
	routeChanged := params.Mode != nil && general.Mode != *params.Mode || params.IPv6 != nil && general.IPv6 != *params.IPv6
	sourceChanged := params.Authentication != nil && !slices.Equal(general.Authentication, *params.Authentication)
	for geoType, link := range params.GeoXUrl {
		if resource, exists := geoResources[strings.ToUpper(geoType)]; exists && link != "" && link != resource.url() {
			sourceChanged = true
		}
	}
	if routeChanged || sourceChanged {
		end := beginAppRouteMutation()
		defer end()
	}
	if err := patchGeneralOverrides(general, params); err != nil {
		return err
	}
	if params.FindProcessMode != nil {
		tunnel.SetFindProcessMode(general.FindProcessMode)
	}
	if params.TCPConcurrent != nil {
		dialer.SetTcpConcurrent(general.TCPConcurrent)
	}
	if params.UnifiedDelay != nil {
		adapter.UnifiedDelay.Store(general.UnifiedDelay)
	}
	if params.Mode != nil {
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		log.SetLevel(general.LogLevel)
	}
	if params.IPv6 != nil {
		resolver.DisableIPv6 = !general.IPv6
	}
	if params.Tun != nil {
		patchTun(&general.Tun, params.Tun)
	}
	if params.ExternalController != nil &&
		*params.ExternalController != currentConfig.Controller.ExternalController {
		currentConfig.Controller.ExternalController = *params.ExternalController
		route.ReCreateServer(routeConfig(currentConfig))
	}
	if params.Authentication != nil {
		applyAuthentication(currentConfig, *params.Authentication)
	}

	for geoType, link := range params.GeoXUrl {
		setGeoResourceUrl(geoType, link)
	}
	syncGeoUpdater(params.GeoAutoUpdate, params.GeoUpdateInterval)
	if routeChanged {
		refreshRouteLocked(true)
	}
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	selectMu.Unlock()
	locked = false
	err := saveAcceptedConfigChanges(params, nil)
	if err != nil {
		return err
	}
	return nil
}

func applyAuthentication(cfg *config.Config, authentication []string) {
	users := config.ParseAuthentication(authentication)
	cfg.General.Authentication = authentication
	cfg.Users = users
	authStore.Default.SetAuthenticator(auth.NewAuthenticator(users))
	if len(users) > 0 {
		// A loopback exemption would let any local app bypass the credentials.
		cfg.General.SkipAuthPrefixes = nil
		inbound.SetSkipAuthPrefixes(nil)
	}
}

func syncGeoUpdater(autoUpdate *bool, interval *int) {
	changed := false
	if autoUpdate != nil && *autoUpdate != updater.GeoAutoUpdate() {
		updater.SetGeoAutoUpdate(*autoUpdate)
		changed = true
	}
	if interval != nil && *interval != updater.GeoUpdateInterval() {
		updater.SetGeoUpdateInterval(*interval)
		changed = true
	}
	if !changed {
		return
	}
	reconcileGeoUpdater()
}

var (
	registerGeoUpdater = updater.RegisterGeoUpdaterWithCancel
	stopGeoUpdater     = updater.StopGeoUpdater
)

func reconcileGeoUpdater() {
	if updater.GeoAutoUpdate() {
		registerGeoUpdater()
		return
	}
	stopGeoUpdater()
}

// mihomo writes the NTP time with settimeofday, which Android's app seccomp
// policy answers by killing the process rather than with EPERM.
var systemTimeWritable = runtime.GOOS != "android"

func loadConfig(path string) (*config.Config, error) {
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw, _, err := decodeConfigDocument(buf)
	if err != nil {
		return nil, err
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return nil, err
	}
	if cfg.NTP.WriteToSystem && !systemTimeWritable {
		log.Warnln("ntp write-to-system ignored: Android does not let apps set the system time")
		cfg.NTP.WriteToSystem = false
	}
	return cfg, nil
}

func applyConfig(params *SetupParams) error {
	return errors.New("immutable configuration input required")
}

func UnmarshalJson(data []byte, v any) error {
	decoder := json.NewDecoder(b.NewReader(data))
	decoder.UseNumber()
	return decoder.Decode(v)
}

func logError(format string, args ...any) {
	log.Errorln(format, args...)
	if debugStderr {
		fmt.Fprintf(os.Stderr, "[ERROR] "+format+"\n", args...)
	}
}
