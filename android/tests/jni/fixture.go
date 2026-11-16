//go:build r09_jni_fixture

package main

/*
#include <stdlib.h>
#include "bride.h"
*/
import "C"

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/metacubex/mihomo/component/requestscope"
	constant "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener/sing_tun"
)

var r09Scenario string
var r09Fired atomic.Bool
var r09Entered, r09Resume chan struct{}
var r09Closed atomic.Bool
var r09Closes atomic.Int32
var r09Armed atomic.Bool

func r09Point(point string) {
	if !r09Armed.Load() || strings.TrimPrefix(r09Scenario, "writer-") != point || !r09Fired.CompareAndSwap(false, true) {
		return
	}
	if point == "control-locked" {
		close(r09Entered)
		<-r09Resume
	}
	panic("controlled R09 " + point)
}

//export r09Arm
func r09Arm() { r09Armed.Store(true) }

func r09Close(_ *sing_tun.Listener) error {
	if r09Scenario == "stop-error" && r09Fired.CompareAndSwap(false, true) {
		return errors.New("controlled uncertain Close")
	}
	r09Point("stop-beforeclose")
	if r09Closed.CompareAndSwap(false, true) {
		r09Closes.Add(1)
	}
	r09Point("stop-afterclose")
	return nil
}

//export r09Configure
func r09Configure(callback unsafe.Pointer, scenario *C.char) {
	selected := takeCString(scenario)
	home := os.Getenv("FLCLASH_R09_HOME")
	if home == "" {
		panic("missing controlled fixture home")
	}
	if err := os.MkdirAll(home, 0700); err != nil {
		panic(err)
	}
	constant.SetHomeDir(home)
	appRequests = newAppRequestRegistry()
	appRequests.client, appRequests.clientReady = "client", true
	appRequests.state = AppRequestState{ProcessEpoch: "epoch", Revision: 1, IntentRunning: true, Phase: "started", DefaultNetworkKind: "nonVpn", DefaultNetworkID: "network"}
	appRequests.owner, appRequests.phase = requestscope.Owner{ID: 1}, "ready"
	tunHandler = &TunHandler{callback: callback, listener: &sing_tun.Listener{}, serviceID: "service", protectGeneration: 1}
	activeTunHandler.Store(tunHandler)
	r09Entered, r09Resume = make(chan struct{}), make(chan struct{})
	if strings.HasPrefix(selected, "writer-") {
		r := appRequests
		r.commits["writer"] = &appRequestReceipt{registry: r, id: "writer", client: "client", begun: true, retired: true}
		unknownRequestWriters.Add(1)
		if err := ensureRequestRecoveryMarker(home); err != nil {
			panic(err)
		}
	}
	if selected == "control-nil-map" {
		appRequests.sourceVersions.values = nil
	}
	r09Scenario = selected
}

//export r09Wait
func r09Wait() bool {
	select {
	case <-r09Entered:
		return true
	case <-time.After(5 * time.Second):
		return false
	}
}

//export r09Continue
func r09Continue() { close(r09Resume) }

//export r09Socket
func r09Socket() bool { return prepareAppRequestSocket("fixture", AppRequestState{}, 42) == nil }

//export r09Snapshot
func r09Snapshot() *C.char {
	out := map[string]any{"fault": requestNativeFault.Load(), "closes": r09Closes.Load(), "writers": unknownRequestWriters.Load()}
	for name, mu := range map[string]interface {
		TryLock() bool
		Unlock()
	}{"registry": &appRequests.mu, "selection": &selectMu, "checkpoint": &checkpointMu, "socket": &requestSocketMu, "tun": &tunLock} {
		ok := mu.TryLock()
		out[name] = ok
		if ok {
			mu.Unlock()
		}
	}
	if tunHandler != nil {
		out["handler"] = true
		ok := tunHandler.mu.TryLock()
		out["handlerLock"] = ok
		if ok {
			out["service"], out["generation"] = tunHandler.serviceID, tunHandler.protectGeneration
			tunHandler.mu.Unlock()
		}
	} else {
		out["handler"] = false
		out["handlerLock"] = true
	}
	out["commits"] = len(appRequests.commits)
	_, markerErr := os.Stat(requestRecoveryPath(constant.Path.HomeDir()))
	out["recoveryMarker"] = markerErr == nil
	data, _ := json.Marshal(out)
	return C.CString(string(data))
}

//export r09RemoveHome
func r09RemoveHome() { _ = os.RemoveAll(constant.Path.HomeDir()) }

func main() {}

func r09UpdateSystemDNS([]string) {}
func r09FlushDefaultResolver()    {}
