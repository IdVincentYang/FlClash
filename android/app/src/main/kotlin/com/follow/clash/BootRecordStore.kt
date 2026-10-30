package com.follow.clash

import java.util.concurrent.Executor

internal interface BootRecordPersistence {
    fun read(): Any?
    fun commit(record: String): Boolean
}

internal class BootRecordStore(
    private val persistence: BootRecordPersistence,
    private val context: Map<String, Any?>,
    private val clock: () -> Long,
    private val worker: Executor,
    private val deliver: (() -> Unit) -> Unit,
) {
    private val gate = Any()
    private var generation = 0L
    private var attached = false
    private var begun = false
    private var revoked = false
    private var closed = false
    private var busy = false

    fun attach(): Long = synchronized(gate) {
        generation++
        attached = true
        begun = false
        revoked = false
        closed = false
        generation
    }

    fun detach(engine: Long) = synchronized(gate) {
        if (engine == generation) {
            attached = false
            revoked = true
        }
    }

    private fun current(engine: Long) = attached && engine == generation && !closed

    private fun token(engine: Long) = "${context["processEpoch"]}:$engine"

    private fun status(engine: Long): Map<String, Any?> = mapOf(
        "current" to current(engine),
        "writable" to (current(engine) && begun && !revoked),
        "busy" to busy,
        "attempt" to token(engine),
    )

    fun handle(
        engine: Long,
        action: String,
        arguments: Map<*, *>,
        reply: (Map<String, Any?>) -> Unit,
    ) {
        synchronized(gate) {
            when (action) {
                "status" -> return reply(status(engine) + ("status" to "ok"))
                "revoke" -> {
                    if (engine == generation) revoked = true
                    return reply(status(engine) + ("status" to "ok"))
                }
                "begin" -> {
                    if (!current(engine) || begun) return reply(status(engine) + ("status" to "stale"))
                    begun = true
                }
                "write", "close" -> {
                    if (!current(engine) || action == "write" &&
                        (!begun || revoked || arguments["attempt"] != token(engine))) {
                        return reply(status(engine) + ("status" to "stale"))
                    }
                    if (action == "close") {
                        closed = true
                        revoked = true
                    }
                }
                else -> return reply(mapOf("status" to "invalid"))
            }
            val raw = arguments["record"]
            if (action == "close" && raw == null) return reply(status(engine) + ("status" to "ok"))
            if (action != "begin" && (raw !is String || raw.toByteArray(Charsets.UTF_8).size > MAX_BYTES)) {
                revoked = true
                return reply(status(engine) + ("status" to "invalid"))
            }
            if (busy) {
                revoked = true
                return reply(status(engine) + context + ("status" to "busy"))
            }
            busy = true
        }
        val deadline = clock() + IO_BUDGET_MS
        worker.execute {
            val result = try {
                if (!valid(engine, action, deadline)) {
                    mapOf("status" to "stale")
                } else if (action == "begin") {
                    val raw = persistence.read()
                    if (raw != null && (raw !is String || raw.toByteArray(Charsets.UTF_8).size > MAX_BYTES)) {
                        mapOf("status" to "ok", "malformed" to true)
                    } else {
                        mapOf("status" to "ok", "record" to raw)
                    }
                } else {
                    mapOf("status" to if (persistence.commit(arguments["record"] as String)) "ok" else "io")
                }
            } catch (_: Exception) {
                mapOf("status" to "io")
            } finally {
                synchronized(gate) { busy = false }
            }
            deliver {
                synchronized(gate) {
                    val accepted = valid(engine, action, deadline)
                    if (engine == generation && (!accepted || result["status"] != "ok")) revoked = true
                    reply(status(engine) + context + if (accepted) result else mapOf("status" to "stale"))
                }
            }
        }
    }

    private fun valid(engine: Long, action: String, deadline: Long): Boolean = synchronized(gate) {
        attached && generation == engine && clock() <= deadline &&
            (if (action == "close") closed else !closed && !revoked)
    }

    companion object {
        const val MAX_BYTES = 8192
        const val IO_BUDGET_MS = 1500L
    }
}
