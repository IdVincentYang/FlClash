package com.follow.clash

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.os.Process
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.GlobalState
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.core.RequestSocketInterface
import com.google.gson.Gson

internal interface RequestSocketAccess {
    fun currentState(): ApplicationRequestState
    fun networkInput(): RequestNetworkFacts
    val selection: RequestNetworkFacts
    fun isSelectionCurrent(): Boolean
    fun ownsDefaultVpn(): Boolean
    fun protect(fd: Int, expected: ApplicationRequestState): Boolean
    fun bind(fd: Int)
}

internal fun prepareRequestSocket(access: RequestSocketAccess, expected: ApplicationRequestState, fd: Int): Boolean = runCatching {
    fun current(): Boolean = access.currentState() == expected && access.isSelectionCurrent()
    val input = access.networkInput()
    val selected = access.selection
    if (fd < 0 || expected.processEpoch.isEmpty() || !current() ||
        expected.protectPhase in setOf("starting", "retiring") || expected.reason == "exiting" ||
        selected.sourceEpoch != input.sourceEpoch || selected.revision != input.revision ||
        selected.sourceEpoch != expected.networkSourceEpoch || selected.revision != expected.networkRevision ||
        selected.directNetworkId != expected.directNetworkId || selected.defaultNetworkId != expected.defaultNetworkId ||
        expected.directNetworkId.isEmpty()
    ) return@runCatching false
    when (expected.defaultNetworkKind) {
        "nonVpn" -> Unit
        "vpn" -> if (expected.protectPhase != "ready" || !access.ownsDefaultVpn()) return@runCatching false
        else -> return@runCatching false
    }
    if (expected.protectPhase == "ready" && (!access.protect(fd, expected) || !current())) return@runCatching false
    access.bind(fd)
    current()
}.getOrDefault(false)

internal object AndroidRequestSocketGate : RequestSocketInterface {
    private val gson = Gson()

    override fun prepareSocket(state: String, fd: Int): Boolean = runCatching {
        val expected = gson.fromJson(state, ApplicationRequestState::class.java) ?: return@runCatching false
        val source = GlobalState.networkSource ?: return@runCatching false
        val selected = source.selection()
        val network = selected.network ?: return@runCatching false
        val protection = ServiceState.getProtection()
        prepareRequestSocket(object : RequestSocketAccess {
            override val selection = selected.facts
            override fun currentState() = ServiceState.getRequestState()
            override fun networkInput() = ServiceState.getNetworkInput()
            override fun isSelectionCurrent() = source.isSystemSelectionCurrent(selected) && source.selection().facts == selection
            override fun ownsDefaultVpn(): Boolean {
                val ownerUid = selected.defaultCapabilities?.ownerUid
                return protection != null && (ownerUid == null || ownerUid < 0 || ownerUid == Process.myUid())
            }
            override fun protect(fd: Int, expected: ApplicationRequestState): Boolean {
                val (service, identity) = protection ?: return false
                return identity.serviceId == expected.serviceId && identity.generation == expected.protectGeneration &&
                    VpnService.prepare(GlobalState.application) == null && service.isRequestLockdownEnabled() != true &&
                    service.protectRequestSocket(fd, identity)
            }
            override fun bind(fd: Int) {
                ParcelFileDescriptor.fromFd(fd).use { network.bindSocket(it.fileDescriptor) }
            }
        }, expected, fd)
    }.getOrDefault(false)
}
