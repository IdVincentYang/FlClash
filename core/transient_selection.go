package main

import (
	"encoding/json"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
)

type transientSelection struct {
	owner         uint64
	group         *outboundgroup.URLTest
	node, testURL string
}

var transientSelections = map[string]transientSelection{}
var transientSelectionObserver bool

func rememberTransientSelectionLocked(name, node string, owner uint64, selector pickableGroup) {
	delete(transientSelections, name)
	group, ok := selector.(*outboundgroup.URLTest)
	if !ok || node == "" {
		return
	}
	data, err := group.MarshalJSON()
	if err != nil {
		return
	}
	var state struct {
		TestURL string `json:"testUrl"`
	}
	if json.Unmarshal(data, &state) != nil {
		return
	}
	transientSelections[name] = transientSelection{owner: owner, group: group, node: node, testURL: state.TestURL}
	if transientSelectionObserver {
		return
	}
	transientSelectionObserver = true
	safeGoDetached("transient selection", func() {
		ticker := time.NewTicker(250 * time.Millisecond)
		defer ticker.Stop()
		for range ticker.C {
			selectMu.Lock()
			checkpointMu.Lock()
			owner := configFact.Owner
			checkpointMu.Unlock()
			for name, choice := range transientSelections {
				current, err := selectableGroup(name)
				if err != nil || current != choice.group || owner != choice.owner {
					delete(transientSelections, name)
					continue
				}
				alive := false
				for _, node := range choice.group.Proxies() {
					if node.Name() == choice.node {
						alive = node.AliveForTestUrl(choice.testURL)
						break
					}
				}
				if !alive || choice.group.Now() != choice.node {
					choice.group.ForceSet("")
					delete(transientSelections, name)
					refreshRouteLocked(false)
				}
			}
			if len(transientSelections) == 0 {
				transientSelectionObserver = false
				selectMu.Unlock()
				return
			}
			selectMu.Unlock()
		}
	})
}
