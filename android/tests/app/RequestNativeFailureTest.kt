package com.follow.clash

import android.app.Application
import android.content.Intent
import android.content.ServiceConnection
import android.os.ParcelFileDescriptor
import com.follow.clash.common.*
import com.follow.clash.core.Core
import com.follow.clash.core.RequestSocketInterface
import com.follow.clash.core.TunInterface
import com.follow.clash.service.VpnService
import com.follow.clash.service.models.AccessControlProps
import com.follow.clash.service.models.VpnOptions
import com.google.gson.JsonObject
import java.io.FileDescriptor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowLog
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.RealObject
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(application = RequestNativeTestApplication::class, sdk = [31], shadows = [RequestControlCoreShadow::class, NativeFailureBuilderShadow::class, NativeFailureDescriptorShadow::class, RequestNativeServiceStateShadow::class])
@OptIn(ExperimentalCoroutinesApi::class)
class RequestNativeFailureTest {
    private val old = RequestServiceIdentity("owned-service", 1, 1)
    private val phases = mutableListOf<String>()
    private var rejectReady = false
    private var vpnStartRequest = 0L
    private var previousBinding: Any? = null
    private var previousRuntime = 0L
    private var testMainInstalled = false
    private val moduleScopes = mutableListOf<CoroutineScope>()
    private val ownedStops = mutableListOf<RequestServiceIdentity>()
    private var systemSettled = CompletableDeferred<ApplicationRequestState>()

    @Before fun prepare() {
        GlobalState.init(RuntimeEnvironment.getApplication())
        previousBinding = ReflectionHelpers.getStaticField(ServiceController::class.java, "binding")
        previousRuntime = ServiceController.getRunTimeMillis()
        RequestControlCoreShadow.reset()
        RequestObservations.handler = object : RequestObservationHandler {
            override fun onNetworkChanged(facts: RequestNetworkFacts) {}
            override fun onProtectionChanged(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String): Long {
                phases += phase
                return if (phase == "starting") 2 else if (phase == "ready" && rejectReady) 0 else identity.generation
            }
            override fun onServiceLost(serviceId: String, requestId: Long) {}
            override fun onVpnStartRequested(serviceId: String): Long = vpnStartRequest
        }
    }

    @After fun finish() {
        RequestObservations.handler = null
        ReflectionHelpers.setStaticField(ServiceController::class.java, "binding", previousBinding)
        ReflectionHelpers.setStaticField(ServiceController::class.java, "runTimeMillis", previousRuntime)
        RequestNativeServiceStateShadow.machine = null
        moduleScopes.forEach { it.cancel() }
        if (testMainInstalled) Dispatchers.resetMain()
    }

    private fun service(): VpnService = Robolectric.buildService(VpnService::class.java).create().get().also {
        ReflectionHelpers.setField(it, "requestIdentity", old)
        ReflectionHelpers.setField(it, "tunIdentity", old)
        ReflectionHelpers.setField(it, "tunRunning", true)
    }

    private fun identity(service: VpnService): RequestServiceIdentity? = ReflectionHelpers.getField(service, "tunIdentity")

    @Test fun socketRegistrationFailureDoesNotEscapeApplicationBinding() {
        RequestControlCoreShadow.registrationFailure = true
        ServiceState.bindRequestObservers()
        assertEquals(1, RequestControlCoreShadow.registrations)
        assertNotNull(RequestObservations.handler)
    }

    @Test fun failedNativeAdoptionRetainsOldIdentityAndNeverPublishesReady() {
        val service = service()
        RequestControlCoreShadow.adoptFailure = true
        val error = runCatching { service.attachRequest(9) }.exceptionOrNull()
        assertEquals("request_restart_required", error?.message)
        assertEquals(old, identity(service))
        assertEquals(old, service.requestIdentity)
        assertEquals(listOf("starting"), phases)
        assertTrue(RequestControlCoreShadow.stops.isEmpty())
    }

    @Test fun systemStartIntentDoesNotRelabelAnExistingNativeOwner() {
        val service = service()
        vpnStartRequest = 9
        service.onStartCommand(Intent(), 0, 1)
        assertEquals(old, service.requestIdentity)
        assertEquals(old, identity(service))
        assertTrue(service.stopOwned(old))
    }

