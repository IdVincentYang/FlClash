package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

type ConfigManifest struct {
	LocalGroups       []sourceLocalGroup         `json:"localGroups,omitempty"`
	RuleLedger        *SourceRuleLedger          `json:"ruleLedger,omitempty"`
	ProviderMaterials []SourceProviderMaterial   `json:"providerMaterials,omitempty"`
	SourceUses        []SourceUse                `json:"sourceUses,omitempty"`
	ManagedMaterials  *ManagedMaterialsReceipt   `json:"managedMaterials,omitempty"`
	Version           int                        `json:"version"`
	YAMLSHA256        string                     `json:"yamlSha256"`
	ProfileID         *int64                     `json:"profileId"`
	ProfileName       string                     `json:"profileName"`
	Dependencies      []string                   `json:"dependencies"`
	SelectedMap       map[string]string          `json:"selectedMap"`
	TestURL           string                     `json:"testUrl"`
	AcceptedOverrides map[string]json.RawMessage `json:"acceptedOverrides"`
	ManagedPolicy     *ManagedPolicyDescriptor   `json:"managedPolicy,omitempty"`
}

type ManagedMaterialsReceipt struct {
	Version        int    `json:"version"`
	ProfileID      *int64 `json:"profileId"`
	OriginSHA256   string `json:"originSha256"`
	RawSHA256      string `json:"rawSha256"`
	MaterialSHA256 string `json:"materialSha256"`
	BindingsSHA256 string `json:"bindingsSha256"`
}

func (receipt *ManagedMaterialsReceipt) UnmarshalJSON(data []byte) error {
	type value ManagedMaterialsReceipt
	var decoded value
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&decoded); err != nil {
		return err
	}
	*receipt = ManagedMaterialsReceipt(decoded)
	return nil
}

type ConfigSourceTicket struct {
	Client  string            `json:"client"`
	Dataset uint64            `json:"dataset"`
	Sources map[string]uint64 `json:"sources"`
}

type ConfigInputRequest struct {
	InputID        string             `json:"inputId"`
	ExpectedRun    AppRequestState    `json:"expectedRun"`
	Active         bool               `json:"active"`
	Init           *InitParams        `json:"init,omitempty"`
	Source         ConfigSourceTicket `json:"source"`
	Replay         bool               `json:"replay"`
	ExpectedConfig *ConfigFence       `json:"expectedConfig,omitempty"`
}

type ConfigReceipt struct {
	Token              uint64 `json:"token"`
	Owner              uint64 `json:"owner"`
	InputID            string `json:"inputId"`
	ServiceID          string `json:"serviceId"`
	ProtectGeneration  uint64 `json:"protectGeneration"`
	OptionsFingerprint string `json:"optionsFingerprint"`
}

type ServiceCoreParams struct {
	MixedPort              int    `json:"mixedPort"`
	BindingID              uint64 `json:"bindingId"`
	LocalReachable         bool   `json:"localReachable"`
	AuthenticationRequired bool   `json:"authenticationRequired"`
}

type ConfigFact struct {
	ApplicationRoutingRules    map[string]string `json:"applicationRoutingRules,omitempty"`
	ApplicationRoutingRevision string            `json:"applicationRoutingRevision,omitempty"`
	MaterialPending            bool              `json:"materialPending,omitempty"`
	RuntimeEpoch               string            `json:"runtimeEpoch"`
	Version                    uint64            `json:"version"`
	Token                      uint64            `json:"token"`
	Owner                      uint64            `json:"owner"`
	InputID                    string            `json:"inputId"`
	YAMLSHA256                 string            `json:"yamlSha256"`
	ParsedSHA256               string            `json:"parsedSha256"`
	ProfileID                  *int64            `json:"profileId"`
	ProfileName                string            `json:"profileName"`
	Phase                      string            `json:"phase"`
	BusinessActive             bool              `json:"businessActive"`
	ReplayEligible             bool              `json:"replayEligible"`
	PolicyVersion              int               `json:"policyVersion"`
	PolicySHA256               string            `json:"policySha256"`
	MaintenanceProxy           string            `json:"maintenanceProxy"`
	MixedPort                  int               `json:"mixedPort"`
	RouteEpoch                 uint64            `json:"routeEpoch"`
	PicksVersion               uint64            `json:"picksVersion"`
}

type ConfigApplyResult struct {
	Status            string             `json:"status"`
	Message           string             `json:"message,omitempty"`
	RequiresFullApply bool               `json:"requiresFullApply,omitempty"`
	Receipt           ConfigReceipt      `json:"receipt"`
	CoreParams        *ServiceCoreParams `json:"coreParams,omitempty"`
	Fact              ConfigFact         `json:"fact"`
}

