package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

const (
	sourceGrantFileLimit     = 4 << 20
	sourceEntityLimit        = 1024
	sourceCandidateMax       = 16 << 20
	sourceCandidateSlots     = 32
	sourceCandidateTotal     = 64 << 20
	sourceMaterialTotal      = 128 << 20
	sourceMaterialLeaseLimit = 128
)

var (
	errSourceRoutingDenied = errors.New("source routing permission excludes this capability")
	sourceAuthorityMu      sync.Mutex
	errSourceReview        = errors.New("source review required")
	errSourceSuperseded    = errors.New("source decision superseded")
	errSourceStore         = errors.New("source permissions unavailable")
	errSourceBudget        = errors.New("source storage budget exceeded")
	errSourceUseRevoked    = errors.New("source use permission revoked")
	writeSourcePermissions = atomicConfigFile
)

type SourceUse struct {
	Key          string `json:"key"`
	Kind         string `json:"kind"`
	Incarnation  string `json:"incarnation"`
	Epoch        uint64 `json:"epoch"`
	PurposeEpoch uint64 `json:"purposeEpoch"`
	Digest       string `json:"digest"`
}

type SourceGrant struct {
	Identity    string                         `json:"identity"`
	Incarnation string                         `json:"incarnation"`
	Revision    uint64                         `json:"revision"`
	UseEpoch    uint64                         `json:"useEpoch"`
	Routing     string                         `json:"routing"`
	Purposes    map[string]*sourcePurposeGrant `json:"purposes"`
}

type sourcePurposeGrant struct {
	Automatic    bool                   `json:"automatic"`
	UseEpoch     uint64                 `json:"useEpoch"`
	Contract     string                 `json:"contract,omitempty"`
	Accepted     []string               `json:"accepted"`
	BoundUses    map[string][]SourceUse `json:"boundUses,omitempty"`
	ReviewBundle *sourceReviewBundle    `json:"reviewBundle,omitempty"`
}

func sourcePurpose(key string) string {
	switch {
	case strings.HasPrefix(key, "script:"):
		return "script"
	case key == "application-config" || strings.HasPrefix(key, "config:"):
		return "config"
	case strings.HasPrefix(key, "provider-rule:"):
		return "provider-rule"
	case strings.HasPrefix(key, "provider-proxy:"):
		return "provider-proxy"
	default:
		return "profile"
	}
}

func validSourceKind(kind string) bool {
	return slices.Contains([]string{"profile", "script", "provider-proxy", "provider-rule", "config"}, kind)
}

type sourcePermissions struct {
	Version int                     `json:"version"`
	Grants  map[string]*SourceGrant `json:"grants"`
}

func sourcePermissionsPath(home string) string {
	return filepath.Join(home, "source-acceptance", "permissions.json")
}

func validSourceKey(key string) bool {
	return key != "" && len(key) <= 256 && !strings.ContainsAny(key, "\x00\r\n\t ")
}

func readSourcePermissions(home string) (*sourcePermissions, error) {
	file, err := os.Open(sourcePermissionsPath(home))
	if os.IsNotExist(err) {
		return &sourcePermissions{Version: 1, Grants: map[string]*SourceGrant{}}, nil
	}
	if err != nil {
		return nil, errSourceStore
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, sourceGrantFileLimit+1))
	if err != nil || len(data) > sourceGrantFileLimit {
		return nil, errSourceStore
	}
	var result sourcePermissions
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&result) != nil || decoder.Decode(new(any)) != io.EOF || result.Version != 1 || result.Grants == nil || len(result.Grants) > sourceEntityLimit {
		return nil, errSourceStore
	}
	for key, grant := range result.Grants {
		if !validSourceKey(key) || grant == nil || !validInputID(grant.Identity) || len(grant.Incarnation) != 48 || grant.Revision == 0 || grant.UseEpoch == 0 || !slices.Contains([]string{"source", "own"}, grant.Routing) || grant.Purposes == nil {
			return nil, errSourceStore
		}
		for kind, purpose := range grant.Purposes {
			if !validSourceKind(kind) || !sourceKindMatchesKey(key, kind) || purpose == nil || purpose.UseEpoch == 0 || purpose.Contract != "" && !validInputID(purpose.Contract) {
				return nil, errSourceStore
			}
			for _, digest := range purpose.Accepted {
				if !validInputID(digest) {
					return nil, errSourceStore
				}
			}
			for digest, uses := range purpose.BoundUses {
				if !slices.Contains(purpose.Accepted, digest) || kind != "config" {
					return nil, errSourceStore
				}
				for _, use := range uses {
					if !validSourceKey(use.Key) || !sourceKindMatchesKey(use.Key, use.Kind) || use.Kind == "config" || len(use.Incarnation) != 48 || use.Epoch == 0 || use.PurposeEpoch == 0 || !validInputID(use.Digest) {
						return nil, errSourceStore
					}
				}
			}
		}
	}
	return &result, nil
}

func saveSourcePermissions(home string, permissions *sourcePermissions) error {
	if len(permissions.Grants) > sourceEntityLimit {
		return errSourceBudget
	}
	data, err := json.Marshal(permissions)
	if err != nil || len(data) > sourceGrantFileLimit {
		return errSourceBudget
	}
	if err = writeSourcePermissions(sourcePermissionsPath(home), data); err != nil {
		return errSourceStore
	}
	return nil
}

func sourceUseAllowed(permissions *sourcePermissions, receipt SourceUse) bool {
	return sourceUseAllowedAt(permissions, receipt, 0)
}