    @Test fun coldSystemStartLeavesIdentityPublicationToControllerAttachment() {
        val service = service()
        val initial = old.copy(requestId = 0, generation = 0)
        ReflectionHelpers.setField(service, "requestIdentity", initial)
        ReflectionHelpers.setField(service, "tunIdentity", null)
        ReflectionHelpers.setField(service, "tunRunning", false)
        vpnStartRequest = 9
        service.onStartCommand(Intent(), 0, 1)
        assertEquals(initial, service.requestIdentity)
        service.attachRequest(9)
        assertEquals(initial.copy(requestId = 9), service.requestIdentity)
        assertTrue(RequestControlCoreShadow.stops.isEmpty())
    }

    @Test fun adoptionPublishesOnlyAfterNativeConfirmation() {
        val service = service()
        RequestControlCoreShadow.beforeAdopt = { assertEquals(old, identity(service)) }
        service.attachRequest(9)
        assertEquals(old.copy(requestId = 9, generation = 2), identity(service))
        assertEquals(listOf("starting", "ready"), phases)
    }

    @Test fun supersededAdoptionCleanupFailureKeepsIdentityAndOriginalError() {
        val service = service()
        rejectReady = true
        RequestControlCoreShadow.stopFailure = true
        val error = runCatching { service.attachRequest(9) }.exceptionOrNull()
        assertEquals("Service request was superseded", error?.message)
        val adopted = old.copy(requestId = 9, generation = 2)
        assertEquals(adopted, identity(service))
        assertEquals(listOf("owned-service" to 2L), RequestControlCoreShadow.stops)
        assertEquals(listOf("starting", "ready", "retiring"), phases)
    }

    @Test fun stoppedOrAlreadyUnownedIdentityCanRetireWithoutTouchingAnotherOwner() {
        for (result in listOf(true, false)) {
            phases.clear()
            val service = service()
            RequestControlCoreShadow.stopResult = result
            service.stop()
            assertNull(identity(service))
            assertEquals(listOf("retiring", "none"), phases)
            assertEquals("owned-service" to 1L, RequestControlCoreShadow.stops.last())
        }
    }

    @Test fun stopFailureDoesNotEscapeDestroyOrReportNone() {
        val service = service()
        RequestControlCoreShadow.stopFailure = true
        service.onDestroy()
        assertEquals(old, identity(service))
        assertEquals(listOf("retiring"), phases)
    }

    @Test fun stopFailureDoesNotEscapeRevokeOrReportNone() {
        val service = service()
        RequestControlCoreShadow.stopFailure = true
        service.onRevoke()
        assertEquals(old, identity(service))
        assertFalse(phases.contains("none"))
    }

    @Test fun startCatchKeepsOriginalErrorWhenNativeCleanupFails() {
        val service = service()
        ReflectionHelpers.setField(service, "tunIdentity", null)
        ReflectionHelpers.setField(service, "tunRunning", false)
        RequestControlCoreShadow.stopFailure = true
        val options = VpnOptions(true, 7890, false, true,
            AccessControlProps(false, AccessControlMode.REJECT_SELECTED, emptyList(), emptyList()),
            false, false, emptyList(), "mixed", listOf("0.0.0.0/0"))
        val method = VpnService::class.java.getDeclaredMethod("handleStart", VpnOptions::class.java).apply { isAccessible = true }
        val error = runCatching { method.invoke(service, options) }.exceptionOrNull()?.cause
        assertEquals("Core rejected the tun file descriptor", error?.message)
        assertEquals(old.copy(generation = 2), identity(service))
        assertEquals(listOf("starting", "retiring"), phases)
        assertEquals(listOf("owned-service" to 2L), RequestControlCoreShadow.stops)
    }

    private fun binding(service: VpnService, runtime: Long = 123L): Any {
        val app = RuntimeEnvironment.getApplication()
        val intent = Intent(app, VpnService::class.java)
        val type = Class.forName("com.follow.clash.ManagedServiceBinding")
        val instance = type.declaredConstructors.single().apply { isAccessible = true }
            .newInstance(intent, service.requestIdentity.requestId, { _: String, _: RequestServiceIdentity? -> })
        ReflectionHelpers.setField(instance, "requestIdentity", service.requestIdentity)
        (instance as ServiceConnection).onServiceConnected(intent.component, service.onBind(intent))
        ReflectionHelpers.setStaticField(ServiceController::class.java, "binding", instance)
        ReflectionHelpers.setStaticField(ServiceController::class.java, "runTimeMillis", runtime)
        return instance
    }

