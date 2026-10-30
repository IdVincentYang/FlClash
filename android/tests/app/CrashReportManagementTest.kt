package com.follow.clash

import android.app.Application
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipInputStream
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [24, 31], shadows = [ReportOsShadow::class])
class CrashReportManagementTest {
    private val base = Files.createTempDirectory("report-management").toFile().canonicalFile
    private val root = File(base, "reports")
    private var clock = 0L
    private val store = CrashReportStore(root, clock = { clock })
    private fun id(value: Int) = "%064x".format(value)
    private fun save(value: Int, system: Boolean = false) {
        assertEquals("stored", store.save(CrashMaterial(id(value), "system_exit", mapOf(
            "versionName" to "SECRET_VERSION", "versionCode" to 123, "api" to 24,
            "processEpoch" to "SECRET_NONCE", "path" to "SECRET_PATH", "abi" to "arm64-v8a",
            "apkSha256" to "a".repeat(64)), mapOf("reason" to 6, "secret" to "SECRET_EVENT"),
            "SECRET_RAW".toByteArray(), "system_trace", truncated = true, system = system), 1500))
    }
    private fun inventory() = store.manage("inventory", emptyMap<Any, Any>(), clock + 1500)
    private fun rows(value: Map<String, Any?>) = (value["items"] as List<*>).map { it as Map<*, *> }
    private fun selection(value: Map<String, Any?>, row: Int = 0): Map<String, Any?> =
        mapOf("revision" to value["revision"], "token" to rows(value)[row]["token"])

    @After fun clean() { base.deleteRecursively() }

    @Test fun sandboxExposesTheMinimumAndroidPosixContract() {
        assertEquals(android.system.StructStat::class.java, android.system.Os::class.java.getMethod("lstat", String::class.java).returnType)
        assertEquals(java.io.FileDescriptor::class.java, android.system.Os::class.java.getMethod("open", String::class.java,
            Int::class.javaPrimitiveType, Int::class.javaPrimitiveType).returnType)
        assertNotEquals(0, android.system.OsConstants.O_NOFOLLOW)
        assertNotNull(android.system.StructStat::class.java.getField("st_ino"))
    }

    @Test fun metadataSummaryWhitelistAndExactRawExportUseDifferentReads() {
        save(1)
        val value = inventory()
        assertEquals("ready", value["status"])
        val args = selection(value)
        val summary = store.export(args + ("kind" to "summary"), 1500).toString(Charsets.UTF_8)
        assertFalse(summary.contains("SECRET"))
        assertTrue(summary.contains("arm64-v8a"))
        assertTrue(summary.contains("unverified"))
        assertFalse(summary.contains("versionName"))
        var rawReads = 0
        val catalog = CrashReportManagement(root, { 0 }, { check(root.isDirectory) }, {
            rawReads++; store.read(it)
        }, File::delete)
        val safe = catalog.handle("inventory", emptyMap<Any, Any>(), 1500)
        catalog.handle("summary", selection(safe), 1500)
        catalog.export(selection(safe) + ("kind" to "summary"), 1500)
        assertEquals(0, rawReads)
        val archive = catalog.export(selection(safe) + ("kind" to "raw"), 1500)
        assertEquals(1, rawReads)
        ZipInputStream(ByteArrayInputStream(archive)).use { zip ->
            assertEquals("summary.json", zip.nextEntry.name)
            assertFalse(zip.readBytes().toString(Charsets.UTF_8).contains("SECRET"))
            assertEquals("raw.bin", zip.nextEntry.name)
            assertArrayEquals("SECRET_RAW".toByteArray(), zip.readBytes())
            assertNull(zip.nextEntry)
        }
    }

