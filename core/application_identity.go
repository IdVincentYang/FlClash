package main

import (
	"encoding/json"
	"slices"
)

type applicationIdentity struct {
	Status    string   `json:"status"`
	UID       *uint32  `json:"uid,omitempty"`
	UserScope string   `json:"userScope"`
	Packages  []string `json:"packages,omitempty"`
	Method    string   `json:"method"`
}

func unknownApplication(reason string) applicationIdentity {
	return applicationIdentity{Status: reason, UserScope: "unknown", Method: "unavailable"}
}

func decodeApplicationIdentity(uid int, data, method string) applicationIdentity {
	result := unknownApplication("lookupFailed")
	if uid < 0 {
		return unknownApplication("unknown")
	}
	value := uint32(uid)
	result.UID, result.Method = &value, method
	var decoded applicationIdentity
	if len(data) > 32768 || json.Unmarshal([]byte(data), &decoded) != nil || len(decoded.Packages) > 64 {
		return result
	}
	switch decoded.Status {
	case "known", "ambiguous", "notFound":
		if decoded.UserScope != "current" {
			return result
		}
	case "otherUser":
		if decoded.UserScope != "other" || len(decoded.Packages) != 0 {
			return result
		}
	case "lookupFailed":
		return result
	default:
		return result
	}
	packages := slices.Clone(decoded.Packages)
	slices.Sort(packages)
	if slices.Contains(packages, "") || len(slices.Compact(packages)) != len(decoded.Packages) {
		return result
	}
	if decoded.Status == "known" && len(packages) != 1 || decoded.Status == "ambiguous" && len(packages) < 2 || decoded.Status == "notFound" && len(packages) != 0 {
		return result
	}
	result.Status, result.UserScope, result.Packages = decoded.Status, decoded.UserScope, packages
	return result
}

func (a applicationIdentity) packageName() string {
	if a.Status == "known" && len(a.Packages) == 1 {
		return a.Packages[0]
	}
	return ""
}
