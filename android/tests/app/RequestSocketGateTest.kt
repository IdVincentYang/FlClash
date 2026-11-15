package com.follow.clash

import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.RequestNetworkFacts
import com.google.gson.Gson
import org.junit.Assert.*
import org.junit.Test

class RequestSocketGateTest {
    private class Access(kind: String = "nonVpn", phase: String = "none", physical: String = "physical") : RequestSocketAccess {
        var state = ApplicationRequestState("synthetic", revision = 1, networkSourceEpoch = "source", networkRevision = 1,
            directNetworkId = physical, defaultNetworkId = "default", defaultNetworkKind = kind, protectPhase = phase)
        override val selection = RequestNetworkFacts("source", 1, kind, "default", physical, true)
        var current = true
        var own = true
        var protected = true
        var bindFailure = false
        var protections = 0
        var bindings = 0
        var boundPhysical: Boolean? = null
        var afterProtect: () -> Unit = {}
        var afterBind: () -> Unit = {}
        override fun currentState() = state
        override fun networkInput() = selection
        override fun isSelectionCurrent() = current
        override fun ownsDefaultVpn() = own
        override fun protect(fd: Int, expected: ApplicationRequestState): Boolean { protections++; afterProtect(); return protected }
        override fun bind(fd: Int, bypassVpn: Boolean) { bindings++; boundPhysical = bypassVpn; if (bindFailure) error("synthetic bind failure"); afterBind() }
    }

    @Test fun `system network binds and own vpn protects before physical binding`() {
        for ((kind, phase) in listOf("nonVpn" to "none", "vpn" to "ready")) {
            val access = Access(kind, phase)
            assertTrue(prepareRequestSocket(access, access.state, 42))
            assertEquals(1, access.bindings)
            assertEquals(if (phase == "ready") 1 else 0, access.protections)
            assertEquals(phase == "ready", access.boundPhysical)
        }
    }

    @Test fun `external vpn uses default network without protection or physical network`() {
        val access = Access("vpn", "none", physical = "").apply { own = false }
        assertTrue(prepareRequestSocket(access, access.state, 42))
        assertEquals(false, access.boundPhysical)
        assertEquals(0, access.protections)
        assertEquals(1, access.bindings)
    }

    @Test fun `wire snapshot preserves empty and active capture fingerprints`() {
        val gson = Gson()
        for (fingerprint in listOf("", "synthetic-capture")) {
            val access = Access().apply { state = state.copy(captureFingerprint = fingerprint) }
            val wire = gson.toJsonTree(access.state).asJsonObject
            assertTrue(prepareRequestSocket(access, gson.fromJson(wire, ApplicationRequestState::class.java), 42))
            wire.remove("captureFingerprint")
            assertFalse(prepareRequestSocket(access, gson.fromJson(wire, ApplicationRequestState::class.java), 42))
            assertEquals(1, access.bindings)
        }
    }

    @Test fun `unknown transitional and mismatched protection states never bind`() {
        for ((kind, phase) in listOf("unknown" to "none", "vpn" to "starting", "vpn" to "retiring")) {
            val access = Access(kind, phase)
            assertFalse(prepareRequestSocket(access, access.state, 42))
            assertEquals(0, access.bindings)
        }
        val foreign = Access("vpn", "ready").apply { own = false }
        assertFalse(prepareRequestSocket(foreign, foreign.state, 42))
        assertEquals(0, foreign.protections)
    }

    @Test fun `failed protection and stale identity never bind`() {
        val failed = Access("vpn", "ready").apply { protected = false }
        assertFalse(prepareRequestSocket(failed, failed.state, 42))
        assertEquals(0, failed.bindings)
        val stale = Access()
        val expected = stale.state
        stale.state = expected.copy(revision = 2)
        assertFalse(prepareRequestSocket(stale, expected, 42))
        assertEquals(0, stale.bindings)
    }

    @Test fun `protection and bind boundaries recheck native and network versions`() {
        val protection = Access("vpn", "ready")
        val expected = protection.state
        protection.afterProtect = { protection.state = expected.copy(revision = 2) }
        assertFalse(prepareRequestSocket(protection, expected, 42))
        assertEquals(0, protection.bindings)
        val binding = Access().apply { afterBind = { current = false } }
        assertFalse(prepareRequestSocket(binding, binding.state, 42))
        val failure = Access().apply { bindFailure = true }
        assertFalse(prepareRequestSocket(failure, failure.state, 42))
    }
}
