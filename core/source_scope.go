package main

import (
	"errors"
	"path/filepath"

	"github.com/metacubex/mihomo/tunnel"
)

func reconcileSourceScopesLocked(home string) error {
	seen := map[*preparedConfig]bool{}
	for _, p := range []*preparedConfig{pendingConfig, appliedConfig} {
		if p == nil || seen[p] || checkSourceUses(home, p.manifest.SourceUses) == nil {
			continue
		}
		seen[p] = true
		if pendingConfig == p {
			blockConfigLocked(p, errSourceUseRevoked)
		} else {
			p.scope.Close()
			if p.stage == nil && p.cfg != nil {
				p.cfg.CloseProviders()
				closeSourceConfigProxies(p, p.cfg)
			}
			if activeBusiness.Load() == p.scope {
				isRunning.Store(false)
				tunnel.OnSuspend()
				stopBusinessListeners()
			}
			checkpointMu.Lock()
			p.eligible = false
			if configFact.Owner == p.receipt.Owner {
				configFact.BusinessActive = false
				configFact.ReplayEligible = false
				configFact.Phase = "retired"
				configFact.Version = configFactSequence.Add(1)
			}
			checkpointMu.Unlock()
		}
	}
	checkpointMu.Lock()
	defer checkpointMu.Unlock()
	ref, err := readCheckpointLocked(home)
	if err != nil {
		return nil
	}
	if _, _, _, _, err := readConfigInput(home, ref.InputID); err == nil {
		return nil
	}
	if err := atomicConfigFile(filepath.Join(inputDirectory(home), "checkpoint.json"), []byte(`{"version":1,"inputId":""}`)); err != nil {
		_ = markConfigRecoveryRequired(home)
		return errors.New("source use was revoked; replay checkpoint persistence failed")
	}
	return nil
}
