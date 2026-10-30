package com.follow.clash

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class CrashReportStoreTest {
    private fun root() = Files.createTempDirectory("report-test").toFile().canonicalFile.apply { deleteOnExit() }
    private fun material(index: Int = 1, system: Boolean = false, bytes: Int = 12) = CrashMaterial(
        CrashReportStore.digest("event$index".toByteArray()), if (system) "system_exit" else "flutter",
        mapOf("versionCode" to 123, "buildStatus" to "unknown"), mapOf("category" to "synthetic"),
        ByteArray(bytes) { 42 }, "synthetic", system = system)

    @Test fun commitReopensWithMatchingRawAndIdentity() {
        val dir = root()
        try {
            val event = material(); val store = CrashReportStore(dir, { 1000 }, { 0 })
            assertEquals("stored", store.save(event, 10))
            val restored = CrashReportStore(dir).read(event.id)!!
            assertArrayEquals(event.raw, restored.raw)
            assertEquals(123, restored.metadata.getAsJsonObject("identity")["versionCode"].asInt)
            assertEquals(CrashReportStore.digest(event.raw!!), restored.metadata.getAsJsonObject("raw")["sha256"].asString)
        } finally { dir.deleteRecursively() }
    }

    @Test fun failedSyncOrPublishPreservesPriorEvidence() {
        for (failure in listOf("sync", "publish")) {
            val dir = root()
            try {
                assertEquals("stored", CrashReportStore(dir, clock = { 0 }).save(material(), 100))
                val store = if (failure == "sync") CrashReportStore(dir, clock = { 0 }, sync = { throw java.io.IOException("synthetic") })
                    else CrashReportStore(dir, clock = { 0 }, publish = { _, _ -> false })
                assertEquals("io", store.save(material(2), 100))
                assertNotNull(CrashReportStore(dir).read(material().id))
                assertEquals(listOf(material().id), CrashReportStore(dir).ids())
            } finally { dir.deleteRecursively() }
        }
    }

    @Test fun expiredWorkAndHalfWritesAreNotCommitted() {
        val dir = root()
        try {
            File(dir, ".staging").mkdir(); File(dir, ".staging/raw.bin").writeText("partial")
            val store = CrashReportStore(dir, clock = { 20 })
            assertEquals("deadline", store.save(material(), 10))
            assertTrue(store.ids().isEmpty())
            assertFalse(File(dir, ".staging").exists())
            var time = 0L
            val late = CrashReportStore(dir, clock = { time }, sync = { it.fd.sync(); time = 100 })
            assertEquals("deadline", late.save(material(), 10))
            assertTrue(store.ids().isEmpty())
        } finally { dir.deleteRecursively() }
    }

    @Test fun duplicatesSurviveEvictionThroughSuccessfulSystemLedger() {
        val dir = root()
        try {
            val store = CrashReportStore(dir, { 1000 }, { 0 })
            for (i in 1..21) assertEquals("stored", store.save(material(i, true), 10))
            assertEquals(20, store.ids().size)
            assertEquals("duplicate", CrashReportStore(dir, clock = { 0 }).save(material(1, true), 10))
            assertEquals(20, store.ids().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun ledgerFailureAfterPublishIsRepairableWithoutDuplicate() {
        val dir = root()
        try {
            val store = CrashReportStore(dir, clock = { 0 }, publish = { from, to -> to.name != "seen.json" && from.renameTo(to) })
            assertEquals("io", store.save(material(system = true), 10))
            assertNotNull(store.read(material().id))
            val retry = CrashReportStore(dir, clock = { 0 })
            assertEquals("duplicate", retry.save(material(system = true), 10))
            assertEquals(1, retry.ids().size)
            assertTrue(File(dir, "seen.json").exists())
        } finally { dir.deleteRecursively() }
    }

    @Test fun futureAndDamagedCommittedItemsAreNotOverwritten() {
        val dir = root()
        try {
            val event = material(); val file = File(dir, event.id).apply { mkdir() }
            val metadata = File(file, "metadata.json").apply { writeText("{\"schema\":2}") }
            val before = metadata.readBytes()
            val store = CrashReportStore(dir, clock = { 0 })
            assertEquals("newer", store.save(event, 10)); assertArrayEquals(before, metadata.readBytes())
            metadata.writeText("broken")
            assertEquals("newer", store.save(event, 10)); assertEquals("broken", metadata.readText())
            assertNull(store.read(event.id))
        } finally { dir.deleteRecursively() }
    }

    @Test fun limitsIncludeUnknownItemsAndFailedCleanupStopsGrowth() {
        val dir = root()
        try {
            val store = CrashReportStore(dir, { 1000 }, { 0 })
            assertEquals("invalid", store.save(material(bytes = CrashReportStore.ERROR_LIMIT + 1), 10))
            for (i in 1..20) assertEquals("stored", store.save(material(i), 10))
            val failed = CrashReportStore(dir, clock = { 0 }, remove = { false })
            assertEquals("io", failed.save(material(21), 10))
            assertEquals("busy", failed.save(material(22), 10))
            assertEquals(21, store.ids().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun totalByteQuotaAndTimeRollbackRemainBounded() {
        val dir = root()
        try {
            var now = 1000L
            val store = CrashReportStore(dir, { now }, { 0 })
            for (i in 1..18) assertEquals("stored", store.save(material(i, true, CrashReportStore.RAW_LIMIT), 10))
            assertTrue(dir.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= CrashReportStore.TOTAL_LIMIT)
            now = 0
            assertEquals("stored", store.save(material(99), 10)); assertFalse(store.ids().isEmpty())
            now = CrashReportStore.RETENTION + 2000
            assertEquals("stored", store.save(material(100), 10)); assertEquals(listOf(material(100).id), store.ids())
        } finally { dir.deleteRecursively() }
    }

    @Test fun canonicalBoundaryRejectsSymlink() {
        val dir = root(); val outside = root()
        try {
            Files.createSymbolicLink(File(dir, material().id).toPath(), outside.toPath())
            assertEquals("io", CrashReportStore(dir, clock = { 0 }).save(material(), 10))
            assertTrue(outside.listFiles()!!.isEmpty())
        } finally { dir.deleteRecursively(); outside.deleteRecursively() }
    }

    @Test fun quietStartupChecksRetentionWithoutNeedingANewError() {
        val dir = root()
        try {
            var now = 1000L
            val store = CrashReportStore(dir, { now }, { 0 })
            assertEquals("stored", store.save(material(), 10))
            now = CrashReportStore.RETENTION + 2000
            assertEquals("ready", store.maintain(10)); assertTrue(store.ids().isEmpty())
            assertEquals("stored", store.save(material(2), 10))
            now = 0
            assertEquals("ready", store.maintain(10)); assertEquals(listOf(material(2).id), store.ids())
        } finally { dir.deleteRecursively() }
    }

    @Test fun newReportSurvivesRollbackAndUnknownOccupancyCannotCauseFalseStored() {
        val dir = root(); val full = root()
        try {
            var now = 1000L
            val store = CrashReportStore(dir, { now }, { 0 })
            repeat(20) { assertEquals("stored", store.save(material(it), 10)) }
            now = 0
            assertEquals("stored", store.save(material(99), 10))
            assertNotNull(store.read(material(99).id)); assertEquals(20, store.ids().size)
            val future = File(full, material().id).apply { mkdir() }
            File(future, "metadata.json").writeText("{\"schema\":2}")
            java.io.RandomAccessFile(File(future, "raw.bin"), "rw").use { it.setLength(CrashReportStore.TOTAL_LIMIT - 128) }
            val protected = CrashReportStore(full, clock = { 0 })
            assertEquals("busy", protected.save(material(99), 10))
            assertEquals("{\"schema\":2}", File(future, "metadata.json").readText())
            assertNull(protected.read(material(99).id))
        } finally { dir.deleteRecursively(); full.deleteRecursively() }
    }

    @Test fun workerQueuesFourAndDoesNotFreeBlockedSlotOnCallerTimeout() {
        val worker = CrashReportWorker(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
        try {
            val first = worker.submit { entered.countDown(); release.await(); "stored" }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            val queued = (1..4).map { worker.submit(5) { "unexpected" } }
            assertEquals("busy", worker.submit { "unexpected" }.get())
            try { first.get(5, TimeUnit.MILLISECONDS); fail() } catch (_: java.util.concurrent.TimeoutException) { }
            assertEquals("busy", worker.submit { "unexpected" }.get())
            release.countDown()
            assertEquals("stored", first.get(2, TimeUnit.SECONDS))
            queued.forEach { assertEquals("deadline", it.get(2, TimeUnit.SECONDS)) }
        } finally { release.countDown(); worker.close() }
    }

    private fun redirectedRoot(afterMaintenance: Boolean, withLedger: Boolean) {
        val private = root(); val target = root()
        try {
            val event = material(system = true).copy(system = withLedger)
            assertEquals("stored", CrashReportStore(target, clock = { 0 }).save(event, 10))
            fun bytes() = target.walkTopDown().filter { it.isFile }.associate {
                it.relativeTo(target).path to CrashReportStore.digest(it.readBytes())
            }
            val before = bytes()
            val path = File(private, "reports")
            val store = CrashReportStore(path, clock = { 0 })
            if (afterMaintenance) {
                assertEquals("ready", store.maintain(10))
                assertTrue(path.renameTo(File(private, "previous")))
            }
            Files.createSymbolicLink(path.toPath(), target.toPath())
            assertNull(store.read(event.id))
            assertTrue(store.ids().isEmpty())
            assertFalse(store.savedSystem(event.id))
            assertEquals(before, bytes())
            assertEquals(withLedger, File(target, "seen.json").exists())
            assertFalse(File(target, ".seen.tmp").exists())
        } finally { private.deleteRecursively(); target.deleteRecursively() }
    }

    @Test fun initialRootSymlinkCannotReadExternalLedger() = redirectedRoot(false, true)
    @Test fun replacedRootCannotReadExternalLedger() = redirectedRoot(true, true)
    @Test fun initialRootSymlinkCannotRepairExternalLedger() = redirectedRoot(false, false)
    @Test fun replacedRootCannotRepairExternalLedger() = redirectedRoot(true, false)

    @Test fun missingReadRootDoesNotCreateOrCleanDirectories() {
        val private = root()
        try {
            val path = File(private, "missing")
            val store = CrashReportStore(path)
            assertNull(store.read(material().id)); assertTrue(store.ids().isEmpty()); assertFalse(store.savedSystem(material().id))
            assertFalse(path.exists())
        } finally { private.deleteRecursively() }
    }
}
