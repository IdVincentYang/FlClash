package main

import (
	"errors"
	"io"
	"os"
	"reflect"
	"strings"
	"time"

	mh "github.com/metacubex/http"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resource"
	C "github.com/metacubex/mihomo/constant"
)

func acceptedSourceProviderPlans(home string, use SourceUse, materialHash string) ([]sourceProviderPlan, error) {
	if use.Kind != "config" {
		return nil, errSourceReview
	}
	body, err := readSourceObject(home, materialHash, sourceCandidateMax)
	if err != nil {
		return nil, err
	}
	_, summary, err := decodeSourceContent(body)
	if err != nil {
		return nil, err
	}
	sourceAuthorityMu.Lock()
	defer sourceAuthorityMu.Unlock()
	permissions, err := readSourcePermissions(home)
	if err != nil {
		return nil, err
	}
	if !sourceUseAllowed(permissions, use) {
		return nil, errSourceUseRevoked
	}
	dependencies := permissions.Grants[use.Key].Purposes[use.Kind].BoundUses[use.Digest]
	if use.Digest != sourceCompositionDigest(summary.Digest, dependencies) {
		return nil, errSourceReview
	}
	plans, err := sourceProviderPlans(body, dependencies, "profile:"+strings.TrimPrefix(use.Key, "config:"))
	if err != nil {
		return nil, err
	}
	for _, plan := range plans {
		if use.Key != "config:"+strings.TrimPrefix(plan.Parent.Key, "profile:") {
			return nil, errSourceReview
		}
	}
	for i := range plans {
		plans[i].Context, plans[i].ContextMaterialHash = use, materialHash
		key, err := sourceProviderOriginKey(home, plans[i].Kind, plans[i].Mapping, dependencies)
		if err != nil {
			return nil, err
		}
		if key != "" {
			grant := permissions.Grants[key]
			if grant == nil {
				return nil, errSourceReview
			}
			origin := &sourceProviderOrigin{Key: key, Identity: grant.Identity}
			for _, dependency := range dependencies {
				if dependency.Key == key && dependency.Kind == plans[i].Kind {
					origin.Uses = append(origin.Uses, dependency)
				}
			}
			if len(origin.Uses) == 0 {
				return nil, errSourceReview
			}
			plans[i].Origin = origin
		}
	}
	return plans, nil
}

func sourceProviderHeaders(mapping map[string]any) (mh.Header, error) {
	header := mh.Header{}
	if values, ok := mapping["header"].(map[string]any); ok {
		for name, value := range values {
			list, valid := sourceStrings(value)
			if !valid {
				return nil, errSourceReview
			}
			header[name] = list
		}
	}
	return header, nil
}

func fetchSourceProviderMaterial(home string, request sourceAcceptanceRequest) ([]byte, error) {
	configMu.Lock()
	preview := request.Action == "previewProvider"
	if !isInit.Load() || !sourceAcceptanceCurrent(request) || (!preview && request.Use == nil) || (preview && request.Parent == nil) {
		configMu.Unlock()
		return nil, errSourceSuperseded
	}
	plansForRequest := func() ([]sourceProviderPlan, error) {
		if preview {
			return previewSourceProviderPlans(home, request.Body, request.Parent.Key, request.Uses)
		}
		return acceptedSourceProviderPlans(home, *request.Use, request.MaterialHash)
	}
	plans, err := plansForRequest()
	registry := appRequests
	configMu.Unlock()
	if err != nil {
		return nil, err
	}
	var plan *sourceProviderPlan
	for i := range plans {
		if (preview || plans[i].Key == request.Key) && plans[i].Name == request.ProviderName && plans[i].Kind == request.Kind {
			plan = &plans[i]
			break
		}
	}
	if plan == nil {
		return nil, errSourceReview
	}
	var body []byte
	var lease *appRequestLease
	local := plan.Mapping["type"] == "file"
	if preview && plan.Origin != nil && !local {
		path, ok := plan.Mapping["path"].(string)
		if !ok || !C.Path.IsSafePath(C.Path.Resolve(path)) {
			return nil, errSourceReview
		}
		if info, err := os.Stat(C.Path.Resolve(path)); err == nil {
			local = info.Mode().IsRegular()
		} else if !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
	}
	if local {
		if requestscope.BeginHook == nil || requestscope.OwnerHook == nil || requestscope.ResourceHook == nil ||
			reflect.ValueOf(requestscope.BeginHook).Pointer() != reflect.ValueOf(registry.begin).Pointer() ||
			reflect.ValueOf(requestscope.OwnerHook).Pointer() != reflect.ValueOf(registry.currentOwner).Pointer() ||
			reflect.ValueOf(requestscope.ResourceHook).Pointer() != reflect.ValueOf(registry.lockResource).Pointer() {
			return nil, errSourceSuperseded
		}
		read, err := beginRequestDataReadAt(registry, home)
		if err != nil {
			return nil, err
		}
		if read == "" {
			return nil, errSourceSuperseded
		}
		defer registry.endDataRead(read)
		configMu.Lock()
		current := registry == appRequests && home == C.Path.HomeDir() && sourceAcceptanceCurrent(request)
		if current {
			_, err = plansForRequest()
			current = err == nil
		}
		configMu.Unlock()
		if !current {
			return nil, errSourceSuperseded
		}
		path, ok := plan.Mapping["path"].(string)
		if !ok {
			return nil, errSourceReview
		}
		path = C.Path.Resolve(path)
		if !C.Path.IsSafePath(path) {
			return nil, errSourceReview
		}
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		body, err = io.ReadAll(io.LimitReader(f, sourceCandidateMax+1))
		_ = f.Close()
		if err != nil {
			return nil, err
		}
	} else {
		registry.mu.Lock()
		lease = registry.leases[request.Session]
		valid := lease != nil && lease.spec.Client == request.Source.Client && lease.spec.Key == request.Key && lease.validLocked()
		registry.mu.Unlock()
		if !valid || lease.Check() != nil {
			return nil, errSourceSuperseded
		}
		url, ok := plan.Mapping["url"].(string)
		if !ok || url == "" || lease.spec.URL != url {
			return nil, errSourceReview
		}
		proxy, _ := plan.Mapping["proxy"].(string)
		if proxy != "" && lease.spec.Proxy != proxy {
			return nil, errSourceReview
		}
		header, err := sourceProviderHeaders(plan.Mapping)
		if err != nil {
			return nil, err
		}
		vehicle := resource.NewHTTPVehicle(url, "", proxy, header, 30*time.Second, sourceCandidateMax+1)
		response, err := vehicle.ScopedRead(lease.Context(), utils.HashType{}, lease)
		if err != nil {
			return nil, err
		}
		body = response.Bytes
	}
	if len(body) == 0 || len(body) > sourceCandidateMax {
		return nil, errSourceBudget
	}
	configMu.Lock()
	defer configMu.Unlock()
	if registry != appRequests || home != C.Path.HomeDir() || !sourceAcceptanceCurrent(request) || lease != nil && lease.Check() != nil {
		return nil, errSourceSuperseded
	}
	if err := requestWriterError(); err != nil {
		return nil, err
	}
	if local {
		marker, err := readRequestRecoveryMarker(home)
		if err != nil || marker != nil {
			return nil, errSourceReview
		}
	}
	if _, err := plansForRequest(); err != nil {
		return nil, err
	}
	return body, nil
}
