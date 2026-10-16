package main

import (
	"cmp"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"io"
	"maps"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	coreNtp "github.com/metacubex/mihomo/ntp/ntp"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	logMu         sync.Mutex
	logSubscriber observable.Subscription[log.Event]
	logCancel     context.CancelFunc
)

func handleInitClash(params *InitParams) bool {
	configMu.Lock()
	defer configMu.Unlock()
	if isInit.Load() {
		return filepath.Clean(params.HomeDir) == filepath.Clean(constant.Path.HomeDir())
	}
	initializeCore(params)
	return true
}

func handleStartListener() bool {
	configMu.Lock()
	defer configMu.Unlock()
	scope := activeBusiness.Load()
	return scope != nil && scope.Check() == nil && currentConfig != nil && configFact.Phase == "ready"
}

func handleStopListener() bool {
	return stopListenerReceived(0)
}

func stopListenerReceived(sequence uint64) bool {
	configMu.Lock()
	defer configMu.Unlock()
	if op := latestConfig.Load(); sequence != 0 && op != nil && op.token > sequence {
		return true
	}
	revokeBusiness()
	preparedConfigGate.Store(nil)
	isRunning.Store(false)
	tunnel.OnSuspend()
	stopBusinessListeners()
	checkpointMu.Lock()
	configFact.BusinessActive = false
	configFact.Phase = "retired"
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	resolver.ResetConnection()
	return true
}

func handleGetIsInit() bool {
	return isInit.Load()
}

func handleForceGC() {
	log.Infoln("[APP] request force GC")
	tunnel.InvalidateAllProxies()
	runtime.GC()
	if features.Android {
		debug.FreeOSMemory()
	}
}

func handleShutdown() bool {
	requestscope.Phase(appRequests.currentOwner(), "retired")
	appRequests.closePrivate()
	handleStopLog()
	stopRouteWatch()

	configMu.Lock()
	isRunning.Store(false)
	stopBusinessListeners()
	updater.StopGeoUpdater()
	coreNtp.ReCreateNTPService("", 0, "", nil, false)
	executor.Shutdown()
	currentConfig = nil
	isInit.Store(false)
	configMu.Unlock()

	handleForceGC()
	return true
}

func handleValidateConfig(path string) string {
	buf, err := os.ReadFile(path)
	if err != nil {
		return err.Error()
	}
	if _, _, err = decodeConfigDocument(buf); err != nil {
		return err.Error()
	}
	return ""
}

// Tailscale and EasyTier register a DNS client under the proxy name when built
// and drop that name's entry on Close, so a probe under the real name would
// take the resolver from a running proxy of the same name.
const validationNameSuffix = "\x00validate"

// The per-proxy parser the config load runs; checks across proxies, such as
// duplicate names, are left to the load itself.
func handleValidateProxies(mappings []map[string]any) []string {
	results := make([]string, len(mappings))
	for i, mapping := range mappings {
		name, _ := mapping["name"].(string)
		probe := mapping
		switch mapping["type"] {
		case "tailscale", "easytier":
			probe = maps.Clone(mapping)
			probe["name"] = name + validationNameSuffix
		}
		proxy, err := adapter.ParseProxy(probe)
		if err != nil {
			results[i] = strings.ReplaceAll(err.Error(), validationNameSuffix, "")
			continue
		}
		_ = proxy.Close()
	}
	return results
}

const globalProxyName = "GLOBAL"

func isProxyGroupType(adapterType constant.AdapterType) bool {
	switch adapterType {
	case constant.Selector, constant.URLTest, constant.Fallback, constant.Relay, constant.LoadBalance:
		return true
	default:
		return false
	}
}

func proxyGroupNames(
	nameList []string,
	typeOf func(name string) (constant.AdapterType, bool),
) []string {
	hasGlobal := false
	names := make([]string, 0, len(nameList)+1)

	for _, name := range nameList {
		if name == globalProxyName {
			hasGlobal = true
		}
		adapterType, ok := typeOf(name)
		if !ok || !isProxyGroupType(adapterType) {
			continue
		}
		names = append(names, name)
	}

	if !hasGlobal {
		if adapterType, ok := typeOf(globalProxyName); ok && isProxyGroupType(adapterType) {
			names = append([]string{globalProxyName}, names...)
		}
	}

	return names
}

