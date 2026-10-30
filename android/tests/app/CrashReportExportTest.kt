package com.follow.clash

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [24, 31], shadows = [ReportOsShadow::class])
class CrashReportExportTest {
    private val context = RuntimeEnvironment.getApplication()
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private val root = File(context.noBackupFilesDir, "crash_reports").canonicalFile
    private val worker = CrashReportWorker(SystemClock::elapsedRealtime)
    private val store = CrashReportStore(root, clock = SystemClock::elapsedRealtime)
    private val provider = ReportDocumentProvider()
    private val uri = DocumentsContract.buildDocumentUri("synthetic.reports", "out")
    private lateinit var args: Map<String, Any?>
    private lateinit var export: CrashReportExport
    private val replies = mutableListOf<Map<String, Any?>>()

    @Before fun prepare() {
        assertEquals("stored", store.save(CrashMaterial("a".repeat(64), "startup", mapOf("versionCode" to 1), emptyMap(),
            "SYNTHETIC_SECRET".toByteArray(), "utf8_exception"), Long.MAX_VALUE))
        val inventory = store.manage("inventory", emptyMap<Any, Any>(), Long.MAX_VALUE)
        val row = (inventory["items"] as List<*>).single() as Map<*, *>
        args = mapOf("revision" to inventory["revision"], "token" to row["token"], "kind" to "summary", "nonce" to "first")
        provider.attachInfo(context, ProviderInfo().apply {
            authority = "synthetic.reports"; exported = true; grantUriPermissions = true
            readPermission = "android.permission.MANAGE_DOCUMENTS"; writePermission = readPermission
        })
        ShadowContentResolver.registerProviderInternal("synthetic.reports", provider)
        export = adapter()
    }

    private fun adapter(clock: () -> Long = SystemClock::elapsedRealtime) = CrashReportExport(context, { task, reply ->
        worker.submitValue({ mapOf<String, Any?>("status" to it) }) { deadline ->
            try { task(store, deadline) } catch (error: ReportFailure) { mapOf("status" to error.status) }
        }.whenComplete { value, _ -> reply(value) }
    }, clock)

    @After fun finish() {
        export.cancel()
        worker.close()
        val executor = org.robolectric.util.ReflectionHelpers.getField<java.util.concurrent.ThreadPoolExecutor>(worker, "executor")
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
    }

    private fun until(condition: () -> Boolean) {
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
        var done = false
        while (!done && System.nanoTime() < end) {
            Shadows.shadowOf(Looper.getMainLooper()).idle()
            done = condition()
            Thread.sleep(5)
        }
        assertTrue("asynchronous report operation did not finish", done)
    }

    private fun pick(arguments: Map<String, Any?> = args): Int {
        export.start(arguments, activity, replies::add)
        var started: org.robolectric.shadows.ShadowActivity.IntentForResult? = null
        until {
            started = Shadows.shadowOf(activity).nextStartedActivityForResult
            started != null || replies.isNotEmpty()
        }
        assertNotNull(replies.toString(), started)
        assertEquals(Intent.ACTION_CREATE_DOCUMENT, started!!.intent.action)
        return started!!.requestCode
    }

    private fun deliver(code: Int) { assertTrue(export.onResult(code, Activity.RESULT_OK, Intent().setData(uri))) }

