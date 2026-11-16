package com.follow.clash.service

import com.google.gson.GsonBuilder
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File
import java.util.Locale

/** Generate with :service:generateUidPackageIdentityFixture; optional -PuidIdentityFixtureOutput selects an evidence file. */
object UidPackageIdentityFixture {
    private data class Input(
        val name: String,
        val packages: List<String>,
        val validCount: Int,
        val uid: Int = 10123,
        val currentUser: Boolean = true,
        val lookupFails: Boolean = false,
    )

    private fun names(count: Int) = List(count) { String.format(Locale.ROOT, "fixture.app%03d", it) }

    private fun inputs() = listOf(
        Input("empty", listOf("", " \t"), 0),
        Input("unique", names(1) + listOf("", " ") + names(1), 1),
        Input("shared-64", names(64).reversed() + listOf("", " \t") + names(4), 64),
        Input("overflow-65", names(65).reversed() + listOf("", " \t") + names(4), 65),
        Input("other-user", names(1), 1, uid = 1010123, currentUser = false),
        Input("lookup-failed", names(1), 1, lookupFails = true),
        Input("invalid-uid", names(1), 1, uid = -1),
    )

    fun payload(): JsonArray = JsonArray().apply {
        inputs().forEach { input ->
            val resolver = UidPackageResolver({ input.currentUser }) {
                if (input.lookupFails) throw SecurityException("synthetic lookup failure")
                input.packages.toTypedArray()
            }
            add(JsonObject().apply {
                addProperty("name", input.name)
                addProperty("uid", input.uid)
                addProperty("currentUser", input.currentUser)
                addProperty("lookupFails", input.lookupFails)
                addProperty("validCount", input.validCount)
                add("inputPackages", JsonArray().apply { input.packages.forEach { add(it) } })
                add("identity", JsonParser.parseString(resolver.resolve(input.uid).toJson()))
            })
        }
    }

    @JvmStatic fun main(args: Array<String>) {
        require(args.size == 1) { "Expected output path; use :service:generateUidPackageIdentityFixture" }
        File(args.single()).apply {
            parentFile?.mkdirs()
            writeText(GsonBuilder().setPrettyPrinting().create().toJson(payload()) + "\n")
        }
    }
}
