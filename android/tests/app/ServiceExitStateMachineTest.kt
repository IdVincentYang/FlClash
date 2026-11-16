package com.follow.clash

import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ServiceExitStateMachineTest {
    private lateinit var scope: CoroutineScope
    private lateinit var host: ConfigServiceTestHost
    private lateinit var machine: ServiceStateMachine
    private var startDispatches = 0
    private var stopDispatches = 0

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        host = ConfigServiceTestHost(scope)
        machine = host.createMachine()
        host.tile = object : TileGateway {
            override fun handleStart() { startDispatches++ }
            override fun handleStop() { stopDispatches++ }
        }
    }

    @After fun tearDown() { scope.cancel() }

    @Suppress("DEPRECATION")
    private fun waitForMonitor(worker: Thread, monitor: Any) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        // Android's compile classpath omits management APIs available in the host test JVM.
        val threads = Class.forName("java.lang.management.ManagementFactory")
            .getMethod("getThreadMXBean").invoke(null)
        val threadInfo = Class.forName("java.lang.management.ThreadMXBean")
            .getMethod("getThreadInfo", Long::class.javaPrimitiveType)
        val lockName = Class.forName("java.lang.management.ThreadInfo").getMethod("getLockName")
        val expectedLock = monitor.javaClass.name + "@" + Integer.toHexString(System.identityHashCode(monitor))
        while (System.nanoTime() < deadline) {
            val info = threadInfo.invoke(threads, worker.id)
            if (worker.state == Thread.State.BLOCKED && info != null &&
                lockName.invoke(info) == expectedLock) return
            if (!worker.isAlive) fail("Request ended before waiting for publicationLock")
            Thread.yield()
        }
        fail("Request did not wait for publicationLock")
    }

    private fun exitBeforeWaitingRequest(action: () -> Unit): Throwable? {
        val field = ServiceStateMachine::class.java.getDeclaredField("publicationLock")
        field.isAccessible = true
        val monitor = checkNotNull(field.get(machine))
        val error = AtomicReference<Throwable?>()
        val worker = Thread({
            try { action() } catch (failure: Throwable) { error.set(failure) }
        }, "waiting-run-intent").apply { isDaemon = true }
        try {
            val winning = synchronized(monitor) {
                worker.start()
                waitForMonitor(worker, monitor)
                assertEquals(1L, machine.prepareRunIntent(false, "exit"))
                val state = machine.getRequestState()
                assertEquals(1L, state.revision)
                assertEquals(1L, state.intentRevision)
                assertEquals("exiting", state.reason)
                assertFalse(state.intentRunning)
                Triple(state, machine.captureRequestToken(), host.requestPublications.toList())
            }
            worker.join(5_000)
            assertFalse("Waiting request did not finish", worker.isAlive)
            assertEquals(winning.first, machine.getRequestState())
            assertSame(winning.second, machine.captureRequestToken())
            assertEquals(winning.third, host.requestPublications)
            assertEquals(1, host.requestPublications.size)
            assertEquals(0, startDispatches)
            assertEquals(0, stopDispatches)
            assertEquals(0, host.startCalls)
            assertEquals(0, host.stopCalls)
            return error.get()
        } finally {
            if (worker.isAlive) { worker.interrupt(); worker.join(5_000) }
            assertFalse("Request thread was not reclaimed", worker.isAlive)
        }
    }

    @Test fun `waiting public start cannot replace exit or mint a token`() {
        val error = exitBeforeWaitingRequest { machine.prepareRunIntent(true, "tile") }
        assertTrue(error is IllegalStateException)
        assertEquals("Application is exiting", error?.message)
    }

    @Test fun `waiting public stop cannot replace exit or mint a token`() {
        val error = exitBeforeWaitingRequest { machine.prepareRunIntent(false, "notification") }
        assertTrue(error is IllegalStateException)
        assertEquals("Application is exiting", error?.message)
    }

    @Test fun `waiting repeated exit cannot replace the winning exit`() {
        assertTrue(exitBeforeWaitingRequest {
            machine.prepareRunIntent(false, "exit")
        } is IllegalStateException)
    }

    @Test fun `waiting native start ends normally without dispatch after exit`() {
        assertNull(exitBeforeWaitingRequest { runBlocking { machine.handleStartAction() } })
    }

    @Test fun `waiting native stop ends normally without dispatch after exit`() {
        assertNull(exitBeforeWaitingRequest { runBlocking { machine.handleStopAction() } })
    }

    @Test fun `waiting always-on request returns zero without binding or dispatch after exit`() {
        assertNull(exitBeforeWaitingRequest {
            assertEquals(0L, machine.handleVpnStartRequest("waiting-vpn"))
        })
        assertEquals("", machine.getRequestState().serviceId)
    }

    @Test fun `native actions after exit end without throwing or publishing`() = runBlocking {
        machine.prepareRunIntent(false, "exit")
        val before = machine.getRequestState()
        val token = machine.captureRequestToken()
        machine.handleStartAction()
        machine.handleStopAction()
        machine.handleToggleAction()
        assertEquals(0L, machine.handleVpnStartRequest("rejected-vpn"))
        assertEquals(before, machine.getRequestState())
        assertSame(token, machine.captureRequestToken())
        assertEquals(1, host.requestPublications.size)
        assertEquals(0, startDispatches)
        assertEquals(0, stopDispatches)
        assertEquals(0, host.startCalls)
    }

    @Test fun `public rejection and invalid arguments preserve their error protocols`() {
        machine.prepareRunIntent(false, "exit")
        val before = machine.getRequestState()
        val token = machine.captureRequestToken()
        for ((running, source) in listOf(true to "ui", false to "ui", false to "exit")) {
            val error = assertThrows(IllegalStateException::class.java) {
                machine.prepareRunIntent(running, source)
            }
            assertEquals("Application is exiting", error.message)
        }
        assertThrows(IllegalArgumentException::class.java) {
            machine.prepareRunIntent(true, "invalid")
        }
        assertEquals(before, machine.getRequestState())
        assertSame(token, machine.captureRequestToken())
        assertEquals(1, host.requestPublications.size)
    }

    @Test fun `expired tokens cannot dispatch and exit cleanup keeps terminal reason`() = runBlocking {
        val start = machine.prepareRunIntent(true)
        val stop = machine.prepareRunIntent(false)
        val exit = machine.prepareRunIntent(false, "exit")
        assertEquals(1L, start)
        assertEquals(2L, stop)
        assertEquals(3L, exit)
        val before = machine.getRequestState()
        assertFalse(machine.requestStart(start).await())
        assertFalse(machine.requestStop(stop).await())
        assertEquals(before, machine.getRequestState())
        assertTrue(machine.requestStop(exit).await())
        assertEquals("stopped", machine.getRequestState().phase)
        assertEquals("exiting", machine.getRequestState().reason)
        assertEquals(exit, machine.captureRequestToken().id)
        assertThrows(IllegalStateException::class.java) { machine.prepareRunIntent(true) }
        assertEquals(0, host.startCalls)
    }

    @Test fun `normal requests retain token numbering and latest intent publication`() {
        assertEquals(1L, machine.prepareRunIntent(true, "tile"))
        assertTrue(machine.captureRequestToken().running)
        assertEquals("preparing", machine.getRequestState().phase)
        assertEquals(2L, machine.prepareRunIntent(false, "notification"))
        assertFalse(machine.captureRequestToken().running)
        assertEquals("userStop", machine.getRequestState().reason)
        assertEquals(2L, machine.getRequestState().revision)
        assertEquals(listOf(1L, 2L), host.requestPublications.map { it.intentRevision })
    }

    @Test fun `always-on request binds and dispatches its accepted token`() {
        assertEquals(1L, machine.handleVpnStartRequest("accepted-vpn"))
        val state = machine.getRequestState()
        assertEquals("accepted-vpn", state.serviceId)
        assertEquals("alwaysOn", state.source)
        assertTrue(state.intentRunning)
        assertEquals(1L, state.intentRevision)
        assertEquals(2L, state.revision)
        assertEquals(1, startDispatches)
        assertEquals(0, stopDispatches)
        assertEquals(0, host.startCalls)
    }

    @Test fun `paused always-on request cannot bind or dispatch`() {
        machine.preparePauseIntent(true)
        assertEquals(0L, machine.handleVpnStartRequest("paused-vpn"))
        val state = machine.getRequestState()
        assertEquals("", state.serviceId)
        assertTrue(state.intentRunning)
        assertTrue(state.paused)
        assertEquals("excludedSsid", state.reason)
        assertEquals(2L, state.intentRevision)
        assertEquals(2, host.requestPublications.size)
        assertEquals(0, startDispatches)
        assertEquals(0, host.startCalls)
    }

    @Test fun `native actions do not swallow invalid arguments`() {
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { machine.handleStartAction("invalid") }
        }
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { machine.handleStopAction("invalid") }
        }
        assertEquals(0L, machine.captureRequestToken().id)
        assertTrue(host.requestPublications.isEmpty())
    }

    @Test fun `publication failure still returns the original id and blocks dispatch`() = runBlocking {
        host.publishAccepted = false
        val request = machine.prepareRunIntent(true)
        assertEquals(1L, request)
        assertEquals(2L, machine.getRequestState().revision)
        assertEquals("failed", machine.getRequestState().phase)
        assertEquals("setupFailed", machine.getRequestState().reason)
        assertFalse(machine.requestStart(request).await())
        assertEquals(1, host.blockedRequests)
        assertEquals(2, host.requestPublications.size)
        assertEquals(0, host.startCalls)
    }

    @Test fun `always-on publication failure keeps the failure and does not bind or dispatch`() {
        host.publishAccepted = false
        assertEquals(0L, machine.handleVpnStartRequest("failed-vpn"))
        val state = machine.getRequestState()
        assertEquals("failed", state.phase)
        assertEquals("setupFailed", state.reason)
        assertEquals("", state.serviceId)
        assertEquals(1L, state.intentRevision)
        assertEquals(2L, state.revision)
        assertEquals(1, host.blockedRequests)
        assertEquals(2, host.requestPublications.size)
        assertEquals(0, startDispatches)
        assertEquals(0, host.startCalls)
    }
}