    private fun machine(scope: CoroutineScope, service: VpnService): ServiceStateMachine {
        val base = ConfigServiceTestHost(scope)
        val machine = base.createMachine(object : ServiceStateHost by base {
            override suspend fun stopOwnedService(identity: RequestServiceIdentity): Boolean = ServiceController.stopOwned(identity)
        })
        RequestNativeServiceStateShadow.machine = machine
        RequestObservations.handler = object : RequestObservationHandler {
            override fun onNetworkChanged(facts: RequestNetworkFacts) = machine.observeNetwork(facts)
            override fun onProtectionChanged(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String): Long =
                machine.observeProtection(service, identity, phase, reason)
            override fun onServiceLost(serviceId: String, requestId: Long) = machine.observeServiceLost(serviceId, requestId)
            override fun onVpnStartRequested(serviceId: String): Long = 0
        }
        val request = machine.prepareRunIntent(true)
        assertEquals(old.requestId, request)
        assertTrue(machine.bindService(old.serviceId, request))
        assertEquals(1L, machine.observeProtection(service, old.copy(generation = 0), "starting", "none"))
        assertEquals(1L, machine.observeProtection(service, old, "ready", "none"))
        return machine
    }

    @Test fun ownedCleanupFailureReachesControllerAndMachine() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        val binding = binding(service)
        RequestControlCoreShadow.stopFailure = true
        val result = machine.failRunIntent(old.requestId, machine.configOperationToken(), abort = false)
        assertEquals("cleanupFailed", result.status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertEquals(123L, ServiceController.getRunTimeMillis())
        assertEquals(old, identity(service))
        assertFalse(ServiceController.stopOwned(old))
        RequestControlCoreShadow.stopFailure = false
        assertTrue(ServiceController.stopOwned(old))
        assertEquals(0L, ServiceController.getRunTimeMillis())
    }

    @Test fun programmaticStopFailureRetainsBindingAndDoesNotRequestSystemDestruction() = runTest {
        val service = service()
        val binding = binding(service)
        RequestControlCoreShadow.stopFailure = true
        assertTrue(runCatching { ServiceController.stop() }.isFailure)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertEquals(123L, ServiceController.getRunTimeMillis())
        assertEquals(0, (RuntimeEnvironment.getApplication() as RequestNativeTestApplication).stopRequests)
        RequestControlCoreShadow.stopFailure = false
        ServiceController.stop()
        assertNull(ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertEquals(0L, ServiceController.getRunTimeMillis())
    }

    @Test fun destroyedServiceCannotReportRetainedOwnerCleaned() = runTest {
        val service = service()
        val binding = binding(service)
        RequestControlCoreShadow.stopFailure = true
        service.onDestroy()
        assertFalse(ServiceController.stopOwned(old))
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        RequestControlCoreShadow.stopFailure = false
        assertTrue(ServiceController.stopOwned(old))
        assertNull(identity(service))
    }

    @Test fun failedControllerAdoptionKeepsOldOwnerAvailableForStrictCleanup() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        val binding = binding(service)
        val request = machine.prepareRunIntent(true)
        RequestControlCoreShadow.adoptFailure = true
        assertEquals("request_restart_required", runCatching { ServiceController.adoptRequest(request) }.exceptionOrNull()?.message)
        assertEquals(old, service.requestIdentity)
        assertEquals(old, identity(service))
        assertEquals(old, ReflectionHelpers.getField<RequestServiceIdentity>(binding, "requestIdentity"))
        assertEquals("cleanupFailed", machine.failRunIntent(request, machine.configOperationToken(), abort = false).status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertTrue(ServiceController.stopOwned(old))
        assertEquals(listOf(old.serviceId to old.generation), RequestControlCoreShadow.stops)
    }

    @Test fun delayedOldCleanupCannotClearSuccessfulNewAdoption() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        val binding = binding(service)
        val request = machine.prepareRunIntent(true)
        ServiceController.adoptRequest(request)
        val next = old.copy(requestId = request, generation = 2)
        assertEquals(next, service.requestIdentity)
        assertEquals(next, ReflectionHelpers.getField<RequestServiceIdentity>(binding, "requestIdentity"))
        assertFalse(ServiceController.stopOwned(old))
        assertTrue(RequestControlCoreShadow.stops.isEmpty())
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertTrue(ServiceController.stopOwned(next))
    }

