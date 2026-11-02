package com.follow.clash

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ServicePauseStateMachineTest {
    @Test
    fun `pause preserves current intent and waits for actual service cleanup`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val pause = machine.preparePauseIntent(true)
        assertTrue(pause.intentRunning)
        assertTrue(pause.paused)
        assertEquals("stopping", pause.phase)
        assertEquals(pause, host.requestPublications.last())
        host.stopGate = CompletableDeferred()
        host.stopEntered = CompletableDeferred()
        val pending = machine.requestStop(pause.intentRevision)
        host.stopEntered!!.await()
        assertEquals("stopping", machine.getRequestState().phase)
        assertNotNull(host.ownedService())
        host.stopGate!!.complete(Unit)
        assertTrue(pending.await())
        val stopped = machine.getRequestState()
        assertEquals("stopped", stopped.phase)
        assertTrue(stopped.intentRunning)
        assertTrue(stopped.paused)
        assertEquals("", stopped.serviceId)
        assertEquals("none", stopped.protectPhase)
        val resume = machine.preparePauseIntent(false)
        assertTrue(machine.requestStart(resume.intentRevision).await())
        assertEquals(2, host.startCalls)
    }

    @Test
    fun `manual stop before pause is not revived by an old running observation`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val observed = machine.getRequestState()
        val stop = machine.prepareRunIntent(false)
        assertTrue(machine.requestStop(stop).await())
        val pause = machine.preparePauseIntent(false)
        assertTrue(observed.intentRunning)
        assertFalse(pause.intentRunning)
        assertTrue(machine.requestStop(pause.intentRevision).await())
        assertEquals(1, host.startCalls)
        assertEquals("stopped", machine.getRequestState().phase)
    }

    @Test
    fun `unconfirmed pause cleanup stays failed rather than suspended`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        host.stopFailure = true
        val pause = machine.preparePauseIntent(true)
        assertFalse(machine.requestStop(pause.intentRevision).await())
        assertEquals("failed", machine.getRequestState().phase)
        assertFalse(machine.getRequestState().intentRunning)
        assertNotNull(host.ownedService())
        assertTrue(host.runTimeMillis != 0L)
    }

    @Test
    fun `late pause cleanup failure cannot clear a newer start intent`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        host.stopFailure = true
        host.stopEntered = CompletableDeferred()
        host.stopGate = CompletableDeferred()
        val pause = machine.preparePauseIntent(true)
        val cleanup = machine.requestStop(pause.intentRevision)
        host.stopEntered!!.await()
        val next = machine.prepareRunIntent(true, paused = false)
        host.stopGate!!.complete(Unit)
        assertFalse(cleanup.await())
        assertEquals(next, machine.getRequestState().intentRevision)
        assertTrue(machine.getRequestState().intentRunning)
        assertEquals("preparing", machine.getRequestState().phase)
    }

    @Test
    fun `publication failure does not return a dispatchable pause id`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        host.publishAccepted = false
        assertThrows(IllegalStateException::class.java) { machine.preparePauseIntent(true) }
        assertEquals("failed", machine.getRequestState().phase)
        assertFalse(machine.getRequestState().intentRunning)
        assertTrue(host.blockedRequests > 0)
    }

    @Test
    fun `exit and service loss cannot leave a resumable pause intent`() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = host.createMachine()
        assertTrue(machine.requestStart().await())
        val identity = requireNotNull(host.ownedService())
        machine.observeServiceLost(identity.serviceId, identity.requestId)
        assertFalse(machine.getRequestState().intentRunning)
        assertFalse(machine.preparePauseIntent(false).intentRunning)
        machine.prepareRunIntent(false, "exit")
        val exiting = machine.getRequestState()
        assertThrows(IllegalStateException::class.java) { machine.preparePauseIntent(true) }
        assertEquals(exiting, machine.getRequestState())
    }
}
