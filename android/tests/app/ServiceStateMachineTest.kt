package com.follow.clash

import com.follow.clash.common.AccessControlMode
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.common.RequestProtection
import com.follow.clash.common.RequestServiceIdentity
import com.follow.clash.models.SetupParams
import com.follow.clash.models.SharedState
import com.follow.clash.models.ConfigReceipt
import com.follow.clash.models.ConfigApplyResult
import com.follow.clash.models.ConfigFact
import com.follow.clash.models.ServiceCoreParams
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.follow.clash.service.models.AccessControlProps
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import com.google.gson.Gson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private fun vpnOptions(enable: Boolean = true, stack: String = "gvisor") = VpnOptions(
    enable = enable,
    port = 7890,
    ipv6 = false,
    dnsHijacking = false,
    accessControlProps = AccessControlProps(
        enable = false,
        mode = AccessControlMode.ACCEPT_SELECTED,
        acceptList = emptyList(),
        rejectList = emptyList(),
    ),
    allowBypass = false,
    systemProxy = true,
    bypassDomain = emptyList(),
    stack = stack,
    routeAddress = emptyList(),
)

private fun configuredState(enable: Boolean = true, stack: String = "gvisor") = SharedState(
    vpnOptions = vpnOptions(enable, stack),
    setupParams = SetupParams(testUrl = "https://example.com", selectedMap = emptyMap()),
)

private class FakeTile : TileGateway {
    var startCount = 0
    var stopCount = 0

    override fun handleStart() {
        startCount++
    }

    override fun handleStop() {
        stopCount++
    }
}

private class FakeApp(
    private val notificationGranted: Boolean = true,
    private val localNetworkGranted: Boolean = true,
    private val vpnGranted: Boolean = true,
    private val holdVpnPreparation: Boolean = false,
) : AppGateway {
    var beforeVpnPrepared: (() -> Unit)? = null
    var cancelledPreparations = 0
    var localNetworkRequests = 0

    private var heldCallback: ((Boolean) -> Unit)? = null

    override fun requestNotificationPermission(callback: (Boolean) -> Unit) =
        callback(notificationGranted)

    override fun requestLocalNetworkPermission(callback: (Boolean) -> Unit) {
        localNetworkRequests++
        callback(localNetworkGranted)
    }

    override fun prepareVpn(enable: Boolean, callback: (Boolean) -> Unit) {
        beforeVpnPrepared?.invoke()
        if (holdVpnPreparation) {
            heldCallback = callback
            return
        }
        callback(vpnGranted)
    }

    override fun cancelVpnPreparation(callback: (Boolean) -> Unit) {
        cancelledPreparations++
        if (heldCallback === callback) {
            heldCallback = null
        }
    }
}

internal class ConfigServiceTestHost(override val scope: CoroutineScope) : ServiceStateHost {
    private lateinit var machine: ServiceStateMachine
    @Volatile private var configSequence = 0L
    private var factVersion = 0L
    private var ownedIdentity: RequestServiceIdentity? = null
    private val activeInputs = mutableMapOf<Long,Boolean>()
    var cleanupGate: CompletableDeferred<Unit>? = null
    var cleanupFailure: String? = null
    val cleanupEntered = CompletableDeferred<Unit>()
    var failingPhase: String? = null
    @Volatile var heldPhase: String? = null
    @Volatile var phaseGate: CompletableDeferred<Unit>? = null
    @Volatile var phaseEntered: CompletableDeferred<Unit>? = null
    var phaseFailureStatus = "blocked"
    var buildFailureStatus = "retained"
    var buildFailureGate: CompletableDeferred<Unit>? = null
    val buildFailureEntered = CompletableDeferred<Unit>()
    val phaseCalls = mutableListOf<Pair<String,Long>>()
    var coreParameters: ServiceCoreParams? = null
    @Volatile var lastConfigFact = ConfigFact(runtimeEpoch="test")
    fun ownedService(): RequestServiceIdentity? = ownedIdentity
    fun replaceOwnedService(identity: RequestServiceIdentity) { ownedIdentity = identity }

