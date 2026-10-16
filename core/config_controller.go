package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"

	"github.com/metacubex/mihomo/component/requestscope"
)

type controllerConfigMutation struct{ owner, token uint64 }

func (m *controllerConfigMutation) valid() bool {
	op := latestConfig.Load()
	return op != nil && op.token == m.token && appRequests.currentOwner().ID == m.owner && configFact.Owner == m.owner && configFact.Phase == "ready"
}

func (m *controllerConfigMutation) Patch(data []byte) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	if fields == nil {
		return errors.New("configuration patch must be an object")
	}
	for name := range fields {
		switch name {
		case "mode", "ipv6", "log-level", "find-process-mode", "tcp-concurrent", "unified-delay", "geo-auto-update", "geo-update-interval", "geox-url":
		default:
			return errors.New("unsupported configuration patch: apply the complete configuration through FlClash")
		}
	}
	var params UpdateParams
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&params); err != nil {
		return err
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("configuration patch must contain one object")
	}
	for name, value := range params.GeoXUrl {
		if name != "geoip" && name != "mmdb" && name != "geosite" && name != "asn" || value == "" {
			return errors.New("unsupported Geo resource patch")
		}
	}
	return updateConfigOwned(&params, m)
}

func (m *controllerConfigMutation) Select(group, name string, clear bool) error {
	if !clear && name == "" {
		return errors.New("a nonempty proxy name is required")
	}
	result := changeProxyOwned(&ChangeProxyParams{GroupName: group, ProxyName: name}, m, clear)
	if result.Message != "" {
		return errors.New(result.Message)
	}
	return nil
}

func init() {
	requestscope.ControllerMutationHook = func() requestscope.ControllerMutation {
		m := &controllerConfigMutation{owner: appRequests.currentOwner().ID}
		if op := latestConfig.Load(); op != nil {
			m.token = op.token
		}
		return m
	}
}