type configOperation struct {
	token   uint64
	request ConfigInputRequest
	reading atomic.Bool
}
type preparedConfig struct {
	inputVersion        int
	sourceClose         sync.Once
	sourceTrace         atomic.Pointer[sourceTraceState]
	sourceSerial        sync.Mutex
	sourceProviders     map[string]*sourceProviderRuntime
	sourcePrepared      bool
	sourceRecovery      *sourceMaterialPending
	sourceRetiredCount  int
	sourceRetiredBytes  int
	sourceInlineRetired []sourceInlineGeneration
	sourceRetiredInputs []string
	op                  *configOperation
	manifest            ConfigManifest
	bytes               []byte
	raw                 *config.RawConfig
	cfg                 *config.Config
	receipt             ConfigReceipt
	coreParams          ServiceCoreParams
	mixed               *listener.MixedBinding
	dns                 *configDNSBinding
	scope               *requestscope.BusinessScope
	stage               *providerStage
	sources             map[string]uint64
	dataset             uint64
	eligible            bool
}

var (
	latestConfig        atomic.Pointer[configOperation]
	activeBusiness      atomic.Pointer[requestscope.BusinessScope]
	preparedConfigGate  atomic.Pointer[preparedConfig]
	pendingConfig       *preparedConfig
	appliedConfig       *preparedConfig
	configFact          ConfigFact
	configFactSequence  atomic.Uint64
	configRuntimeEpoch  = newConfigRuntimeEpoch()
	checkpointMu        sync.Mutex
	errConfigSuperseded = errors.New("configuration request superseded")
)

func newConfigRuntimeEpoch() string { value, _ := randomRequestToken(); return value }
func inputHash(data []byte) string  { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
func validInputID(id string) bool {
	if len(id) != 64 {
		return false
	}
	for _, c := range id {
		if c < '0' || c > '9' && c < 'a' || c > 'f' {
			return false
		}
	}
	return true
}
func inputDirectory(home string) string { return filepath.Join(home, "config-inputs") }

func registerConfigInput(call *MethodCall, response MethodResponse) {
	if call.seq == 0 {
		call.seq = methodCallSeq.Add(1)
	}
	var request ConfigInputRequest
	if !decodeMethodArguments(call, response, &request) {
		return
	}
	if !validInputID(request.InputID) {
		response.failure("invalid_arguments", "invalid input identifier", nil)
		return
	}
	response.success(registerConfigOperation(call.seq, request))
}

func registerConfigOperation(sequence uint64, request ConfigInputRequest) ConfigReceipt {
	op := &configOperation{token: sequence, request: request}
	op.reading.Store(true)
	for {
		previous := latestConfig.Load()
		if previous != nil && previous.token >= op.token {
			break
		}
		if latestConfig.CompareAndSwap(previous, op) {
			if providerStageEnabled {
				appRequests.mu.Lock()
				appRequests.changedLocked()
				appRequests.mu.Unlock()
			}
			break
		}
	}
	return ConfigReceipt{Token: op.token, InputID: request.InputID}
}

func (p *preparedConfig) current() bool { return p != nil && latestConfig.Load() == p.op }
func currentConfigOperation(receipt ConfigReceipt) (*configOperation, error) {
	op := latestConfig.Load()
	if op == nil || op.token != receipt.Token || op.request.InputID != receipt.InputID {
		return nil, errConfigSuperseded
	}
	return op, nil
}

func sourceTicketValidLocked(ticket ConfigSourceTicket, keys []string) bool {
	if !features.Android && ticket.Client == "" {
		return true
	}
	if ticket.Client == "" || ticket.Client != appRequests.client || !appRequests.clientReady || ticket.Dataset != appRequests.dataset {
		return false
	}
	for _, key := range keys {
		value, ok := ticket.Sources[key]
		if !ok || value != appRequests.sources[key] {
			return false
		}
	}
	return true
}

func operationRunValidLocked(op *configOperation) bool {
	if !features.Android {
		return true
	}
	state, expected := appRequests.state, op.request.ExpectedRun
	return state.ProcessEpoch != "" && state.ProcessEpoch == expected.ProcessEpoch && state.IntentRevision == expected.IntentRevision && state.IntentRunning == expected.IntentRunning && state.Paused == expected.Paused && (!op.request.Active || state.IntentRunning && !state.Paused && state.Phase != "failed")
}

func readConfigManifest(home, id string) (ConfigManifest, error) {
	var manifest ConfigManifest
	if !validInputID(id) {
		return manifest, errors.New("invalid input identifier")
	}
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), id+".json"))
	if err != nil {
		return manifest, err
	}
	if len(data) > 4<<20 || inputHash(data) != id {
		return manifest, errors.New("input manifest digest mismatch")
	}
	if err = json.Unmarshal(data, &manifest); err != nil {
		return manifest, err
	}
	if manifest.Version != 1 && manifest.Version != 2 || features.Android && manifest.Version != 2 || !validInputID(manifest.YAMLSHA256) || len(manifest.Dependencies) == 0 {
		return manifest, errors.New("invalid input manifest")
	}
	if receipt := manifest.ManagedMaterials; receipt != nil {
		if manifest.ManagedPolicy == nil || receipt.Version != 1 || receipt.ProfileID == nil || *receipt.ProfileID < 0 || manifest.ProfileID == nil || *receipt.ProfileID != *manifest.ProfileID ||
			!validInputID(receipt.OriginSHA256) || !validInputID(receipt.RawSHA256) || !validInputID(receipt.MaterialSHA256) || !validInputID(receipt.BindingsSHA256) {
			return manifest, errors.New("invalid managed material receipt")
		}
	}
	return manifest, nil
}