    fun createMachine(): ServiceStateMachine = ServiceStateMachine(this).also { machine = it }
    @Synchronized override fun registerConfigInput(input: JsonObject): ConfigReceipt {
        val token = ++configSequence
        activeInputs[token] = input.get("active").asBoolean
        return ConfigReceipt(token=token,inputId=input.get("inputId").asString)
    }
    override suspend fun replayConfigInput(): JsonObject {
        if (storedSharedState.setupParams == null || storedSharedState.vpnOptions == null) error(MISSING_CONFIG_MESSAGE)
        setupCalls++
        lastInitParams = ServiceStateMachine.initParams(homeDirPath,sdkInt)
        lastSetupParams = Gson().toJson(storedSharedState.setupParams)
        val result = setupResult.getOrThrow()
        check(result.isEmpty()) { result }
        return JsonParser.parseString("{\"inputId\":\""+"a".repeat(64)+"\"}").asJsonObject
    }
    override suspend fun configPhase(method: String, receipt: ConfigReceipt): ConfigApplyResult {
        if (heldPhase == method) {
            val gate = phaseGate
            heldPhase = null
            phaseEntered?.complete(Unit)
            gate?.await()
        }
        if (receipt.token != configSequence) return ConfigApplyResult("superseded",receipt=receipt)
        phaseCalls += method to receipt.token
        val prepared = receipt.copy(owner=receipt.token)
        val status = if (method == failingPhase) phaseFailureStatus else when(method) { "prepareConfig" -> "prepared"; "installConfig" -> "installed"; "activateConfig" -> if(activeInputs[receipt.token] == true) "activated" else "installedInactive"; else -> "blocked" }
        val fact = ConfigFact(runtimeEpoch="test",version=++factVersion,token=receipt.token,owner=prepared.owner,inputId=receipt.inputId,profileName="Applied",phase=if(status in setOf("activated","installedInactive")) "ready" else if(status=="blocked") "failed" else "parsing",businessActive=status=="activated")
        lastConfigFact = fact
        return ConfigApplyResult(status,receipt=prepared,coreParams=coreParameters ?: ServiceCoreParams(mixedPort=7890,bindingId=receipt.token,localReachable=true),fact=fact)
    }
    override suspend fun failConfigBuild(input: JsonObject): ConfigApplyResult {
        buildFailureEntered.complete(Unit)
        buildFailureGate?.await()
        val expected = input.getAsJsonObject("expected")
        if (expected.get("owner").asLong != lastConfigFact.owner || expected.get("token").asLong != lastConfigFact.token) return ConfigApplyResult("superseded",fact=lastConfigFact)
        if (buildFailureStatus == "blocked") lastConfigFact = lastConfigFact.copy(version=++factVersion,phase="failed",businessActive=false,replayEligible=false)
        return ConfigApplyResult(buildFailureStatus,fact=lastConfigFact)
    }
    override suspend fun startService(options: VpnOptions, requestId: Long): Long {
        var identity = RequestServiceIdentity("fake-service-${startCalls+1}",requestId)
        check(machine.bindService(identity.serviceId,requestId))
        ownedIdentity = identity
        val result = startService(options)
        if (result == 0L) return result
        if (machine.getRequestState().intentRevision != requestId) {
            stopOwnedService(identity)
            return 0
        }
        if (options.enable) {
            val protection = object: RequestProtection {
                override val requestIdentity get() = identity
                override fun protectRequestSocket(fd:Int,expected:RequestServiceIdentity) = expected == identity
                override fun isRequestLockdownEnabled(): Boolean? = false
            }
            val generation = machine.observeProtection(protection,identity,"starting","none")
            identity = identity.copy(generation=generation)
            machine.observeProtection(protection,identity,"ready","none")
        }
        ownedIdentity = identity
        return result
    }
    override suspend fun stopOwnedService(identity: RequestServiceIdentity): Boolean {
        cleanupEntered.complete(Unit)
        cleanupGate?.await()
        if (cleanupFailure == "throw") error("synthetic cleanup failure")
        if (cleanupFailure == "false") return false
        if (ownedIdentity != null && ownedIdentity != identity) return false
        stopService()
        ownedIdentity = null
        machine.observeServiceLost(identity.serviceId,identity.requestId)
        return true
    }