    @Test fun actualDocumentProviderWritesAndVerifiesSummaryWithoutRawSecret() {
        val code = pick()
        deliver(code)
        deliver(code)
        until { replies.isNotEmpty() }
        assertEquals("exported", replies.single()["status"])
        assertTrue(provider.file.readText().contains("unverified"))
        assertFalse(provider.file.readText().contains("SYNTHETIC_SECRET"))
        assertEquals(0, provider.deleted)
        deliver(code)
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, provider.deleted)
    }

    @Test fun deletingSourceBeforePickRejectsExport() {
        val code = pick(args + ("kind" to "raw"))
        store.manage("delete", args, Long.MAX_VALUE)
        deliver(code)
        until { replies.isNotEmpty() }
        assertEquals("stale", replies.single()["status"])
        assertFalse(provider.file.exists())
        assertEquals(1, provider.deleted)
    }

    @Test fun explicitRawChoiceWritesExactPrivatePayloadWithSafeSummary() {
        deliver(pick(args + ("kind" to "raw")))
        until { replies.isNotEmpty() }
        assertEquals("exported", replies.single()["status"])
        java.util.zip.ZipInputStream(provider.file.inputStream()).use { zip ->
            assertEquals("summary.json", zip.nextEntry.name)
            assertFalse(zip.readBytes().toString(Charsets.UTF_8).contains("SYNTHETIC_SECRET"))
            assertEquals("raw.bin", zip.nextEntry.name)
            assertArrayEquals("SYNTHETIC_SECRET".toByteArray(), zip.readBytes())
        }
    }

    @Test fun pickerCancelAndCorruptSequenceDoNotProduceSuccessfulOutput() {
        val code = pick()
        export.onResult(code, Activity.RESULT_CANCELED, null)
        assertEquals("cancelled", replies.single()["status"])
        assertFalse(provider.file.exists())
        replies.clear()
        File(context.noBackupFilesDir, "report_launch_sequence").writeText("bad")
        export.start(args, activity, replies::add)
        until { replies.isNotEmpty() }
        assertEquals("io", replies.single()["status"])
        assertNull(Shadows.shadowOf(activity).nextStartedActivityForResult)
    }

    @Test fun cancellationAndNewAdapterNeverReusePersistentCodeOrAcceptLateUriAsNewSelection() {
        val old = pick()
        export.cancel("another-owner")
        assertTrue(replies.isEmpty())
        export.cancel("first")
        assertEquals("cancelled", replies.single()["status"])
        export = adapter()
        replies.clear()
        val fresh = pick(args + ("nonce" to "second"))
        assertNotEquals(old, fresh)
        deliver(old)
        until { provider.deleted == 1 }
        assertTrue(replies.isEmpty())
        deliver(fresh)
        until { replies.isNotEmpty() }
        assertEquals("exported", replies.single()["status"])
    }

    @Test fun shortWriteIsNotSuccessAndReadbackDenialIsExplicitlyUnverified() {
        val shadow = Shadows.shadowOf(context.contentResolver)
        shadow.registerOutputStream(uri, object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, length: Int) { super.write(bytes, offset, maxOf(0, length - 1)) }
        })
        shadow.registerInputStream(uri, ByteArrayInputStream(byteArrayOf()))
        deliver(pick())
        until { replies.isNotEmpty() }
        assertEquals("integrity", replies.single()["status"])
        assertEquals(1, provider.deleted)
    }

    @Test fun providerDenyingReadbackReportsWrittenUnverified() {
        provider.denyRead = true
        deliver(pick())
        until { replies.isNotEmpty() }
        assertEquals("written_unverified", replies.single()["status"])
        assertTrue(provider.file.exists())
    }

    @Test fun nullDescriptorAndWriteFailureAreNotSuccessful() {
        provider.nullWrite = true
        deliver(pick())
        until { replies.isNotEmpty() }
        assertEquals("io", replies.single()["status"])
        assertEquals(1, provider.deleted)
    }

    @Test fun writeFlushCloseAndDeadlineFailuresKeepFailureSemantics() {
        val shadow = Shadows.shadowOf(context.contentResolver)
        for (phase in listOf("write", "flush", "close", "deadline")) {
            replies.clear()
            val now = java.util.concurrent.atomic.AtomicLong(SystemClock.elapsedRealtime())
            export = adapter(now::get)
            shadow.registerOutputStream(uri, object : ByteArrayOutputStream() {
                override fun write(bytes: ByteArray, offset: Int, length: Int) {
                    if (phase == "write") throw java.io.IOException()
                    super.write(bytes, offset, length)
                    if (phase == "deadline") now.addAndGet(2000)
                }
                override fun flush() { if (phase == "flush") throw java.io.IOException() }
                override fun close() { if (phase == "close") throw java.io.IOException() }
            })
            deliver(pick())
            until { replies.isNotEmpty() }
            assertEquals(if (phase == "deadline") "deadline" else "io", replies.single()["status"])
        }
        assertTrue(provider.deleted >= 4)
    }

    @Test fun pendingPickerIsBoundedAndTimerRevokesItsOwnership() {
        val code = pick()
        val rejected = mutableListOf<Map<String, Any?>>()
        export.start(args + ("nonce" to "other"), activity, rejected::add)
        assertEquals("busy", rejected.single()["status"])
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMinutes(5))
        assertEquals("cancelled", replies.single()["status"])
        deliver(code)
        until { provider.deleted > 0 }
        assertFalse(provider.file.exists())
    }

    @Test fun blockedWriteCancellationHoldsWorkerAndQueueRemainsBounded() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        Shadows.shadowOf(context.contentResolver).registerOutputStream(uri, object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                entered.countDown()
                assertTrue(release.await(8, TimeUnit.SECONDS))
                super.write(bytes, offset, length)
            }
        })
        deliver(pick())
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        export.cancel()
        assertEquals("cancelled", replies.single()["status"])
        try {
            val waiting = (1..4).map { worker.submit { "ready" } }
            assertEquals("busy", worker.submit { "unexpected" }.get())
            assertTrue(waiting.all { !it.isDone })
        } finally { release.countDown() }
        until { provider.deleted > 0 }
        assertFalse(provider.file.exists())
        assertEquals(1, replies.size)
    }

    @Test fun writePhaseCallerTimeoutDoesNotFreeThePhysicalWorkerSlot() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        Shadows.shadowOf(context.contentResolver).registerOutputStream(uri, object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                entered.countDown()
                assertTrue(release.await(8, TimeUnit.SECONDS))
                super.write(bytes, offset, length)
            }
        })
        deliver(pick())
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(2))
        assertEquals("deadline", replies.single()["status"])
        try {
            val waiting = (1..4).map { worker.submit { "ready" } }
            assertEquals("busy", worker.submit { "unexpected" }.get())
            assertTrue(waiting.all { !it.isDone })
        } finally { release.countDown() }
        until { provider.deleted > 0 }
        assertEquals(1, replies.size)
    }
}

class ReportDocumentProvider : DocumentsProvider() {
    lateinit var file: File
    var deleted = 0
    var denyRead = false
    var nullWrite = false
    override fun onCreate(): Boolean {
        file = File(context!!.cacheDir, "synthetic-report-destination")
        return true
    }
    override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(arrayOf("root_id"))
    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor = MatrixCursor(arrayOf("document_id"))
    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor = MatrixCursor(arrayOf("document_id"))
    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor? {
        if (mode == "r" && denyRead) throw FileNotFoundException()
        if (mode != "r" && nullWrite) return null
        return ParcelFileDescriptor.open(file, if (mode == "r") ParcelFileDescriptor.MODE_READ_ONLY else
            ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE or ParcelFileDescriptor.MODE_WRITE_ONLY)
    }
    override fun deleteDocument(documentId: String) { deleted++; file.delete() }
}
