package com.follow.clash

import com.google.gson.Gson
import com.google.gson.JsonObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

internal data class CrashMaterial(
    val id: String,
    val source: String,
    val identity: Map<String, Any?>,
    val event: Map<String, Any?>,
    val raw: ByteArray? = null,
    val format: String = "none",
    val truncated: Boolean = false,
    val system: Boolean = false,
)

internal data class CrashReport(val metadata: JsonObject, val raw: ByteArray?)

internal class CrashReportStore(
    private val root: File,
    private val wall: () -> Long = System::currentTimeMillis,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    private val publish: (File, File) -> Boolean = File::renameTo,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
    private val remove: (File) -> Boolean = File::delete,
) {
    private val gson = Gson()
    private val idPattern = Regex("[0-9a-f]{64}")
    private data class Entry(val file: File, val report: CrashReport?, val bytes: Long)

    @Synchronized fun save(material: CrashMaterial, deadline: Long): String {
        if (!idPattern.matches(material.id) || material.source !in SOURCES ||
            (material.raw?.size ?: 0) > (if (material.system) RAW_LIMIT else ERROR_LIMIT)
        ) return "invalid"
        var staging: File? = null
        return try {
            prepare()
            checkDeadline(deadline)
            val entries = entries()
            if (material.system && seen().contains(material.id)) return "duplicate"
            val existing = entries.firstOrNull { it.file.name == material.id }
            if (existing != null) {
                if (existing.report == null) return "newer"
                if (material.system) remember(material.id)
                return "duplicate"
            }
            val current = entries()
            val used = current.sumOf { it.bytes } + ledgerBytes()
            if (used > TOTAL_LIMIT || current.size > COUNT_LIMIT) return "busy"
            val raw = material.raw
            val metadata = linkedMapOf<String, Any?>(
                "schema" to 1, "id" to material.id, "source" to material.source,
                "savedAt" to wall(), "identity" to material.identity, "event" to material.event,
                "raw" to mapOf("format" to material.format, "bytes" to (raw?.size ?: 0),
                    "sha256" to raw?.let(::digest), "truncated" to material.truncated),
            )
            val json = gson.toJson(metadata).toByteArray(Charsets.UTF_8)
            if (json.size > META_LIMIT) return "invalid"
            val unknown = current.filter { it.report == null }
            if (unknown.size + 1 > COUNT_LIMIT || unknown.sumOf { it.bytes } +
                maxOf(META_LIMIT.toLong(), ledgerBytes()) + json.size + (raw?.size ?: 0) > TOTAL_LIMIT
            ) return "busy"
            staging = child(".staging")
            if (staging.exists()) deleteTree(staging)
            if (!staging.mkdir()) throw IOException("staging")
            raw?.let { write(File(staging, "raw.bin"), it) }
            write(File(staging, "metadata.json"), json)
            checkDeadline(deadline)
            if (!publish(staging, child(material.id))) throw IOException("publish")
            staging = null
            if (material.system) remember(material.id)
            trim(entries(), deadline, material.id)
            if (raw == null) "metadata_only" else "stored"
        } catch (_: Expired) {
            "deadline"
        } catch (_: Throwable) {
            "io"
        } finally {
            staging?.let { runCatching { deleteTree(it) } }
        }
    }

    @Synchronized fun read(id: String): CrashReport? = try {
        checkRoot()
        if (!idPattern.matches(id)) null else readDirectory(child(id))
    } catch (_: Throwable) { null }

    @Synchronized fun maintain(deadline: Long): String = try {
        prepare()
        checkDeadline(deadline)
        trim(entries(), deadline)
        "ready"
    } catch (_: Expired) { "deadline" } catch (_: Throwable) { "io" }

    @Synchronized fun ids(): List<String> = try {
        checkRoot()
        entries().filter { it.report != null }.map { it.file.name }
    } catch (_: Throwable) { emptyList() }

    @Synchronized fun savedSystem(id: String): Boolean = try {
        checkRoot()
        if (id in seen()) true else if (read(id) != null) {
            remember(id)
            true
        } else false
    } catch (_: Throwable) { false }

    private fun prepare() {
        if (!root.exists() && !root.mkdirs()) throw IOException("root")
        checkRoot()
        val staging = child(".staging")
        if (staging.exists()) deleteTree(staging)
        val temporary = child(".seen.tmp")
        if (temporary.exists() && !remove(temporary)) throw IOException("ledger")
    }

    private fun checkRoot() {
        if (!root.isDirectory || root.absoluteFile != root.canonicalFile) throw IOException("root")
    }

    private fun child(name: String): File {
        checkRoot()
        return File(root, name).also {
            if (it.canonicalFile.parentFile != root.canonicalFile || it.canonicalFile.name != name)
                throw IOException("path")
        }
    }

    private fun entries(): List<Entry> {
        checkRoot()
        val children = root.listFiles() ?: throw IOException("list")
        if (children.size > 128) throw IOException("entries")
        return children.filter { it.name != "seen.json" && it.name != ".seen.tmp" }.map { f ->
            val file = child(f.name)
            val bytes = if (file.isDirectory) {
                val parts = file.listFiles() ?: throw IOException("list")
                if (parts.size > 8) throw IOException("parts")
                parts.sumOf { part ->
                    if (part.canonicalFile.parentFile != file.canonicalFile || part.isDirectory)
                        throw IOException("path")
                    part.length()
                }
            } else file.length()
            Entry(file, if (idPattern.matches(file.name)) readDirectory(file) else null, bytes)
        }
    }

    private fun readDirectory(dir: File): CrashReport? = runCatching {
        if (!dir.isDirectory) return null
        val names = dir.list()?.toSet() ?: return null
        if (names.any { it != "metadata.json" && it != "raw.bin" }) return null
        fun part(name: String): File = File(dir, name).also {
            if (it.canonicalFile != it.absoluteFile) throw IOException("path")
        }
        val json = gson.fromJson(String(readBounded(part("metadata.json"), META_LIMIT), Charsets.UTF_8), JsonObject::class.java)
        fun unsigned(name: String): Long? {
            val value = json[name]?.takeIf { it.isJsonPrimitive }?.asJsonPrimitive ?: return null
            return if (value.isNumber && value.asString.matches(Regex("0|[1-9][0-9]{0,18}"))) value.asString.toLongOrNull() else null
        }
        if (unsigned("schema") != 1L || json["id"]?.asString != dir.name ||
            json["source"]?.asString !in SOURCES || unsigned("savedAt") == null ||
            json["identity"]?.isJsonObject != true || json["event"]?.isJsonObject != true
        ) return null
        val info = json.getAsJsonObject("raw")
        val size = info["bytes"].asInt
        if (size !in 0..RAW_LIMIT) return null
        val raw = if (part("raw.bin").exists()) readBounded(part("raw.bin"), RAW_LIMIT) else null
        if ((raw?.size ?: 0) != size || (raw != null && digest(raw) != info["sha256"].asString)) return null
        CrashReport(json, raw)
    }.getOrNull()

    private fun seen(): List<String> {
        val file = child("seen.json")
        if (!file.exists()) return emptyList()
        val data = gson.fromJson(String(readBounded(file, META_LIMIT), Charsets.UTF_8), JsonObject::class.java)
        if (data["schema"]?.asInt != 1) throw IOException("ledger")
        val ids = data.getAsJsonArray("ids").map { it.asString }
        if (ids.size > 64 || ids.any { !idPattern.matches(it) }) throw IOException("ledger")
        return ids
    }

    private fun remember(id: String) {
        val ids = (seen().filter { it != id } + id).takeLast(64)
        val temporary = child(".seen.tmp")
        write(temporary, gson.toJson(mapOf("schema" to 1, "ids" to ids)).toByteArray(Charsets.UTF_8))
        if (!publish(temporary, child("seen.json"))) throw IOException("ledger")
    }

    private fun trim(items: List<Entry>, deadline: Long, protectedId: String? = null) {
        var bytes = items.sumOf { it.bytes } + ledgerBytes()
        var count = items.size
        for (entry in items.filter { it.report != null && it.file.name != protectedId }.sortedBy { it.report!!.metadata["savedAt"].asLong }) {
            checkDeadline(deadline)
            val savedAt = entry.report!!.metadata["savedAt"].asLong
            val expired = savedAt <= wall() && wall() - savedAt > RETENTION
            if (!expired && bytes <= TOTAL_LIMIT && count <= COUNT_LIMIT) continue
            deleteTree(entry.file)
            bytes -= entry.bytes
            count--
        }
    }

    private fun ledgerBytes() = child("seen.json").let { if (it.exists()) it.length() else 0L }

    private fun deleteTree(file: File) {
        if (file.canonicalFile != file.absoluteFile) throw IOException("path")
        if (file.isDirectory) {
            val parts = file.listFiles() ?: throw IOException("list")
            if (parts.size > 8) throw IOException("parts")
            parts.forEach { child ->
                if (child.isDirectory || child.canonicalFile != child.absoluteFile) throw IOException("path")
                if (!remove(child)) throw IOException("remove")
            }
        }
        if (!remove(file)) throw IOException("remove")
    }

    private fun write(file: File, bytes: ByteArray) {
        checkRoot()
        FileOutputStream(file).use { stream -> stream.write(bytes); stream.flush(); sync(stream) }
    }

    private fun readBounded(file: File, limit: Int): ByteArray {
        if (file.length() > limit) throw IOException("size")
        return file.inputStream().use { stream ->
            val bytes = CrashBuildIdentity.prefix(stream, limit + 1)
            if (bytes.size > limit) throw IOException("size")
            bytes
        }
    }

    private fun checkDeadline(deadline: Long) { if (clock() >= deadline) throw Expired() }
    private class Expired : Exception()

    companion object {
        const val META_LIMIT = 16 * 1024
        const val ERROR_LIMIT = 64 * 1024
        const val RAW_LIMIT = 1024 * 1024
        const val TOTAL_LIMIT = 16L * 1024 * 1024
        const val COUNT_LIMIT = 20
        const val RETENTION = 30L * 24 * 60 * 60 * 1000
        val SOURCES = setOf("flutter", "zone", "startup", "java_uncaught", "system_exit")
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}
