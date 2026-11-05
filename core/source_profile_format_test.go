package main

import (
	"testing"

	"github.com/metacubex/mihomo/component/age"
)

func TestSourceAgeProfileUsesOriginalDecoderBeforeAcceptanceAndProjection(t *testing.T) {
	if !sourceTestIsolation(t) {
		return
	}
	sourceRuntimeFixture(t)
	appRequests.client, appRequests.clientReady = "age-profile-client", true
	secret, public, err := age.GenX25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}
	age.SetGlobalSecretKeys(secret)
	body := []byte("mode: rule\nproxies: [{name: accepted-node, type: socks5, server: 127.0.0.1, port: 1}]\nrules: [\"MATCH,DIRECT\"]\n")
	encrypted, err := age.EncryptBytes(body, public)
	if err != nil {
		t.Fatal(err)
	}
	if raw, _, err := decodeConfigDocument(encrypted); err != nil || len(raw.Proxy) != 1 {
		t.Fatal("original profile decoder did not accept the controlled age body", err)
	}
	request := sourceAcceptanceRequest{Action: "review", Key: "profile:40", Kind: "profile", Identity: inputHash([]byte("controlled encrypted profile")), Settings: inputHash(nil), Body: string(encrypted), Source: ConfigSourceTicket{Client: appRequests.client, Dataset: appRequests.dataset, Sources: map[string]uint64{"profile:40": 0}}}
	first := sourceMaterialRPCOK(t, request)
	request.Action, request.Candidate, request.Routing = "accept", first.Candidate, "source"
	accepted := sourceMaterialRPCOK(t, request)
	if accepted.MaterialHash != inputHash(encrypted) || accepted.Use == nil {
		t.Fatal("acceptance did not preserve the actual encrypted material", accepted)
	}
	request.Action = "project"
	projected := sourceMaterialRPCOK(t, request)
	if projected.Status != "accepted" || projected.Document["proxies"] == nil {
		t.Fatal("accepted encrypted profile was not projected through its actual plaintext", projected.Status)
	}
}
