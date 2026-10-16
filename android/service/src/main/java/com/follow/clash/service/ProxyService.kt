package com.follow.clash.service

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import com.follow.clash.core.Core
import com.follow.clash.service.modules.ServiceModules
import com.follow.clash.common.RequestServiceIdentity
import com.follow.clash.common.RequestObservations
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class ProxyService : Service(), ManagedService {
    private val modules = ServiceModules(this)
    private val binder = LocalBinder()
    private val requestLock = ReentrantLock()
    @Volatile private var destroyed = false
    @Volatile override var requestIdentity = RequestServiceIdentity(UUID.randomUUID().toString(), 0)
        private set

    override fun attachRequest(requestId: Long) = requestLock.withLock {
        check(!destroyed) { "Service instance was destroyed" }
        requestIdentity = requestIdentity.copy(requestId = requestId)
    }

    override fun onDestroy() {
        destroyed = true
        val identity = requestIdentity
        RequestObservations.handler?.onServiceLost(identity.serviceId, identity.requestId)
        try {
            cleanup()
        } finally {
            super.onDestroy()
        }
    }

    override fun onLowMemory() {
        Core.forceGC()
        super.onLowMemory()
    }

    inner class LocalBinder : Binder() {
        val service: ProxyService
            get() = this@ProxyService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun start() = requestLock.withLock {
        check(!destroyed) { "Service instance was destroyed" }
        try {
            modules.start()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    override fun stopOwned(expected: RequestServiceIdentity): Boolean = requestLock.withLock {
        if (requestIdentity != expected) return@withLock false
        if (destroyed) return@withLock true
        stop()
        true
    }

    override fun stop() {
        try {
            cleanup()
        } finally {
            stopSelf()
        }
    }

    private fun cleanup() = modules.stop()
}