    @Test fun confirmedAdoptionDestroyedBeforePublicationRetainsItsActualOwner() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        val binding = binding(service)
        val request = machine.prepareRunIntent(true)
        RequestControlCoreShadow.beforeAdopt = { ReflectionHelpers.setField(service, "destroyed", true) }
        RequestControlCoreShadow.stopFailure = true
        assertEquals("Service instance changed", runCatching { ServiceController.adoptRequest(request) }.exceptionOrNull()?.message)
        val retained = old.copy(requestId = request, generation = 2)
        assertEquals(retained, service.requestIdentity)
        assertEquals(retained, identity(service))
        assertEquals(retained, ReflectionHelpers.getField<RequestServiceIdentity>(binding, "requestIdentity"))
        assertEquals("cleanupFailed", machine.failRunIntent(request, machine.configOperationToken(), abort = false).status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertFalse(ServiceController.stopOwned(old))
        RequestControlCoreShadow.stopFailure = false
        assertTrue(ServiceController.stopOwned(retained))
    }

    @Test fun failedStartPublishesRetainedIdentityToRealBinding() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        ReflectionHelpers.setField(service, "tunIdentity", null)
        ReflectionHelpers.setField(service, "tunRunning", false)
        ReflectionHelpers.setField(service, "requestIdentity", old.copy(generation = 0))
        val binding = binding(service, runtime = 0)
        val modules = ReflectionHelpers.getField<Any>(service, "modules")
        ReflectionHelpers.setField(modules, "scope", CoroutineScope(SupervisorJob()))
        RequestControlCoreShadow.stopFailure = true
        val options = VpnOptions(true, 7890, false, true,
            AccessControlProps(false, AccessControlMode.REJECT_SELECTED, emptyList(), emptyList()),
            false, false, emptyList(), "mixed", listOf("0.0.0.0/0"))
        assertEquals(0L, ServiceController.start(options, old.requestId))
        assertTrue(ShadowLog.getLogsForTag("FlClash").any { it.msg.contains("Unable to start background service: java.lang.IllegalStateException: Core rejected the tun file descriptor") })
        val retained = service.requestIdentity
        assertEquals(2L, retained.generation)
        assertEquals(retained, identity(service))
        assertEquals(retained, ReflectionHelpers.getField<RequestServiceIdentity>(binding, "requestIdentity"))
        assertEquals("cleanupFailed", machine.failRunIntent(old.requestId, machine.configOperationToken(), abort = false).status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        RequestControlCoreShadow.stopFailure = false
        assertTrue(ServiceController.stopOwned(retained))
    }

