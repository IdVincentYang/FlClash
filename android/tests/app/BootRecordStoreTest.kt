package com.follow.clash

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class BootRecordStoreTest {
    private class Tasks : Executor {
        val pending = ArrayDeque<Runnable>()
        override fun execute(task: Runnable) { pending.addLast(task) }
        fun run() { pending.removeFirst().run() }
    }

    private class Disk : BootRecordPersistence {
        var raw: Any? = null
        var success = true
        var writes = 0
        override fun read(): Any? = raw
        override fun commit(record: String): Boolean {
            writes++
            raw = record
            return success
        }
    }

    private class Fixture {
        val disk = Disk()
        val tasks = Tasks()
        val deliveries = ArrayDeque<() -> Unit>()
        var now = 0L
        val store = BootRecordStore(disk, mapOf("processEpoch" to "process"), { now }, tasks, { deliveries.addLast(it) })
        var reply = emptyMap<String, Any?>()
        fun call(engine: Long, action: String, record: String? = null) {
            store.handle(engine, action, mapOf("attempt" to "process:$engine", "record" to record)) { reply = it }
        }
        fun finish() { tasks.run(); deliveries.removeFirst()() }
        fun begin(): Long = store.attach().also { call(it, "begin"); finish(); assertEquals("ok", reply["status"]) }
    }

    @Test fun lateOldBeginCannotReclaimNewEngine() {
        val f = Fixture()
        val a = f.store.attach()
        f.call(a, "begin")
        val b = f.store.attach()
        f.finish()
        assertEquals("stale", f.reply["status"])
        assertEquals(false, f.reply["current"])
        f.call(a, "begin")
        assertEquals("stale", f.reply["status"])
        f.call(b, "begin"); f.finish()
        assertEquals(true, f.reply["writable"])
    }

    @Test fun unavailablePreferencesCanUseSessionStatusAndCloseWithoutRecordIo() {
        val f = Fixture()
        val engine = f.store.attach()
        f.call(engine, "status")
        assertEquals(true, f.reply["current"])
        assertEquals(false, f.reply["writable"])
        f.call(engine, "close")
        assertEquals("ok", f.reply["status"])
        assertEquals(false, f.reply["current"])
        assertTrue(f.tasks.pending.isEmpty())
        assertEquals(0, f.disk.writes)
    }

    @Test fun completionQueuedForDeliveryCannotRestoreOldClaim() {
        val f = Fixture()
        val a = f.store.attach()
        f.call(a, "begin"); f.tasks.run()
        val b = f.store.attach()
        f.deliveries.removeFirst()()
        assertEquals("stale", f.reply["status"])
        f.call(b, "begin"); f.finish()
        assertEquals("ok", f.reply["status"])
    }

    @Test fun busyHasNoQueueAndStatusRevokeNeverWaitForWorker() {
        val f = Fixture()
        val a = f.begin()
        f.call(a, "write", "starting")
        assertEquals(1, f.tasks.pending.size)
        val b = f.store.attach()
        f.call(b, "begin")
        assertEquals("busy", f.reply["status"])
        assertEquals(1, f.tasks.pending.size)
        f.call(b, "status")
        assertEquals(true, f.reply["current"])
        f.call(b, "revoke")
        assertEquals(false, f.reply["writable"])
        f.finish()
        assertEquals(0, f.disk.writes)
    }

    @Test fun deadlineBeforeIoSkipsPersistence() {
        val f = Fixture()
        val a = f.begin()
        f.call(a, "write", "running")
        f.now = BootRecordStore.IO_BUDGET_MS + 1
        f.finish()
        assertEquals("stale", f.reply["status"])
        assertEquals(0, f.disk.writes)
    }

    @Test fun falseCommitIsNeverReportedAsDurableSuccess() {
        val f = Fixture()
        val a = f.begin()
        f.disk.success = false
        f.call(a, "write", "starting"); f.finish()
        assertEquals("io", f.reply["status"])
        assertEquals(false, f.reply["writable"])
        assertEquals(true, f.reply["current"])
    }

    @Test fun completedCommitDeliveredAfterDeadlineIsNotCurrentSuccess() {
        val f = Fixture()
        val a = f.begin()
        f.call(a, "write", "running")
        f.tasks.run()
        f.now = BootRecordStore.IO_BUDGET_MS + 1
        f.deliveries.removeFirst()()
        assertEquals("running", f.disk.raw)
        assertEquals("stale", f.reply["status"])
        assertEquals(false, f.reply["writable"])
        assertEquals(true, f.reply["current"])
    }

    @Test fun closeIsTerminalEvenWhenDiskIsBusy() {
        val f = Fixture()
        val a = f.begin()
        f.call(a, "write", "running")
        f.call(a, "close", "closed")
        assertEquals(false, f.reply["current"])
        f.finish()
        assertEquals(0, f.disk.writes)
        f.call(a, "write", "late ready")
        assertEquals("stale", f.reply["status"])
    }

    @Test fun detachRejectsLateRebuildAndCannotRevokeNewEngine() {
        val f = Fixture()
        val a = f.begin()
        f.call(a, "write", "rebuilt")
        f.store.detach(a)
        val b = f.store.attach()
        f.store.detach(a)
        f.finish()
        f.call(b, "status")
        assertEquals(true, f.reply["current"])
        assertEquals(0, f.disk.writes)
    }

    @Test fun malformedValuesArePreservedWithoutReturningTheirPayload() {
        val f = Fixture()
        f.disk.raw = "private".repeat(2000)
        f.begin()
        assertEquals(true, f.reply["malformed"])
        assertFalse(f.reply.containsKey("record"))
        assertEquals(0, f.disk.writes)
    }

    @Test fun inFlightCommitMayFinishAfterRevokeButCannotBecomeCurrentSuccess() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        var raw = ""
        val backend = object : BootRecordPersistence {
            override fun read(): Any? = null
            override fun commit(record: String): Boolean {
                entered.countDown()
                check(release.await(3, TimeUnit.SECONDS))
                raw = record
                return true
            }
        }
        val store = BootRecordStore(backend, mapOf("processEpoch" to "process"), { 0L }, executor, { it() })
        val a = store.attach()
        val began = CountDownLatch(1)
        store.handle(a, "begin", emptyMap<Any, Any>()) { began.countDown() }
        assertTrue(began.await(3, TimeUnit.SECONDS))
        var result: Map<String, Any?>? = null
        try {
            store.handle(a, "write", mapOf("attempt" to "process:$a", "record" to "old starting")) { result = it; finished.countDown() }
            assertTrue(entered.await(3, TimeUnit.SECONDS))
            val b = store.attach()
            store.handle(b, "begin", emptyMap<Any, Any>()) { assertEquals("busy", it["status"]) }
            store.handle(b, "status", emptyMap<Any, Any>()) { assertEquals(true, it["current"]) }
            store.handle(a, "revoke", emptyMap<Any, Any>()) { assertEquals(false, it["current"]) }
            release.countDown()
            assertTrue(finished.await(3, TimeUnit.SECONDS))
            assertEquals("old starting", raw)
            assertEquals("stale", result?.get("status"))
            assertEquals(false, result?.get("current"))
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }
}
