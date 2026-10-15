package com.follow.clash.service.modules

import android.app.Service
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core

internal class NetworkObserveModule(private val service: Service) : ServiceModule {
    private val gate = Any()
    private var active = false
    private var unsubscribe: (() -> Unit)? = null

    override fun start() = synchronized(gate) {
        if (active) return@synchronized
        active = true
        unsubscribe = GlobalState.networkSource?.subscribeDns { dns ->
            synchronized(gate) {
                if (active) Core.updateDNS(dns.joinToString(","))
            }
        }
    }

    override fun stop() = synchronized(gate) {
        active = false
        unsubscribe?.invoke()
        unsubscribe = null
        Core.updateDNS("")
    }
}
