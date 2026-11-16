package com.follow.clash

import com.follow.clash.models.ConfigApplyResult
import com.follow.clash.models.ConfigFact
import com.follow.clash.models.ConfigReceipt
import com.follow.clash.service.ServiceConfig
import com.follow.clash.service.models.NotificationParams
import com.google.gson.JsonObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ConfigFactStateMachineTest {
    private lateinit var scope: CoroutineScope
    private lateinit var host: ConfigServiceTestHost
    private lateinit var machine: ServiceStateMachine
    private var phaseFact: ConfigFact? = null
    private var beforeNotification: (NotificationParams) -> Unit = {}
    private val releases = mutableListOf<CountDownLatch>()
    private val workers = mutableListOf<Worker>()

    private class Worker(val thread: Thread, val error: AtomicReference<Throwable?>)

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        host = ConfigServiceTestHost(scope)
        machine = host.createMachine(object : ServiceStateHost by host {
            override fun updateNotificationParams(params: NotificationParams) {
                beforeNotification(params)
                ServiceConfig.updateNotificationParams(params)
            }

            override suspend fun configPhase(method: String, receipt: ConfigReceipt): ConfigApplyResult {
                val fact = phaseFact
                return if (fact != null && method == "prepareConfig") {
                    ConfigApplyResult("staleInput", receipt = receipt, fact = fact)
                } else host.configPhase(method, receipt)
            }
        })
        host.storedSharedState = host.storedSharedState.copy(configApplyingTip = "Applying", configInactiveTip = "Idle")
        machine.syncSharedState(host.storedSharedState)
    }

    @After fun tearDown() {
        releases.forEach { it.countDown() }
        workers.forEach {
            if (it.thread.isAlive) it.thread.interrupt()
            it.thread.join(5_000)
            assertFalse("Worker was not reclaimed", it.thread.isAlive)
        }
        scope.cancel()
        ServiceConfig.updateNotificationParams(NotificationParams())
    }

    private fun fact(version: Long, name: String = "v$version", active: Boolean = true, epoch: String = "test") = ConfigFact(
        runtimeEpoch = epoch, version = version, profileName = name,
        phase = if (active) "ready" else "retired", businessActive = active,
    )

    private fun currentFact(): ConfigFact {
        val field = ServiceStateMachine::class.java.getDeclaredField("configFact")
        field.isAccessible = true
        return field.get(machine) as ConfigFact
    }

    private fun start() = runBlocking {
        assertTrue(machine.requestStart().await())
        machine.observeConfigFact(fact(10, "Baseline"))
        assertEquals(host.startResult, machine.refresh())
    }

    private fun applyFact(fact: ConfigFact): ConfigApplyResult = runBlocking {
        phaseFact = fact
        try {
            machine.applyConfig(JsonObject().apply {
                addProperty("inputId", "a".repeat(64))
                addProperty("requestId", machine.getRequestState().intentRevision)
            }).await().also { assertEquals("staleInput", it.status) }
        } finally { phaseFact = null }
    }

    private fun worker(action: () -> Unit): Worker {
        val error = AtomicReference<Throwable?>()
        val thread = Thread({
            try { action() } catch (failure: Throwable) { error.set(failure) }
        }, "config-fact-worker").apply { isDaemon = true }
        return Worker(thread, error).also { workers += it; thread.start() }
    }

    private fun join(worker: Worker) {
        worker.thread.join(5_000)
        assertFalse("Worker did not finish", worker.thread.isAlive)
        worker.error.get()?.let { throw AssertionError("Worker failed", it) }
    }

    private fun await(latch: CountDownLatch) {
        assertTrue("Worker did not reach its controlled boundary", latch.await(5, TimeUnit.SECONDS))
    }

    @Suppress("DEPRECATION")
    private fun atPublicationBoundary(worker: Worker, owner: Worker, method: String): Boolean {
        val field = ServiceStateMachine::class.java.getDeclaredField("publicationLock")
        field.isAccessible = true
        val monitor = checkNotNull(field.get(machine))
        val expected = monitor.javaClass.name + "@" + Integer.toHexString(System.identityHashCode(monitor))
        val bean = Class.forName("java.lang.management.ManagementFactory").getMethod("getThreadMXBean").invoke(null)
        val beanClass = Class.forName("java.lang.management.ThreadMXBean")
        val infoClass = Class.forName("java.lang.management.ThreadInfo")
        val getInfo = beanClass.getMethod("getThreadInfo", Long::class.javaPrimitiveType, Int::class.javaPrimitiveType)
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (System.nanoTime() < deadline) {
            val info = getInfo.invoke(bean, worker.thread.id, 64)
            if (!worker.thread.isAlive) return false
            if (worker.thread.state == Thread.State.BLOCKED && info != null &&
                infoClass.getMethod("getLockName").invoke(info) == expected &&
                infoClass.getMethod("getLockOwnerId").invoke(info) == owner.thread.id) {
                val frames = infoClass.getMethod("getStackTrace").invoke(info) as Array<*>
                assertTrue("Caller did not reach $method", frames.any {
                    it is StackTraceElement && it.className == ServiceStateMachine::class.java.name && it.methodName.startsWith(method)
                })
                return true
            }
            Thread.yield()
        }
        fail("Caller neither completed nor reached the publication boundary")
        return false
    }

    private fun overlap(
        heldTitle: String,
        first: () -> Unit,
        second: () -> Unit,
        secondMethod: String,
        expectedFact: ConfigFact,
        expectedTitle: String,
        expectedTime: Long,
    ) {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1).also { releases += it }
        val attempted = CountDownLatch(1)
        val held = AtomicBoolean()
        beforeNotification = {
            if (it.title == heldTitle && held.compareAndSet(false, true)) {
                entered.countDown()
                await(release)
            }
        }
        val old = worker(first)
        var newer: Worker? = null
        val blocked: Boolean
        try {
            await(entered)
            newer = worker { attempted.countDown(); second() }
            await(attempted)
            blocked = atPublicationBoundary(newer, old, secondMethod)
        } finally { release.countDown() }
        join(old)
        join(checkNotNull(newer))
        assertEquals(expectedFact, currentFact())
        assertEquals(expectedTitle, ServiceConfig.notificationParams.value.title)
        assertEquals(expectedTime, runBlocking { machine.refresh() })
        assertTrue("Competing caller bypassed the held publication", blocked)
    }

    @Test fun `event projection cannot overtake an earlier event publication`() {
        start()
        val newest = fact(30, "Newest")
        overlap("Older", { machine.observeConfigFact(fact(20, "Older")) },
            { machine.observeConfigFact(newest) }, "observeConfigFact", newest, "Newest", host.startResult)
    }

    @Test fun `real apply receipt cannot overtake an event publication`() {
        start()
        val newest = fact(30, "Newest")
        overlap("Older", { machine.observeConfigFact(fact(20, "Older")) },
            { applyFact(newest) }, "observeConfigFact", newest, "Newest", host.startResult)
    }

    @Test fun `event cannot overtake a real apply receipt publication`() {
        start()
        val newest = fact(30, "Newest")
        overlap("Older", { applyFact(fact(20, "Older")) },
            { machine.observeConfigFact(newest) }, "observeConfigFact", newest, "Newest", host.startResult)
    }

    @Test fun `authoritative epoch switch follows publication then rejects late old events`() {
        start()
        val newest = fact(1, "Newest", epoch = "new-runtime")
        overlap("Older", { machine.observeConfigFact(fact(20, "Older")) },
            { applyFact(newest) }, "observeConfigFact", newest, "Newest", host.startResult)
        machine.observeConfigFact(fact(999, "Late old runtime"))
        assertEquals(newest, currentFact())
        assertEquals("Newest", ServiceConfig.notificationParams.value.title)
    }

    @Test fun `shared preferences projection uses the latest accepted fact`() {
        start()
        val newest = fact(30, "Newest")
        overlap("Baseline", { machine.syncSharedState(host.storedSharedState.copy(stopText = "Stop now")) },
            { machine.observeConfigFact(newest) }, "observeConfigFact", newest, "Newest", host.startResult)
        assertEquals("Stop now", ServiceConfig.notificationParams.value.stopText)
    }

    @Test fun `late phase projection cannot replace a newer stop projection`() {
        start()
        val before = currentFact()
        overlap("Applying", { machine.prepareRunIntent(true) },
            { machine.prepareRunIntent(false) }, "publishSnapshot", before, "Idle", 0L)
        assertFalse(machine.getRequestState().intentRunning)
        assertEquals("stopping", machine.getRequestState().phase)
    }

    @Test fun `refresh waits for the accepted inactive fact to finish publication`() {
        start()
        val inactive = fact(20, "Inactive", active = false)
        val actual = AtomicReference<Long>()
        overlap("Idle", { machine.observeConfigFact(inactive) },
            { actual.set(runBlocking { machine.refresh() }) }, "refresh", inactive, "Idle", 0L)
        assertEquals(0L, actual.get())
    }

    @Test fun `same epoch ignores lower versions from both events and real receipts`() {
        start()
        val newest = fact(30, "Newest")
        machine.observeConfigFact(newest)
        val params = ServiceConfig.notificationParams.value
        machine.observeConfigFact(fact(20, "Old event", active = false))
        applyFact(fact(20, "Old response", active = false))
        assertEquals(newest, currentFact())
        assertEquals(params, ServiceConfig.notificationParams.value)
        assertEquals(host.startResult, runBlocking { machine.refresh() })
    }

    @Test fun `same version snapshots remain eligible for actual state updates and duplicates`() {
        start()
        val inactive = fact(30, "Inactive", active = false)
        machine.observeConfigFact(fact(30, "Ready"))
        machine.observeConfigFact(inactive)
        assertEquals(inactive, currentFact())
        assertEquals("Idle", ServiceConfig.notificationParams.value.title)
        assertEquals(0L, runBlocking { machine.refresh() })
        machine.observeConfigFact(inactive.copy())
        assertEquals(inactive, currentFact())
        applyFact(fact(30, "Updated snapshot"))
        assertEquals("Updated snapshot", ServiceConfig.notificationParams.value.title)
        assertEquals(host.startResult, runBlocking { machine.refresh() })
    }

    @Test fun `first epoch is accepted but empty and foreign events are ignored`() {
        val first = fact(2, "Initial", active = false)
        machine.observeConfigFact(fact(99, epoch = ""))
        assertEquals(ConfigFact(), currentFact())
        machine.observeConfigFact(first)
        machine.observeConfigFact(fact(99, epoch = "foreign"))
        machine.observeConfigFact(fact(99, epoch = ""))
        assertEquals(first, currentFact())
        assertEquals("Idle", ServiceConfig.notificationParams.value.title)
        assertEquals(0L, runBlocking { machine.refresh() })
    }

    @Test fun `notification failure releases publication and preserves the accepted fact`() {
        start()
        val once = AtomicBoolean()
        beforeNotification = { if (once.compareAndSet(false, true)) error("synthetic notification failure") }
        val accepted = fact(20, "Accepted")
        val failure = assertThrows(IllegalStateException::class.java) { machine.observeConfigFact(accepted) }
        assertEquals("synthetic notification failure", failure.message)
        assertEquals(accepted, currentFact())
        val newest = fact(30, "Newest")
        join(worker { machine.observeConfigFact(newest) })
        assertEquals(newest, currentFact())
        assertEquals("Newest", ServiceConfig.notificationParams.value.title)
    }

    @Test fun `same-thread StateFlow callback can reenter projection and refresh`() {
        start()
        val callbackThread = AtomicReference<Thread>()
        val callbackTime = AtomicReference<Long>()
        val collector = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            ServiceConfig.notificationParams.drop(1).take(1).collect {
                callbackThread.set(Thread.currentThread())
                machine.syncSharedState(host.storedSharedState.copy(stopText = "Reentered"))
                callbackTime.set(machine.refresh())
            }
        }
        val newest = fact(30, "Newest")
        val publisher = worker { machine.observeConfigFact(newest) }
        join(publisher)
        runBlocking { withTimeout(5_000) { collector.join() } }
        assertSame(publisher.thread, callbackThread.get())
        assertEquals(host.startResult, callbackTime.get())
        assertEquals(newest, currentFact())
        assertEquals("Newest", ServiceConfig.notificationParams.value.title)
        assertEquals("Reentered", ServiceConfig.notificationParams.value.stopText)
    }
}
