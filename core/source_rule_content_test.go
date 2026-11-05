package main

import (
	"bytes"
	"encoding/base64"
	"testing"
)

func TestSourceRuleBodiesRequireExactAndRoleSpecificAcceptance(t *testing.T) {
	previous := pendingSourceReviews
	pendingSourceReviews = map[string]*sourceReviewCandidate{}
	t.Cleanup(func() { pendingSourceReviews = previous })
	home := t.TempDir()
	body := []byte{0, 255, 1, 128, 2}
	request := sourceAcceptanceRequest{
		Action: "review", Key: "clash-provider:7", Kind: "provider-rule", Identity: inputHash([]byte("rule source")), Settings: inputHash(nil),
		Format: "mrs", Behavior: "domain", BodyBase64: base64.StdEncoding.EncodeToString(body),
	}
	first, err := sourceAcceptance(home, request)
	if err != nil || first.Status != "reviewRequired" || first.Details == nil || !first.Details.Binary {
		t.Fatalf("binary bytes did not receive explicit review: %+v %v", first, err)
	}
	accept := request
	accept.Action, accept.Candidate, accept.Routing, accept.Automatic = "accept", first.Candidate, "source", true
	accepted, err := sourceAcceptance(home, accept)
	if err != nil || accepted.Use == nil {
		t.Fatal(err)
	}
	sealed, err := readSourceObject(home, accepted.MaterialHash, sourceCandidateMax)
	if err != nil || !bytes.Equal(sealed, body) {
		t.Fatal("sealed binary material differs from explicitly accepted bytes", err)
	}
	body[0]++
	request.BodyBase64 = base64.StdEncoding.EncodeToString(body)
	changed, err := sourceAcceptance(home, request)
	if err != nil || changed.Status != "reviewRequired" {
		t.Fatalf("binary maintenance delegated unknown byte changes: %+v %v", changed, err)
	}
	request.Kind = "provider-proxy"
	if _, err := sourceAcceptance(home, request); err == nil {
		t.Fatal("binary rule material was accepted as proxy content")
	}
}

func TestSourceRuleSummaryDoesNotInferOriginalParserSemantics(t *testing.T) {
	for _, fixture := range []struct {
		format, body string
		count        int
	}{
		{"yaml", "payload:\n  - +.example.invalid\n", 1},
		{"text", "# note\n+.example.invalid\n\n", 1},
	} {
		summary, err := summarizeSourceRuleContent([]byte(fixture.body), fixture.format, "domain")
		if err != nil || summary.Details.Rules != fixture.count || summary.Details.Binary {
			t.Fatalf("rule summary failed: %+v %v", summary, err)
		}
		next, err := summarizeSourceRuleContent([]byte(fixture.body+"\n"), fixture.format, "domain")
		if err != nil {
			t.Fatal(err)
		}
		if len(classifySourceDelta(sourceContentContract{Version: 1, Base: summary}, next)) == 0 {
			t.Fatal("schema-only rule summary granted unproven parser-equivalent maintenance")
		}
	}
	if _, err := summarizeSourceRuleContent([]byte{255}, "text", "domain"); err == nil {
		t.Fatal("invalid text encoding was accepted")
	}
	if _, err := summarizeSourceRuleContent([]byte("payload: []\n"), "mrs", "classical"); err == nil {
		t.Fatal("unsupported binary behavior was accepted")
	}
}