    @Test fun gnuAndGoBuildIdsSurviveManagementAndExportsOnlyInTheirOwnFormats() {
        val short = "AbCdEfGhIjKlMnOpQrSt/_-0123456789AbCdEfGh"
        val full = "$short/zyxwvutsrqponmlkjihg/ABCDEFGHabcdefgh0123"
        val oracle = System.getenv("FLCLASH_REPORT_IDENTITY_FIXTURE")?.let {
            com.google.gson.JsonParser.parseString(File(it).readText()).asJsonObject
                .getAsJsonObject("ids")["libclash.so:go"].asString
        }
        val cases = (listOf(short, full) + listOfNotNull(oracle)).map { it to true } + listOf(
            "/Users/private/report", "https://example.invalid/secret", "$full\nSECRET", "a".repeat(129),
            "a".repeat(20) + "/" + "b".repeat(19), "$short/zyxwvutsrqponmlkjihg", "$short=",
        ).map { it to false }
        val gnu = "1234abcdef".repeat(4)
        for ((index, test) in cases.withIndex()) {
            val local = CrashReportStore(File(base, "identity-$index"), clock = { clock })
            val ids = mapOf("libclash.so:go" to test.first, "libclash.so:gnu" to gnu,
                "libcore.so:go" to "../PRIVATE_PATH", "libapp.so:gnu" to "a".repeat(129),
                "librust_api.so:gnu" to "INVALID_TEXT", "libflutter.so:go" to "a".repeat(129),
                "unknown.so:go" to full, "libclash.so:other" to full)
            assertEquals("stored", local.save(CrashMaterial(id(1), "startup", mapOf("buildIds" to ids),
                emptyMap(), "PRIVATE_RAW".toByteArray(), "utf8_exception"), 1500))
            val value = local.manage("inventory", emptyMap<Any, Any>(), 1500)
            val selected = selection(value)
            val observed = mutableListOf<Map<*, *>>(rows(value).single()["summary"] as Map<*, *>)
            observed.add(local.manage("summary", selected, 1500)["summary"] as Map<*, *>)
            observed.add(com.google.gson.Gson().fromJson(local.export(selected + ("kind" to "summary"), 1500).toString(Charsets.UTF_8), Map::class.java))
            ZipInputStream(ByteArrayInputStream(local.export(selected + ("kind" to "raw"), 1500))).use { zip ->
                assertEquals("summary.json", zip.nextEntry.name)
                observed.add(com.google.gson.Gson().fromJson(zip.readBytes().toString(Charsets.UTF_8), Map::class.java))
                assertEquals("raw.bin", zip.nextEntry.name)
                assertArrayEquals("PRIVATE_RAW".toByteArray(), zip.readBytes())
            }
            for (summary in observed) {
                assertEquals(gnu, summary["libclash.so:gnu"])
                assertEquals(if (test.second) test.first else null, summary["libclash.so:go"])
                assertEquals(if (test.second) setOf("libclash.so:gnu", "libclash.so:go") else setOf("libclash.so:gnu"),
                    summary.keys.filterIsInstance<String>().filter { ':' in it }.toSet())
                assertFalse(summary.toString().contains("PRIVATE"))
            }
        }
    }

    @Test fun unknownDamagedAndLinkedItemsAreVisibleAndDeletingKeepsLedgerAndNewCapture() {
        save(1, system = true)
        File(root, "foreign-name").writeText("SECRET_UNKNOWN")
        File(root, id(2)).mkdirs()
        File(root, "${id(2)}/metadata.json").writeText("{\"schema\":7}")
        val outside = File(base, "outside").apply { mkdirs() }
        File(outside, "secret").writeText("DO_NOT_REMOVE")
        Files.createSymbolicLink(File(root, "outside-link").toPath(), outside.toPath())
        val value = inventory()
        assertEquals(4, rows(value).size)
        assertFalse(value.toString().contains("SECRET_UNKNOWN"))
        assertTrue(value.toString().contains("unknown_schema"))
        for (row in rows(value).filter { (it["summary"] as Map<*, *>)["state"] == "corrupt" }) {
            assertEquals("deleted", store.manage("delete", mapOf("revision" to value["revision"], "token" to row["token"]), 1500)["status"])
        }
        save(3)
        val result = store.manage("delete", mapOf("revision" to value["revision"], "all" to true), 1500)
        assertEquals("deleted", result["status"])
        assertEquals(2, result["deleted"])
        assertTrue(File(root, "seen.json").exists())
        assertTrue(store.savedSystem(id(1)))
        assertEquals("DO_NOT_REMOVE", File(outside, "secret").readText())
        assertNotNull(store.read(id(3)))
        save(4)
    }

