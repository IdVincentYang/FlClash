package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

type sourceAcceptanceRequest struct {
	Pattern           string                     `json:"pattern,omitempty"`
	Names             []string                   `json:"names,omitempty"`
	Action            string                     `json:"action"`
	Key               string                     `json:"key"`
	Identity          string                     `json:"identity"`
	Kind              string                     `json:"kind"`
	Body              string                     `json:"body"`
	Preview           string                     `json:"preview,omitempty"`
	Bundle            bool                       `json:"bundle,omitempty"`
	Settings          string                     `json:"settings"`
	Source            ConfigSourceTicket         `json:"source"`
	Candidate         string                     `json:"candidate"`
	Routing           string                     `json:"routing"`
	Automatic         bool                       `json:"automatic"`
	Rules             *sourceRuleContract        `json:"rules,omitempty"`
	Use               *SourceUse                 `json:"use,omitempty"`
	Uses              []SourceUse                `json:"uses,omitempty"`
	Incarnation       string                     `json:"incarnation,omitempty"`
	Revision          uint64                     `json:"revision,omitempty"`
	StopUse           bool                       `json:"stopUse,omitempty"`
	ForceReview       bool                       `json:"forceReview,omitempty"`
	BodyBase64        string                     `json:"bodyBase64,omitempty"`
	Format            string                     `json:"format,omitempty"`
	Behavior          string                     `json:"behavior,omitempty"`
	Fresh             bool                       `json:"fresh,omitempty"`
	Keys              []string                   `json:"keys,omitempty"`
	Session           string                     `json:"session,omitempty"`
	MaterialHash      string                     `json:"materialHash,omitempty"`
	ProviderName      string                     `json:"providerName,omitempty"`
	ProviderMaterials []SourceProviderMaterial   `json:"providerMaterials,omitempty"`
	Provider          map[string]any             `json:"provider,omitempty"`
	Parent            *SourceUse                 `json:"parent,omitempty"`
	ExpectedConfig    *ConfigFence               `json:"expectedConfig,omitempty"`
	LocalGroupsBefore []sourceLocalGroup         `json:"localGroupsBefore,omitempty"`
	LocalGroups       []sourceLocalGroup         `json:"localGroups,omitempty"`
	Input             *ConfigInputRequest        `json:"input,omitempty"`
	MaterialLease     string                     `json:"materialLease,omitempty"`
	MaterialOperation string                     `json:"materialOperation,omitempty"`
	Receipt           string                     `json:"receipt,omitempty"`
	ExpectedState     *requestscope.StateVersion `json:"expectedState,omitempty"`
	Owner             uint64                     `json:"owner,omitempty"`
	Operation         uint64                     `json:"operation,omitempty"`
	Recovery          *sourceRecoverySnapshot    `json:"recovery,omitempty"`
}

type sourceAcceptanceResult struct {
	Matches           []string                 `json:"matches,omitempty"`
	PatternError      string                   `json:"patternError,omitempty"`
	Status            string                   `json:"status"`
	Candidate         string                   `json:"candidate,omitempty"`
	Reasons           []string                 `json:"reasons,omitempty"`
	Use               *SourceUse               `json:"use,omitempty"`
	Uses              []SourceUse              `json:"uses,omitempty"`
	Grant             *SourceGrant             `json:"grant,omitempty"`
	MaterialHash      string                   `json:"materialHash,omitempty"`
	Routing           string                   `json:"routing,omitempty"`
	Document          map[string]any           `json:"document,omitempty"`
	Details           *sourceReviewDetails     `json:"details,omitempty"`
	Previous          *sourceReviewDetails     `json:"previous,omitempty"`
	RuleContract      *sourceRuleContract      `json:"ruleContract,omitempty"`
	Providers         []sourceProviderPlan     `json:"providers,omitempty"`
	BodyBase64        string                   `json:"bodyBase64,omitempty"`
	Config            *ConfigFence             `json:"config,omitempty"`
	MaterialLease     string                   `json:"materialLease,omitempty"`
	ProviderMaterials []SourceProviderMaterial `json:"providerMaterials,omitempty"`
	MaterialLeases    []string                 `json:"materialLeases,omitempty"`
	Receipt           string                   `json:"receipt,omitempty"`
	SelectedMap       map[string]string        `json:"selectedMap,omitempty"`
	Recovery          *sourceRecoverySnapshot  `json:"recovery,omitempty"`
}