func handleGetProxies() ProxiesData {
	proxies := tunnel.AllProxies()

	allNames := proxyGroupNames(config.GetProxyNameList(), func(name string) (constant.AdapterType, bool) {
		p, ok := proxies[name]
		if !ok || p == nil {
			return 0, false
		}
		return p.Type(), true
	})

	views := make(map[string]any, len(proxies))
	for name, proxy := range proxies {
		views[name] = proxyView(proxy)
	}
	return ProxiesData{
		All:     allNames,
		Proxies: views,
	}
}

// Proxy.MarshalJSON encodes each node twice, with history the host never reads.
func proxyView(proxy constant.Proxy) any {
	node := nodeView{Name: proxy.Name(), Type: proxy.Type().String()}
	if !isProxyGroupType(proxy.Type()) {
		return node
	}
	data, err := proxy.Adapter().MarshalJSON()
	view := map[string]any{}
	if err == nil {
		err = json.Unmarshal(data, &view)
	}
	if err != nil {
		log.Warnln("[APP] encode group %s: %v", node.Name, err)
		return node
	}
	view["name"] = node.Name
	return view
}

var (
	errGroupNotFound    = errors.New("Not found group")
	errGroupInvalidType = errors.New("Group has invalid proxy type")
	errGroupNotSelect   = errors.New("Group is not selectable")
)

func lookupProxy(name string) constant.Proxy {
	return tunnel.AllProxies()[name]
}

func selectableGroup(groupName string) (pickableGroup, error) {
	group := lookupProxy(groupName)
	if group == nil {
		return nil, errGroupNotFound
	}
	adapterProxy, ok := group.(*adapter.Proxy)
	if !ok {
		return nil, errGroupInvalidType
	}
	selector, ok := adapterProxy.ProxyAdapter.(pickableGroup)
	if !ok {
		return nil, errGroupNotSelect
	}
	return selector, nil
}

func handleChangeProxy(params *ChangeProxyParams) *ChangeProxyResult {
	return changeProxyOwned(params, nil, false)
}

func changeProxyOwned(params *ChangeProxyParams, expected *controllerConfigMutation, clear bool) *ChangeProxyResult {
	selectMu.Lock()
	checkpointMu.Lock()
	locked := true
	defer func() {
		if locked {
			checkpointMu.Unlock()
			selectMu.Unlock()
		}
	}()
	if expected != nil && !expected.valid() {
		return &ChangeProxyResult{Message: errConfigSuperseded.Error()}
	}
	if pendingConfig != nil && configFact.Phase != "ready" {
		return &ChangeProxyResult{Message: errConfigNotApplied.Error()}
	}
	owner := configFact.Owner

	selector, err := selectableGroup(params.GroupName)
	if err != nil {
		return &ChangeProxyResult{Message: err.Error()}
	}
	if clear && lookupProxy(params.GroupName).Type() == constant.Selector {
		return &ChangeProxyResult{Message: "Only automatic groups can clear a forced selection"}
	}
	before := selector.Now()
	if before != params.ProxyName {
		invalidateAppRequestGroup(params.GroupName)
	}
	if params.ProxyName == "" {
		selector.ForceSet(params.ProxyName)
	} else if fallback, ok := selector.(*outboundgroup.Fallback); ok {
		probe, err := fallback.SetWithProbe(params.ProxyName)
		if err != nil {
			return &ChangeProxyResult{Message: err.Error()}
		}
		checkpointMu.Unlock()
		selectMu.Unlock()
		locked = false
		probe()
		selectMu.Lock()
		checkpointMu.Lock()
		locked = true
		if owner != configFact.Owner || pendingConfig != nil && configFact.Phase != "ready" {
			return &ChangeProxyResult{Message: errConfigSuperseded.Error()}
		}
	} else if err := selector.Set(params.ProxyName); err != nil {
		return &ChangeProxyResult{Message: err.Error()}
	}
	changed := selector.Now() != before
	refreshRouteLocked(false)
	checkpointMu.Unlock()
	selectMu.Unlock()
	locked = false
	configMu.Lock()
	checkpointMu.Lock()
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	err = saveAcceptedConfigChanges(nil, nil)
	configMu.Unlock()
	if err != nil {
		return &ChangeProxyResult{Message: err.Error(), Changed: changed}
	}
	return &ChangeProxyResult{Changed: changed}
}

func handleGetTraffic(onlyStatisticsProxy bool) Traffic {
	up, down := statistic.DefaultManager.NowTraffic(onlyStatisticsProxy)
	return Traffic{
		Up:   up,
		Down: down,
	}
}

