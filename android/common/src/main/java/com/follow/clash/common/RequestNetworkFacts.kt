package com.follow.clash.common

import androidx.annotation.Keep

data class RequestNetworkFacts(
    val sourceEpoch: String = "",
    val revision: Long = 0,
    val defaultNetworkKind: String = "unknown",
    val defaultNetworkId: String = "",
    val directNetworkId: String = "",
    val blockedKnown: Boolean = false,
)

@Keep
data class ApplicationRequestState(
    val processEpoch: String,
    val revision: Long = 0,
    val intentRevision: Long = 0,
    val intentRunning: Boolean = false,
    val paused: Boolean = false,
    val serviceId: String = "",
    val source: String = "bootstrap",
    val phase: String = "stopped",
    val reason: String = "none",
    val networkRevision: Long = 0,
    val networkSourceEpoch: String = "",
    val defaultNetworkKind: String = "unknown",
    val defaultNetworkId: String = "",
    val directNetworkId: String = "",
    val protectGeneration: Long = 0,
    val protectPhase: String = "none",
)

data class RequestServiceIdentity(val serviceId: String, val requestId: Long, val generation: Long = 0)

interface RequestProtection {
    val requestIdentity: RequestServiceIdentity
    fun protectRequestSocket(fd: Int, expected: RequestServiceIdentity): Boolean
    fun isRequestLockdownEnabled(): Boolean?
}

interface RequestObservationHandler {
    fun onNetworkChanged(facts: RequestNetworkFacts)
    fun onProtectionChanged(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String = "none"): Long
    fun onServiceLost(serviceId: String, requestId: Long)
    fun onVpnStartRequested(serviceId: String): Long
}

object RequestObservations {
    @Volatile var handler: RequestObservationHandler? = null
}