type sourceReviewCandidate struct {
	id               string
	request          sourceAcceptanceRequest
	summary          sourceContentSummary
	revision         uint64
	body             []byte
	grantFingerprint string
	material         *sourceMaterialApprovalState
}

var pendingSourceReviews = map[string]*sourceReviewCandidate{}

func sourceObjectPath(home, digest string) string {
	return filepath.Join(home, "source-acceptance", "materials", digest)
}

func readSourceObject(home, digest string, limit int64) ([]byte, error) {
	if !validInputID(digest) {
		return nil, errSourceStore
	}
	f, err := os.Open(sourceObjectPath(home, digest))
	if err != nil {
		return nil, errSourceStore
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil || int64(len(data)) > limit || inputHash(data) != digest {
		return nil, errSourceStore
	}
	return data, nil
}

func sealSourceObject(home string, body []byte, limit int) (string, error) {
	if len(body) > limit {
		return "", errSourceBudget
	}
	digest := inputHash(body)
	path := sourceObjectPath(home, digest)
	if _, err := os.Stat(path); err == nil {
		_, err = readSourceObject(home, digest, int64(limit))
		return digest, err
	} else if !os.IsNotExist(err) {
		return "", errSourceStore
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil && !os.IsNotExist(err) {
		return "", errSourceStore
	}
	used := int64(len(body))
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() || !validInputID(entry.Name()) {
			return "", errSourceStore
		}
		used += info.Size()
	}
	if used > sourceMaterialTotal {
		return "", errSourceBudget
	}
	if err := atomicConfigFile(path, body); err != nil {
		return "", errSourceStore
	}
	return digest, nil
}

func sourceAcceptanceCurrent(request sourceAcceptanceRequest) bool {
	if !validSourceKey(request.Key) {
		return false
	}
	origin := sourcePermissionOrigin(request.Key, request.Kind)
	if _, present := request.Source.Sources[origin]; !present {
		return false
	}
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	return sourceTicketValidLocked(request.Source, []string{origin})
}

func sourcePermissionOrigin(key, kind string) string {
	if kind == "config" && strings.HasPrefix(key, "config:") {
		return "application-config"
	}
	return key
}

func handleSourceAcceptance(call *MethodCall, response MethodResponse) {
	var request sourceAcceptanceRequest
	if !decodeMethodArguments(call, response, &request) {
		return
	}
	if request.Action == "matchLocalNodes" {
		matches, err := matchLocalNodes(request.Pattern, request.Names)
		result := sourceAcceptanceResult{Status: "matched", Matches: matches}
		if err != nil {
			result.PatternError = err.Error()
		}
		response.success(result)
		return
	}
	if request.Action != "withdraw" && request.Action != "reset" && request.Action != "inspect" && request.Action != "discard" && request.Action != "releaseMaterial" && request.Action != "releaseMaterialApproval" {
		if err := requestWriterError(); err != nil {
			response.failure(err.Error(), err.Error(), nil)
			return
		}
	}
	if request.Action == "adoptInline" {
		response.success(adoptSourceInlineRequest(request.Input))
		return
	}
	if request.Action == "fetchProvider" || request.Action == "previewProvider" {
		body, err := fetchSourceProviderMaterial(C.Path.HomeDir(), request)
		if err != nil {
			response.failure("source_material_unavailable", "Provider material is unavailable", nil)
			return
		}
		response.success(sourceAcceptanceResult{Status: "downloaded", BodyBase64: base64.StdEncoding.EncodeToString(body)})
		return
	}
	if request.Action == "adoptProvider" {
		if err := adoptSourceProviderRequest(request); err != nil {
			response.failure("source_review_required", err.Error(), nil)
			return
		}
		response.success(sourceAcceptanceResult{Status: "applied"})
		return
	}
	configMu.Lock()
	defer configMu.Unlock()
	if request.Action == "releaseMaterial" {
		releaseSourceMaterialLease(request.MaterialLease, request.Source.Client)
		response.success(sourceAcceptanceResult{Status: "released"})
		return
	}
	if handled, result, err := handleSourceMaterialCommit(C.Path.HomeDir(), request); handled {
		if err != nil {
			code := "source_review_required"
			if errors.Is(err, errRequestCommitBusy) || errors.Is(err, errRequestWriterUnknown) {
				code = err.Error()
			}
			response.failure(code, err.Error(), nil)
		} else {
			response.success(result)
		}
		return
	}
	if !isInit.Load() || !sourceAcceptanceCurrent(request) {
		response.failure("source_superseded", errSourceSuperseded.Error(), nil)
		return
	}
	var result sourceAcceptanceResult
	var err error
	if request.Action == "resolveLocalGroups" {
		result, err := resolvedLocalGroupConfig(C.Path.HomeDir(), request)
		if err != nil {
			response.failure("local_groups_invalid", err.Error(), nil)
		} else {
			response.success(result)
		}
		return
	}
	if request.Action == "review" || request.Action == "accept" || request.Action == "approveMaterial" || request.Action == "approveLocalGroups" {
		if err := collectSourceMaterialsLocked(C.Path.HomeDir()); err != nil {
			response.failure("source_permissions_unavailable", err.Error(), nil)
			return
		}
		if len(sourceMaterialLeases) >= sourceMaterialLeaseLimit {
			response.failure("source_budget_exceeded", errSourceBudget.Error(), nil)
			return
		}
	}
	if request.Action == "approveLocalGroups" {
		result, err = approveLocalSourceGroups(C.Path.HomeDir(), request)
	} else if request.Action == "preview" {
		result, err = previewSourceReview(C.Path.HomeDir(), request)
	} else if request.Action == "previewCachedProvider" {
		result, err = previewCachedSourceProvider(C.Path.HomeDir(), request)
	} else if request.Action == "inspectProvider" {
		result, err = inspectSourceProviderRequest(request)
	} else {
		result, err = sourceAcceptance(C.Path.HomeDir(), request)
	}
	if err == nil && result.Status == "accepted" && request.Kind == "config" && result.Use != nil {
		result.Providers, err = acceptedSourceProviderPlans(C.Path.HomeDir(), *result.Use, result.MaterialHash)
	}
	if err != nil {
		for _, lease := range result.MaterialLeases {
			releaseSourceMaterialLease(lease, request.Source.Client)
		}
		code := "source_content_invalid"
		switch {
		case errors.Is(err, errLocalGroupAmbiguous):
			code = "local_groups_ambiguous"
		case errors.Is(err, errLocalGroupInUse):
			code = "local_groups_in_use"
		case errors.Is(err, errLocalGroups):
			code = "local_groups_invalid"
		case errors.Is(err, errRequestWriterUnknown):
			code = err.Error()
		case errors.Is(err, errSourceBudget):
			code = "source_budget_exceeded"
		case errors.Is(err, errSourceStore):
			code = "source_permissions_unavailable"
		case errors.Is(err, errSourceUseRevoked):
			code = "source_use_revoked"
		case errors.Is(err, errSourceSuperseded):
			code = "source_superseded"
		case errors.Is(err, errSourceRoutingDenied):
			code = "source_routing_excluded"
		case errors.Is(err, errSourceReview):
			code = "source_review_required"
		}
		response.failure(code, err.Error(), nil)
		return
	}
	if request.Action == "accept" || request.Action == "review" || request.Action == "withdraw" || request.Action == "reset" {
		if err := reconcileSourceScopesLocked(C.Path.HomeDir()); err != nil {
			response.failure("source_recovery_unavailable", err.Error(), nil)
			return
		}
	}
	if (result.Status == "accepted" || result.Status == "approved") && validInputID(result.MaterialHash) && (request.Action == "review" || request.Action == "accept" || request.Action == "approveMaterial") {
		result.MaterialLease, err = pinSourceMaterial(C.Path.HomeDir(), result.MaterialHash, request.Source.Client)
		if err != nil {
			response.failure("source_budget_exceeded", err.Error(), nil)
			return
		}
		if result.Status == "approved" {
			pendingSourceReviews[request.Key].material.lease = result.MaterialLease
		}
	}
	response.success(result)
}

func sourceAcceptance(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if request.Action != "withdraw" && request.Action != "reset" && request.Action != "inspect" && request.Action != "discard" {
		if err := requestWriterError(); err != nil {
			return sourceAcceptanceResult{}, err
		}
	}
	request.Uses = canonicalSourceUses(request.Uses)
	switch request.Action {
	case "reset":
		if request.Key != "application-config" || request.Kind != "config" {
			return sourceAcceptanceResult{}, errSourceReview
		}
		if err := resetSourcePermissions(home, request.Keys); err != nil {
			return sourceAcceptanceResult{}, err
		}
		for key := range pendingSourceReviews {
			if request.Keys == nil || slices.Contains(request.Keys, key) {
				delete(pendingSourceReviews, key)
			}
		}
		return sourceAcceptanceResult{Status: "reset"}, nil
	case "withdraw":
		if !sourceKindMatchesKey(request.Key, request.Kind) {
			return sourceAcceptanceResult{}, errSourceReview
		}
		if err := withdrawSourcePermission(home, request.Key, request.Incarnation, request.Revision, request.StopUse, request.Kind); err != nil {
			return sourceAcceptanceResult{}, err
		}
		return sourceAcceptanceResult{Status: "withdrawn"}, nil
	case "inspect":
		sourceAuthorityMu.Lock()
		defer sourceAuthorityMu.Unlock()
		permissions, err := readSourcePermissions(home)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		return sourceAcceptanceResult{Status: "inspected", Grant: permissions.Grants[request.Key]}, nil
	case "status":
		return sourceSubscriptionStatus(home, request)
	case "reuseCachedProvider":
		return reuseCachedSourceProvider(home, request)
	case "reuseProvider", "reuseReviewedProvider":
		return reuseSourceProviderMaterial(home, request)
	case "review":
		if request.MaterialOperation != "" {
			if err := checkSourceMaterialCapture(request); err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		return reviewSourceCandidate(home, request)
	case "approveMaterial":
		return approveSourceMaterial(home, request)
	case "reuseCachedProviders":
		return reuseCachedSourceProviders(home, request)
	case "bindProviders":
		if request.Use == nil || request.Use.Key != request.Key || request.Kind != "config" {
			return sourceAcceptanceResult{}, errSourceReview
		}
		use, err := bindSourceProviderMaterials(home, *request.Use, request.MaterialHash, request.ProviderMaterials)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		if request.Bundle {
			if err := rememberSourceReviewBundle(home, *request.Use, use, request.MaterialHash, request.ProviderMaterials); err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		uses, err := sourceCompositionUses(home, use)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		uses = slices.DeleteFunc(uses, func(dependency SourceUse) bool { return dependency.Kind == "config" })
		return sourceAcceptanceResult{Status: "accepted", Use: &use, Uses: uses, MaterialHash: request.MaterialHash}, nil
	case "project":
		return projectAcceptedSource(home, request)
	case "checkCode":
		if request.Kind != "script" || !strings.HasPrefix(request.Key, "script:") || len(request.Body) > sourceCandidateMax {
			return sourceAcceptanceResult{}, errSourceReview
		}
		sourceAuthorityMu.Lock()
		defer sourceAuthorityMu.Unlock()
		permissions, err := readSourcePermissions(home)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		grant := permissions.Grants[request.Key]
		if grant == nil || grant.Identity != request.Identity || request.Use == nil || request.Use.Key != request.Key || request.Use.Kind != "script" || request.Use.Digest != inputHash([]byte(request.Body)) || !sourceUseAllowed(permissions, *request.Use) {
			return sourceAcceptanceResult{}, errSourceReview
		}
		return sourceAcceptanceResult{Status: "accepted"}, nil
	case "accept":
		if request.MaterialOperation != "" {
			return sourceAcceptanceResult{}, errSourceReview
		}
		return acceptReviewedSource(home, request)
	case "discard":
		if candidate := pendingSourceReviews[request.Key]; candidate != nil && candidate.id == request.Candidate {
			delete(pendingSourceReviews, request.Key)
		}
		return sourceAcceptanceResult{Status: "discarded"}, nil
	default:
		return sourceAcceptanceResult{}, errors.New("unsupported source acceptance action")
	}
}

func sourceKindMatchesKey(key, kind string) bool {
	switch kind {
	case "profile", "script":
		return strings.HasPrefix(key, kind+":")
	case "config":
		return key == "application-config" || strings.HasPrefix(key, "config:")
	case "provider-proxy", "provider-rule":
		return strings.HasPrefix(key, "profile:") || strings.HasPrefix(key, "clash-provider:") || strings.HasPrefix(key, "provider:") || strings.HasPrefix(key, kind+":")
	default:
		return false
	}
}

func reviewSourceCandidate(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	if !validSourceKey(request.Key) || !validInputID(request.Identity) || !validInputID(request.Settings) || !slices.Contains([]string{"profile", "script", "provider-proxy", "provider-rule", "config"}, request.Kind) || len(request.Body) > sourceCandidateMax {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if !sourceKindMatchesKey(request.Key, request.Kind) {
		return sourceAcceptanceResult{}, errSourceReview
	}
	if len(request.Source.Sources) > 1 || len(request.Uses) > sourceEntityLimit || request.Kind != "config" && len(request.Uses) > 0 {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	if err := checkSourceUses(home, request.Uses); err != nil {
		return sourceAcceptanceResult{}, err
	}
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	sourceAuthorityMu.Unlock()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	grant := permissions.Grants[request.Key]
	profileKey := "profile:" + strings.TrimPrefix(request.Key, "config:")
	if request.Kind == "config" && (!strings.HasPrefix(request.Key, "config:") || !slices.ContainsFunc(request.Uses, func(use SourceUse) bool {
		return use.Kind == "profile" && use.Key == profileKey && sourceUseAllowed(permissions, use)
	})) {
		return sourceAcceptanceResult{}, errSourceReview
	}
	var purpose *sourcePurposeGrant
	if grant != nil && grant.Identity == request.Identity {
		purpose = grant.Purposes[request.Kind]
	}
	if request.Routing == "" {
		request.Routing = "source"
		if grant != nil && grant.Identity == request.Identity && request.Kind == "profile" {
			request.Routing = grant.Routing
		}
	}
	if !slices.Contains([]string{"source", "own"}, request.Routing) || request.Kind != "profile" && request.Routing != "source" {
		return sourceAcceptanceResult{}, errSourceReview
	}
	body := []byte(request.Body)
	if request.BodyBase64 != "" {
		if request.Kind != "provider-rule" && request.Kind != "provider-proxy" || request.Body != "" || len(request.BodyBase64) > base64.StdEncoding.EncodedLen(sourceCandidateMax) {
			return sourceAcceptanceResult{}, errSourceReview
		}
		body, err = base64.StdEncoding.DecodeString(request.BodyBase64)
		if err != nil || len(body) > sourceCandidateMax {
			return sourceAcceptanceResult{}, errSourceReview
		}
	}
	var summary sourceContentSummary
	if request.Kind == "script" {
		summary = sourceContentSummary{Digest: inputHash(body)}
	} else if request.Kind == "provider-rule" {
		summary, err = summarizeSourceRuleContent(body, request.Format, request.Behavior)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
	} else if request.Kind == "provider-proxy" {
		if request.Provider != nil && (request.Parent == nil || !sourceUseAllowed(permissions, *request.Parent) || request.Identity != sourceProviderDeclaration(*request.Parent, request.Kind, request.ProviderName, request.Provider)) {
			return sourceAcceptanceResult{}, errSourceReview
		}
		var context *config.RawConfig
		if request.Provider != nil {
			if request.Use == nil {
				return sourceAcceptanceResult{}, errSourceReview
			}
			plans, err := acceptedSourceProviderPlans(home, *request.Use, request.MaterialHash)
			if err != nil || !slices.ContainsFunc(plans, func(plan sourceProviderPlan) bool {
				return plan.Key == request.Key && plan.Declaration == request.Identity
			}) {
				return sourceAcceptanceResult{}, errSourceReview
			}
			body, err := readSourceObject(home, request.MaterialHash, sourceCandidateMax)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
			context, err = config.UnmarshalRawConfig(body)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		document, err := sourceProviderProxyDocument(body, request.Provider)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		if grant != nil && grant.Identity == request.Identity && grant.Routing == "own" {
			if _, err := sourceRoutingProjection(document, request.Key); err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		if request.Parent != nil && permissions.Grants[request.Parent.Key].Routing == "own" {
			if _, err := sourceRoutingProjection(document, request.Parent.Key); err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		summary, err = summarizeSourceProviderProxy(document, context)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
	} else {
		document, decoded, err := decodeSourceContent(body)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		if request.Kind == "config" && permissions.Grants[profileKey].Routing == "own" {
			if err := validateOwnRoutingInput(document, profileKey); err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		if request.Routing == "own" {
			document, err = sourceRoutingProjection(document, request.Key)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
			decoded, err = summarizeSourceContent(document)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
		}
		summary = decoded
	}
	revision := uint64(0)
	useDigest := sourceReviewUseDigest(request, summary)
	reasons := []string{"first_use"}
	var previous *sourceReviewDetails
	if grant != nil && grant.Identity == request.Identity {
		revision = grant.Revision
		if !request.ForceReview && !request.Fresh && purpose != nil && (request.Kind != "profile" || grant.Routing == request.Routing) && slices.Contains(purpose.Accepted, useDigest) && slices.Equal(purpose.BoundUses[useDigest], request.Uses) {
			use := sourceUseReceipt(request.Key, request.Kind, useDigest, grant)
			if !sourceUseAllowed(permissions, use) {
				return sourceAcceptanceResult{}, errSourceUseRevoked
			}
			if request.Action == "status" {
				return sourceAcceptanceResult{Status: "accepted", Use: &use}, nil
			}
			materialHash, err := sealSourceObject(home, body, sourceCandidateMax)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
			return sourceAcceptanceResult{Status: "accepted", Use: &use, Grant: grant, MaterialHash: materialHash, Routing: request.Routing}, nil
		}
		reasons = []string{"automatic_maintenance_not_delegated"}
		if purpose != nil && purpose.Contract != "" {
			data, err := readSourceObject(home, purpose.Contract, sourceGrantFileLimit)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
			var contract sourceContentContract
			if json.Unmarshal(data, &contract) != nil {
				return sourceAcceptanceResult{}, errSourceStore
			}
			previous = &contract.Base.Details
		}
		if request.Kind == "script" {
			reasons = []string{"script_code_changed"}
		} else if !request.ForceReview && !request.Fresh && purpose != nil && purpose.Automatic && purpose.Contract != "" && (request.Kind != "profile" || grant.Routing == request.Routing) {
			data, err := readSourceObject(home, purpose.Contract, sourceGrantFileLimit)
			if err != nil {
				return sourceAcceptanceResult{}, err
			}
			var contract sourceContentContract
			if err := json.Unmarshal(data, &contract); err != nil {
				return sourceAcceptanceResult{}, errSourceStore
			}
			reasons = classifySourceDelta(contract, summary)
			if request.Kind == "config" && !slices.Equal(contract.Bindings, sourceBindingIdentities(request.Uses)) {
				reasons = append(reasons, "source_bindings_changed")
			}
			if len(reasons) == 0 {
				if request.Action == "status" {
					return sourceAcceptanceResult{Status: "maintenanceAllowed"}, nil
				}
				if _, err := sealSourceObject(home, body, sourceCandidateMax); err != nil {
					return sourceAcceptanceResult{}, err
				}
				use, err := acceptSourceRevisionUses(home, request.Key, request.Identity, useDigest, request.Routing, purpose.Contract, true, grant.Revision, request.Kind, request.Uses)
				if err != nil {
					return sourceAcceptanceResult{}, err
				}
				delete(pendingSourceReviews, request.Key)
				return sourceAcceptanceResult{Status: "accepted", Use: &use, MaterialHash: inputHash(body), Routing: request.Routing}, nil
			}
		}
	}
	if request.Action == "status" {
		return sourceAcceptanceResult{Status: "reviewRequired", Reasons: reasons}, nil
	}
	used, count := len(body), 1
	for key, candidate := range pendingSourceReviews {
		if key != request.Key {
			used += len(candidate.body)
			count++
		}
	}
	if used > sourceCandidateTotal || count > sourceCandidateSlots {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	id, err := randomRequestToken()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if summaryBytes, err := json.Marshal(summary); err != nil || len(summaryBytes) > sourceGrantFileLimit {
		return sourceAcceptanceResult{}, errSourceBudget
	}
	request.Body, request.BodyBase64 = "", ""
	pendingSourceReviews[request.Key] = &sourceReviewCandidate{id: id, request: request, summary: summary, revision: revision, body: body, grantFingerprint: sourceValueHash(grant)}
	return sourceAcceptanceResult{Status: "reviewRequired", Candidate: id, Reasons: reasons, Grant: grant, Routing: request.Routing, Details: &summary.Details, Previous: previous, RuleContract: proposeSourceRuleContract(summary)}, nil
}

func acceptReviewedSource(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	candidate, contractHash, materialHash, err := prepareReviewedSource(home, request)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	use, err := replaceSourceRevisionUses(home, request.Key, request.Identity, sourceReviewUseDigest(candidate.request, candidate.summary), request.Routing, contractHash, request.Automatic, candidate.revision, candidate.request.Kind, candidate.request.Uses, candidate.request.Fresh)
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	delete(pendingSourceReviews, request.Key)
	return sourceAcceptanceResult{Status: "accepted", Use: &use, MaterialHash: materialHash, Routing: request.Routing}, nil
}

func prepareReviewedSource(home string, request sourceAcceptanceRequest) (*sourceReviewCandidate, string, string, error) {
	candidate := pendingSourceReviews[request.Key]
	if candidate == nil || candidate.id != request.Candidate || candidate.request.Identity != request.Identity || candidate.request.Settings != request.Settings || sourceValueHash(candidate.request.Source) != sourceValueHash(request.Source) || sourceValueHash(candidate.request.Uses) != sourceValueHash(request.Uses) {
		return nil, "", "", errSourceSuperseded
	}
	if err := checkSourceUses(home, candidate.request.Uses); err != nil {
		return nil, "", "", err
	}
	if request.Routing != candidate.request.Routing || candidate.request.Kind == "script" && request.Automatic {
		return nil, "", "", errSourceReview
	}
	contractHash := ""
	if candidate.request.Kind != "script" {
		if request.Rules != nil && !sourceRulesAutomaticallyAllowed(candidate.summary, candidate.summary, request.Rules) {
			return nil, "", "", errSourceReview
		}
		contract := sourceContentContract{Version: 1, Base: candidate.summary, Rules: request.Rules}
		if candidate.request.Kind == "config" {
			contract.Bindings = sourceBindingIdentities(candidate.request.Uses)
		}
		data, err := json.Marshal(contract)
		if err != nil {
			return nil, "", "", errSourceReview
		}
		contractHash, err = sealSourceObject(home, data, sourceGrantFileLimit)
		if err != nil {
			return nil, "", "", err
		}
	}
	materialHash, err := sealSourceObject(home, candidate.body, sourceCandidateMax)
	if err != nil {
		return nil, "", "", err
	}
	return candidate, contractHash, materialHash, nil
}

func projectAcceptedSource(home string, request sourceAcceptanceRequest) (sourceAcceptanceResult, error) {
	sourceAuthorityMu.Lock()
	permissions, err := readSourcePermissions(home)
	sourceAuthorityMu.Unlock()
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	grant := permissions.Grants[request.Key]
	if grant == nil || grant.Identity != request.Identity {
		return sourceAcceptanceResult{}, errSourceReview
	}
	document, summary, err := decodeSourceContent([]byte(request.Body))
	if err != nil {
		return sourceAcceptanceResult{}, err
	}
	if grant.Routing == "own" {
		document, err = sourceRoutingProjection(document, request.Key)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
		summary, err = summarizeSourceContent(document)
		if err != nil {
			return sourceAcceptanceResult{}, err
		}
	}
	if grant.Purposes["profile"] == nil {
		return sourceAcceptanceResult{}, errSourceReview
	}
	use := sourceUseReceipt(request.Key, "profile", summary.Digest, grant)
	if !sourceUseAllowed(permissions, use) {
		return sourceAcceptanceResult{}, errSourceReview
	}
	return sourceAcceptanceResult{Status: "accepted", Use: &use, Routing: grant.Routing, Document: document}, nil
}
