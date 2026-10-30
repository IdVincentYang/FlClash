package com.follow.clash

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.SystemClock
import java.io.File
import java.util.UUID

internal object CrashReports {
    @Volatile private var collector: CrashReportCollector? = null
    @Volatile private var identity: Map<String, Any?> = emptyMap()
    private var storage: Lazy<CrashReportStore>? = null
    private var io: CrashReportWorker? = null
    private val clock = SystemClock::elapsedRealtime

    @Synchronized fun start(context: Context) {
        if (collector != null || (context.applicationInfo.processName ?: context.packageName) != context.packageName) return
        identity = mapOf("package" to context.packageName, "processName" to context.packageName,
            "pid" to Process.myPid(), "processEpoch" to UUID.randomUUID().toString(),
            "api" to Build.VERSION.SDK_INT, "is64Bit" to Process.is64Bit(), "buildStatus" to "pending")
        val worker = CrashReportWorker(clock)
        val backend = lazy { CrashReportStore(reportRoot(context), clock = clock) }
        storage = backend
        io = worker
        val store by backend
        val capture = CrashReportCollector({ store }, worker, { identity }, clock)
        collector = capture
        Thread.getDefaultUncaughtExceptionHandler()?.let { previous ->
            Thread.setDefaultUncaughtExceptionHandler(CrashUncaughtHandler(previous, capture::java))
        }
        worker.submit(2000) { deadline ->
            @Suppress("DEPRECATION")
            val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
            identity = identity + mapOf("versionCode" to if (Build.VERSION.SDK_INT >= 28) pkg.longVersionCode else pkg.versionCode.toLong(),
                "versionName" to pkg.versionName)
            summary(context)
            val build = if (!context.applicationInfo.splitSourceDirs.isNullOrEmpty()) mapOf("buildStatus" to "split_unknown") else
                CrashBuildIdentity.read(File(context.applicationInfo.sourceDir), Build.SUPPORTED_ABIS.toList(), Process.is64Bit(), deadline, clock)
            identity = identity + build
            if (build["apkSha256"] != null) summary(context)
            "ready"
        }.whenComplete { _, _ ->
            worker.submit { deadline -> store.maintain(deadline) }.whenComplete { status, _ ->
                if (status == "ready" && Build.VERSION.SDK_INT >= 30) worker.submit { _ ->
                    val manager = context.getSystemService(ActivityManager::class.java)
                    val exits = manager?.getHistoricalProcessExitReasons(context.packageName, 0, 8).orEmpty()
                        .filter { it.processName == context.packageName }.map { exit ->
                            CrashExit(exit.processName, exit.pid, exit.timestamp, exit.reason, exit.status,
                                exit.processStateSummary, { exit.traceInputStream })
                        }
                    capture.import(exits, context.packageName, Build.VERSION.SDK_INT)
                    "scheduled"
                }
            }
        }
    }

    fun enqueue(task: (CrashReportStore, Long) -> Map<String, Any?>, reply: (Map<String, Any?>) -> Unit) {
        val worker = io
        val backend = storage
        if (collector == null || worker == null || backend == null) {
            reply(mapOf("status" to "unsupported")); return
        }
        worker.submitValue({ mapOf<String, Any?>("status" to it) }) { deadline ->
            try { task(backend.value, deadline) }
            catch (error: ReportFailure) { mapOf("status" to error.status) }
        }.whenComplete { value, _ -> reply(value ?: mapOf("status" to "io")) }
    }

    fun manage(arguments: Any?, reply: (Map<String, Any?>) -> Unit) {
        val values = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        enqueue({ store, deadline -> store.manage(values["action"] as? String ?: "", values, deadline) }, reply)
    }

    private fun summary(context: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        runCatching { context.getSystemService(ActivityManager::class.java)?.setProcessStateSummary(CrashBuildIdentity.encode(identity)) }
    }

    private fun reportRoot(context: Context): File {
        val supplied = context.noBackupFilesDir.absoluteFile
        val backup = File(supplied.parentFile!!.canonicalFile, supplied.name)
        check(backup == backup.canonicalFile)
        return File(backup, "crash_reports")
    }

    fun capture(arguments: Any?, reply: (Map<String, Any?>) -> Unit) {
        val values = arguments as? Map<*, *>
        val source = values?.get("source") as? String
        val text = values?.get("raw") as? String
        if (source !in setOf("flutter", "zone", "startup") || text == null || text.length > CrashReportStore.ERROR_LIMIT) {
            reply(mapOf("status" to "invalid")); return
        }
        val target = collector
        if (target == null) { reply(mapOf("status" to "unsupported")); return }
        target.error(source!!, text.toByteArray(Charsets.UTF_8), values["truncated"] == true)
            .whenComplete { status, _ -> reply(mapOf("status" to (status ?: "io"))) }
    }
}
