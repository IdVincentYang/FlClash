package main

import (
	"context"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
	"time"
)

// Compatible has no task join; retain process-wide hooks until this fixture exits.
func sourceTestIsolation(t *testing.T) bool {
	t.Helper()
	if os.Getenv("FLCLASH_SOURCE_TEST_CHILD") == t.Name() {
		return true
	}
	path, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(t.Name(), "/")
	for i, part := range parts {
		parts[i] = "^" + regexp.QuoteMeta(part) + "$"
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, path, "-test.run="+strings.Join(parts, "/"), "-test.count=1")
	command.Env = append(os.Environ(), "FLCLASH_SOURCE_TEST_CHILD="+t.Name())
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("isolated source fixture failed: %v\n%s", err, output)
	}
	return false
}
