package main

import (
	"fmt"
	"testing"
)

func requestTestSourceVersion(r *appRequestRegistry, key string) uint64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.sourceVersionLocked(key)
}

func requestTestOperationVersion(r *appRequestRegistry, key string) uint64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.operationVersionLocked(key)
}

func TestRequestVersionTableBoundedOwnership(t *testing.T) {
	v := newRequestVersions(map[string]uint64{})
	first, release := v.retain("held")
	if next := v.advance("held", false); next != first+1 {
		t.Fatal("existing key lost its exact successor", first, next)
	}
	for i := 0; i < requestHistoryLimit*3; i++ {
		v.ensure(fmt.Sprintf("retired-%d", i))
		if len(v.values) > requestHistoryLimit+1 || len(v.entries) != len(v.values) || v.cold.Len() > requestHistoryLimit {
			t.Fatal("version auxiliaries exceed the live plus cold bound")
		}
	}
	if !v.matches("held", first+1) {
		t.Fatal("active holder was evicted")
	}
	v.clearCold()
	if len(v.values) != 1 || v.cold.Len() != 0 {
		t.Fatal("bulk cleanup removed active state or retained history")
	}
	release()
	release()
	v.clearCold()
	if len(v.values) != 0 || len(v.entries) != 0 {
		t.Fatal("released key retained auxiliary history")
	}
	if reborn := v.ensure("held"); reborn <= first+2 || v.matches("held", first) {
		t.Fatal("recreated key reused a version", reborn, first)
	}
}

func TestRequestVersionExhaustionDoesNotWrap(t *testing.T) {
	for _, action := range []string{"birth", "successor"} {
		t.Run(action, func(t *testing.T) {
			v := newRequestVersions(map[string]uint64{})
			v.highWater = requestVersionLimit - 2
			version, release := v.retain("last")
			if version != requestVersionLimit {
				t.Fatal("last exact JSON integer not allocated", version)
			}
			if _, ok := requestVersionSuccessor(version); ok {
				t.Fatal("prediction exceeded the protocol bound")
			}
			if action == "birth" {
				v.ensure("new")
			} else {
				v.advance("last", false)
			}
			if !v.exhausted || v.matches("last", version) || v.ensure("retry") != 0 {
				t.Fatal("exhausted qualification survived or wrapped")
			}
			release()
			v.clearCold()
			if len(v.values) != 0 || len(v.entries) != 0 || v.cold.Len() != 0 {
				t.Fatal("exhaustion prevented cleanup")
			}
		})
	}
}