    var storedSharedState = configuredState()
    var sharedStateUnavailable = false
    var sharedStateReadFailure: Exception? = null
    override suspend fun loadSharedStateForStart(): SharedState? {
        sharedStateReadFailure?.let { throw it }
        return if (sharedStateUnavailable) null else storedSharedState
    }
    var setupResult: Result<String> = Result.success("")
    var startResult = 1_700_000_000_000L
    var vpnPermissionGranted = true
    var localNetworkPermissionGranted = true
    var vpnServiceActive = true
    var tile: TileGateway? = null
    var app: AppGateway? = null
    var beforeStartService: (() -> Unit)? = null
    var lastStartOptions: VpnOptions? = null

    override var runTimeMillis = 0L
    override val homeDirPath = "/data/user/0/com.follow.clash/files"
    override val sdkInt = 34

    val toasts = mutableListOf<String>()
    val logs = mutableListOf<String>()
    val notificationParams = mutableListOf<NotificationParams>()
    var setupCalls = 0
    var startCalls = 0
    var stopCalls = 0
    var lastInitParams: String? = null
    var lastSetupParams: String? = null
    val requestPublications = mutableListOf<ApplicationRequestState>()
    var publishAccepted = true
    var blockedRequests = 0
    override fun publishRequestState(state: ApplicationRequestState): Boolean {
        requestPublications += state
        return publishAccepted
    }
    override fun blockRequestState() { blockedRequests++ }

    override fun log(message: String) {
        logs += message
    }

    override fun showToast(message: String) {
        toasts += message
    }

    override fun updateNotificationParams(params: NotificationParams) {
        notificationParams += params
    }

    override fun loadSharedState(): SharedState = storedSharedState

    override fun isVpnPermissionGranted(): Boolean = vpnPermissionGranted

    override fun isLocalNetworkPermissionGranted(): Boolean = localNetworkPermissionGranted

    override fun tile(): TileGateway? = tile

    override fun app(): AppGateway? = app

    override suspend fun startService(options: VpnOptions): Long {
        startCalls++
        lastStartOptions = options
        beforeStartService?.invoke()
        runTimeMillis = startResult
        return startResult
    }

    override suspend fun stopService() {
        stopCalls++
        runTimeMillis = 0L
    }

    override suspend fun isVpnServiceActive(): Boolean = vpnServiceActive
}

@OptIn(ExperimentalCoroutinesApi::class)
class ServiceStateMachineTest {

