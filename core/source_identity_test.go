package main

import (
	"os"
	"testing"
)

func TestSourceExternalImportWaitsForAcceptanceBeforeNewIncarnation(t *testing.T) {
	previous := pendingSourceReviews
	pendingSourceReviews = map[string]*sourceReviewCandidate{}
	t.Cleanup(func() { pendingSourceReviews = previous })
	home := t.TempDir()
	identity := inputHash([]byte("same source URL and ID"))
	_, summary, err := decodeSourceContent([]byte(sourceAcceptanceFixture))
	if err != nil {
		t.Fatal(err)
	}
	old, err := acceptSourceRevision(home, "profile:7", identity, summary.Digest, "source", "", false, 0)
	if err != nil {
		t.Fatal(err)
	}
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:7", Kind: "profile", Identity: identity,
		Settings: inputHash(nil), Body: sourceAcceptanceFixture, Fresh: true}
	first, err := sourceAcceptance(home, request)
	if err != nil || first.Status != "reviewRequired" {
		t.Fatalf("external import inherited same-ID permission: %+v %v", first, err)
	}
	if err := checkSourceUses(home, []SourceUse{old}); err != nil {
		t.Fatal("opening an import candidate revoked the existing source", err)
	}
	discard := request
	discard.Action, discard.Candidate = "discard", first.Candidate
	if _, err := sourceAcceptance(home, discard); err != nil {
		t.Fatal(err)
	}
	if err := checkSourceUses(home, []SourceUse{old}); err != nil {
		t.Fatal("cancelled import revoked existing permission", err)
	}
	second, err := sourceAcceptance(home, request)
	if err != nil {
		t.Fatal(err)
	}
	request.Action, request.Candidate, request.Routing = "accept", second.Candidate, "source"
	accepted, err := sourceAcceptance(home, request)
	if err != nil || accepted.Use == nil || accepted.Use.Incarnation == old.Incarnation {
		t.Fatalf("accepted external import reused its old incarnation: %+v %v", accepted, err)
	}
	if err := checkSourceUses(home, []SourceUse{old}); err == nil {
		t.Fatal("old source permission survived the new incarnation")
	}
}

func TestSourceRestoreResetPreservesUnchangedEntities(t *testing.T) {
	home := t.TempDir()
	identity, digest := inputHash([]byte("origin")), inputHash([]byte("material"))
	a, err := acceptSourceRevision(home, "profile:1", identity, digest, "source", "", false, 0)
	if err != nil {
		t.Fatal(err)
	}
	b, err := acceptSourceRevision(home, "profile:2", identity, digest, "source", "", false, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := resetSourcePermissions(home, []string{"profile:1"}); err != nil {
		t.Fatal(err)
	}
	if checkSourceUses(home, []SourceUse{a}) == nil || checkSourceUses(home, []SourceUse{b}) != nil {
		t.Fatal("partial restore did not isolate restored entities")
	}
	next, err := acceptSourceRevision(home, "profile:1", identity, digest, "source", "", false, 0)
	if err != nil || next.Incarnation == a.Incarnation {
		t.Fatal("restored same-ID entity inherited the old incarnation", err)
	}
	if err := os.WriteFile(sourcePermissionsPath(home), []byte("corrupt"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := resetSourcePermissions(home, []string{"profile:1"}); err == nil {
		t.Fatal("partial restore guessed unaffected permissions from corruption")
	}
	if err := resetSourcePermissions(home, nil); err != nil {
		t.Fatal("explicit complete permission reset could not replace corruption", err)
	}
	if checkSourceUses(home, []SourceUse{b}) == nil {
		t.Fatal("complete restore retained an old permission")
	}
}
