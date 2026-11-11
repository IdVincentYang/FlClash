package com.follow.clash.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import com.google.gson.JsonParser

class UidPackageResolverTest {
    @Test
    fun `only a unique package is known`() {
        val resolver = UidPackageResolver({ true }) { arrayOf("test.app", "", "test.app") }
        assertEquals(UidPackageIdentity("known", "current", listOf("test.app")), resolver.resolve(10001))
    }

    @Test
    fun `shared uid retains candidates without picking an owner`() {
        val resolver = UidPackageResolver({ true }) { arrayOf("test.b", "test.a") }
        assertEquals(UidPackageIdentity("ambiguous", "current", listOf("test.a", "test.b")), resolver.resolve(10001))
    }

    @Test
    fun `other android users never resolve against current user packages`() {
        var queried = false
        val resolver = UidPackageResolver({ false }) { queried = true; arrayOf("wrong.app") }
        assertEquals(UidPackageIdentity("otherUser", "other"), resolver.resolve(1010001))
        assertFalse(queried)
    }

    @Test
    fun `uid remapping and previously missing packages are read afresh`() {
        var packages: Array<String>? = arrayOf("test.old")
        val resolver = UidPackageResolver({ true }) { packages }
        assertEquals(listOf("test.old"), resolver.resolve(10001).packages)
        packages = null
        assertEquals("notFound", resolver.resolve(10001).status)
        packages = arrayOf("test.new")
        assertEquals(listOf("test.new"), resolver.resolve(10001).packages)
    }

    @Test
    fun `invalid uid and lookup failure have explicit unknown results`() {
        val resolver = UidPackageResolver({ true }) { throw SecurityException() }
        assertEquals("unknown", resolver.resolve(-1).status)
        assertEquals("lookupFailed", resolver.resolve(10001).status)
    }

    @Test
    fun `jni payload preserves ambiguity and bounds candidate size`() {
        val resolver = UidPackageResolver({ true }) { Array(80) { "test.app$it" } }
        val result = resolver.resolve(10001)
        assertEquals("ambiguous", result.status)
        assertEquals(64, result.packages.size)
        assertFalse(result.toJson().contains("packageName"))
        val payload = JsonParser.parseString(result.toJson()).asJsonObject
        assertEquals(setOf("status", "userScope", "packages"), payload.keySet())
        assertEquals("ambiguous", payload.get("status").asString)
        assertEquals("current", payload.get("userScope").asString)
        assertEquals(64, payload.getAsJsonArray("packages").size())
    }
}