func sourceUseAllowedAt(permissions *sourcePermissions, receipt SourceUse, depth int) bool {
	if depth > 16 {
		return false
	}
	grant := permissions.Grants[receipt.Key]
	if grant == nil || grant.Incarnation != receipt.Incarnation || grant.UseEpoch != receipt.Epoch {
		return false
	}
	purpose := grant.Purposes[receipt.Kind]
	if purpose == nil || purpose.UseEpoch != receipt.PurposeEpoch || !slices.Contains(purpose.Accepted, receipt.Digest) {
		return false
	}
	for _, dependency := range purpose.BoundUses[receipt.Digest] {
		if !sourceUseAllowedAt(permissions, dependency, depth+1) {
			return false
		}
	}
	return true
}

func checkSourceUses(home string, receipts []SourceUse) error {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	for _, receipt := range receipts {
		if !sourceUseAllowed(permissions, receipt) {
			return errSourceUseRevoked
		}
	}
	return nil
}

func acceptSourceRevision(home, key, identity, digest, routing, contract string, automatic bool, expectedRevision uint64, kinds ...string) (SourceUse, error) {
	kind := sourcePurpose(key)
	if len(kinds) != 0 {
		kind = kinds[0]
	}
	return acceptSourceRevisionUses(home, key, identity, digest, routing, contract, automatic, expectedRevision, kind, nil)
}

func acceptSourceRevisionUses(home, key, identity, digest, routing, contract string, automatic bool, expectedRevision uint64, kind string, uses []SourceUse) (SourceUse, error) {
	return replaceSourceRevisionUses(home, key, identity, digest, routing, contract, automatic, expectedRevision, kind, uses, false)
}

func replaceSourceRevisionUses(home, key, identity, digest, routing, contract string, automatic bool, expectedRevision uint64, kind string, uses []SourceUse, fresh bool) (SourceUse, error) {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	if !validSourceKey(key) || !validSourceKind(kind) || !sourceKindMatchesKey(key, kind) || !validInputID(identity) || !validInputID(digest) || !slices.Contains([]string{"source", "own"}, routing) || contract != "" && !validInputID(contract) || automatic && contract == "" {
		return SourceUse{}, errSourceReview
	}
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return SourceUse{}, err
	}
	if kind != "config" && len(uses) != 0 {
		return SourceUse{}, errSourceReview
	}
	for _, use := range uses {
		if use.Kind == "config" || !sourceUseAllowed(permissions, use) {
			return SourceUse{}, errSourceUseRevoked
		}
	}
	grant := permissions.Grants[key]
	if fresh && grant != nil && grant.Identity == identity && grant.Revision != expectedRevision {
		return SourceUse{}, errSourceSuperseded
	}
	if grant == nil || grant.Identity != identity || fresh {
		if expectedRevision != 0 && !(fresh && grant != nil && grant.Identity == identity) {
			return SourceUse{}, errSourceSuperseded
		}
		incarnation, err := randomRequestToken()
		if err != nil {
			return SourceUse{}, err
		}
		grant = &SourceGrant{Identity: identity, Incarnation: incarnation, UseEpoch: 1, Routing: "source", Purposes: map[string]*sourcePurposeGrant{}}
		permissions.Grants[key] = grant
	} else if grant.Revision != expectedRevision {
		return SourceUse{}, errSourceSuperseded
	}
	purpose := grant.Purposes[kind]
	if purpose == nil {
		purpose = &sourcePurposeGrant{UseEpoch: 1}
		grant.Purposes[kind] = purpose
	}
	if kind == "profile" && grant.Routing != routing {
		purpose.UseEpoch++
		purpose.Accepted = nil
		purpose.BoundUses = nil
	}
	if kind == "profile" {
		grant.Routing = routing
	}
	grant.Revision++
	purpose.Automatic, purpose.Contract = automatic, contract
	if !slices.Contains(purpose.Accepted, digest) {
		purpose.Accepted = append(purpose.Accepted, digest)
	}
	if len(uses) > 0 {
		if purpose.BoundUses == nil {
			purpose.BoundUses = map[string][]SourceUse{}
		}
		purpose.BoundUses[digest] = slices.Clone(uses)
	}
	if err := saveSourcePermissions(home, permissions); err != nil {
		return SourceUse{}, err
	}
	return sourceUseReceipt(key, kind, digest, grant), nil
}

func sourceUseReceipt(key, kind, digest string, grant *SourceGrant) SourceUse {
	return SourceUse{Key: key, Kind: kind, Incarnation: grant.Incarnation, Epoch: grant.UseEpoch, PurposeEpoch: grant.Purposes[kind].UseEpoch, Digest: digest}
}

func withdrawSourcePermission(home, key, incarnation string, revision uint64, stopUse bool, kinds ...string) error {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return err
	}
	grant := permissions.Grants[key]
	if grant == nil || grant.Incarnation != incarnation || grant.Revision != revision {
		return errSourceSuperseded
	}
	grant.Revision++
	if stopUse && len(kinds) == 0 {
		grant.UseEpoch++
	}
	for kind, purpose := range grant.Purposes {
		if len(kinds) > 0 && !slices.Contains(kinds, kind) {
			continue
		}
		purpose.Automatic = false
		if stopUse {
			purpose.UseEpoch++
			purpose.ReviewBundle = nil
			purpose.Accepted = nil
			purpose.BoundUses = nil
		}
	}
	return saveSourcePermissions(home, permissions)
}

func resetSourcePermissions(home string, keys []string) error {
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	if len(keys) > sourceEntityLimit*4 {
		return errSourceBudget
	}
	permissions := &sourcePermissions{Version: 1, Grants: map[string]*SourceGrant{}}
	if keys != nil {
		var err error
		permissions, err = readSourcePermissions(home)
		if err != nil {
			return err
		}
		for _, key := range keys {
			if !validSourceKey(key) {
				return errSourceReview
			}
			delete(permissions.Grants, key)
		}
	}
	return saveSourcePermissions(home, permissions)
}
