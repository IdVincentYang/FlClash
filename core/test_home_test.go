package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

func TestMain(m *testing.M) {
	home, err := os.MkdirTemp("", "flclash-core-test-home-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "create isolated Core test home:", err)
		os.Exit(1)
	}
	C.SetHomeDir(home)
	C.SetConfig(filepath.Join(home, "config.yaml"))
	status := m.Run()
	_ = os.RemoveAll(home)
	os.Exit(status)
}