func handleGetTotalTraffic(onlyStatisticsProxy bool) Traffic {
	up, down := statistic.DefaultManager.TotalTraffic(onlyStatisticsProxy)
	return Traffic{
		Up:   up,
		Down: down,
	}
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func delayValue(delay uint16) int32 {
	if delay == 0 {
		return -1
	}
	return int32(delay)
}

var anyDelayTestStatus utils.IntRanges[uint16]

func delayTestTimeout(milliseconds int64) time.Duration {
	if milliseconds <= 0 {
		return defaultDelayTestTimeout
	}
	return time.Duration(milliseconds) * time.Millisecond
}

var missingDelayTestProxyAt atomic.Int64

// Rate-limit missing-node diagnostics so stale UI batches cannot flood the log.
func reportMissingDelayTestProxy(name string) {
	now := time.Now().UnixNano()
	last := missingDelayTestProxyAt.Load()
	if last != 0 && now-last < int64(time.Second) {
		return
	}
	if !missingDelayTestProxyAt.CompareAndSwap(last, now) {
		return
	}
	logError("delay test: %q is not part of the applied config", name)
}

func handleTestDelay(params *TestDelayParams) *Delay {
	url := params.TestUrl
	if url == "" {
		url = currentTestURL()
	}
	delayData := &Delay{
		Name:  params.ProxyName,
		Url:   url,
		Value: -1,
	}

	parent, lease, requestErr := requestOperationContext(params.ScopeID, params.ProxyName)
	if requestErr != nil {
		return nil
	}
	proxy := lookupProxy(params.ProxyName)
	if chosen, fixed := requestscope.FixedProxy(lease); fixed {
		proxy = chosen
	}
	if proxy == nil {
		reportMissingDelayTestProxy(params.ProxyName)
		return delayData
	}

	timeout := delayTestTimeout(params.Timeout)

	// Queueing for a slot and probing the node each get the full timeout.
	// Sharing one deadline meant a node that waited four seconds behind a
	// saturated semaphore had one second left to connect, so a bulk test of a
	// large subscription reported Timeout for whatever happened to be at the
	// back of the queue.
	queueCtx, cancelQueue := context.WithTimeout(parent, timeout)
	granted := acquireDelayTestSlot(queueCtx)
	cancelQueue()
	if !granted {
		return nil
	}
	defer releaseDelayTestSlot()

	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()

	delay, err := proxy.URLTest(ctx, url, anyDelayTestStatus)
	if err != nil {
		return delayData
	}

	if requestscope.Check(lease) != nil {
		return nil
	}
	delayData.Value = delayValue(delay)
	return delayData
}

func handleGetConnections() *statistic.Snapshot {
	return statistic.DefaultManager.Snapshot()
}

func handleGetConnectionCount() int {
	count := 0
	statistic.DefaultManager.Range(func(statistic.Tracker) bool {
		count++
		return true
	})
	return count
}

func handleCloseConnections() bool {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
	return true
}

func handleResetConnections() bool {
	resolver.ResetConnection()
	return true
}

func handleCloseConnection(connectionId string) bool {
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}

func handleGetExternalProviders() []ExternalProvider {
	providers := externalProviders()
	eps := make([]ExternalProvider, 0, len(providers))
	for _, p := range providers {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	slices.SortFunc(eps, func(a, b ExternalProvider) int {
		return cmp.Compare(a.Name, b.Name)
	})
	return eps
}

func handleGetExternalProvider(externalProviderName string) *ExternalProvider {
	p, exist := lookupExternalProvider(externalProviderName)
	if !exist {
		return nil
	}
	externalProvider, err := toExternalProvider(p)
	if err != nil {
		return nil
	}
	return externalProvider
}

type geoResource struct {
	update func() error
	url    func() string
	setUrl func(string)
}

var geoResources = map[string]geoResource{
	"MMDB":    {update: updater.UpdateMMDB, url: geodata.MmdbUrl, setUrl: geodata.SetMmdbUrl},
	"ASN":     {update: updater.UpdateASN, url: geodata.ASNUrl, setUrl: geodata.SetASNUrl},
	"GEOIP":   {update: updater.UpdateGeoIp, url: geodata.GeoIpUrl, setUrl: geodata.SetGeoIpUrl},
	"GEOSITE": {update: updater.UpdateGeoSite, url: geodata.GeoSiteUrl, setUrl: geodata.SetGeoSiteUrl},
}

// mihomo's updaters read these links without a lock, so an unchanged one is never rewritten.
func setGeoResourceUrl(geoType string, link string) {
	resource, exist := geoResources[strings.ToUpper(geoType)]
	if !exist {
		log.Warnln("geox-url: unknown geo resource %q", geoType)
		return
	}
	if link != "" && link != resource.url() {
		resource.setUrl(link)
	}
}

const (
	geoUpdateScope      = "geo:"
	providerUpdateScope = "provider:"
)

var (
	updateMu       sync.Mutex
	updateInFlight = map[string]bool{}
	geoHookClaims  = map[string]bool{}
)

func claimUpdate(key string) bool {
	updateMu.Lock()
	defer updateMu.Unlock()
	if updateInFlight[key] {
		return false
	}
	updateInFlight[key] = true
	return true
}

func releaseUpdate(key string) {
	updateMu.Lock()
	defer updateMu.Unlock()
	delete(updateInFlight, key)
	delete(geoHookClaims, key)
}

func claimGeoUpdate(geoType string) bool {
	return claimUpdate(geoUpdateScope + geoType)
}

func releaseGeoUpdate(geoType string) {
	releaseUpdate(geoUpdateScope + geoType)
}

func claimGeoUpdateFromHook(geoType string) {
	key := geoUpdateScope + geoType
	updateMu.Lock()
	defer updateMu.Unlock()
	if updateInFlight[key] {
		return
	}
	updateInFlight[key] = true
	geoHookClaims[key] = true
}

func releaseGeoUpdateFromHook(geoType string) {
	key := geoUpdateScope + geoType
	updateMu.Lock()
	defer updateMu.Unlock()
	if !geoHookClaims[key] {
		return
	}
	delete(geoHookClaims, key)
	delete(updateInFlight, key)
}

type geoUpdateRequest struct {
	Type    string `json:"type"`
	ScopeID string `json:"scopeId"`
}

func (p *geoUpdateRequest) UnmarshalJSON(data []byte) error {
	if len(data) > 0 && data[0] == '"' {
		return json.Unmarshal(data, &p.Type)
	}
	type raw geoUpdateRequest
	return json.Unmarshal(data, (*raw)(p))
}

func handleScopedGeoUpdate(params geoUpdateRequest) string {
	lease, err := requestLease(params.ScopeID)
	if err != nil || lease == nil {
		return "request_blocked"
	}
	target, ok := geoResources[params.Type]
	if !ok {
		return "unknown Geo resource"
	}
	if err = requestscope.CheckTarget(lease, target.url()); err != nil {
		return "request_cancelled"
	}
	if !claimGeoUpdate(params.Type) {
		return "geo update already in progress"
	}
	defer releaseGeoUpdate(params.Type)
	if err = updater.UpdateGeoResource(lease.Context(), params.Type, lease); err != nil {
		return err.Error()
	}
	if lease.Check() == nil {
		bumpRouteEpoch()
	}
	return ""
}

func handleUpdateGeoData(geoType string) string {
	resource, exist := geoResources[geoType]
	if !exist {
		logError("updateGeoData: unknown geo resource %q", geoType)
		return "unknown geo resource: " + geoType
	}
	if !claimGeoUpdate(geoType) {
		return "geo update already in progress: " + geoType
	}
	safeGoDetached("updateGeoData("+geoType+")", func() {
		defer releaseGeoUpdate(geoType)
		if err := resource.update(); err != nil {
			logError("updateGeoData(%s) error: %v", geoType, err)
		}
	})
	return ""
}

type providerRequestFailure struct {
	code       string
	reason     string
	statusCode int
}

// The reason values are matched by lib/common/network_error.dart.
func classifyProviderRequestError(err error) (providerRequestFailure, bool) {
	// mihomo reports a non-2xx fetch as errors.New(resp.Status).
	message := err.Error()
	if len(message) >= 4 && message[3] == ' ' {
		status, parseErr := strconv.Atoi(message[:3])
		if parseErr == nil && status >= 100 && status <= 599 {
			return providerRequestFailure{
				code:       "request_bad_response",
				statusCode: status,
			}, true
		}
	}
	var urlError *url.Error
	var networkError net.Error
	if reason := providerRequestFailureReason(err); reason != "" ||
		errors.As(err, &urlError) ||
		errors.As(err, &networkError) {
		return providerRequestFailure{code: "request_error", reason: reason}, true
	}
	return providerRequestFailure{}, false
}

func providerRequestFailureReason(err error) string {
	var unknownAuthority x509.UnknownAuthorityError
	var hostname x509.HostnameError
	var invalidCertificate x509.CertificateInvalidError
	var certificateVerification *tls.CertificateVerificationError
	var recordHeader tls.RecordHeaderError
	var alert tls.AlertError
	var dnsError *net.DNSError
	var networkError net.Error
	var opError *net.OpError
	switch {
	case errors.As(err, &unknownAuthority),
		errors.As(err, &hostname),
		errors.As(err, &invalidCertificate),
		errors.As(err, &certificateVerification),
		errors.As(err, &recordHeader),
		errors.As(err, &alert):
		return "tls"
	case errors.As(err, &dnsError), errors.Is(err, resolver.ErrIPNotFound):
		return "dns"
	case errors.Is(err, context.DeadlineExceeded),
		errors.Is(err, os.ErrDeadlineExceeded),
		errors.As(err, &networkError) && networkError.Timeout():
		return "timeout"
	case errors.As(err, &opError),
		errors.Is(err, syscall.ECONNREFUSED),
		errors.Is(err, syscall.ECONNRESET),
		errors.Is(err, io.EOF),
		errors.Is(err, io.ErrUnexpectedEOF):
		return "connection"
	}
	return ""
}

func providerMethodError(code, providerName string, err error) *MethodError {
	return &MethodError{
		Code:    code,
		Message: err.Error(),
		Details: map[string]any{"providerName": providerName},
	}
}

func providerRequestMethodError(
	failure providerRequestFailure,
	providerName string,
	err error,
) *MethodError {
	details := map[string]any{"providerName": providerName}
	if failure.reason != "" {
		details["reason"] = failure.reason
	}
	if failure.statusCode != 0 {
		details["statusCode"] = failure.statusCode
	}
	return &MethodError{
		Code:    failure.code,
		Message: err.Error(),
		Details: details,
	}
}

func handleUpdateExternalProvider(providerName string) *MethodError {
	p, exist := lookupExternalProvider(providerName)
	if !exist {
		return providerMethodError(
			"provider_not_found",
			providerName,
			errors.New("external provider does not exist"),
		)
	}
	key := providerUpdateScope + providerName
	if !claimUpdate(key) {
		return providerMethodError(
			"provider_updating",
			providerName,
			errors.New("external provider is updating"),
		)
	}
	defer releaseUpdate(key)
	if err := p.Update(); err != nil {
		if failure, ok := classifyProviderRequestError(err); ok {
			return providerRequestMethodError(failure, providerName, err)
		}
		return providerMethodError("provider_update_error", providerName, err)
	}
	refreshRoute()
	return nil
}

func handleSideLoadExternalProvider(providerName string, data []byte) *MethodError {
	p, exist := lookupExternalProvider(providerName)
	if !exist {
		return providerMethodError(
			"provider_not_found",
			providerName,
			errors.New("external provider does not exist"),
		)
	}
	key := providerUpdateScope + providerName
	if !claimUpdate(key) {
		return providerMethodError(
			"provider_updating",
			providerName,
			errors.New("external provider is updating"),
		)
	}
	defer releaseUpdate(key)
	if err := sideUpdateExternalProvider(p, data); err != nil {
		return providerMethodError("provider_update_error", providerName, err)
	}
	refreshRoute()
	return nil
}

func handleStartLog() {
	logMu.Lock()
	if logCancel != nil {
		logCancel()
		logCancel = nil
	}
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	subscriber := log.Subscribe()
	logSubscriber = subscriber
	logCancel = cancel
	logMu.Unlock()

	go func() {
		defer func() {
			logMu.Lock()
			if logSubscriber == subscriber {
				log.UnSubscribe(subscriber)
				logSubscriber = nil
				logCancel = nil
			}
			logMu.Unlock()
		}()
		for {
			select {
			case <-ctx.Done():
				return
			case logData, ok := <-subscriber:
				if !ok {
					return
				}
				if logData.LogLevel < log.Level() {
					continue
				}
				sendMessage(Message{
					Type: LogMessage,
					Data: logData,
				})
			}
		}
	}()
}

func handleStopLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if logCancel != nil {
		logCancel()
		logCancel = nil
	}
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
}

// HeapIdle still counts spans the runtime has already handed back to the OS,
// so the retained-but-unused figure subtracts HeapReleased.
func handleGetMemoryStats() MemoryStats {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return MemoryStats{
		Rss:          statistic.DefaultManager.Memory(),
		HeapInuse:    stats.HeapInuse,
		HeapIdle:     stats.HeapIdle - stats.HeapReleased,
		StackInuse:   stats.StackInuse,
		RuntimeOther: stats.MSpanInuse + stats.MCacheInuse + stats.BuckHashSys + stats.GCSys + stats.OtherSys,
	}
}

func handleGetConfig(path string) (*config.RawConfig, error) {
	id, err := beginRequestDataRead()
	if err != nil {
		return nil, err
	}
	defer appRequests.endDataRead(id)
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw, _, err := decodeConfigDocument(buf)
	return raw, err
}

func handleDumpRuleSet(path string) (string, error) {
	buf, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	mrsBehaviors := []cp.RuleBehavior{cp.Domain, cp.IPCIDR}
	var errs []error
	for _, behavior := range mrsBehaviors {
		var text strings.Builder
		err := rp.ConvertToMrs(buf, behavior, cp.MrsRule, &text)
		if err == nil {
			return text.String(), nil
		}
		errs = append(errs, err)
	}
	return "", errors.Join(errs...)
}

func handleCrash() {
	panic("handle invoke crash")
}

func handleUpdateConfig(params *UpdateParams) string {
	if err := updateConfig(params); err != nil {
		return err.Error()
	}
	return ""
}

// The profile ID is an int64 rendered through strconv, so the last element can
// never carry a separator or a `..` — that is what keeps handleClearEffect from
// becoming a general-purpose privileged file deletion API.
func providerPaths(homeDir string, profileId int64) (root string, target string) {
	root = filepath.Join(homeDir, "profiles", "providers")
	return root, filepath.Join(root, strconv.FormatInt(profileId, 10))
}

// handleClearEffect derives the provider directory from a profile ID so the
// method cannot be used as a general-purpose privileged file deletion API.
func handleClearEffect(profileId int64) string {
	if !isInit.Load() {
		return "not initialized"
	}
	if profileId <= 0 {
		return "invalid profile id"
	}
	providersRoot, providersPath := providerPaths(constant.Path.HomeDir(), profileId)
	if err := os.RemoveAll(providersPath); err != nil {
		return err.Error()
	}
	_ = os.Remove(providersRoot)
	return ""
}

var setupConfig = applyConfig

func handleSetupConfig(params *SetupParams) string {
	if !isInit.Load() {
		return "not initialized"
	}
	if err := setupConfig(params); err != nil {
		return err.Error()
	}
	return ""
}

func init() {
	installAppRequests()
	adapter.UrlTestHook = func(url string, name string, delay uint16) {
		sendMessage(Message{
			Type: DelayMessage,
			Data: &Delay{
				Url:   url,
				Name:  name,
				Value: delayValue(delay),
			},
		})
	}
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		notifyProbeRoute(c)
		sendMessage(Message{
			Type: RequestMessage,
			Data: c,
		})
	}
	dns.DefaultQueryNotify = func(record dns.QueryRecord) {
		sendMessage(Message{
			Type: DnsMessage,
			Data: newDnsQuery(record),
		})
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		scheduleReclaimOwnership()
		sendMessage(Message{
			Type: LoadedMessage,
			Data: providerName,
		})
	}
	updater.GeoUpdatedHook = func(completion *requestscope.Completion, sources map[string]string) {
		selectMu.Lock()
		defer selectMu.Unlock()
		if requestscope.BeginHook == nil {
			refreshRouteLocked(true)
			return
		}
		if completion == nil {
			return
		}
		for name, source := range sources {
			resource, exists := geoResources[name]
			if !exists || resource.url() != source {
				return
			}
		}
		refreshRouteQualifiedLocked(true, completion)
	}
	requestscope.ProxyUpdateHook = func(owner requestscope.Owner, update func()) {
		selectMu.Lock()
		defer selectMu.Unlock()
		update()
		if appRequests.ownerActive(owner) {
			refreshRouteLocked(true)
		}
	}
	updater.GeoUpdateHook = func(geoType string, updating bool, skipped bool, updateErr error) {
		if updating {
			claimGeoUpdateFromHook(geoType)
		} else {
			releaseGeoUpdateFromHook(geoType)
			scheduleReclaimOwnership()

		}
		status := GeoUpdateStatus{
			Type:     geoType,
			Updating: updating,
			Skipped:  skipped,
		}
		if updateErr != nil {
			status.Error = updateErr.Error()
		}
		sendMessage(Message{
			Type: GeoUpdateMessage,
			Data: status,
		})
	}
}
