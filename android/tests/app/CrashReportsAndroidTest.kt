package com.follow.clash

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.pm.ProviderInfo
import android.os.Looper
import com.follow.clash.plugins.AppPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.follow.clash.service.FilesProvider
import com.follow.clash.core.Core
import com.follow.clash.core.RequestSocketInterface
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Implementation
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowApplicationExitInfo
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [30, 31], shadows = [ReportCoreShadow::class])
class CrashReportsAndroidTest {
    @Test @Config(sdk = [24, 31], shadows = [ReportCoreShadow::class, ReportOsShadow::class])
    fun realAppPluginManagesAndCancelsReportsThroughTheSharedCollectorStore() {
        val context = RuntimeEnvironment.getApplication()
        CrashReports.start(context)
        val plugin = AppPlugin()
        fun invoke(method: String, args: Map<String, Any?>): Map<*, *> {
            var result: Map<*, *>? = null
            plugin.onMethodCall(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(value: Any?) { result = value as? Map<*, *> ?: emptyMap<Any, Any>() }
                override fun error(code: String, message: String?, details: Any?) { throw AssertionError(code) }
                override fun notImplemented() { throw AssertionError(method) }
            })
            val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (result == null && System.nanoTime() < end) {
                Shadows.shadowOf(Looper.getMainLooper()).idle()
                Thread.sleep(5)
            }
            return result ?: throw AssertionError("no native reply")
        }
        assertEquals("stored", invoke("captureErrorReport", mapOf("source" to "startup", "raw" to "PRIVATE_MANAGEMENT_SECRET"))["status"])
        val inventory = invoke("manageReports", mapOf("action" to "inventory"))
        assertEquals("ready", inventory["status"])
        assertFalse(inventory.toString().contains("PRIVATE_MANAGEMENT_SECRET"))
        val row = (inventory["items"] as List<*>).single() as Map<*, *>
        val args = mapOf("revision" to inventory["revision"], "token" to row["token"])
        assertEquals("ready", invoke("manageReports", args + ("action" to "summary"))["status"])
        val adapter = CrashReportExport(context)
        ReflectionHelpers.setField(plugin, "reportExport", adapter)
        val activity = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().get()
        ReflectionHelpers.setField(plugin, "activity", activity)
        var exportStatus: String? = null
        plugin.onMethodCall(MethodCall("exportReport", args + mapOf("kind" to "summary", "nonce" to "owned")), object : MethodChannel.Result {
            override fun success(value: Any?) { exportStatus = (value as Map<*, *>)["status"] as String }
            override fun error(code: String, message: String?, details: Any?) { throw AssertionError(code) }
            override fun notImplemented() { throw AssertionError() }
        })
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        var launched = false
        while (!launched && exportStatus == null && System.nanoTime() < end) {
            Shadows.shadowOf(Looper.getMainLooper()).idle()
            launched = Shadows.shadowOf(activity).nextStartedActivityForResult != null
            Thread.sleep(5)
        }
        assertTrue(launched)
        plugin.onDetachedFromActivityForConfigChanges()
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        assertEquals("cancelled", exportStatus)
        assertEquals("deleted", invoke("manageReports", args + ("action" to "delete"))["status"])
        assertTrue((invoke("manageReports", mapOf("action" to "inventory"))["items"] as List<*>).isEmpty())
    }

    @After fun finishSyntheticProcess() {
        val collector = ReflectionHelpers.getStaticField<CrashReportCollector?>(CrashReports::class.java, "collector")
        if (collector != null) {
            val worker = ReflectionHelpers.getField<CrashReportWorker>(collector, "worker")
            worker.close()
            ReflectionHelpers.getField<java.util.concurrent.ThreadPoolExecutor>(worker, "executor").awaitTermination(5, TimeUnit.SECONDS)
        }
        ReflectionHelpers.setStaticField(CrashReports::class.java, "collector", null)
        val handler = Thread.getDefaultUncaughtExceptionHandler()
        if (handler is CrashUncaughtHandler) Thread.setDefaultUncaughtExceptionHandler(ReflectionHelpers.getField(handler, "previous"))
    }
    @Test @Config(application = FlClashApplication::class)
    fun actualApplicationHookAndPlatformSaveProduceReopenablePrivateReport() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val app = RuntimeEnvironment.getApplication()
        try {
            val done = CountDownLatch(1); var status: String? = null
            AppPlugin().onMethodCall(MethodCall("captureErrorReport", mapOf("source" to "startup", "raw" to "SYNTHETIC_PRIVATE_REPORT", "truncated" to false)),
                object : MethodChannel.Result {
                    override fun success(value: Any?) { status = (value as Map<*, *>)["status"] as String; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { status = "error"; done.countDown() }
                    override fun notImplemented() { status = "notImplemented"; done.countDown() }
                })
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (done.count > 0 && System.nanoTime() < until) {
                Shadows.shadowOf(Looper.getMainLooper()).idle()
                Thread.sleep(5)
            }
            assertEquals(0, done.count); assertEquals("stored", status)
            val root = File(app.noBackupFilesDir, "crash_reports").canonicalFile
            val store = CrashReportStore(root)
            val report = store.ids().map { store.read(it)!! }.single { it.metadata["source"].asString == "startup" }
            assertEquals("SYNTHETIC_PRIVATE_REPORT", String(report.raw!!))
            assertFalse(root.canonicalPath.startsWith(app.filesDir.canonicalPath + File.separator))
            assertFalse(report.metadata.toString().contains("SYNTHETIC_PRIVATE_REPORT"))
        } finally { Thread.setDefaultUncaughtExceptionHandler(previous) }
    }

    @Test @Config(sdk = [24])
    fun lowApiStillSavesDartWithoutCallingExitHistoryApi() {
        val context = RuntimeEnvironment.getApplication()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        try {
            CrashReports.start(context)
            val done = CountDownLatch(1); var status: String? = null
            CrashReports.capture(mapOf("source" to "flutter", "raw" to "synthetic low API")) {
                status = it["status"] as String; done.countDown()
            }
            assertTrue(done.await(5, TimeUnit.SECONDS)); assertEquals("stored", status)
            val store = CrashReportStore(File(context.noBackupFilesDir, "crash_reports").canonicalFile)
            assertTrue(store.ids().mapNotNull(store::read).any { it.metadata["source"].asString == "flutter" })
        } finally { Thread.setDefaultUncaughtExceptionHandler(previous) }
    }

    @Test fun systemSourceAndTraceAdapterUseHistoricalRecord() {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(ActivityManager::class.java)
        val info = ReflectionHelpers.callConstructor(ApplicationExitInfo::class.java)
        ReflectionHelpers.setField(info, "mProcessName", context.packageName)
        ReflectionHelpers.setField(info, "mPid", 123)
        ReflectionHelpers.setField(info, "mTimestamp", 456L)
        ReflectionHelpers.setField(info, "mReason", 6)
        Shadow.extract<ShadowApplicationExitInfo>(info).setTraceInputStream(ByteArrayInputStream("synthetic android trace".toByteArray()))
        Shadows.shadowOf(manager).addApplicationExitInfo(info)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        try {
            CrashReports.start(context)
            val root = File(context.noBackupFilesDir, "crash_reports").canonicalFile
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            var report: CrashReport? = null
            while (report == null && System.nanoTime() < until) {
                val store = CrashReportStore(root)
                report = store.ids().mapNotNull(store::read).firstOrNull { it.metadata["source"].asString == "system_exit" }
                if (report == null) Thread.sleep(10)
            }
            assertNotNull(report)
            assertEquals("synthetic android trace", String(report!!.raw!!))
            assertEquals(123, report.metadata.getAsJsonObject("identity")["pid"].asInt)
            assertFalse(report.metadata.getAsJsonObject("identity").has("api"))
        } finally { Thread.setDefaultUncaughtExceptionHandler(previous) }
    }

    @Test fun filesProviderCannotEnumerateOrOpenReportByDirectIdOrSymlink() {
        val context = RuntimeEnvironment.getApplication()
        val raw = File(context.noBackupFilesDir, "crash_reports/private/raw.bin")
        raw.parentFile!!.mkdirs(); raw.writeText("SYNTHETIC_PRIVATE_REPORT")
        val provider = FilesProvider()
        provider.attachInfo(context, ProviderInfo().apply {
            authority = context.packageName + ".synthetic"
            exported = true
            grantUriPermissions = true
            readPermission = "android.permission.MANAGE_DOCUMENTS"
            writePermission = "android.permission.MANAGE_DOCUMENTS"
        })
        provider.queryChildDocuments("/", null, null as String?).use { cursor ->
            while (cursor.moveToNext()) assertFalse(cursor.getString(0).contains("crash_reports"))
        }
        fun denied(id: String) {
            try { provider.openDocument(id, "r", null).close(); fail("private path opened") } catch (_: java.io.FileNotFoundException) { }
            try { provider.queryChildDocuments(id, null, null as String?).close(); fail("private directory enumerated") } catch (_: java.io.FileNotFoundException) { }
        }
        denied(raw.absolutePath)
        val link = File(context.filesDir, "report-link")
        Files.createSymbolicLink(link.toPath(), raw.parentFile!!.toPath())
        denied(File(link, "raw.bin").absolutePath)
    }

    @Test fun reportRootSymlinkCannotRedirectCaptureIntoBackupFiles() {
        val context = RuntimeEnvironment.getApplication()
        val target = File(context.filesDir, "synthetic-report-target").apply { mkdirs() }
        val link = File(context.noBackupFilesDir, "crash_reports")
        Files.createSymbolicLink(link.toPath(), target.toPath())
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        try {
            CrashReports.start(context)
            val done = CountDownLatch(1); var status: String? = null
            CrashReports.capture(mapOf("source" to "flutter", "raw" to "SYNTHETIC_PRIVATE_REPORT")) {
                status = it["status"] as String; done.countDown()
            }
            assertTrue(done.await(5, TimeUnit.SECONDS)); assertEquals("io", status)
            assertTrue(target.listFiles()!!.isEmpty())
        } finally { Thread.setDefaultUncaughtExceptionHandler(previous) }
    }
}

@Implements(Core::class)
class ReportCoreShadow {
    @Implementation fun setRequestSocketListener(callback: RequestSocketInterface?) {}
    @Implementation fun requestControl(data: String): String = "{\"ready\":true}"
    companion object {
        @JvmStatic @Implementation fun __staticInitializer__() {
            ReflectionHelpers.setStaticField(Core::class.java, "INSTANCE", ReflectionHelpers.callConstructor(Core::class.java))
        }
    }
}
