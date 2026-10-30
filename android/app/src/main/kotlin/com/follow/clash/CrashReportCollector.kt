package com.follow.clash

import java.io.InputStream
import java.util.Collections
import java.util.IdentityHashMap
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal data class CrashExit(
    val process: String, val pid: Int, val timestamp: Long, val reason: Int, val status: Int,
    val summary: ByteArray? = null, val trace: () -> InputStream? = { null },
)

internal class CrashReportCollector(
    private val store: () -> CrashReportStore,
    private val worker: CrashReportWorker,
    private val identity: () -> Map<String, Any?>,
    private val clock: () -> Long,
) {
    private val live = linkedSetOf<String>()

    fun error(source: String, raw: ByteArray, truncated: Boolean): CompletableFuture<String> {
        if (source !in setOf("flutter", "zone", "startup") || raw.size > CrashReportStore.ERROR_LIMIT)
            return CompletableFuture.completedFuture("invalid")
        return worker.submit { deadline -> saveError(source, raw, truncated, deadline) }
    }

    fun java(error: Throwable): CompletableFuture<String> = worker.submit { deadline ->
        val raw = format(error)
        saveError("java_uncaught", raw, raw.size >= CrashReportStore.ERROR_LIMIT, deadline)
    }

    private fun saveError(source: String, raw: ByteArray, truncated: Boolean, deadline: Long): String {
        val context = identity()
        val id = CrashReportStore.digest((context["processEpoch"].toString() + "\u0000" + source + "\u0000").toByteArray() + raw)
        if (id in live) return "duplicate"
        val status = store().save(CrashMaterial(id, source, context,
            mapOf("fatal" to (source == "java_uncaught")), raw, "utf8_exception", truncated), deadline)
        if (status in setOf("stored", "duplicate")) {
            live.add(id)
            if (live.size > 64) live.remove(live.first())
        }
        return status
    }

    fun import(exits: List<CrashExit>, packageName: String, observerApi: Int): CompletableFuture<String> {
        val result = CompletableFuture<String>()
        val deadline = clock() + 4000
        val candidates = exits.filter { it.process == packageName }.take(8)
        var index = 0
        var bytes = 0
        fun next() {
            if (index >= candidates.size || clock() >= deadline || bytes >= 4 * CrashReportStore.RAW_LIMIT) {
                result.complete("finished"); return
            }
            val exit = candidates[index++]
            worker.submit(minOf(1500, deadline - clock())) { itemDeadline ->
                val id = CrashReportStore.digest(listOf(packageName, exit.process, exit.pid, exit.timestamp, exit.reason, exit.status).joinToString("\u0000").toByteArray())
                if (store().savedSystem(id)) return@submit "duplicate"
                val limit = minOf(CrashReportStore.RAW_LIMIT, 4 * CrashReportStore.RAW_LIMIT - bytes)
                var traceStatus = "unavailable"
                val raw = try {
                    exit.trace()?.use { stream ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (out.size() < limit && clock() < itemDeadline) {
                            val n = stream.read(buffer, 0, minOf(buffer.size, limit - out.size()))
                            if (n < 0) break
                            if (n == 0) throw java.io.IOException("empty read")
                            out.write(buffer, 0, n)
                        }
                        out.toByteArray().takeIf { it.isNotEmpty() }?.also {
                            traceStatus = if (it.size >= limit) "truncated" else "available"
                        } ?: run { traceStatus = "empty"; null }
                    }
                } catch (_: Exception) { traceStatus = "io"; null }
                bytes += raw?.size ?: 0
                val diagnostic = exit.reason in setOf(0, 2, 3, 4, 5, 6, 7, 9, 12, 13, 14) || (exit.reason == 1 && exit.status != 0)
                if (!diagnostic && raw == null) return@submit "skipped"
                val original = CrashBuildIdentity.decode(exit.summary)
                val context = linkedMapOf<String, Any?>("package" to packageName, "processName" to exit.process,
                    "pid" to exit.pid, "buildStatus" to "unknown_previous_process") + original
                store().save(CrashMaterial(id, "system_exit", context,
                    mapOf("timestamp" to exit.timestamp, "reason" to exit.reason, "status" to exit.status,
                        "observerApi" to observerApi, "traceStatus" to traceStatus), raw,
                    if (raw == null) "none" else if (exit.reason == 5 && observerApi >= 31) "native_protobuf" else "system_trace",
                    traceStatus == "truncated", system = true), itemDeadline)
            }.whenComplete { status, _ ->
                if (status in setOf("busy", "io", "deadline")) result.complete(status) else next()
            }
        }
        next()
        return result
    }

    companion object {
        fun format(error: Throwable): ByteArray {
            val text = StringBuilder()
            val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
            var current: Throwable? = error
            repeat(4) {
                val value = current ?: return@repeat
                if (!seen.add(value)) return@repeat
                text.append(value.javaClass.name.take(128)).append(": ").append(value.message?.take(4096)).append('\n')
                value.stackTrace.take(48).forEach { frame -> text.append(" at ").append(frame.toString().take(512)).append('\n') }
                current = value.cause
            }
            return text.toString().toByteArray(Charsets.UTF_8).let { if (it.size <= CrashReportStore.ERROR_LIMIT) it else it.copyOf(CrashReportStore.ERROR_LIMIT) }
        }
    }
}

internal class CrashUncaughtHandler(
    private val previous: Thread.UncaughtExceptionHandler,
    private val capture: (Throwable) -> CompletableFuture<String>,
) : Thread.UncaughtExceptionHandler {
    private val entered = AtomicBoolean()
    override fun uncaughtException(thread: Thread, error: Throwable) {
        val started = System.nanoTime()
        try {
            if (entered.compareAndSet(false, true)) {
                val pending = capture(error)
                val remaining = 250_000_000L - (System.nanoTime() - started)
                if (remaining > 0) pending.get(remaining, TimeUnit.NANOSECONDS)
            }
        } catch (_: Throwable) {
        } finally {
            previous.uncaughtException(thread, error)
        }
    }
}
