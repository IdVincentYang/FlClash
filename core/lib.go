//go:build android && cgo

package main

/*
#include <stdlib.h>
#include "bride.h"
*/
import "C"

import (
	"core/platform"
	t "core/tun"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"unsafe"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/requestscope"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
)

var (
	eventListenerLock sync.RWMutex
	eventListener     unsafe.Pointer
)

type TunHandler struct {
	listener *sing_tun.Listener
	callback unsafe.Pointer

	mu                sync.RWMutex
	serviceID         string
	protectGeneration uint64
}

func (th *TunHandler) start(fd int, stack, address, dns string) bool {
	configMu.Lock()
	defer configMu.Unlock()
	if !canStartRequestTun(th.serviceID, th.protectGeneration) {
		_ = syscall.Close(fd)
		th.mu.Lock()
		th.clear()
		th.mu.Unlock()
		return false
	}

	th.mu.Lock()
	th.initHook()
	th.mu.Unlock()

	// t.Start runs outside th.mu on purpose. The hook is live from initHook
	// onwards, and a socket opened anywhere inside Start reaches handleProtect
	// on this very goroutine — an RLock taken while this one holds the write
	// lock deadlocks the start outright. Nothing is lost by dropping it: both
	// hooks return early until th.listener is set, which is below.
	tunListener := t.Start(fd, stack, address, dns)

	th.mu.Lock()
	defer th.mu.Unlock()
	if tunListener != nil {
		log.Infoln("TUN address: %v", tunListener.Address())
		th.listener = tunListener
		return true
	}
	th.clear()
	return false
}

func (th *TunHandler) close() {
	th.mu.Lock()
	defer th.mu.Unlock()
	th.clear()
}

func (th *TunHandler) clear() {
	th.removeHook()
	if th.listener != nil {
		_ = th.listener.Close()
	}
	if th.callback != nil {
		releaseObject(th.callback)
	}
	th.callback = nil
	th.listener = nil
}

// protectFailing tracks whether the last protect call was refused, so a stuck
// VpnService produces one log line rather than one per connection.
var protectFailing atomic.Bool

func (th *TunHandler) handleProtect(fd int) error {
	th.mu.RLock()
	defer th.mu.RUnlock()

	if th.listener == nil || th.callback == nil {
		// The tun routes are already live at this point (Android establishes
		// them before it hands the fd over), so an unprotected socket would be
		// routed straight back into the tunnel and hang until it times out.
		// Failing it here costs nothing and is at least visible.
		return errTunNotReady
	}

	if !protect(th.callback, fd) {
		if protectFailing.CompareAndSwap(false, true) {
			logError("VpnService.protect refused a socket; connections would loop back into the tunnel")
		}
		return errProtectRefused
	}

	if protectFailing.CompareAndSwap(true, false) {
		log.Infoln("[TUN] VpnService.protect recovered")
	}
	return nil
}

func (th *TunHandler) handleResolveProcess(source, target net.Addr) (int, string) {
	th.mu.RLock()
	defer th.mu.RUnlock()

	// A released callback is a null jobject, and JNI aborts on a call through one.
	if th.listener == nil || th.callback == nil {
		return -1, ""
	}
	var protocol int
	switch source.Network() {
	case "udp", "udp4", "udp6":
		protocol = syscall.IPPROTO_UDP
	case "tcp", "tcp4", "tcp6":
		protocol = syscall.IPPROTO_TCP
	}
	var uid int
	if sdkVersion.Load() < 29 {
		uid = platform.QuerySocketUidFromProcFs(source, target)
	} else {
		uid = resolveUid(th.callback, protocol, source.String(), target.String())
	}
	if uid < 0 {
		return -1, ""
	}
	return uid, resolvePackage(th.callback, uid)
}

var (
	installHooksOnce sync.Once
	activeTunHandler atomic.Pointer[TunHandler]
)

func installHooks() {
	installHooksOnce.Do(func() {
		dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
			if platform.ShouldBlockConnection() {
				return errBlocked
			}
			th := activeTunHandler.Load()
			if th == nil {
				return nil
			}
			var protectErr error
			if err := conn.Control(func(fd uintptr) {
				protectErr = th.handleProtect(int(fd))
			}); err != nil {
				return err
			}
			return protectErr
		}
		process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
			th := activeTunHandler.Load()
			if th == nil {
				return "", process.ErrInvalidNetwork
			}
			src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
			if src == nil || dst == nil {
				return "", process.ErrInvalidNetwork
			}
			// Everywhere else mihomo fills Uid from its own procfs lookup, the one Android took away.
			uid, packageName := th.handleResolveProcess(src, dst)
			if uid >= 0 {
				metadata.Uid = uint32(uid)
			}
			return packageName, nil
		}
	})
}

func (th *TunHandler) initHook() {
	installHooks()
	activeTunHandler.Store(th)
}

