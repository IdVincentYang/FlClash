package com.follow.clash

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import android.util.AtomicFile
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FilterInputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

internal class CrashReportExport(
    private val context: Context,
    private val dispatch: ((CrashReportStore, Long) -> Map<String, Any?>, (Map<String, Any?>) -> Unit) -> Unit = CrashReports::enqueue,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) {
    private class Flight(val args: Map<*, *>, val reply: (Map<String, Any?>) -> Unit) {
        val revoked = AtomicBoolean(false)
        var code = -1
        var picking = false
        var replied = false
        var timeout: Runnable? = null
    }
    private val handler = Handler(Looper.getMainLooper())
    private var flight: Flight? = null
    private var lastResultCode = FIRST - 1

    fun start(args: Map<*, *>, activity: Activity?, reply: (Map<String, Any?>) -> Unit) {
        if (flight != null) { reply(mapOf("status" to "busy")); return }
        if (activity == null) { reply(mapOf("status" to "unavailable")); return }
        if (args["kind"] !in setOf("summary", "raw") || (args["nonce"] as? String)?.length?.let { it in 1..64 } != true) {
            reply(mapOf("status" to "invalid")); return
        }
        val current = Flight(args.toMap(), reply)
        flight = current
        watch(current, 2000, "deadline")
        dispatch({ store, deadline ->
            if (current.revoked.get()) throw ReportFailure("cancelled")
            val status = store.manage("summary", current.args, deadline)
            if (status["status"] != "ready") status else {
                val summary = status["summary"] as Map<*, *>
                if (current.args["kind"] == "raw" && summary["rawAvailable"] != true) throw ReportFailure("unavailable")
                if (current.revoked.get()) throw ReportFailure("cancelled")
                if (clock() >= deadline) throw ReportFailure("deadline")
                current.code = reserveCode()
                if (current.revoked.get()) throw ReportFailure("cancelled")
                if (clock() >= deadline) throw ReportFailure("deadline")
                mapOf("status" to "ready")
            }
        }) { value -> handler.post {
            if (flight !== current || current.revoked.get()) return@post
            if (value["status"] != "ready") { finish(current, value); return@post }
            try {
                val raw = current.args["kind"] == "raw"
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (raw) "application/zip" else "application/json"
                    putExtra(Intent.EXTRA_TITLE, if (raw) "crash-report.zip" else "crash-summary.json")
                }
                current.picking = true
                watch(current, 300_000, "cancelled")
                activity.startActivityForResult(intent, current.code)
            } catch (_: Exception) { finish(current, mapOf("status" to "unavailable")) }
        } }
    }

    fun cancel(nonce: Any? = null) {
        val current = flight ?: return
        if (nonce != null && nonce != current.args["nonce"]) return
        current.revoked.set(true)
        finish(current, mapOf("status" to "cancelled"))
    }

    fun onResult(code: Int, result: Int, data: Intent?): Boolean {
        if (code !in FIRST..LAST) return false
        if (code <= lastResultCode) return true
        lastResultCode = code
        val uri = data?.data?.takeIf { it.scheme == "content" }
        val current = flight
        if (current == null || current.code != code || !current.picking || current.revoked.get()) {
            uri?.let(::discard)
            return true
        }
        current.picking = false
        if (result != Activity.RESULT_OK || uri == null) {
            uri?.let(::discard)
            finish(current, mapOf("status" to if (result == Activity.RESULT_CANCELED) "cancelled" else "io"))
            return true
        }
        watch(current, 2000, "deadline")
        dispatch({ store, deadline ->
            try {
                fun guard() {
                    if (current.revoked.get()) throw ReportFailure("cancelled")
                    if (clock() >= deadline) throw ReportFailure("deadline")
                }
                guard()
                val bytes = store.export(current.args, deadline)
                guard()
                val output = context.contentResolver.openOutputStream(uri, "w") ?: throw IOException()
                output.use { stream ->
                    var offset = 0
                    while (offset < bytes.size) {
                        guard()
                        val count = minOf(8192, bytes.size - offset)
                        stream.write(bytes, offset, count)
                        offset += count
                    }
                    guard()
                    stream.flush()
                }
                guard()
                val input = try { context.contentResolver.openInputStream(uri) }
                    catch (_: FileNotFoundException) { null }
                    catch (_: SecurityException) { null }
                    catch (_: UnsupportedOperationException) { null }
                val status = if (input == null) "written_unverified" else input.use {
                    val checked = object : FilterInputStream(it) {
                        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                            guard()
                            return super.read(bytes, offset, length)
                        }
                    }
                    val observed = CrashBuildIdentity.prefix(checked, 2 * 1024 * 1024 + 1)
                    guard()
                    if (observed.size != bytes.size || CrashReportStore.digest(observed) != CrashReportStore.digest(bytes)) {
                        throw ReportFailure("integrity")
                    }
                    "exported"
                }
                guard()
                mapOf("status" to status)
            } catch (error: Throwable) {
                deleteDocument(uri)
                mapOf("status" to if (error is ReportFailure) error.status else "io")
            }
        }) { value -> handler.post {
            if (current.revoked.get() || value["status"] in setOf("busy", "deadline")) discard(uri)
            if (flight === current) finish(current, value)
        } }
        return true
    }

    private fun finish(current: Flight, value: Map<String, Any?>) {
        current.timeout?.let(handler::removeCallbacks)
        current.timeout = null
        if (flight === current) flight = null
        if (!current.replied) {
            current.replied = true
            current.reply(value)
        }
    }

    private fun watch(current: Flight, wait: Long, status: String) {
        current.timeout?.let(handler::removeCallbacks)
        current.timeout = Runnable {
            if (flight === current) {
                current.revoked.set(true)
                finish(current, mapOf("status" to status))
            }
        }
        handler.postDelayed(current.timeout!!, wait)
    }

    private fun discard(uri: Uri) {
        dispatch({ _, _ -> deleteDocument(uri); mapOf("status" to "cancelled") }) { }
    }

    private fun deleteDocument(uri: Uri) {
        runCatching { DocumentsContract.deleteDocument(context.contentResolver, uri) }
    }

    private fun reserveCode(): Int {
        val supplied = context.noBackupFilesDir.absoluteFile
        val directory = File(supplied.parentFile!!.canonicalFile, supplied.name)
        if (directory.canonicalFile != directory) throw IOException()
        val base = File(directory, "report_launch_sequence")
        if (listOf(base, File(base.path + ".bak"), File(base.path + ".new")).any {
                it.canonicalFile != it.absoluteFile
            }) throw IOException()
        val file = AtomicFile(base)
        val next = try {
            file.openRead().use { input -> DataInputStream(input).let { data ->
                val number = data.readLong()
                if (data.read() != -1) throw IOException()
                number
            } }
        } catch (error: FileNotFoundException) {
            if (listOf(base, File(base.path + ".bak"), File(base.path + ".new")).any { it.exists() }) throw error
            FIRST.toLong()
        }
        if (next !in FIRST.toLong()..LAST.toLong()) throw ReportFailure("unavailable")
        val stream = file.startWrite()
        try {
            DataOutputStream(stream).writeLong(next + 1)
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        } finally { stream.close() }
        if (file.openRead().use { DataInputStream(it).readLong() } != next + 1) throw IOException()
        return next.toInt()
    }

    companion object {
        const val FIRST = 0x6E000000
        const val LAST = 0x6EFFFFFF
    }
}
