package com.follow.clash

import android.app.Application
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.common.RequestNetworkSource
import java.net.InetAddress
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowNetworkCapabilities
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class RequestNetworkSourceTest {
    private fun callback(source: RequestNetworkSource, name: String): ConnectivityManager.NetworkCallback =
        RequestNetworkSource::class.java.getDeclaredField(name).apply { isAccessible = true }.get(source) as ConnectivityManager.NetworkCallback

    private fun links(dns: String): LinkProperties = LinkProperties().apply {
        ReflectionHelpers.callInstanceMethod<Any>(this, "setDnsServers", ClassParameter.from(Collection::class.java, listOf(InetAddress.getByName(dns))))
    }

    @Test fun `duplicate callbacks and bandwidth changes retain request network revision`() {
        val facts = mutableListOf<RequestNetworkFacts>()
        val source = RequestNetworkSource(RuntimeEnvironment.getApplication(), facts::add)
        source.start()
        try {
            val physical = callback(source, "physicalCallback")
            val default = callback(source, "defaultCallback")
            val wifi = ShadowNetwork.newInstance(101)
            val vpn = ShadowNetwork.newInstance(102)
            val wifiCaps = ShadowNetworkCapabilities.newInstance().apply {
                shadowOf(this).addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            }
            val vpnCaps = ShadowNetworkCapabilities.newInstance().apply {
                shadowOf(this).addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                shadowOf(this).removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                shadowOf(this).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }
            val links = links("192.0.2.53")
            physical.onAvailable(wifi)
            physical.onCapabilitiesChanged(wifi, wifiCaps)
            physical.onLinkPropertiesChanged(wifi, links)
            physical.onBlockedStatusChanged(wifi, false)
            default.onAvailable(vpn)
            default.onCapabilitiesChanged(vpn, vpnCaps)
            default.onBlockedStatusChanged(vpn, false)
            val stable = facts.last()
            val publications = facts.size
            repeat(5) { index ->
                shadowOf(wifiCaps).setLinkDownstreamBandwidthKbps(1000 + index)
                shadowOf(vpnCaps).setLinkDownstreamBandwidthKbps(1000 + index)
                physical.onCapabilitiesChanged(wifi, wifiCaps)
                default.onCapabilitiesChanged(vpn, vpnCaps)
                physical.onLinkPropertiesChanged(wifi, links)
                physical.onBlockedStatusChanged(wifi, false)
                default.onBlockedStatusChanged(vpn, false)
            }
            assertEquals(publications, facts.size)
            assertEquals(stable, source.selection().facts)
            physical.onLinkPropertiesChanged(wifi, links("192.0.2.54"))
            assertTrue(facts.last().revision > stable.revision)
            val dnsRevision = facts.last().revision
            physical.onBlockedStatusChanged(wifi, true)
            assertTrue(facts.last().revision > dnsRevision)
            assertEquals("", facts.last().directNetworkId)
            default.onLost(vpn)
            assertEquals("unknown", facts.last().defaultNetworkKind)
        } finally {
            source.close()
        }
    }

    @Test fun `restart publishes a fresh observation even with no available network`() {
        val facts = mutableListOf<RequestNetworkFacts>()
        val source = RequestNetworkSource(RuntimeEnvironment.getApplication(), facts::add)
        source.start()
        source.close()
        val closed = facts.last().revision
        source.start()
        try {
            assertTrue(facts.last().revision > closed)
            assertEquals("unknown", facts.last().defaultNetworkKind)
        } finally {
            source.close()
        }
    }
}
