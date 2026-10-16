package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type configCheckpoint struct {
	Version      int      `json:"version"`
	InputID      string   `json:"inputId"`
	Dependencies []string `json:"dependencies"`
}

var writeConfigManifest = atomicConfigFile

func atomicConfigFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".input-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func markConfigRecoveryRequired(home string) error {
	return atomicConfigFile(filepath.Join(home, "request-recovery-required"), []byte("configuration checkpoint commit incomplete\n"))
}

func readCheckpointLocked(home string) (configCheckpoint, error) {
	var ref configCheckpoint
	if _, err := os.Stat(filepath.Join(home, "request-recovery-required")); !os.IsNotExist(err) {
		return ref, errors.New("configuration recovery requires Flutter")
	}
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json"))
	if err != nil {
		return ref, errors.New("no verifiable configuration checkpoint; open Flutter to rebuild it")
	}
	if err = json.Unmarshal(data, &ref); err != nil || ref.Version != 1 || !validInputID(ref.InputID) {
		return ref, errors.New("configuration checkpoint is unavailable; open Flutter to rebuild it")
	}
	return ref, nil
}

func replayTicketValidLocked(ticket ConfigSourceTicket, keys []string) bool {
	if ticket.Dataset != appRequests.dataset {
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

func replayConfigInput(init *InitParams) (ConfigInputRequest, error) {
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	home := init.HomeDir
	if isInit.Load() && filepath.Clean(home) != filepath.Clean(C.Path.HomeDir()) {
		return ConfigInputRequest{}, errors.New("core home mismatch")
	}
	ref, err := readCheckpointLocked(home)
	if err != nil {
		return ConfigInputRequest{}, err
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	ticket := ConfigSourceTicket{Dataset: appRequests.dataset, Sources: make(map[string]uint64)}
	for _, key := range ref.Dependencies {
		ticket.Sources[key] = appRequests.sources[key]
	}
	return ConfigInputRequest{InputID: ref.InputID, Source: ticket, Replay: true, Init: init}, nil
}

func publishCheckpointLocked(p *preparedConfig) error {
	if !p.eligible {
		return errors.New("input was revoked for replay")
	}
	appRequests.mu.Lock()
	valid := appliedConfig == p && configFact.Owner == p.receipt.Owner && configFact.Phase == "ready"
	for key, version := range p.sources {
		if appRequests.sources[key] != version {
			valid = false
		}
	}
	appRequests.mu.Unlock()
	if !valid {
		return errConfigSuperseded
	}
	data, err := json.Marshal(configCheckpoint{Version: 1, InputID: configFact.InputID, Dependencies: slices.Clone(p.manifest.Dependencies)})
	if err != nil {
		return err
	}
	err = atomicConfigFile(filepath.Join(inputDirectory(C.Path.HomeDir()), "checkpoint.json"), data)
	if err != nil {
		_ = markConfigRecoveryRequired(C.Path.HomeDir())
	}
	return err
}

func invalidateConfigCheckpointLocked(key string, dataset bool) error {
	for _, p := range []*preparedConfig{pendingConfig, appliedConfig} {
		if p != nil && (dataset || slices.Contains(p.manifest.Dependencies, key)) {
			p.eligible = false
		}
	}
	home := C.Path.HomeDir()
	var ref configCheckpoint
	data, err := os.ReadFile(filepath.Join(inputDirectory(home), "checkpoint.json"))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		_ = markConfigRecoveryRequired(home)
		return err
	}
	if json.Unmarshal(data, &ref) != nil {
		dataset = true
	}
	if !dataset && !slices.Contains(ref.Dependencies, key) {
		return nil
	}

	err = atomicConfigFile(filepath.Join(inputDirectory(home), "checkpoint.json"), []byte(`{"version":1,"inputId":""}`))
	if err != nil {
		_ = markConfigRecoveryRequired(home)
	}
	return err
}

type checkpointCandidate struct {
	target                                     *preparedConfig
	manifest                                   ConfigManifest
	id                                         string
	version, dataset, routeEpoch, picksVersion uint64
	eligible                                   bool
	published                                  bool
	sources                                    map[string]uint64
}

func saveAcceptedConfigChanges(params *UpdateParams, picks map[string]string) error {
	checkpointMu.Lock()
	p := appliedConfig
	if p != nil && configFact.Phase == "ready" && configFact.Owner == p.receipt.Owner {
		if err := mergeAcceptedOverrides(&p.manifest, params); err != nil {
			checkpointMu.Unlock()
			return err
		}
	}
	checkpointMu.Unlock()
	for attempt := 0; attempt < 8; attempt++ {
		candidate, err := prepareCheckpointCandidate(nil, picks)
		if err != nil {
			return err
		}
		if candidate == nil {
			return nil
		}
		if err = publishCheckpointCandidate(candidate); err != nil {
			return err
		}
		if candidate.published {
			return nil
		}
	}
	return errors.New("accepted configuration checkpoint changed before publication")
}

func prepareCheckpointCandidate(params *UpdateParams, picks map[string]string) (*checkpointCandidate, error) {
	p := appliedConfig
	if p == nil {
		return nil, nil
	}
	selectMu.Lock()
	actualPicks, err := checkpointSelectionsLocked()
	if err != nil {
		selectMu.Unlock()
		return nil, err
	}
	checkpointMu.Lock()
	selectMu.Unlock()
	if configFact.Phase != "ready" || configFact.Owner != p.receipt.Owner {
		checkpointMu.Unlock()
		return nil, nil
	}
	epoch, picksVersion := routeStamp()
	version := configFact.Version
	eligible := p.eligible
	manifest := p.manifest
	manifest.SelectedMap = maps.Clone(actualPicks)
	manifest.AcceptedOverrides = maps.Clone(manifest.AcceptedOverrides)
	if manifest.AcceptedOverrides == nil {
		manifest.AcceptedOverrides = make(map[string]json.RawMessage)
	}
	for key, value := range picks {
		manifest.SelectedMap[key] = value
	}
	if err := mergeAcceptedOverrides(&manifest, params); err != nil {
		checkpointMu.Unlock()
		return nil, err
	}
	appRequests.mu.Lock()
	dataset := appRequests.dataset
	sources := make(map[string]uint64, len(p.sources))
	for key := range p.sources {
		sources[key] = appRequests.sources[key]
	}
	appRequests.mu.Unlock()
	checkpointMu.Unlock()
	data, err := json.Marshal(manifest)
	if err != nil {
		return nil, err
	}
	id := inputHash(data)
	if err = writeConfigManifest(filepath.Join(inputDirectory(C.Path.HomeDir()), id+".json"), data); err != nil {
		return nil, err
	}
	return &checkpointCandidate{target: p, manifest: manifest, id: id, version: version, eligible: eligible, dataset: dataset, sources: sources, routeEpoch: epoch, picksVersion: picksVersion}, nil
}

func mergeAcceptedOverrides(manifest *ConfigManifest, params *UpdateParams) error {
	manifest.AcceptedOverrides = maps.Clone(manifest.AcceptedOverrides)
	if manifest.AcceptedOverrides == nil {
		manifest.AcceptedOverrides = make(map[string]json.RawMessage)
	}
	if params != nil {
		data, err := json.Marshal(params)
		if err != nil {
			return err
		}
		var values map[string]json.RawMessage
		_ = json.Unmarshal(data, &values)
		for key, value := range values {
			if string(value) == "null" {
				continue
			}
			if key == "tun" || key == "geox-url" {
				merged := make(map[string]json.RawMessage)
				_ = json.Unmarshal(manifest.AcceptedOverrides[key], &merged)
				if merged == nil {
					merged = make(map[string]json.RawMessage)
				}
				var incoming map[string]json.RawMessage
				_ = json.Unmarshal(value, &incoming)
				for k, v := range incoming {
					if string(v) != "null" {
						merged[k] = v
					}
				}
				value, _ = json.Marshal(merged)
			}
			manifest.AcceptedOverrides[key] = slices.Clone(value)
		}
	}
	return nil
}

func checkpointSelectionsLocked() (map[string]string, error) {
	picks, _ := readPicks()
	for name, proxy := range tunnel.AllProxies() {
		if _, ok := proxy.Adapter().(outboundgroup.SelectAble); !ok || proxy.Type() == C.Selector {
			continue
		}
		data, err := proxy.Adapter().MarshalJSON()
		if err != nil {
			return nil, err
		}
		var state struct {
			Fixed *string `json:"fixed"`
		}
		if err := json.Unmarshal(data, &state); err != nil {
			return nil, err
		}
		if state.Fixed != nil {
			picks[name] = *state.Fixed
		}
	}
	return picks, nil
}

func publishCheckpointCandidate(candidate *checkpointCandidate) error {
	if candidate == nil {
		return nil
	}
	p := candidate.target

	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	appRequests.mu.Lock()
	epoch, picksVersion := routeStamp()
	valid := p == appliedConfig && p.eligible == candidate.eligible && configFact.Version == candidate.version && configFact.Owner == p.receipt.Owner && appRequests.dataset == candidate.dataset && epoch == candidate.routeEpoch && picksVersion == candidate.picksVersion
	for key, value := range candidate.sources {
		if value != appRequests.sources[key] {
			valid = false
		}
	}
	appRequests.mu.Unlock()
	if !valid {
		return nil
	}
	candidate.published = true
	p.manifest = candidate.manifest
	configFact.InputID = candidate.id
	configFact.Version = configFactSequence.Add(1)
	configFact.ReplayEligible = p.eligible
	if p.eligible {
		if err := publishCheckpointLocked(p); err != nil {
			return fmt.Errorf("persist accepted changes: %w", err)
		}
	}
	sendMessage(Message{Type: ConfigStateMessage, Data: configFact})
	queueInputCollection()
	return nil
}
