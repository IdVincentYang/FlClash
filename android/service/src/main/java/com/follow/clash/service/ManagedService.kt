package com.follow.clash.service

import android.app.Service
import com.follow.clash.common.BroadcastAction
import com.follow.clash.common.GlobalState
import com.follow.clash.common.sendBroadcast
import com.follow.clash.common.RequestServiceIdentity

interface ManagedService {
    val requestIdentity: RequestServiceIdentity

    fun attachRequest(requestId: Long)
    fun start()

    fun stop()
}

internal fun Service.notifyVpnStartRequested() {
    GlobalState.log("VPN start requested")
    BroadcastAction.VPN_START_REQUESTED.sendBroadcast()
}

internal fun Service.notifyVpnRevoked() {
    GlobalState.log("VPN permission revoked")
    BroadcastAction.VPN_REVOKED.sendBroadcast()
}
