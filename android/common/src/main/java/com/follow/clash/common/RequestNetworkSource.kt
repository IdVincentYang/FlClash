package com.follow.clash.common

import android.app.Application
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.getSystemService
import java.net.Inet6Address
import java.net.InetAddress
import java.util.UUID

class RequestNetworkSource(
    application: Application,
    private val onFacts: (RequestNetworkFacts) -> Unit,
) {
    data class Capabilities(
        val vpn: Boolean,
        val notVpn: Boolean,
        val internet: Boolean,
        val priority: Int,
        val ownerUid: Int?,
    )

    data class Selection(
        val facts: RequestNetworkFacts,
        val network: Network?,
        val defaultCapabilities: Capabilities?,
        val defaultNetwork: Network?,
    )

    private data class Entry(
        val capabilities: Capabilities? = null,
        val dns: List<InetAddress> = emptyList(),
        val blocked: Boolean? = null,
        val losingUntilMillis: Long = 0,
    )

    private val connectivity = application.getSystemService<ConnectivityManager>()
    private val handler = Handler(Looper.getMainLooper())
    private val gate = Any()
    private val sourceEpoch = UUID.randomUUID().toString()
    private val entries = mutableMapOf<Network, Entry>()
    private val dnsObservers = mutableMapOf<Any, (List<String>) -> Unit>()
    private var active = false
    private var physicalRegistered = false
    private var defaultRegistered = false
    private var revision = 0L
    private var defaultNetwork: Network? = null
    private var defaultEntry = Entry()
    private var lastDns = emptyList<String>()
    private val dnsTask = Runnable(::publishDns)

    private fun capabilities(value: NetworkCapabilities): Capabilities = Capabilities(
        vpn = value.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
        notVpn = value.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN),
        internet = value.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
        priority = when {
            value.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
            value.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && value.hasTransport(NetworkCapabilities.TRANSPORT_USB) -> 2
            value.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> 3
            value.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM && value.hasTransport(NetworkCapabilities.TRANSPORT_SATELLITE) -> 5
            else -> 20
        },
        ownerUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && value.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) value.ownerUid else null,
    )

    private fun change(action: () -> Unit) {
        val facts = synchronized(gate) {
            if (!active) return
            action()
            revision++
            selectionLocked().facts
        }
        onFacts(facts)
        handler.removeCallbacks(dnsTask)
        handler.postDelayed(dnsTask, 200)
    }

    private val physicalCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = change { entries[network] = Entry() }
        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) = change {
            entries[network]?.let { entries[network] = it.copy(capabilities = capabilities(networkCapabilities)) }
        }
        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) = change {
            entries[network]?.let { entries[network] = it.copy(dns = linkProperties.dnsServers.toList()) }
        }
        override fun onBlockedStatusChanged(network: Network, blocked: Boolean) = change {
            entries[network]?.let { entries[network] = it.copy(blocked = blocked) }
        }
        override fun onLosing(network: Network, maxMsToLive: Int) {
            change { entries[network]?.let { entries[network] = it.copy(losingUntilMillis = System.currentTimeMillis() + maxMsToLive) } }
            if (maxMsToLive > 0) handler.postDelayed({ change {} }, maxMsToLive.toLong() + 50)
        }
        override fun onLost(network: Network) = change { entries.remove(network) }
    }

    private val defaultCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = change { defaultNetwork = network; defaultEntry = Entry() }
        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) = change {
            if (defaultNetwork == network) defaultEntry = defaultEntry.copy(capabilities = capabilities(networkCapabilities))
        }
        override fun onBlockedStatusChanged(network: Network, blocked: Boolean) = change {
            if (defaultNetwork == network) defaultEntry = defaultEntry.copy(blocked = blocked)
        }
        override fun onLost(network: Network) = change { if (defaultNetwork == network) { defaultNetwork = null; defaultEntry = Entry() } }
    }

    fun start() {
        synchronized(gate) { if (active) return; active = true }
        change {}
        val manager = connectivity ?: return
        try {
            val request = NetworkRequest.Builder().apply {
                addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) addCapability(NetworkCapabilities.NET_CAPABILITY_FOREGROUND)
            }.build()
            manager.registerNetworkCallback(request, physicalCallback)
            physicalRegistered = true
            manager.registerDefaultNetworkCallback(defaultCallback)
            defaultRegistered = true
        } catch (_: Exception) {
            close()
        }
    }

    private fun eligible(entry: Entry): Boolean {
        val caps = entry.capabilities ?: return false
        if (!caps.notVpn || caps.vpn || !caps.internet || entry.blocked == true) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || entry.blocked != null
    }

    private fun preferredLocked(): Map.Entry<Network, Entry>? = entries.entries.filter { eligible(it.value) }.minByOrNull {
        (it.value.capabilities?.priority ?: 100) + if (it.value.losingUntilMillis > System.currentTimeMillis()) 10 else 0
    }

    private fun identity(network: Network?): String = network?.let { "$sourceEpoch:${it.networkHandle}" }.orEmpty()

    private fun selectionLocked(): Selection {
        val caps = defaultEntry.capabilities
        val defaultKnown = active && defaultNetwork != null && caps != null && defaultEntry.blocked != true &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || defaultEntry.blocked != null)
        val kind = when {
            !defaultKnown -> "unknown"
            caps?.notVpn == true && !caps.vpn -> "nonVpn"
            caps?.vpn == true && !caps.notVpn -> "vpn"
            else -> "unknown"
        }
        val selected = when (kind) {
            "nonVpn" -> defaultNetwork?.takeIf { entries[it]?.let(::eligible) == true }
            "vpn" -> preferredLocked()?.key
            else -> null
        }
        return Selection(
            facts = RequestNetworkFacts(sourceEpoch, revision, kind, identity(defaultNetwork), identity(selected), defaultEntry.blocked != null),
            network = selected,
            defaultCapabilities = caps,
            defaultNetwork = defaultNetwork,
        )
    }

    fun selection(): Selection = synchronized(gate) { selectionLocked() }

    val observing: Boolean
        get() = synchronized(gate) { active }

    fun isSystemSelectionCurrent(selection: Selection): Boolean = runCatching {
        val manager = connectivity ?: return@runCatching false
        val default = manager.activeNetwork ?: return@runCatching false
        if (default != selection.defaultNetwork) return@runCatching false
        val network = selection.network ?: return@runCatching false
        val currentDefault = manager.getNetworkCapabilities(default)?.let(::capabilities) ?: return@runCatching false
        val currentDirect = manager.getNetworkCapabilities(network)?.let(::capabilities) ?: return@runCatching false
        currentDefault == selection.defaultCapabilities && currentDirect.notVpn && !currentDirect.vpn && currentDirect.internet
    }.getOrDefault(false)

    fun subscribeDns(observer: (List<String>) -> Unit): () -> Unit {
        val key = Any()
        val current = synchronized(gate) { dnsObservers[key] = observer; lastDns }
        observer(current)
        return { synchronized(gate) { dnsObservers.remove(key) }; Unit }
    }

    private fun publishDns() {
        val publication = synchronized(gate) {
            if (!active) return
            val dns = preferredLocked()?.value?.dns.orEmpty().map { if (it is Inet6Address) "[${it.hostAddress}]:53" else "${it.hostAddress}:53" }.distinct()
            if (dns == lastDns) return
            lastDns = dns
            dns to dnsObservers.values.toList()
        }
        publication.second.forEach { it(publication.first) }
    }

    fun close() {
        val facts = synchronized(gate) {
            if (!active) return
            active = false
            entries.clear()
            defaultNetwork = null
            defaultEntry = Entry()
            revision++
            selectionLocked().facts
        }
        handler.removeCallbacksAndMessages(null)
        if (physicalRegistered) { runCatching { connectivity?.unregisterNetworkCallback(physicalCallback) }; physicalRegistered = false }
        if (defaultRegistered) { runCatching { connectivity?.unregisterNetworkCallback(defaultCallback) }; defaultRegistered = false }
        onFacts(facts)
        val observers = synchronized(gate) { lastDns = emptyList(); dnsObservers.values.toList() }
        observers.forEach { it(emptyList()) }
    }
}
