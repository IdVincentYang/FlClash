package main

import "container/list"

const requestHistoryLimit = 4096
const requestVersionLimit uint64 = 1<<53 - 1

type requestVersionEntry struct {
	key  string
	pins int
	cold *list.Element
}

type requestVersions struct {
	values    map[string]uint64
	entries   map[string]*requestVersionEntry
	cold      list.List
	highWater uint64
	exhausted bool
}

func newRequestVersions(values map[string]uint64) *requestVersions {
	return &requestVersions{values: values, entries: make(map[string]*requestVersionEntry)}
}

func (v *requestVersions) get(key string) uint64 {
	if v.exhausted {
		return 0
	}
	e := v.entries[key]
	if e == nil {
		return 0
	}
	if e.cold != nil {
		v.cold.MoveToBack(e.cold)
	}
	value := v.values[key]
	if value == 0 || value > requestVersionLimit {
		v.exhausted = true
		return 0
	}
	return value
}

func (v *requestVersions) matches(key string, version uint64) bool {
	return version != 0 && version <= requestVersionLimit && v.get(key) == version
}

func (v *requestVersions) ensure(key string) uint64 {
	if value := v.get(key); value != 0 {
		return value
	}
	if v.exhausted || v.highWater > requestVersionLimit-2 {
		v.exhausted = true
		return 0
	}
	// Skip the successor reserved for one material invalidation.
	v.highWater += 2
	e := &requestVersionEntry{key: key}
	v.values[key], v.entries[key] = v.highWater, e
	e.cold = v.cold.PushBack(e)
	v.trim()
	return v.highWater
}

func (v *requestVersions) advance(key string, create bool) uint64 {
	value := v.get(key)
	if value == 0 {
		if create {
			return v.ensure(key)
		}
		return 0
	}
	if value == requestVersionLimit {
		v.exhausted = true
		return 0
	}
	value++
	v.values[key] = value
	if value > v.highWater {
		v.highWater = value
	}
	return value
}

func (v *requestVersions) retain(key string) (uint64, func()) {
	value := v.ensure(key)
	if value == 0 {
		return 0, func() {}
	}
	e := v.entries[key]
	if e.cold != nil {
		v.cold.Remove(e.cold)
		e.cold = nil
	}
	e.pins++
	released := false
	return value, func() {
		if released {
			return
		}
		released = true
		e.pins--
		if e.pins == 0 {
			e.cold = v.cold.PushBack(e)
			v.trim()
		}
	}
}

func (v *requestVersions) removeCold(e *requestVersionEntry) {
	v.cold.Remove(e.cold)
	delete(v.values, e.key)
	delete(v.entries, e.key)
}

func (v *requestVersions) trim() {
	for v.cold.Len() > requestHistoryLimit {
		v.removeCold(v.cold.Front().Value.(*requestVersionEntry))
	}
}

func (v *requestVersions) clearCold() {
	for v.cold.Len() != 0 {
		v.removeCold(v.cold.Front().Value.(*requestVersionEntry))
	}
}

func requestVersionSuccessor(value uint64) (uint64, bool) {
	if value == 0 || value >= requestVersionLimit {
		return 0, false
	}
	return value + 1, true
}