    @Test fun refreshExpiryReplacementAndDeletionMakeOldSelectionsStale() {
        save(1)
        val first = inventory()
        val args = selection(first)
        val fresh = inventory()
        assertEquals("stale", store.manage("summary", args, 1500)["status"])
        val selected = selection(fresh)
        val original = File(root, id(1))
        original.renameTo(File(base, "old"))
        original.mkdirs()
        File(original, "metadata.json").writeText("{}")
        assertEquals("stale", store.manage("delete", selected, 1500)["status"])
        assertTrue(original.exists())
        val last = inventory()
        clock = 300_001
        assertEquals("stale", store.manage("delete", selection(last), clock + 1500)["status"])
    }

    @Test fun rawChecksumMissingMetadataOnlyAndRootReplacementAreNotFalselySuccessful() {
        save(1)
        File(root, "${id(1)}/raw.bin").writeText("ALTERED___")
        val value = inventory()
        try { store.export(selection(value) + ("kind" to "raw"), 1500); fail() }
        catch (error: ReportFailure) { assertEquals("integrity", error.status) }
        File(root, "${id(1)}/raw.bin").delete()
        assertTrue(inventory().toString().contains("missing_raw"))
        assertEquals("metadata_only", store.save(CrashMaterial(id(2), "startup", emptyMap(), emptyMap()), 1500))
        assertTrue(inventory().toString().contains("metadata_only"))
        val selected = selection(inventory())
        root.renameTo(File(base, "moved"))
        val target = File(base, "redirect").apply { mkdirs() }
        File(target, "sentinel").writeText("SAFE")
        Files.createSymbolicLink(root.toPath(), target.toPath())
        assertEquals("io", inventory()["status"])
        assertNotEquals("deleted", store.manage("delete", selected, 1500)["status"])
        assertEquals("SAFE", File(target, "sentinel").readText())
    }

    @Test fun partialRemovalAndBoundedTraversalReturnFailureAndCanBeRefreshed() {
        save(1)
        val failing = CrashReportStore(root, clock = { 0 }, remove = { it.name != "metadata.json" && it.delete() })
        val value = failing.manage("inventory", emptyMap<Any, Any>(), 1500)
        val result = failing.manage("delete", selection(value), 1500)
        assertEquals("io", result["status"])
        assertEquals(0, result["deleted"])
        assertTrue(rows(failing.manage("inventory", emptyMap<Any, Any>(), 1500)).isNotEmpty())
        repeat(129) { File(root, "unknown-$it").writeText("") }
        assertEquals("limited", inventory()["status"])
        assertTrue(File(root, id(1)).exists())
    }

    @Test fun malformedRawMetadataAndEmptyRawNeverOfferMisleadingRawExport() {
        save(1)
        val metadata = File(root, "${id(1)}/metadata.json")
        metadata.writeText(metadata.readText().replace("\"truncated\":true", "\"truncated\":\"invalid\""))
        val value = inventory()
        assertEquals("corrupt", (rows(value).single()["summary"] as Map<*, *>)["state"])
        assertFalse((rows(value).single()["summary"] as Map<*, *>)["rawAvailable"] as Boolean)
        assertEquals("stored", store.save(CrashMaterial(id(2), "startup", emptyMap(), emptyMap(), byteArrayOf(), "utf8_exception"), 1500))
        assertTrue(inventory().toString().contains("metadata_only"))
    }

    @Test fun absentRootIsReadOnlyAndAbandonedStagingCountsWithoutBeingPublished() {
        assertEquals("ready", inventory()["status"])
        assertFalse(root.exists())
        val staging = File(root, ".staging").apply { mkdirs() }
        File(staging, "raw.bin").writeBytes(ByteArray(100))
        File(staging, "metadata.json").writeText("{}")
        val value = inventory()
        assertEquals(102L, value["bytes"])
        assertTrue(rows(value).isEmpty())
        assertTrue(staging.exists())
    }

    @Test fun deletionStopsBeforeRemovingParentWhenLastChildIoExhaustsBudget() {
        assertEquals("metadata_only", store.save(CrashMaterial(id(1), "startup", emptyMap(), emptyMap()), 1500))
        val bounded = CrashReportStore(root, clock = { clock }, remove = { file ->
            file.delete().also { clock = 2000 }
        })
        val value = bounded.manage("inventory", emptyMap<Any, Any>(), 1500)
        assertEquals("deadline", bounded.manage("delete", selection(value), 1500)["status"])
        assertTrue(File(root, id(1)).exists())
        assertFalse(File(root, "${id(1)}/metadata.json").exists())
    }
}