func readConfigInput(home, id string) (ConfigManifest, []byte, *config.RawConfig, string, error) {
	manifest, err := readConfigManifest(home, id)
	if err != nil {
		return manifest, nil, nil, "", err
	}
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), manifest.YAMLSHA256+".yaml"))
	if err != nil {
		return manifest, nil, nil, "", err
	}
	if inputHash(data) != manifest.YAMLSHA256 {
		return manifest, nil, nil, "", errors.New("input YAML digest mismatch")
	}
	if manifest.Version == 2 {
		if err = validateInputSourceUses(home, manifest, data); err != nil {
			return manifest, nil, nil, "", err
		}
	}
	raw, parsedSHA, err := decodeConfigDocument(data)
	if err != nil {
		return manifest, nil, nil, "", err
	}
	if err := validateSourceRuleLedger(manifest, raw.Rule, raw.SubRules); err != nil {
		return manifest, nil, nil, "", err
	}

	var app applicationRouteSettings
	if value := manifest.AcceptedOverrides["application-routing"]; len(value) != 0 {
		if json.Unmarshal(value, &app) != nil || app.ProfileID == nil || manifest.ProfileID == nil || *app.ProfileID != *manifest.ProfileID {
			return manifest, nil, nil, "", errors.New("application routing profile mismatch")
		}
	}
	if err = patchConfigInput(raw, manifest.AcceptedOverrides); err != nil {
		return manifest, nil, nil, "", err
	}
	if err = validateManagedInput(manifest, raw); err != nil {
		return manifest, nil, nil, "", err
	}
	if err = validateSourceProviderMaterials(home, manifest, raw); err != nil {
		return manifest, nil, nil, "", err
	}
	if err = validateLocalGroupMaterials(home, manifest, raw); err != nil {
		return manifest, nil, nil, "", err
	}
	return manifest, slices.Clone(data), raw, parsedSHA, nil
}

func decodeConfigDocument(data []byte) (*config.RawConfig, string, error) {
	parsed, err := age.DecryptBytes(data)
	if err != nil {
		return nil, "", err
	}
	var object map[string]any
	if err = yaml.Unmarshal(parsed, &object); err != nil {
		return nil, "", err
	}
	if len(object) == 0 {
		return nil, "", errors.New("configuration must be a nonempty YAML object")
	}
	raw, err := config.UnmarshalRawConfig(data)
	return raw, inputHash(parsed), err
}

func configResult(status string, receipt ConfigReceipt, err error) ConfigApplyResult {
	result := ConfigApplyResult{Status: status, Receipt: receipt, Fact: configFact}
	if err != nil {
		result.Message = capabilityError(err).Error()
	}
	return result
}

