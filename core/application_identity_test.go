package main

import "testing"

func TestApplicationIdentityRequiresUniquePackageInCurrentUser(t *testing.T) {
	cases := []struct {
		name, data, status, pkg string
	}{
		{"unique", `{"status":"known","userScope":"current","packages":["test.app"]}`, "known", "test.app"},
		{"shared", `{"status":"ambiguous","userScope":"current","packages":["test.b","test.a"]}`, "ambiguous", ""},
		{"missing", `{"status":"notFound","userScope":"current","packages":[]}`, "notFound", ""},
		{"other user", `{"status":"otherUser","userScope":"other"}`, "otherUser", ""},
		{"first candidate", `{"status":"known","userScope":"current","packages":["test.a","test.b"]}`, "lookupFailed", ""},
		{"duplicate", `{"status":"known","userScope":"current","packages":["test.a","test.a"]}`, "lookupFailed", ""},
		{"cross user guess", `{"status":"known","userScope":"other","packages":["test.a"]}`, "lookupFailed", ""},
		{"legacy string", `test.app`, "lookupFailed", ""},
		{"malformed", `{`, "lookupFailed", ""},
		{"future status", `{"status":"guessed","userScope":"current","packages":["test.app"]}`, "lookupFailed", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			value := decodeApplicationIdentity(10123, tc.data, "androidUid")
			if value.Status != tc.status || value.packageName() != tc.pkg || value.UID == nil || *value.UID != 10123 {
				t.Fatalf("incorrect application identity: %+v", value)
			}
		})
	}
}

func TestApplicationIdentityDoesNotConfuseMissingUIDWithRoot(t *testing.T) {
	unknown := decodeApplicationIdentity(-1, `{}`, "androidUid")
	root := decodeApplicationIdentity(0, `{"status":"notFound","userScope":"current"}`, "androidUid")
	if unknown.UID != nil || unknown.packageName() != "" || root.UID == nil || *root.UID != 0 {
		t.Fatal("missing UID was converted to root")
	}
}
