package com.follow.clash

import java.io.ByteArrayInputStream
import java.nio.file.Files
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class CrashReportCollectorTest {
    @Test fun systemImportPreservesOriginalIdentityAndDistinctPidWithoutRecoveryCursor() {
        val root = Files.createTempDirectory("exit-reports").toFile().canonicalFile
        val worker = CrashReportWorker()
        val store = CrashReportStore(root)
        val collector = CrashReportCollector({ store }, worker, { mapOf("versionCode" to 999, "processEpoch" to "current") }, { System.nanoTime() / 1_000_000 })
        try {
            val old = CrashBuildIdentity.encode(mapOf("versionCode" to 12, "versionName" to "old", "api" to 30, "is64Bit" to false, "abi" to "armeabi-v7a"))
            val exits = listOf(
                CrashExit("example.app", 100, 1234, 6, 0, old) { ByteArrayInputStream("synthetic trace".toByteArray()) },
                CrashExit("example.app", 101, 1234, 5, 6),
                CrashExit("foreign", 102, 1234, 4, 0) { error("must not open") },
                CrashExit("example.app", 103, 1234, 10, 0),
            )
            assertEquals("finished", collector.import(exits, "example.app", 31).get(4, TimeUnit.SECONDS))
            assertEquals(2, store.ids().size)
            val reports = store.ids().map { store.read(it)!! }
            val traced = reports.single { it.raw != null }
            assertEquals("synthetic trace", String(traced.raw!!))
            assertEquals(12, traced.metadata.getAsJsonObject("identity")["versionCode"].asInt)
            assertEquals(30, traced.metadata.getAsJsonObject("identity")["api"].asInt)
            assertEquals(31, traced.metadata.getAsJsonObject("event")["observerApi"].asInt)
            val missing = reports.single { it.raw == null }.metadata.getAsJsonObject("identity")
            assertFalse(missing.has("versionCode")); assertFalse(missing.has("api")); assertFalse(missing.has("is64Bit"))
            assertEquals("finished", collector.import(exits, "example.app", 31).get(4, TimeUnit.SECONDS))
            assertEquals(2, store.ids().size)
        } finally { worker.close(); root.deleteRecursively() }
    }

    @Test fun nativePrefixIsExplicitlyTruncatedAndNullTraceStillPersistsMetadata() {
        val root = Files.createTempDirectory("prefix-reports").toFile().canonicalFile
        val worker = CrashReportWorker(); val store = CrashReportStore(root)
        val capture = CrashReportCollector({ store }, worker, { emptyMap() }, { System.nanoTime() / 1_000_000 })
        try {
            val exits = listOf(CrashExit("app", 1, 1, 5, 6) { ByteArrayInputStream(ByteArray(CrashReportStore.RAW_LIMIT + 1)) },
                CrashExit("app", 2, 2, 6, 0),
                CrashExit("app", 3, 3, 6, 0) { ByteArrayInputStream(byteArrayOf()) })
            capture.import(exits, "app", 31).get(4, TimeUnit.SECONDS)
            val reports = store.ids().map { store.read(it)!! }
            val raw = reports.single { it.raw != null }
            assertEquals(CrashReportStore.RAW_LIMIT, raw.raw!!.size)
            assertTrue(raw.metadata.getAsJsonObject("raw")["truncated"].asBoolean)
            assertEquals("native_protobuf", raw.metadata.getAsJsonObject("raw")["format"].asString)
            assertEquals(setOf("unavailable", "empty"), reports.filter { it.raw == null }.map {
                it.metadata.getAsJsonObject("event")["traceStatus"].asString
            }.toSet())
        } finally { worker.close(); root.deleteRecursively() }
    }

    @Test fun blockedTraceKeepsOneWorkerAndCannotPublishAfterDeadline() {
        val root = Files.createTempDirectory("blocked-trace").toFile().canonicalFile
        var now = 0L; val worker = CrashReportWorker { now }; val store = CrashReportStore(root, clock = { now })
        val capture = CrashReportCollector({ store }, worker, { emptyMap() }, { now })
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        try {
            val future = capture.import(listOf(CrashExit("app", 1, 1, 6, 0) {
                object : java.io.InputStream() {
                    override fun read(): Int { entered.countDown(); release.await(); return -1 }
                }
            }), "app", 30)
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            now = 10000
            release.countDown()
            assertEquals("deadline", future.get(2, TimeUnit.SECONDS)); assertTrue(store.ids().isEmpty())
        } finally { release.countDown(); worker.close(); root.deleteRecursively() }
    }

    @Test fun liveDedupAndRawStayOutOfMetadata() {
        val root = Files.createTempDirectory("live-reports").toFile().canonicalFile
        val worker = CrashReportWorker(); val store = CrashReportStore(root)
        val capture = CrashReportCollector({ store }, worker, { mapOf("processEpoch" to "one") }, { System.nanoTime() / 1_000_000 })
        try {
            val secret = "SYNTHETIC_PRIVATE_RAW_ONLY".toByteArray()
            assertEquals("stored", capture.error("flutter", secret, false).get())
            assertEquals("duplicate", capture.error("flutter", secret, false).get())
            val report = store.read(store.ids().single())!!
            assertFalse(report.metadata.toString().contains(String(secret)))
            assertArrayEquals(secret, report.raw)
        } finally { worker.close(); root.deleteRecursively() }
    }

    @Test fun uncaughtAlwaysDelegatesOnceEvenWhenCaptureThrowsOrTimesOut() {
        for (mode in listOf("throw", "blocked", "stored", "busy")) {
            var calls = 0
            val handler = CrashUncaughtHandler({ _, _ -> calls++ }) {
                when (mode) {
                    "throw" -> throw OutOfMemoryError("synthetic")
                    "blocked" -> CompletableFuture()
                    else -> CompletableFuture.completedFuture(mode)
                }
            }
            handler.uncaughtException(Thread.currentThread(), IllegalStateException("synthetic"))
            assertEquals(1, calls)
        }
    }

    @Test fun redirectedRootCannotAcknowledgeAnExternalSystemReport() {
        for (replaced in listOf(false, true)) {
            val private = Files.createTempDirectory("private-report-root").toFile().canonicalFile
            val target = Files.createTempDirectory("simulated-files-dir").toFile().canonicalFile
            val worker = CrashReportWorker { 0 }
            try {
                val exit = CrashExit("app", 1, 2, 6, 0) { ByteArrayInputStream("synthetic trace".toByteArray()) }
                val id = CrashReportStore.digest(listOf("app", "app", 1, 2L, 6, 0).joinToString("\u0000").toByteArray())
                assertEquals("stored", CrashReportStore(target, clock = { 0 }).save(CrashMaterial(
                    id, "system_exit", emptyMap(), emptyMap(), "external synthetic trace".toByteArray(), system = true), 10))
                fun bytes() = target.walkTopDown().filter { it.isFile }.associate {
                    it.relativeTo(target).path to CrashReportStore.digest(it.readBytes())
                }
                val before = bytes()
                val path = java.io.File(private, "reports")
                val store = CrashReportStore(path, clock = { 0 })
                if (replaced) {
                    assertEquals("ready", store.maintain(10))
                    assertTrue(path.renameTo(java.io.File(private, "previous")))
                }
                Files.createSymbolicLink(path.toPath(), target.toPath())
                val collector = CrashReportCollector({ store }, worker, { emptyMap() }, { 0 })
                assertEquals("io", collector.import(listOf(exit), "app", 31).get(2, TimeUnit.SECONDS))
                assertEquals(before, bytes())
            } finally { worker.close(); private.deleteRecursively(); target.deleteRecursively() }
        }
    }
}