func lockConfigInputRead() (string, error) {
	deadline := time.Now().Add(10 * time.Second)
	for {
		id, err := beginRequestDataRead()
		if err != nil {
			return "", err
		}
		if configMu.TryLock() {
			return id, nil
		}
		appRequests.endDataRead(id)
		if time.Now().After(deadline) {
			return "", errRequestCommitBusy
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func prepareConfig(receipt ConfigReceipt) ConfigApplyResult {
	if coreLifecycleUnavailable(receipt.Token) {
		return ConfigApplyResult{Status: "blocked", Receipt: receipt, Message: errCoreLifecycleUnavailable.Error()}
	}
	op, err := currentConfigOperation(receipt)
	if err != nil {
		return ConfigApplyResult{Status: "superseded", Receipt: receipt, Message: err.Error()}
	}
	defer op.reading.Store(false)
	if err := requestWriterError(); err != nil {
		return configResult("rejected", receipt, err)
	}
	readID, err := lockConfigInputRead()
	if err != nil {
		return ConfigApplyResult{Status: "rejected", Receipt: receipt, Message: err.Error()}
	}
	defer configMu.Unlock()
	defer appRequests.endDataRead(readID)
	if err := requestWriterError(); err != nil {
		return configResult("rejected", receipt, err)
	}

	op, err = currentConfigOperation(receipt)
	if err != nil {
		return configResult("superseded", receipt, err)
	}
	home := C.Path.HomeDir()
	if op.request.Init != nil {
		home = op.request.Init.HomeDir
		if isInit.Load() && filepath.Clean(home) != filepath.Clean(C.Path.HomeDir()) {
			return configResult("rejected", receipt, errors.New("core home cannot change after initialization"))
		}
	}
	if _, err := os.Stat(filepath.Join(home, "request-recovery-required")); !os.IsNotExist(err) {
		return configResult("rejected", receipt, errors.New("configuration recovery requires Flutter"))
	}
	manifest, bytes, raw, parsedSHA, err := readConfigInput(home, op.request.InputID)
	if err != nil {
		return configResult("rejected", receipt, err)
	}
	if manifest.ManagedPolicy != nil && !op.request.Replay && op.request.ExpectedConfig == nil {
		return configResult("rejected", receipt, errManagedPolicy)
	}
	selectMu.Lock()
	checkpointMu.Lock()
	if !configFenceMatchesLocked(op.request.ExpectedConfig) {
		checkpointMu.Unlock()
		selectMu.Unlock()
		return configResult("staleInput", receipt, errConfigSuperseded)
	}
	replayValid := true
	if op.request.Replay {
		ref, err := readCheckpointLocked(home)
		replayValid = err == nil && ref.InputID == op.request.InputID
	}
	appRequests.mu.Lock()
	valid := latestConfig.Load() == op && operationRunValidLocked(op)
	if op.request.Replay {
		valid = valid && replayValid && replayTicketValidLocked(op.request.Source, manifest.Dependencies)
	} else {
		valid = valid && sourceTicketValidLocked(op.request.Source, manifest.Dependencies)
	}
	sources := make(map[string]uint64, len(manifest.Dependencies))
	dataset := appRequests.dataset
	for _, key := range manifest.Dependencies {
		sources[key] = appRequests.sources[key]
	}
	appRequests.mu.Unlock()
	if !valid {
		checkpointMu.Unlock()
		selectMu.Unlock()
		return configResult("superseded", receipt, errConfigSuperseded)
	}
	if coreLifecycleUnavailable(receipt.Token) {
		checkpointMu.Unlock()
		selectMu.Unlock()
		return configResult("blocked", receipt, errCoreLifecycleUnavailable)
	}
	if providerStageEnabled && pendingConfig != nil && pendingConfig.stage != nil {
		pendingConfig.stage.retire()
	}
	if op.request.Init != nil && !isInit.Load() {
		if providerStageEnabled && stageBusyForInit() {
			checkpointMu.Unlock()
			selectMu.Unlock()
			return configResult("blocked", receipt, errCoreLifecycleUnavailable)
		}
		initializeCore(op.request.Init)
	}
	if providerStageEnabled {
		stagedCore.Lock()
		if lifecycleUnavailableLocked(receipt.Token) {
			stagedCore.Unlock()
			checkpointMu.Unlock()
			selectMu.Unlock()
			return configResult("blocked", receipt, errCoreLifecycleUnavailable)
		}
	}
	owner, cleanups := appRequests.nextConfigOwner()
	appRequests.mu.Lock()
	appRequests.configToken = op.token
	appRequests.mu.Unlock()
	receipt.Owner = owner.ID
	p := &preparedConfig{op: op, manifest: manifest, bytes: bytes, raw: raw, receipt: receipt, sources: sources, dataset: dataset, eligible: true}
	p.scope = requestscope.NewBusinessScope(receipt.Token, func() bool { return businessAllowed(p) })
	p.inputVersion = manifest.Version
	p.coreParams = ServiceCoreParams{MixedPort: raw.MixedPort, LocalReachable: !raw.AllowLan || raw.BindAddress == "*" || raw.BindAddress == "0.0.0.0" || raw.BindAddress == "127.0.0.1" || raw.BindAddress == "", AuthenticationRequired: len(config.ParseAuthentication(raw.Authentication)) != 0}
	previousPrepared := pendingConfig
	pendingConfig = p
	appliedConfig = nil
	configFact = ConfigFact{RuntimeEpoch: configRuntimeEpoch, Version: configFactSequence.Add(1), Token: receipt.Token, Owner: owner.ID, InputID: receipt.InputID, YAMLSHA256: manifest.YAMLSHA256, ParsedSHA256: parsedSHA, ProfileID: manifest.ProfileID, ProfileName: manifest.ProfileName, Phase: "parsing", ReplayEligible: true}
	configFact.MixedPort = raw.MixedPort
	if manifest.ManagedPolicy != nil {
		configFact.PolicyVersion = manifest.ManagedPolicy.Version
		configFact.PolicySHA256 = manifest.ManagedPolicy.PolicySHA256
		configFact.MaintenanceProxy = manifest.ManagedPolicy.MaintenanceProxy
	}
	checkpointMu.Unlock()
	selectMu.Unlock()
	if providerStageEnabled {
		stagedCore.Unlock()
	}
	finishRequestCleanup(cleanups)
	revokeBusiness()
	isRunning.Store(false)
	preparedConfigGate.Store(nil)
	tunnel.OnSuspend()
	stopBusinessListeners()
	if currentConfig != nil {
		if !providerStageEnabled {
			currentConfig.CloseProviders()
			closeSourceConfigProxies(previousPrepared, currentConfig)
		}
		currentConfig = nil
	}
	activeBusiness.Store(p.scope)
	if op.request.Active {
		listener.SetAllowLan(raw.AllowLan)
		listener.SetBindAddress(raw.BindAddress)
		p.mixed, err = listener.PrepareMixed(raw.MixedPort, bindObservedBusiness(p.scope))
		if err != nil {
			return blockConfigLocked(p, err)
		}
		if p.mixed != nil {
			p.coreParams.BindingID = p.mixed.ID
		}
	}
	preparedConfigGate.Store(p)
	result := configResult("prepared", receipt, nil)
	result.CoreParams = &p.coreParams
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	return result
}

func pendingForReceipt(receipt ConfigReceipt) (*preparedConfig, error) {
	p := pendingConfig
	if p == nil || !p.current() || p.receipt.Token != receipt.Token || p.receipt.Owner != receipt.Owner || p.receipt.InputID != receipt.InputID {
		return nil, errConfigSuperseded
	}
	appRequests.mu.Lock()
	valid := isInit.Load() && appRequests.phase != "failed" && appRequests.phase != "retired" && appRequests.owner.ID == receipt.Owner && appRequests.dataset == p.dataset && operationRunValidLocked(p.op)
	for key, revision := range p.sources {
		if revision != appRequests.sources[key] {
			valid = false
		}
	}
	appRequests.mu.Unlock()
	if !valid {
		return nil, errConfigSuperseded
	}
	if err := checkSourceUses(C.Path.HomeDir(), p.manifest.SourceUses); err != nil {
		return nil, err
	}
	return p, nil
}

func supersededConfigResult(receipt ConfigReceipt, err error) ConfigApplyResult {
	if p := pendingConfig; p != nil && p.receipt.Token == receipt.Token && p.receipt.Owner == receipt.Owner && configFact.Phase != "ready" {
		result := blockConfigLocked(p, err)
		result.Status = "superseded"
		return result
	}
	return configResult("superseded", receipt, err)
}

func installConfig(receipt ConfigReceipt) ConfigApplyResult {
	if providerStageEnabled {
		return installGuardedConfig(receipt)
	}
	configMu.Lock()
	defer configMu.Unlock()
	p, result := prepareInstallLocked(receipt)
	if result != nil {
		return *result
	}
	cfg := p.cfg
	dnsListen := cfg.DNS.Listen
	cfg.DNS.Listen = ""
	hub.ApplyConfigStaged(cfg)
	cfg.DNS.Listen = dnsListen
	return finishInstallLocked(p)
}

func installFailure(p *preparedConfig, err error) *ConfigApplyResult {
	result := blockConfigLocked(p, capabilityError(err))
	return &result
}

func prepareInstallLocked(receipt ConfigReceipt) (*preparedConfig, *ConfigApplyResult) {
	p, err := pendingForReceipt(receipt)
	if err != nil {
		result := supersededConfigResult(receipt, err)
		return nil, &result
	}
	if p.cfg != nil {
		result := configResult("installed", receipt, nil)
		return nil, &result
	}
	if err = p.mixed.Validate(); err != nil {
		return nil, installFailure(p, err)
	}
	if !p.sourcePrepared {
		if err := prepareSourceProviders(p); err != nil {
			return nil, installFailure(p, err)
		}
		p.sourcePrepared = true
	}
	recordSourceRawFactories(p.raw)
	for _, source := range p.sourceProviders {
		if source.plan.Kind != "provider-proxy" {
			continue
		}
		body, err := readSourceObject(C.Path.HomeDir(), source.material.MaterialHash, sourceCandidateMax)
		if err != nil {
			return nil, installFailure(p, err)
		}
		document, err := sourceProviderProxyDocument(body, source.plan.Mapping)
		if err != nil {
			return nil, installFailure(p, err)
		}
		recordSourceNodeFactories(document)
	}
	cfg, err := config.ParseRawConfig(p.raw)
	if err != nil {
		appRequests.mu.Lock()
		recoverable := appRequests.bootstrap != nil && appRequests.bootstrap.Owner.ID == p.receipt.Owner
		appRequests.mu.Unlock()
		if recoverable {
			result := configResult("bootstrapRequired", p.receipt, err)
			return nil, &result
		}
		return nil, installFailure(p, err)
	}
	p.cfg = cfg
	recordSourceDNSReaders(cfg.DNS)
	if err := installSourceProviders(p); err != nil {
		return nil, installFailure(p, err)
	}
	installSourceRuleTracing(p)
	if cfg.NTP.WriteToSystem && !systemTimeWritable {
		cfg.NTP.WriteToSystem = false
	}
	if cfg.General.MixedPort != p.coreParams.MixedPort || (len(cfg.Users) != 0) != p.coreParams.AuthenticationRequired {
		return nil, installFailure(p, errors.New("service parameters differ from prepared input"))
	}
	if _, err = pendingForReceipt(receipt); err != nil {
		return nil, installFailure(p, err)
	}
	setTestURL(p.manifest.TestURL)
	if p.op.request.Active && cfg.DNS.Enable {
		p.dns, err = prepareConfigDNS(cfg.DNS.Listen, cfg.DNS.ListenRoutingMark, p.scope)
		if err != nil {
			return nil, installFailure(p, err)
		}
		ordinaryDNS.Store(p.dns)
	}
	return p, nil
}

func finishInstallLocked(p *preparedConfig) ConfigApplyResult {
	cfg := p.cfg
	if err := p.dns.start(p.scope, resolver.DefaultService); err != nil {
		return blockConfigLocked(p, err)
	}
	patchSelectGroup(p.manifest.SelectedMap)
	bumpRouteEpoch()
	if _, err := pendingForReceipt(p.receipt); err != nil {
		return blockConfigLocked(p, err)
	}
	if p.op.request.Active {
		if err := updateListenersChecked(cfg, bindObservedBusiness(p.scope), p.mixed); err != nil {
			return blockConfigLocked(p, err)
		}
	}
	if providerStageEnabled {
		stagedCore.Lock()
		if lifecycleUnavailableLocked(0) {
			stagedCore.Unlock()
			return blockConfigLocked(p, errCoreLifecycleUnavailable)
		}
		defer stagedCore.Unlock()
	}
	checkpointMu.Lock()
	currentConfig = cfg
	if trace := p.sourceTrace.Load(); trace != nil {
		configFact.ApplicationRoutingRevision = trace.applicationRevision
		configFact.ApplicationRoutingRules = trace.applicationRuleKeys
	}
	configFact.Phase = "installed"
	configFact.BusinessActive = false
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	return configResult("installed", p.receipt, nil)
}

func activateConfig(receipt ConfigReceipt) ConfigApplyResult {
	configMu.Lock()
	defer configMu.Unlock()
	p, err := pendingForReceipt(receipt)
	if err != nil {
		return supersededConfigResult(receipt, err)
	}
	if !stageReady(p) {
		return configResult("rejected", receipt, errors.New("Provider initialization is incomplete"))
	}
	if p.cfg == nil || configFact.Phase != "installed" {
		return blockConfigLocked(p, errors.New("configuration is not installed"))
	}
	if err = p.mixed.Validate(); err != nil {
		return blockConfigLocked(p, err)
	}
	if err = p.dns.validate(); err != nil {
		return blockConfigLocked(p, err)
	}
	if providerStageEnabled {
		stagedCore.Lock()
		if lifecycleUnavailableLocked(0) {
			stagedCore.Unlock()
			return configResult("rejected", receipt, errCoreLifecycleUnavailable)
		}
	}
	checkpointMu.Lock()
	appRequests.mu.Lock()
	valid := isInit.Load() && appRequests.phase != "failed" && appRequests.phase != "retired" && p.current() && operationRunValidLocked(p.op) && appRequests.owner.ID == receipt.Owner && appRequests.dataset == p.dataset
	state := appRequests.state
	if features.Android && p.op.request.Active {
		valid = valid && receipt.ServiceID != "" && receipt.ServiceID == state.ServiceID && state.Phase == "starting" && (receipt.ProtectGeneration == 0 && state.ProtectPhase == "none" || receipt.ProtectGeneration != 0 && receipt.ProtectGeneration == state.ProtectGeneration && state.ProtectPhase == "ready") && receipt.OptionsFingerprint != ""
	}
	for key, revision := range p.sources {
		if revision != appRequests.sources[key] {
			valid = false
		}
	}
	if valid {
		p.receipt = receipt
		appRequests.phase = "ready"
	}
	appRequests.mu.Unlock()
	if !valid {
		checkpointMu.Unlock()
		if providerStageEnabled {
			stagedCore.Unlock()
		}
		return blockConfigLocked(p, errConfigSuperseded)
	}
	appliedConfig = p
	configFact.Phase = "ready"
	configFact.BusinessActive = p.op.request.Active
	configFact.Version = configFactSequence.Add(1)
	status := "installedInactive"
	if p.op.request.Active {
		isRunning.Store(true)
		if activated := p.scope.Activate(); providerStageEnabled && !activated {
			checkpointMu.Unlock()
			stagedCore.Unlock()
			return blockConfigLocked(p, errConfigSuperseded)
		}
		tunnel.OnRunning()
		status = "activated"
	} else {
		isRunning.Store(false)
		tunnel.OnSuspend()
	}
	if providerStageEnabled {
		stagedCore.Unlock()
	}
	err = publishCheckpointLocked(p)
	publishSourceTraceState(p, configFact.InputID, false)
	checkpointMu.Unlock()
	if err != nil {
		return blockConfigLocked(p, fmt.Errorf("persist accepted configuration: %w", err))
	}
	if coreLifecycleUnavailable(0) {
		return blockConfigLocked(p, errCoreLifecycleUnavailable)
	}
	reconcileGeoUpdater()
	for _, provider := range p.sourceProviders {
		provider.start()
	}
	queueInputCollection()
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	return configResult(status, receipt, nil)
}

func businessAllowed(p *preparedConfig) bool {
	if coreLifecycleUnavailable(0) {
		return false
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	if p.scope != activeBusiness.Load() || appRequests.owner.ID != p.receipt.Owner || appRequests.phase != "ready" || !isRunning.Load() {
		return false
	}
	if !features.Android {
		return true
	}
	state := appRequests.state
	return operationRunValidLocked(p.op) && state.ServiceID == p.receipt.ServiceID && (p.receipt.ProtectGeneration == 0 && state.ProtectPhase == "none" || p.receipt.ProtectGeneration != 0 && state.ProtectGeneration == p.receipt.ProtectGeneration && state.ProtectPhase == "ready") && (state.Phase == "starting" || state.Phase == "started")
}

func revokeBusiness() {
	if scope := activeBusiness.Swap(nil); scope != nil {
		scope.Close()
	}
}

func retireOwnedBusiness(scope *requestscope.BusinessScope) {
	configMu.Lock()
	defer configMu.Unlock()
	if activeBusiness.Load() != scope {
		return
	}
	isRunning.Store(false)
	tunnel.OnSuspend()
	stopBusinessListeners()
	checkpointMu.Lock()
	configFact.BusinessActive = false
	configFact.Phase = "retired"
	configFact.Version = configFactSequence.Add(1)
	checkpointMu.Unlock()
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
}

func blockConfigLocked(p *preparedConfig, err error) ConfigApplyResult {
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	if pendingConfig != p {
		return configResult("superseded", p.receipt, errConfigSuperseded)
	}
	if providerStageEnabled && p.stage != nil {
		p.stage.retire()
	}
	p.scope.Close()
	preparedConfigGate.CompareAndSwap(p, nil)
	tunnel.OnSuspend()
	isRunning.Store(false)
	stopBusinessListeners()
	if p.cfg != nil && (!providerStageEnabled || p.stage == nil) {
		p.cfg.CloseProviders()
		closeSourceConfigProxies(p, p.cfg)
	}
	p.cfg, p.raw, p.bytes = nil, nil, nil
	p.eligible = false
	if appliedConfig == p {
		appliedConfig = nil
	}
	currentConfig = nil
	appRequests.setPhase(requestscope.Owner{ID: p.receipt.Owner}, "failed")
	configFact.Phase = "failed"
	configFact.BusinessActive = false
	configFact.ReplayEligible = false
	configFact.Version = configFactSequence.Add(1)
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	return configResult("blocked", p.receipt, err)
}

func abortConfig(receipt ConfigReceipt) ConfigApplyResult {
	configMu.Lock()
	defer configMu.Unlock()
	p := pendingConfig
	if p == nil || !p.current() || p.receipt.Token != receipt.Token || receipt.Owner != 0 && p.receipt.Owner != receipt.Owner || p.receipt.InputID != receipt.InputID {
		return configResult("superseded", receipt, errConfigSuperseded)
	}
	appRequests.mu.Lock()
	valid := appRequests.owner.ID == p.receipt.Owner
	if features.Android {
		valid = valid && appRequests.state.ProcessEpoch == p.op.request.ExpectedRun.ProcessEpoch && appRequests.state.IntentRevision == p.op.request.ExpectedRun.IntentRevision
	}
	failed := appRequests.phase == "failed"
	appRequests.mu.Unlock()
	if !valid {
		return configResult("superseded", receipt, errConfigSuperseded)
	}
	if failed {
		return configResult("blocked", receipt, nil)
	}
	return blockConfigLocked(p, errors.New("configuration setup failed"))
}

func configStateSnapshot() ConfigFact {
	configMu.Lock()
	defer configMu.Unlock()
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	fact := configFact
	fact.RouteEpoch, fact.PicksVersion = routeStamp()
	if appliedConfig != nil && fact.Owner == appliedConfig.receipt.Owner {
		fact.ReplayEligible = appliedConfig.eligible
		if trace := appliedConfig.sourceTrace.Load(); trace != nil {
			fact.ApplicationRoutingRevision = trace.applicationRevision
			fact.ApplicationRoutingRules = trace.applicationRuleKeys
		}
	}
	if fact.RuntimeEpoch == "" {
		fact.RuntimeEpoch = configRuntimeEpoch
		fact.Phase = "unknown"
	}
	if scope := activeBusiness.Load(); fact.BusinessActive && (scope == nil || scope.Check() != nil) {
		fact.BusinessActive = false
		fact.Phase = "retired"
	}
	return fact
}

func patchGeneralOverrides(target any, params *UpdateParams) error {
	encoded, err := json.Marshal(params)
	if err != nil {
		return err
	}
	var values map[string]json.RawMessage
	if err = json.Unmarshal(encoded, &values); err != nil {
		return err
	}
	for key, value := range values {
		if string(value) == "null" || key == "tun" || key == "external-controller" || key == "geox-url" {
			delete(values, key)
		}
	}
	encoded, err = json.Marshal(values)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, target)
}

func patchConfigInput(raw *config.RawConfig, values map[string]json.RawMessage) error {
	data, err := json.Marshal(values)
	if err != nil {
		return err
	}
	var p UpdateParams
	if err = json.Unmarshal(data, &p); err != nil {
		return err
	}
	if err := validateApplicationRoutes(p.ApplicationRouting); err != nil {
		return err
	}
	if err := patchGeneralOverrides(raw, &p); err != nil {
		return err
	}
	if p.Authentication != nil {
		if len(config.ParseAuthentication(raw.Authentication)) > 0 {
			raw.SkipAuthPrefixes = nil
		}
	}
	if p.ExternalController != nil {
		raw.ExternalController = *p.ExternalController
	}
	if p.GeoXUrl != nil {
		if v := p.GeoXUrl["geoip"]; v != "" {
			raw.GeoXUrl.GeoIp = v
		}
		if v := p.GeoXUrl["mmdb"]; v != "" {
			raw.GeoXUrl.Mmdb = v
		}
		if v := p.GeoXUrl["geosite"]; v != "" {
			raw.GeoXUrl.GeoSite = v
		}
		if v := p.GeoXUrl["asn"]; v != "" {
			raw.GeoXUrl.ASN = v
		}
	}
	if p.Tun != nil {
		raw.Tun.Enable = p.Tun.Enable
		if p.Tun.AutoRoute != nil {
			raw.Tun.AutoRoute = *p.Tun.AutoRoute
		}
		if p.Tun.Device != nil {
			raw.Tun.Device = *p.Tun.Device
		}
		if p.Tun.Stack != nil {
			raw.Tun.Stack = *p.Tun.Stack
		}
		if p.Tun.DNSHijack != nil {
			raw.Tun.DNSHijack = *p.Tun.DNSHijack
		}
		if p.Tun.RouteAddress != nil {
			raw.Tun.RouteAddress = *p.Tun.RouteAddress
		}
	}
	return nil
}

func initializeCore(params *InitParams) {
	sdkVersion.Store(int32(params.Version))
	C.SetHomeDir(params.HomeDir)
	initOwnership(params.HomeDir)
	isInit.Store(true)
}

func init() {
	registerMethod(failConfigBuildMethod, withArguments(func(request *ConfigBuildFailure, response MethodResponse) {
		response.success(failConfigBuild(request))
	}))
	registerMethod(getAppliedInputMethod, withoutArguments(func(response MethodResponse) {
		configMu.Lock()
		defer configMu.Unlock()
		if appliedConfig == nil || currentConfig == nil || configFact.Owner != appliedConfig.receipt.Owner {
			response.failure("configuration_unavailable", "no installed input", nil)
			return
		}
		raw, _, err := decodeConfigDocument(appliedConfig.bytes)
		if err == nil {
			err = patchConfigInput(raw, appliedConfig.manifest.AcceptedOverrides)
		}
		if err != nil {
			response.failure("configuration_unavailable", err.Error(), nil)
			return
		}
		response.success(raw)
	}))
	tunnel.ApplicationRoutingHook = resolveApplicationRoute
	requestscope.BusinessHook = activeBusiness.Load
	registerMethod(prepareConfigMethod, withArguments(func(p *ConfigReceipt, response MethodResponse) { response.success(prepareConfig(*p)) }))
	registerMethod(installConfigMethod, withArguments(func(p *ConfigReceipt, response MethodResponse) { response.success(installConfig(*p)) }))
	registerMethod(activateConfigMethod, withArguments(func(p *ConfigReceipt, response MethodResponse) { response.success(activateConfig(*p)) }))
	registerMethod(abortConfigMethod, withArguments(func(p *ConfigReceipt, response MethodResponse) { response.success(abortConfig(*p)) }))
	registerMethod(getConfigStateMethod, withoutArguments(func(response MethodResponse) { response.success(configStateSnapshot()) }))
	registerMethod(getReplayInputMethod, withArguments(func(p *InitParams, response MethodResponse) {
		value, err := replayConfigInput(p)
		if err != nil {
			response.failure("configuration_unavailable", err.Error(), nil)
		} else {
			response.success(value)
		}
	}))
}
