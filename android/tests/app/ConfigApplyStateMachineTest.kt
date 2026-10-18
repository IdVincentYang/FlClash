package com.follow.clash

import com.follow.clash.common.RequestServiceIdentity
import com.follow.clash.models.ServiceCoreParams
import com.google.gson.JsonParser
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ConfigApplyStateMachineTest {
    @Test
    fun `conditional build failure retires only its own service and keeps retained input`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val failure = JsonParser.parseString("""{"expected":${com.google.gson.Gson().toJson(host.lastConfigFact)}}""").asJsonObject
        assertEquals("retained",machine.failConfigBuild(failure).status)
        assertEquals(0,host.stopCalls)
        host.buildFailureStatus = "blocked"
        assertEquals("blocked",machine.failConfigBuild(failure).status)
        assertEquals(1,host.stopCalls)
        assertEquals("failed",machine.getRequestState().phase)
    }

    @Test
    fun `late conditional failure cannot stop a newly applied service`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val failure = JsonParser.parseString("""{"expected":${com.google.gson.Gson().toJson(host.lastConfigFact)}}""").asJsonObject
        host.buildFailureGate = CompletableDeferred()
        host.buildFailureStatus = "blocked"
        val pending = async { machine.failConfigBuild(failure) }
        host.buildFailureEntered.await()
        val next = machine.prepareRunIntent(true)
        assertEquals("activated",machine.applyConfig(input(next)).await().status)
        val stops = host.stopCalls
        host.buildFailureGate!!.complete(Unit)
        assertEquals("superseded",pending.await().status)
        assertEquals(stops,host.stopCalls)
        assertEquals("started",machine.getRequestState().phase)
    }
    @Test
    fun `observed failure cannot adopt an intent that arrived before its call`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val failure = com.google.gson.JsonObject().apply {
            add("expected", com.google.gson.Gson().toJsonTree(host.lastConfigFact))
            add("expectedRun", com.google.gson.Gson().toJsonTree(machine.getRequestState()))
            addProperty("registeredToken", machine.configOperationToken())
        }
        host.buildFailureStatus = "blocked"
        val next = machine.prepareRunIntent(true)
        val stops = host.stopCalls
        assertEquals("superseded", machine.failConfigBuild(failure).status)
        assertFalse(host.buildFailureEntered.isCompleted)
        assertEquals(stops, host.stopCalls)
        assertEquals(next, machine.getRequestState().intentRevision)
        assertEquals("activated", machine.applyConfig(input(next)).await().status)
    }

    @Test
    fun `observed failure cannot adopt a newer registered token before its call`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val failure = com.google.gson.JsonObject().apply {
            add("expected", com.google.gson.Gson().toJsonTree(host.lastConfigFact))
            add("expectedRun", com.google.gson.Gson().toJsonTree(machine.getRequestState()))
            addProperty("registeredToken", machine.configOperationToken())
        }
        host.buildFailureStatus = "blocked"
        host.heldPhase = "prepareConfig"
        host.phaseGate = CompletableDeferred()
        host.phaseEntered = CompletableDeferred()
        val pending = machine.applyConfig(input(machine.getRequestState().intentRevision))
        host.phaseEntered!!.await()
        val stops = host.stopCalls
        assertEquals("superseded", machine.failConfigBuild(failure).status)
        assertFalse(host.buildFailureEntered.isCompleted)
        assertEquals(stops, host.stopCalls)
        host.heldPhase = null
        host.phaseGate!!.complete(Unit)
        assertEquals("activated", pending.await().status)
    }

    private fun input(requestId: Long) = JsonParser.parseString(
        """{"inputId":"${"a".repeat(64)}","requestId":$requestId}""",
    ).asJsonObject

    @Test
    fun `phase completion alone refreshes actual notification and service loss clears it`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        host.storedSharedState = host.storedSharedState.copy(configApplyingTip="Applying",configInactiveTip="Idle")
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        assertEquals("Applied",host.notificationParams.last().title)
        val state = machine.getRequestState()
        machine.observeServiceLost(state.serviceId,state.intentRevision)
        assertEquals("Idle",host.notificationParams.last().title)
        assertEquals(0L,machine.refresh())
    }

    @Test
    fun `unreadable cold preferences converge and allow a later valid system start`() = runTest {
        for (throws in listOf(false,true)) {
            val host = ConfigServiceTestHost(backgroundScope)
            host.sharedStateUnavailable = !throws
            host.sharedStateReadFailure = if (throws) IllegalArgumentException("damaged preferences") else null
            val machine = host.createMachine()
            machine.handleStartAction()
            assertEquals("failed",machine.getRequestState().phase)
            assertFalse(machine.getRequestState().intentRunning)
            assertEquals(0L,machine.refresh())
            assertEquals(0,host.startCalls)
            assertTrue(host.toasts.isNotEmpty())
            host.sharedStateUnavailable=false
            host.sharedStateReadFailure=null
            machine.handleStartAction()
            assertEquals("started",machine.getRequestState().phase)
            assertEquals(1,host.startCalls)
        }
    }

    @Test
    fun `recoverable Geo install keeps prepared service until retry or explicit terminal cleanup`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        machine.syncSharedState(host.storedSharedState)
        val request = machine.prepareRunIntent(true)
        host.failingPhase = "installConfig"
        host.phaseFailureStatus = "bootstrapRequired"
        val waiting = machine.applyConfig(input(request)).await()
        assertEquals("bootstrapRequired",waiting.status)
        assertEquals(0,host.stopCalls)
        assertEquals("starting",machine.getRequestState().phase)
        host.failingPhase = null
        assertEquals("activated",machine.applyConfig(input(request)).await().status)
        assertEquals(1,host.startCalls)
        assertEquals(0,host.stopCalls)
        assertEquals("superseded",machine.failRunIntent(request,waiting.receipt.token).status)
        assertEquals("started",machine.getRequestState().phase)
    }

    @Test
    fun `terminal failure waits for owned cleanup and the new start prepares and activates again`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val first = machine.getRequestState().intentRevision
        host.cleanupGate = CompletableDeferred()
        val firstToken = machine.configOperationToken()
        val failing = async { machine.failRunIntent(first, firstToken) }
        host.cleanupEntered.await()
        assertFalse(failing.isCompleted)
        val next = machine.prepareRunIntent(true)
        val restarting = machine.applyConfig(input(next))
        testScheduler.runCurrent()
        assertFalse(restarting.isCompleted)
        assertEquals(1,host.startCalls)
        host.cleanupGate!!.complete(Unit)
        assertEquals("superseded",failing.await().status)
        assertEquals("activated",restarting.await().status)
        assertEquals(2,host.startCalls)
        assertEquals(1,host.stopCalls)
        assertEquals(RunState.STARTED,machine.runState.value)
        assertEquals(2,host.phaseCalls.count { it.first == "activateConfig" })
    }

    @Test
    fun `old cleanup cannot stop a service adopted under a new identity`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val first = machine.getRequestState().intentRevision
        host.cleanupGate = CompletableDeferred()
        val firstToken = machine.configOperationToken()
        val failing = async { machine.failRunIntent(first, firstToken) }
        host.cleanupEntered.await()
        val next = machine.prepareRunIntent(true)
        val replacement = RequestServiceIdentity("system-replacement",next,0)
        machine.bindService(replacement.serviceId,next)
        host.replaceOwnedService(replacement)
        host.cleanupGate!!.complete(Unit)
        assertEquals("superseded",failing.await().status)
        assertEquals(replacement,host.ownedService())
        assertEquals(0,host.stopCalls)
        assertEquals(next,machine.getRequestState().intentRevision)
        assertEquals("preparing",machine.getRequestState().phase)
    }

    @Test
    fun `prepared service uses actual Core port and authentication while preserving independent preferences`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val desired = host.storedSharedState
        host.storedSharedState = desired.copy(
            systemProxyRequested=true,
            vpnOptions=desired.vpnOptions!!.copy(port=9999,systemProxy=false,allowBypass=true),
        )
        host.coreParameters=ServiceCoreParams(mixedPort=7891,bindingId=41,localReachable=true)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        assertEquals(7891,host.lastStartOptions!!.port)
        assertTrue(host.lastStartOptions!!.systemProxy)
        assertTrue(host.lastStartOptions!!.allowBypass)
        host.coreParameters=ServiceCoreParams(mixedPort=7892,bindingId=42,localReachable=true,authenticationRequired=true)
        val request = machine.getRequestState().intentRevision
        assertEquals("activated",machine.applyConfig(input(request)).await().status)
        assertEquals(2,host.startCalls)
        assertEquals(1,host.stopCalls)
        assertEquals(7892,host.lastStartOptions!!.port)
        assertFalse(host.lastStartOptions!!.systemProxy)
        assertTrue(host.lastStartOptions!!.allowBypass)
    }

    @Test
    fun `desired name cannot replace the applied notification and installation failure removes active claims`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        machine.syncSharedState(host.storedSharedState.copy(currentProfileName="unapplied desired"))
        assertEquals("Applied",host.notificationParams.last().title)
        host.failingPhase="installConfig"
        val result = machine.applyConfig(input(machine.getRequestState().intentRevision)).await()
        assertEquals("blocked",result.status)
        assertEquals("No active configuration",host.notificationParams.last().title)
        assertEquals(0L,machine.refresh())
        assertEquals(1,host.stopCalls)
    }
}