// Swap the handler, never the hook: mihomo nil-checks DefaultSocketHook once and
// dereferences it again when the socket is created, so clearing it mid-dial
// calls a nil func value.
func (th *TunHandler) removeHook() {
	activeTunHandler.CompareAndSwap(th, nil)
}

var (
	tunLock           sync.Mutex
	errBlocked        = errors.New("blocked: the process is out of file descriptors")
	errTunNotReady    = errors.New("blocked: the tun listener is not ready")
	errProtectRefused = errors.New("blocked: VpnService.protect refused the socket")
	tunHandler        *TunHandler
)

func handleStopTun() {
	tunLock.Lock()
	defer tunLock.Unlock()
	stopTunLocked()
}

func stopTunLocked() {
	if tunHandler == nil {
		return
	}
	tunHandler.close()
	tunHandler = nil
}

func handleStartTun(callback unsafe.Pointer, fd int, stack, address, dns, serviceID string, generation uint64) bool {
	tunLock.Lock()
	defer tunLock.Unlock()
	if !canStartRequestTun(serviceID, generation) {
		if callback != nil {
			releaseObject(callback)
		}
		if fd != 0 {
			_ = syscall.Close(fd)
		}
		return false
	}
	stopTunLocked()
	if fd == 0 {
		if callback != nil {
			releaseObject(callback)
		}
		logError("startTun was handed no tun descriptor")
		return false
	}
	tunHandler = &TunHandler{
		callback:          callback,
		serviceID:         serviceID,
		protectGeneration: generation,
	}
	if tunHandler.start(fd, stack, address, dns) {
		return true
	}
	// start() already cleared the handler, so nothing protects sockets from
	// here on. Android has the routes up regardless, so the caller has to tear
	// the VPN down rather than leave the device pointed at a black hole.
	tunHandler = nil
	return false
}

var (
	dnsUpdateMu  sync.Mutex
	dnsUpdateSeq atomic.Uint64
)

func handleUpdateDns(value string) {
	// mihomo turns the [""] that Split returns for no servers into a "udp://:"
	// nameserver, which keeps the system resolver off its default fallback.
	var addr []string
	if value != "" {
		addr = strings.Split(value, ",")
	}
	seq := dnsUpdateSeq.Add(1)
	safeGoDetached("updateDns", func() {
		dnsUpdateMu.Lock()
		defer dnsUpdateMu.Unlock()
		if seq != dnsUpdateSeq.Load() {
			return
		}
		log.Infoln("[DNS] updateDns %s", value)
		dns.UpdateSystemDNS(addr)
		dns.FlushCacheWithDefaultResolver()
	})
}

func (response MethodResponse) send() {
	data, err := response.JSON()
	if err != nil {
		logError("MethodResponse marshal error: id=%s err=%v", response.ID, err)
		releaseObject(response.callback)
		return
	}
	invokeResult(response.callback, string(data))
	releaseObject(response.callback)
}

func init() {
	registerMethod(updateDnsMethod, withArguments(func(value *string, response MethodResponse) {
		handleUpdateDns(*value)
		response.success(true)
	}))
}

//export invokeMethod
func invokeMethod(callback unsafe.Pointer, paramsChar *C.char) {
	params := takeCString(paramsChar)
	call := &MethodCall{}
	if err := json.Unmarshal([]byte(params), call); err != nil {
		newMethodResponse("", callback).failure("invalid_method_call", err.Error(), nil)
		return
	}
	dispatchMethodCall(call, newMethodResponse(call.ID, callback))
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar, serviceID *C.char, generation C.longlong) bool {
	identity := takeCString(serviceID)
	version := uint64(generation)
	started := handleStartTun(callback, int(fd), takeCString(stackChar), takeCString(addressChar), takeCString(dnsChar), identity, version)
	if !started {
		return false
	}
	if !startRequestListener(identity, version) {
		handleStopTunIdentity(identity, version)
		return false
	}
	return true
}

func startRequestListener(identity string, generation uint64) bool {
	configMu.Lock()
	defer configMu.Unlock()
	if !canStartRequestTun(identity, generation) {
		return false
	}
	opened := !isRunning.Load()
	if opened {
		isRunning.Store(true)
		updateListeners(currentConfig)
		resolver.ResetConnection()
		refreshRoute()
	} else {
		handleResetConnections()
	}
	if !canStartRequestTun(identity, generation) {
		if opened {
			isRunning.Store(false)
			listener.StopListener()
		}
		return false
	}
	return true
}

//export quickSetup
func quickSetup(callback unsafe.Pointer, initParamsChar *C.char, setupParamsChar *C.char) {
	go func() {
		defer releaseObject(callback)
		defer func() {
			if r := recover(); r != nil {
				logError("panic in quickSetup: %v\n%s", r, stackTrace())
				invokeResult(callback, fmt.Sprintf("internal panic: %v", r))
			}
		}()
		initParamsString := takeCString(initParamsChar)
		setupParamsString := takeCString(setupParamsChar)
		initParams := InitParams{}
		if err := json.Unmarshal([]byte(initParamsString), &initParams); err != nil || !handleInitClash(&initParams) {
			invokeResult(callback, "init failed")
			return
		}
		setupParams := defaultSetupParams()
		if err := UnmarshalJson([]byte(setupParamsString), setupParams); err != nil {
			invokeResult(callback, err.Error())
			return
		}
		isRunning.Store(true)
		invokeResult(callback, handleSetupConfig(setupParams))
	}()
}

