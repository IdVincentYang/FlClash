package com.follow.clash.common

import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicLong

/**
 * Every request mints a fresh [Token]. Work that was started for an older token is obsolete once a
 * newer request arrives, so callers check [isCurrent] before applying a result and roll back with
 * [resetToStopped], which only wins while the token is still the latest one.
 */
class RunIntentArbiter(initialRunning: Boolean = false) {
    class Token internal constructor(
        val running: Boolean,
        val id: Long = 0,
    )

    private val latest = AtomicReference(Token(initialRunning))
    private val nextId = AtomicLong()

    val isRunningRequested: Boolean
        get() = latest.get().running

    fun current(): Token = latest.get()

    @Synchronized
    fun request(running: Boolean): Token = Token(running, nextId.incrementAndGet()).also(latest::set)

    fun isCurrent(token: Token): Boolean = latest.get() === token

    fun resetToStopped(token: Token): Boolean =
        latest.compareAndSet(token, Token(running = false, id = token.id))
}