    @Test
    fun `intent is published before setup or permission waits and reads are inert`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        val request = machine.prepareRunIntent(true)
        val state = machine.getRequestState()
        assertEquals(request, state.intentRevision)
        assertEquals("preparing", state.phase)
        assertTrue(state.intentRunning)
        assertEquals(0, host.setupCalls)
        assertEquals(0, host.startCalls)
        assertEquals(state, machine.getRequestState())
        assertEquals(1, host.requestPublications.size)
    }

    @Test
    fun `SSID pause preserves intent and manual stop prevents resume`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        val start = machine.prepareRunIntent(true)
        assertTrue(machine.requestStart(start).await())
        val pause = machine.prepareRunIntent(true, "ssid", true)
        assertTrue(machine.getRequestState().intentRunning)
        assertEquals("excludedSsid", machine.getRequestState().reason)
        machine.requestStop(pause).await()
        val stop = machine.prepareRunIntent(false)
        machine.requestStop(stop).await()
        val resume = machine.prepareRunIntent(machine.getRequestState().intentRunning, "ssid", false)
        machine.requestStop(resume).await()
        assertFalse(machine.getRequestState().intentRunning)
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `old instance and pending binding loss cannot replace a newer intent`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        val old = machine.prepareRunIntent(true)
        assertTrue(machine.bindService("old-service", old))
        val current = machine.prepareRunIntent(true)
        assertTrue(machine.bindService("new-service", current))
        val before = machine.getRequestState()
        machine.observeServiceLost("old-service", old)
        machine.observeBindingLost(old)
        assertEquals(before, machine.getRequestState())
    }

    @Test
    fun `publication failure blocks prepared starts`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.publishAccepted = false
        val machine = host.createMachine()
        val request = machine.prepareRunIntent(true)
        assertEquals("failed", machine.getRequestState().phase)
        assertEquals(1, host.blockedRequests)
        assertFalse(machine.requestStart(request).await())
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `initParams spells the keys the Go wrapper expects`() {
        val json = ServiceStateMachine.initParams("/files", 34)

        assertEquals("""{"home-dir":"/files","version":34}""", json)
    }

    @Test
    fun `notification style uses shared state without claiming the desired profile is active`() {
        val params = ServiceStateMachine.notificationParams(
            SharedState(
                currentProfileName = "Work",
                stopText = "Disconnect",
                onlyStatisticsProxy = true,
            ),
        )

        assertEquals(NotificationParams("FlClash", "Disconnect", true), params)
    }

    @Test
    fun `notification params carry the stop action switch`() {
        val params = ServiceStateMachine.notificationParams(
            SharedState(showStopAction = false),
        )

        assertEquals(false, params.showStopAction)
    }

    @Test
    fun `refresh does not display physical runtime before activation`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        assertEquals(0L, machine.refresh())
        assertEquals(RunState.STOPPED, machine.runState.value)

        host.runTimeMillis = 42L
        val before = machine.getRequestState()
        assertEquals(0L, machine.refresh())
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(before, machine.getRequestState())
    }

    @Test
    fun `a start request drives the service to STARTED`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        assertTrue(machine.requestStart().await())
        assertEquals(RunState.STARTED, machine.runState.value)
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `a start that the service refuses settles back to STOPPED`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.startResult = 0L
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start without stored vpn options never reaches the service`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.storedSharedState = SharedState()
        val machine = host.createMachine()

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a denied notification permission cancels the start`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.app = FakeApp(notificationGranted = false)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a denied vpn permission cancels the start`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.app = FakeApp(vpnGranted = false)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
    }

    /**
     * Without a foreground app there is nobody to show the system consent dialog, so the machine
     * has to explain the refusal itself.
     */
    @Test
    fun `a missing vpn permission is reported when no app is attached`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.vpnPermissionGranted = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertTrue(host.toasts.contains(VPN_PERMISSION_MESSAGE))
    }

    @Test
    fun `a proxy-only start does not need the vpn permission`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.vpnPermissionGranted = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState(enable = false))

        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
    }

    /** Android 17 drops the kernel hop system/mixed rely on until the permission is granted. */
    @Test
    fun `a denied local network permission falls back to the gvisor stack`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.localNetworkPermissionGranted = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState(stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals("gvisor", host.lastStartOptions?.stack)
        assertTrue(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `a granted local network permission keeps the chosen stack`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState(stack = "mixed"))

        assertTrue(machine.requestStart().await())
        assertEquals("mixed", host.lastStartOptions?.stack)
        assertFalse(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `a proxy-only start keeps its stack without the local network permission`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.localNetworkPermissionGranted = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState(enable = false, stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals("system", host.lastStartOptions?.stack)
        assertFalse(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `the local network prompt is asked once and never blocks the start`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val app = FakeApp(localNetworkGranted = false)
        host.app = app
        host.localNetworkPermissionGranted = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState(stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals(1, app.localNetworkRequests)
        assertEquals(1, host.startCalls)
        assertEquals("gvisor", host.lastStartOptions?.stack)
    }

    @Test
    fun `a stop request drives the service to STOPPED`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        assertTrue(machine.requestStop().await())
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `stopping an already stopped service touches nothing`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        assertTrue(machine.requestStop().await())
        assertEquals(0, host.stopCalls)
    }

    @Test
    fun `a stop that lands mid-preparation keeps the service stopped`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        val app = FakeApp()
        host.app = app
        app.beforeVpnPrepared = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start reports failure when a stop overtakes the service call`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        host.beforeStartService = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
    }

    @Test
    fun `handleServiceLost clears the state for the token that observed the loss`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        val token = machine.captureRequestToken()
        host.runTimeMillis = 0L
        machine.handleServiceLost(token)

        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `handleServiceLost keeps the intent of a start that raced ahead of it`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        val staleToken = machine.captureRequestToken()

        machine.requestStart().await()
        host.runTimeMillis = 0L
        machine.handleServiceLost(staleToken)

        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `handleServiceLost ignores a service that is running again`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        machine.handleServiceLost(machine.captureRequestToken())

        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `handleStartAction hands the start to the tile when one is attached`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = host.createMachine()

        machine.handleStartAction()

        assertEquals(1, tile.startCount)
        assertEquals(0, host.setupCalls)
    }

    @Test
    fun `handleStartAction is a no-op while a run is already requested`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val startsBefore = host.startCalls
        val setupsBefore = host.setupCalls

        machine.handleStartAction()

        assertEquals(startsBefore, host.startCalls)
        assertEquals(setupsBefore, host.setupCalls)
    }

    @Test
    fun `handleStartAction reports a missing configuration`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.storedSharedState = SharedState()
        val machine = host.createMachine()

        machine.handleStartAction()

        assertEquals(listOf(MISSING_CONFIG_MESSAGE), host.toasts)
        assertEquals(0, host.setupCalls)
    }

    @Test
    fun `handleStartAction loads the stored configuration and sets the core up`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        machine.handleStartAction()

        assertEquals(1, host.setupCalls)
        assertEquals(1, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
        assertEquals(
            ServiceStateMachine.initParams(host.homeDirPath, host.sdkInt),
            host.lastInitParams,
        )
        assertEquals(Gson().toJson(host.storedSharedState.setupParams), host.lastSetupParams)
    }

    @Test
    fun `a core that rejects the configuration reports its own message`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.setupResult = Result.success("proxy group not found")
        val machine = host.createMachine()

        machine.handleStartAction()

        assertTrue(host.toasts.contains("proxy group not found"))
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a core setup that throws without a message falls back to the generic one`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.setupResult = Result.failure(RuntimeException("   "))
        val machine = host.createMachine()

        machine.handleStartAction()

        assertTrue(host.toasts.contains(INVALID_CONFIG_MESSAGE))
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a service that refuses the start after a good setup is reported`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.startResult = 0L
        val machine = host.createMachine()

        machine.handleStartAction()

        assertTrue(host.toasts.contains(START_FAILED_MESSAGE))
    }

    @Test
    fun `handleStopAction hands the stop to the tile when one is attached`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val tile = FakeTile()
        host.tile = tile

        machine.handleStopAction()

        assertEquals(1, tile.stopCount)
        assertEquals(0, host.stopCalls)
    }

    @Test
    fun `handleStopAction is a no-op while nothing is running`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        machine.handleStopAction()

        assertEquals(0, host.stopCalls)
        assertTrue(host.toasts.isEmpty())
    }

    @Test
    fun `handleStopAction announces itself before stopping`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState().copy(stopTip = "Stopping..."))
        machine.requestStart().await()

        machine.handleStopAction()

        assertEquals("Stopping...", host.toasts.last())
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `handleToggleAction starts when stopped and stops when started`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        machine.handleToggleAction()
        assertEquals(1, host.startCalls)

        machine.handleToggleAction()
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `a revoke is ignored while no vpn service is active`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.vpnServiceActive = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        machine.handleVpnRevokeAction()

        assertEquals(0, host.stopCalls)
    }

    @Test
    fun `a revoke stops the active vpn service`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val requestId = machine.captureRequestToken().id
        val identity = RequestServiceIdentity("synthetic-vpn", requestId)
        val protection = object : RequestProtection {
            override val requestIdentity = identity
            override fun protectRequestSocket(fd: Int, expected: RequestServiceIdentity) = true
            override fun isRequestLockdownEnabled() = false
        }
        assertTrue(machine.bindService(identity.serviceId, requestId))
        val generation = machine.observeProtection(protection, identity, "starting", "none")
        machine.observeProtection(protection, identity.copy(generation = generation), "ready", "none")
        machine.observeProtection(protection, identity.copy(generation = generation), "retiring", "vpnRevoked")
        machine.handleVpnRevokeAction()
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `syncSharedState updates style and keeps an unverified desired name inactive`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()

        machine.syncSharedState(
            SharedState(
                currentProfileName = "Work",
                stopText = "Disconnect",
                onlyStatisticsProxy = true,
            ),
        )

        assertEquals(listOf(NotificationParams("No active configuration", "Disconnect", true)), host.notificationParams)
    }

    @Test
    fun `a start that a stop overtakes never announces STARTED`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        val states = mutableListOf<RunState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            machine.runState.toList(states)
        }
        host.beforeStartService = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
        testScheduler.runCurrent()

        assertFalse(states.contains(RunState.STARTED))
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(0L, host.runTimeMillis)
    }

    @Test
    fun `a start rolled back after the service came up stops it again`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        host.beforeStartService = {
            host.app = FakeApp(vpnGranted = false)
            machine.requestStart()
        }

        assertFalse(machine.requestStart().await())
        testScheduler.runCurrent()

        assertEquals(1, host.stopCalls)
        assertEquals(0L, host.runTimeMillis)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertFalse(machine.captureRequestToken().running)
    }

    @Test
    fun `a start that overtakes another inside the binding window prepares a new owned service`() =
        runTest {
            val host = ConfigServiceTestHost(backgroundScope)
            val machine = host.createMachine()
            machine.syncSharedState(configuredState())
            host.beforeStartService = {
                host.beforeStartService = null
                machine.requestStart()
            }

            machine.requestStart().await()
            testScheduler.runCurrent()

            assertEquals(2, host.startCalls)
            assertEquals(1, host.stopCalls)
            assertEquals(RunState.STARTED, machine.runState.value)
            assertTrue(machine.captureRequestToken().running)
        }

    @Test
    fun `a start rebinds when the running service is not the one the options ask for`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.vpnServiceActive = false
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        host.beforeStartService = {
            host.beforeStartService = null
            machine.requestStart()
        }

        machine.requestStart().await()
        testScheduler.runCurrent()

        assertEquals(2, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a stop releases a start that is waiting on the vpn consent`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())

        val start = machine.requestStart()
        testScheduler.runCurrent()
        assertEquals(0, host.startCalls)

        assertTrue(machine.requestStop().await())
        assertFalse(start.await())
        assertEquals(0, host.startCalls)
        assertEquals(1, app.cancelledPreparations)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start request that throws is logged and rolled back`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(configuredState())
        host.beforeStartService = { throw IllegalStateException("binder died") }

        assertFalse(machine.requestStart().await())
        assertTrue(host.logs.any { it.contains("binder died") })
        assertFalse(machine.captureRequestToken().running)
    }
    @Test
    fun `network source gaps reordering and reconstruction reach the real socket gate`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        var activeEpoch = "first"
        val machine = ServiceStateMachine(object : ServiceStateHost by host {
            override fun isNetworkSourceCurrent(epoch: String) = epoch == activeEpoch
        })
        machine.initializeRequestState(machine.getRequestState().revision, false)
        var selected = RequestNetworkFacts()
        var bindings = 0
        val access = object : RequestSocketAccess {
            override val selection get() = selected
            override fun currentState() = machine.getRequestState()
            override fun networkInput() = machine.getNetworkInput()
            override fun isSelectionCurrent() = true
            override fun ownsDefaultVpn() = false
            override fun protect(fd: Int, expected: ApplicationRequestState) = false
            override fun bind(fd: Int) { bindings++ }
        }
        for (revision in listOf(1L, 3L, 2L, 4L)) {
            val facts = RequestNetworkFacts(activeEpoch, revision, "nonVpn", "physical", "physical", true)
            if (revision > selected.revision) selected = facts
            machine.observeNetwork(facts)
            assertEquals(selected.revision, machine.getRequestState().networkRevision)
            assertTrue(prepareRequestSocket(access, machine.getRequestState(), 42))
        }
        val prior = machine.getRequestState()
        activeEpoch = "second"
        selected = RequestNetworkFacts(activeEpoch, 1, "nonVpn", "new physical", "new physical", true)
        machine.observeNetwork(selected)
        assertTrue(machine.getRequestState().revision > prior.revision)
        assertEquals(1L, machine.getRequestState().networkRevision)
        machine.observeNetwork(RequestNetworkFacts("first", 99, "unknown"))
        assertEquals("second", machine.getRequestState().networkSourceEpoch)
        assertTrue(prepareRequestSocket(access, machine.getRequestState(), 42))
        assertFalse(prepareRequestSocket(access, prior, 42))
        assertEquals(5, bindings)
    }

}