// The listener goes away with the Flutter engine, which never gets to release
// the route watch it held, while the service and this core run on.
//
//export setEventListener
func setEventListener(listener unsafe.Pointer) {
	eventListenerLock.Lock()
	if eventListener != nil {
		releaseObject(eventListener)
	}
	eventListener = listener
	eventListenerLock.Unlock()
	if listener == nil {
		stopRouteWatch()
	}
}

func hasEventListener() bool {
	eventListenerLock.RLock()
	defer eventListenerLock.RUnlock()
	return eventListener != nil
}

//export getTotalTraffic
func getTotalTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(marshalResult(handleGetTotalTraffic(onlyStatisticsProxy)))
}

//export getTraffic
func getTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(marshalResult(handleGetTraffic(onlyStatisticsProxy)))
}

func marshalResult(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		logError("Result marshal error: %v", err)
		return ""
	}
	return string(data)
}

func deliverEvent(data []byte) {
	eventListenerLock.RLock()
	defer eventListenerLock.RUnlock()
	if eventListener == nil {
		return
	}
	invokeResult(eventListener, string(data))
}

//export stopTun
func stopTun() {
	handleStopTun()
	if isRunning.Load() {
		handleStopListener()
	}
}

//export forceGC
func forceGC() {
	handleForceGC()
}

//export updateDns
func updateDns(s *C.char) {
	handleUpdateDns(takeCString(s))
}

var requestSocketMu sync.RWMutex
var requestSocketCallback unsafe.Pointer

//export requestControl
func requestControl(data *C.char) *C.char {
	return C.CString(handleRequestControl(takeCString(data)))
}

//export setRequestSocketListener
func setRequestSocketListener(callback unsafe.Pointer) {
	requestSocketMu.Lock()
	previous := requestSocketCallback
	requestSocketCallback = callback
	requestSocketMu.Unlock()
	if previous != nil {
		releaseObject(previous)
	}
}

//export setTunRequestIdentity
func setTunRequestIdentity(serviceID *C.char, generation C.longlong) {
	identity := takeCString(serviceID)
	tunLock.Lock()
	defer tunLock.Unlock()
	if tunHandler == nil {
		return
	}
	tunHandler.mu.Lock()
	tunHandler.serviceID = identity
	tunHandler.protectGeneration = uint64(generation)
	tunHandler.mu.Unlock()
}

func prepareAppRequestSocket(id string, state AppRequestState, fd int) error {
	if state.ProtectPhase == "ready" {
		handler := activeTunHandler.Load()
		if handler == nil {
			return requestscope.ErrBlocked
		}
		handler.mu.RLock()
		valid := handler.listener != nil && handler.callback != nil && handler.serviceID == state.ServiceID && handler.protectGeneration == state.ProtectGeneration
		handler.mu.RUnlock()
		if !valid {
			return requestscope.ErrBlocked
		}
	}
	payload, err := json.Marshal(state)
	if err != nil {
		return requestscope.ErrBlocked
	}
	data := C.CString(string(payload))
	defer C.free(unsafe.Pointer(data))
	requestSocketMu.RLock()
	defer requestSocketMu.RUnlock()
	if requestSocketCallback == nil || C.request_socket(requestSocketCallback, data, C.int(fd)) == 0 {
		return requestscope.ErrBlocked
	}
	return nil
}

func init() { appRequests.socketGate = prepareAppRequestSocket }

func canStartRequestTun(serviceID string, generation uint64) bool {
	appRequests.mu.Lock()
	defer appRequests.mu.Unlock()
	state := appRequests.state
	return state.IntentRunning && !state.Paused && state.Phase == "starting" && state.ProtectPhase == "starting" && state.ServiceID == serviceID && generation != 0 && state.ProtectGeneration == generation && appRequests.phase == "ready"
}

//export stopTunRequest
func stopTunRequest(serviceID *C.char, generation C.longlong) bool {
	return handleStopTunIdentity(takeCString(serviceID), uint64(generation))
}

func handleStopTunIdentity(identity string, generation uint64) bool {
	tunLock.Lock()
	defer tunLock.Unlock()
	if tunHandler == nil {
		return false
	}
	tunHandler.mu.RLock()
	matches := tunHandler.serviceID == identity && tunHandler.protectGeneration == generation
	tunHandler.mu.RUnlock()
	if !matches {
		return false
	}
	return stopOwnedRequestService(requestTunIdentity{identity, generation}, requestTunIdentity{tunHandler.serviceID, tunHandler.protectGeneration}, stopTunLocked)
}
