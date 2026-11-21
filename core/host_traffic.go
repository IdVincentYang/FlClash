package main

import (
	"strings"
	"sync"
	"sync/atomic"

	C "github.com/metacubex/mihomo/constant"
)

const maxHostTrafficTargets = 8192
const otherHostTrafficKey = "other:"

var hostTraffic = newHostTrafficStore(maxHostTrafficTargets)

type hostTrafficRow struct {
	Key      string `json:"key"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
}

type hostTrafficSnapshot struct {
	RuntimeEpoch string           `json:"runtimeEpoch"`
	Rows         []hostTrafficRow `json:"rows"`
}

type hostTrafficCounter struct {
	up   atomic.Int64
	down atomic.Int64
}

func (c *hostTrafficCounter) row(key string) hostTrafficRow {
	return hostTrafficRow{Key: key, Upload: c.up.Load(), Download: c.down.Load()}
}

type hostTrafficStore struct {
	mu       sync.RWMutex
	capacity int
	targets  map[string]*hostTrafficCounter
	other    hostTrafficCounter
}

func newHostTrafficStore(capacity int) *hostTrafficStore {
	return &hostTrafficStore{capacity: capacity, targets: make(map[string]*hostTrafficCounter)}
}

func hostTrafficKey(metadata *C.Metadata) string {
	if host := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(metadata.Host)), "."); host != "" {
		return "host:" + host
	}
	if metadata.DstIP.IsValid() {
		return "ip:" + metadata.DstIP.String()
	}
	return "unknown:"
}

func (s *hostTrafficStore) account(metadata *C.Metadata) func(int64, int64) {
	if metadata == nil || metadata.Type == C.INNER {
		return nil
	}
	if _, probe := pendingProbeRoutes.Load(metadata); probe {
		return nil
	}
	key := hostTrafficKey(metadata)
	var counter *hostTrafficCounter
	var bind sync.Once
	return func(up, down int64) {
		if up <= 0 && down <= 0 {
			return
		}
		bind.Do(func() { counter = s.counter(key) })
		if up > 0 {
			counter.up.Add(up)
		}
		if down > 0 {
			counter.down.Add(down)
		}
	}
}

func (s *hostTrafficStore) counter(key string) *hostTrafficCounter {
	s.mu.Lock()
	defer s.mu.Unlock()
	if counter := s.targets[key]; counter != nil {
		return counter
	}
	if len(s.targets) >= s.capacity {
		return &s.other
	}
	counter := &hostTrafficCounter{}
	s.targets[key] = counter
	return counter
}

func (s *hostTrafficStore) snapshot(epoch string) hostTrafficSnapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := hostTrafficSnapshot{RuntimeEpoch: epoch, Rows: make([]hostTrafficRow, 0, len(s.targets)+1)}
	for key, counter := range s.targets {
		if row := counter.row(key); row.Upload > 0 || row.Download > 0 {
			result.Rows = append(result.Rows, row)
		}
	}
	if other := s.other.row(otherHostTrafficKey); other.Upload > 0 || other.Download > 0 {
		result.Rows = append(result.Rows, other)
	}
	return result
}
