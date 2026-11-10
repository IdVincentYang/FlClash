package main

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestSourceSubscriptionStatusIsReadOnlyAndChecksDependencies(t *testing.T) {
	for _, automatic := range []bool{false, true} {
		t.Run(map[bool]string{false: "explicit", true: "maintenance"}[automatic], func(t *testing.T) {
			home := t.TempDir()
			request := sourceAcceptanceRequest{Action: "status", Key: "profile:1", Kind: "profile", Identity: inputHash([]byte("identity")), Settings: inputHash([]byte("settings")), Body: sourceAcceptanceFixture}
			count := len(pendingSourceReviews)
			check := func(want string) {
				t.Helper()
				before, _ := os.ReadFile(sourcePermissionsPath(home))
				result, err := sourceAcceptance(home, request)
				if err != nil || result.Status != want {
					t.Fatal(result, err, "want", want)
				}
				after, _ := os.ReadFile(sourcePermissionsPath(home))
				if !bytes.Equal(before, after) || len(pendingSourceReviews) != count || result.Candidate != "" || result.MaterialLease != "" {
					t.Fatal("status changed authority or created a review")
				}
			}
			check("reviewRequired")
			if entries, _ := os.ReadDir(home); len(entries) != 0 {
				t.Fatal("first-use status wrote files")
			}
			summary := sourceTestSummary(t, request.Body)
			contract, _ := json.Marshal(sourceContentContract{Version: 1, Base: summary})
			contractHash, err := sealSourceObject(home, contract, sourceGrantFileLimit)
			if err != nil {
				t.Fatal(err)
			}
			root, err := acceptSourceRevisionUses(home, request.Key, request.Identity, summary.Digest, "source", contractHash, automatic, 0, "profile", nil)
			if err != nil {
				t.Fatal(err)
			}
			check("reviewRequired")
			child, err := acceptSourceRevisionUses(home, "provider-proxy:child", request.Identity, request.Identity, "source", "", false, 0, "provider-proxy", nil)
			if err != nil {
				t.Fatal(err)
			}
			config, err := acceptSourceRevisionUses(home, "config:1", request.Identity, request.Identity, "source", "", false, 0, "config", []SourceUse{root, child})
			if err != nil {
				t.Fatal(err)
			}
			if err := rememberSourceReviewBundle(home, config, config, request.Identity, nil); err != nil {
				t.Fatal(err)
			}
			check("accepted")
			request.Body = strings.Replace(sourceAcceptanceFixture, "19001", "19002", 1)
			if automatic {
				check("accepted")
			} else {
				check("reviewRequired")
			}
			request.Body = sourceAcceptanceFixture + "dns: {nameserver: [1.1.1.1]}\n"
			check("reviewRequired")
			request.Body = sourceAcceptanceFixture
			permissions, _ := readSourcePermissions(home)
			grant := permissions.Grants[child.Key]
			if err := withdrawSourcePermission(home, child.Key, grant.Incarnation, grant.Revision, true, child.Kind); err != nil {
				t.Fatal(err)
			}
			check("reviewRequired")
		})
	}
}
