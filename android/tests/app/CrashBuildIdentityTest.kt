package com.follow.clash

import org.junit.Assert.*
import org.junit.Test

class CrashBuildIdentityTest {
    @Test fun actualPackagedIdentityMatchesIndependentInspectionWhenArtifactProvided() {
        val fixture = System.getenv("FLCLASH_REPORT_IDENTITY_FIXTURE")
        org.junit.Assume.assumeNotNull(fixture)
        val expected = com.google.gson.Gson().fromJson(java.io.File(fixture!!).readText(), com.google.gson.JsonObject::class.java)
        val actual = CrashBuildIdentity.read(java.io.File(expected["apk"].asString), listOf("arm64-v8a"), true,
            System.nanoTime() / 1_000_000 + 2000, { System.nanoTime() / 1_000_000 })
        assertEquals(expected["sha256"].asString, actual["apkSha256"])
        assertEquals("arm64-v8a", actual["abi"])
        val ids = actual["buildIds"] as Map<*, *>
        val expectedIds = expected.getAsJsonObject("ids").entrySet().associate { it.key to it.value.asString }
        assertEquals(expectedIds, ids)
    }
    @Test fun oldProcessSummaryRoundTripsFullIdsWithoutUsingObserverIdentity() {
        val original = mapOf("versionCode" to 123L, "versionName" to "old", "api" to 30,
            "is64Bit" to true, "abi" to "arm64-v8a", "apkSha256" to "ab".repeat(32),
            "buildIds" to mapOf("libclash.so:gnu" to "cd".repeat(20), "libcore.so:gnu" to "ef".repeat(20),
                "librust_api.so:gnu" to "12".repeat(32), "libclash.so:go" to "g".repeat(83)))
        val encoded = CrashBuildIdentity.encode(original)
        assertTrue(encoded.size <= 128)
        val decoded = CrashBuildIdentity.decode(encoded)
        assertEquals(123L, decoded["versionCode"])
        assertEquals("ab".repeat(32), decoded["apkSha256"])
        val ids = decoded["buildIds"] as Map<*, *>
        assertEquals("cd".repeat(20), ids["libclash.so:gnu"])
        assertEquals("ef".repeat(20), ids["libcore.so:gnu"])
        assertFalse(ids.containsKey("librust_api.so:gnu"))
        assertFalse(ids.containsKey("libclash.so:go"))
    }

    @Test fun malformedFutureAndMissingSummaryAreUnknown() {
        for (value in listOf(null, byteArrayOf(), ByteArray(129), "FCR2".toByteArray(), byteArrayOf(0, 1, 2)))
            assertTrue(CrashBuildIdentity.decode(value).isEmpty())
    }

    @Test fun elfBoundsAndMissingNotesAreUnknown() {
        assertTrue(CrashBuildIdentity.notes(byteArrayOf()).isEmpty())
        assertTrue(CrashBuildIdentity.notes(ByteArray(256)).isEmpty())
        val bytes = ByteArray(256)
        val b = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        bytes[0] = 127; bytes[1] = 69; bytes[2] = 76; bytes[3] = 70; bytes[4] = 2; bytes[5] = 1
        b.putLong(32, 64); b.putShort(54, 56); b.putShort(56, 1)
        b.putInt(64, 4); b.putLong(72, 120); b.putLong(96, 36)
        b.putInt(120, 4); b.putInt(124, 20); b.putInt(128, 3)
        bytes[132] = 71; bytes[133] = 78; bytes[134] = 85
        for (i in 136..155) bytes[i] = 42
        assertEquals("2a".repeat(20), CrashBuildIdentity.notes(bytes)["gnu"])
        b.putLong(72, Long.MAX_VALUE)
        assertTrue(CrashBuildIdentity.notes(bytes).isEmpty())
    }

    @Test fun unrelatedAndroidNoteDoesNotHideFollowingGnuIdentity() {
        val bytes = ByteArray(512)
        val b = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        byteArrayOf(127, 69, 76, 70, 2, 1).copyInto(bytes)
        b.putLong(32, 64); b.putShort(54, 56); b.putShort(56, 1)
        b.putInt(64, 4); b.putLong(72, 120); b.putLong(96, 188)
        b.putInt(120, 8); b.putInt(124, 132); b.putInt(128, 1)
        "Android\u0000".toByteArray().copyInto(bytes, 132)
        b.putInt(272, 4); b.putInt(276, 20); b.putInt(280, 3)
        "GNU\u0000".toByteArray().copyInto(bytes, 284)
        for (i in 288..307) bytes[i] = 123
        assertEquals("7b".repeat(20), CrashBuildIdentity.notes(bytes)["gnu"])
    }
}