    @Test fun existingOwnerMustBeCleanedBeforeStartingAReplacement() = runTest {
        val service = service()
        val machine = machine(backgroundScope, service)
        val binding = binding(service)
        RequestControlCoreShadow.stopFailure = true
        val options = VpnOptions(true, 7890, false, true,
            AccessControlProps(false, AccessControlMode.REJECT_SELECTED, emptyList(), emptyList()),
            false, false, emptyList(), "mixed", listOf("0.0.0.0/0"))
        assertEquals(0L, ServiceController.start(options, old.requestId))
        assertEquals(0, RequestControlCoreShadow.starts)
        assertEquals(old.copy(generation = 2), identity(service))
        assertEquals(identity(service), service.requestIdentity)
        assertEquals(service.requestIdentity, ReflectionHelpers.getField<RequestServiceIdentity>(binding, "requestIdentity"))
        assertEquals("cleanupFailed", machine.failRunIntent(old.requestId, machine.configOperationToken(), abort = false).status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        RequestControlCoreShadow.stopFailure = false
        assertTrue(ServiceController.stopOwned(service.requestIdentity))
    }

    private fun coldService(): VpnService = Robolectric.buildService(VpnService::class.java).create().get().also {
        // Notification/network observers are system leaves, outside the ownership transition.
        val scope = CoroutineScope(SupervisorJob()).also { moduleScopes += it }
        ReflectionHelpers.setField(ReflectionHelpers.getField<Any>(it, "modules"), "scope", scope)
    }

    private fun systemMachine(scope: CoroutineScope, firstService: VpnService): Pair<ServiceStateMachine, ConfigServiceTestHost> {
        val app = RuntimeEnvironment.getApplication() as RequestNativeTestApplication
        var firstBind = true
        app.serviceToBind = { if (firstBind) firstService.also { firstBind = false } else coldService() }
        ReflectionHelpers.setStaticField(ServiceController::class.java, "binding", null)
        ReflectionHelpers.setStaticField(ServiceController::class.java, "runTimeMillis", 0L)
        RequestControlCoreShadow.startResult = true
        val base = ConfigServiceTestHost(scope)
        val machine = base.createMachine(object : ServiceStateHost by base {
            override val runTimeMillis: Long get() = ServiceController.getRunTimeMillis()
            override suspend fun isVpnServiceActive(): Boolean = ServiceController.isVpnServiceActive()
            override suspend fun startService(options: VpnOptions, requestId: Long): Long = ServiceController.start(options, requestId)
            override suspend fun stopService() = ServiceController.stop()
            override suspend fun stopOwnedService(identity: RequestServiceIdentity): Boolean {
                ownedStops += identity
                return ServiceController.stopOwned(identity)
            }
            override fun publishRequestState(state: ApplicationRequestState): Boolean {
                if (state.source == "alwaysOn" && state.phase in setOf("started", "failed")) systemSettled.complete(state)
                return base.publishRequestState(state)
            }
        })
        RequestNativeServiceStateShadow.machine = machine
        RequestObservations.handler = object : RequestObservationHandler {
            override fun onNetworkChanged(facts: RequestNetworkFacts) = machine.observeNetwork(facts)
            override fun onProtectionChanged(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String): Long =
                machine.observeProtection(service, identity, phase, reason)
            override fun onServiceLost(serviceId: String, requestId: Long) = machine.observeServiceLost(serviceId, requestId)
            override fun onVpnStartRequested(serviceId: String): Long = machine.handleVpnStartRequest()
        }
        return machine to base
    }

    private suspend fun verifySystemReplacement(machine: ServiceStateMachine, service: VpnService) {
        val previous = service.requestIdentity
        service.onStartCommand(Intent(), 0, 1)
        val ownerWhileQueued = ReflectionHelpers.getField<Long>(machine, "serviceRequestId")
        val result = systemSettled.await()
        assertEquals("started", result.phase)
        assertEquals(listOf(previous), ownedStops)
        assertEquals(previous.requestId, ownerWhileQueued)
        val next = requireNotNull(machine.getProtection()).second
        assertEquals(result.intentRevision, next.requestId)
        assertNotEquals(previous.serviceId, next.serviceId)
        assertEquals(2, RequestControlCoreShadow.starts)
        assertFalse(ServiceController.stopOwned(previous))
        val stops = RequestControlCoreShadow.stops.toList()
        service.onDestroy()
        assertEquals(next, requireNotNull(machine.getProtection()).second)
        assertEquals(stops, RequestControlCoreShadow.stops)
        assertTrue(ServiceController.stopOwned(next))
    }

    private suspend fun startForSystemTest(machine: ServiceStateMachine) {
        val started = machine.requestStart().await()
        assertTrue(ShadowLog.getLogsForTag("FlClash").joinToString { it.msg }, started)
    }

    @Test fun systemStartReplacesExistingOwnerThroughActualConfigAndController() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler)); testMainInstalled = true
        val service = coldService()
        val (machine, host) = systemMachine(backgroundScope, service)
        startForSystemTest(machine)
        host.storedSharedState = host.storedSharedState.copy(vpnOptions = host.storedSharedState.vpnOptions!!.copy(stack = "mixed"))
        machine.syncSharedState(host.storedSharedState)
        verifySystemReplacement(machine, service)
    }

    @Test fun systemStartWithSameOptionsCannotBorrowOldOwnersCompatibility() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler)); testMainInstalled = true
        val service = coldService()
        val (machine, _) = systemMachine(backgroundScope, service)
        startForSystemTest(machine)
        verifySystemReplacement(machine, service)
    }

    @Test fun coldSystemStartBindsThroughActualController() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler)); testMainInstalled = true
        val service = coldService()
        val (machine, _) = systemMachine(backgroundScope, service)
        service.onStartCommand(Intent(), 0, 1)
        val settled = systemSettled.await()
        assertEquals(ShadowLog.getLogsForTag("FlClash").joinToString { it.msg }, "started", settled.phase)
        val next = requireNotNull(machine.getProtection()).second
        assertEquals(machine.getRequestState().intentRevision, next.requestId)
        assertEquals(next, service.requestIdentity)
        assertTrue(ownedStops.isEmpty())
        assertEquals(1, RequestControlCoreShadow.starts)
        assertTrue(ServiceController.stopOwned(next))
    }

    @Test fun compatibleConfigForSameIntentKeepsActualOwnerAndBinding() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler)); testMainInstalled = true
        val service = coldService()
        val (machine, _) = systemMachine(backgroundScope, service)
        startForSystemTest(machine)
        val previous = service.requestIdentity
        val binding = ReflectionHelpers.getStaticField<Any>(ServiceController::class.java, "binding")
        val result = machine.applyConfig(JsonObject().apply {
            addProperty("inputId", "b".repeat(64)); addProperty("requestId", previous.requestId); addProperty("active", true)
        }).await()
        assertEquals("activated", result.status)
        assertSame(binding, ReflectionHelpers.getStaticField(ServiceController::class.java, "binding"))
        assertEquals(previous, service.requestIdentity)
        assertTrue(ownedStops.isEmpty())
        assertEquals(1, RequestControlCoreShadow.starts)
        assertTrue(ServiceController.stopOwned(previous))
    }

    @Test fun supersededSystemStartCannotClaimTheNewerIntentsService() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler)); testMainInstalled = true
        val service = coldService()
        val (machine, host) = systemMachine(backgroundScope, service)
        startForSystemTest(machine)
        val previous = service.requestIdentity
        host.heldPhase = "prepareConfig"
        val gate = CompletableDeferred<Unit>().also { host.phaseGate = it }
        val entered = CompletableDeferred<Unit>().also { host.phaseEntered = it }
        service.onStartCommand(Intent(), 0, 1)
        val systemIntent = machine.getRequestState().intentRevision
        entered.await()
        assertEquals(previous.requestId, ReflectionHelpers.getField<Long>(machine, "serviceRequestId"))
        val newer = machine.prepareRunIntent(true)
        assertTrue(newer > systemIntent)
        val started = machine.requestStart(newer)
        gate.complete(Unit)
        assertTrue(started.await())
        val next = requireNotNull(machine.getProtection()).second
        assertEquals(newer, next.requestId)
        assertEquals(newer, machine.getRequestState().intentRevision)
        assertEquals(listOf(previous), ownedStops)
        assertEquals(2, RequestControlCoreShadow.starts)
        assertFalse(ServiceController.stopOwned(previous))
        service.onDestroy()
        assertEquals(next, requireNotNull(machine.getProtection()).second)
        assertTrue(ServiceController.stopOwned(next))
    }
}

class RequestNativeTestApplication : Application() {
    var stopRequests = 0
    var serviceToBind: (() -> VpnService)? = null
    override fun bindService(intent: Intent, connection: ServiceConnection, flags: Int): Boolean {
        val service = serviceToBind?.invoke() ?: return super.bindService(intent, connection, flags)
        connection.onServiceConnected(intent.component, service.onBind(intent))
        return true
    }
    override fun unbindService(connection: ServiceConnection) {
        if (serviceToBind == null) super.unbindService(connection)
    }
    override fun stopService(service: Intent): Boolean { stopRequests++; return true }
}

@Implements(ServiceState::class)
class RequestNativeServiceStateShadow {
    @Implementation fun bindService(serviceId: String, requestId: Long): Boolean = requireNotNull(machine).bindService(serviceId, requestId)
    companion object { internal var machine: ServiceStateMachine? = null }
}

@Implements(android.net.VpnService.Builder::class)
class NativeFailureBuilderShadow {
    @RealObject private lateinit var builder: android.net.VpnService.Builder
    @Implementation fun addAddress(address: String, prefixLength: Int): android.net.VpnService.Builder = builder
    @Implementation fun addRoute(address: String, prefixLength: Int): android.net.VpnService.Builder = builder
    @Implementation fun addDnsServer(server: String): android.net.VpnService.Builder = builder
    @Implementation fun establish(): ParcelFileDescriptor = ReflectionHelpers.callConstructor(
        ParcelFileDescriptor::class.java, ReflectionHelpers.ClassParameter.from(FileDescriptor::class.java, FileDescriptor()))
}

@Implements(ParcelFileDescriptor::class)
class NativeFailureDescriptorShadow {
    @Implementation fun __constructor__(fd: FileDescriptor) {}
    @Implementation fun detachFd(): Int = 42
}
