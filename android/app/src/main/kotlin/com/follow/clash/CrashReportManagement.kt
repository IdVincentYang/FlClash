package com.follow.clash

import android.system.Os
import android.system.OsConstants
import com.google.gson.Gson
import com.google.gson.JsonObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal class ReportFailure(val status: String) : IOException(status)

internal class CrashReportManagement(
    private val root: File,
    private val clock: () -> Long,
    private val checkRoot: () -> Unit,
    private val read: (String) -> CrashReport?,
    private val remove: (File) -> Boolean,
) {
    private data class Item(val name: String, val stamp: String, val summary: Map<String, Any?>)
    private val gson = Gson()
    private var revision = ""
    private var expires = 0L
    private var items = emptyMap<String, Item>()

    fun handle(action: String, args: Map<*, *>, deadline: Long): Map<String, Any?> = try {
        when (action) {
            "inventory" -> inventory(deadline)
            "summary" -> mapOf("status" to "ready", "summary" to selected(args, deadline).summary)
            "delete" -> delete(args, deadline)
            else -> mapOf("status" to "invalid")
        }
    } catch (error: ReportFailure) { mapOf("status" to error.status) }
      catch (_: Throwable) { mapOf("status" to "io") }

    private fun inventory(deadline: Long): Map<String, Any?> {
        items = emptyMap()
        revision = UUID.randomUUID().toString()
        expires = clock() + 300_000
        if (!root.exists() && root.absoluteFile == root.canonicalFile) {
            return mapOf("status" to "ready", "revision" to revision, "items" to emptyList<Any>(), "bytes" to 0L)
        }
        checkRoot()
        val children = root.listFiles() ?: throw IOException()
        if (children.size > 128) throw ReportFailure("limited")
        val next = linkedMapOf<String, Item>()
        var bytes = 0L
        for (file in children.sortedBy { it.name }) {
            guard(deadline)
            if (file.name in setOf(".staging", ".seen.tmp", "seen.json")) {
                bytes += stamp(file, deadline).second
                continue
            }
            val observed = stamp(file, deadline)
            val summary = summary(file, observed.second)
            next[UUID.randomUUID().toString()] = Item(file.name, observed.first, summary)
            bytes += observed.second
        }
        items = next
        return mapOf("status" to "ready", "revision" to revision, "bytes" to bytes,
            "items" to next.map { (token, item) -> mapOf("token" to token, "summary" to item.summary) })
    }

    private fun selected(args: Map<*, *>, deadline: Long): Item {
        guard(deadline)
        if (args["revision"] != revision || clock() >= expires) throw ReportFailure("stale")
        val item = items[args["token"]] ?: throw ReportFailure("stale")
        val current = runCatching { stamp(File(root, item.name), deadline).first }.getOrNull()
        if (current != item.stamp) throw ReportFailure("stale")
        return item
    }

    private fun delete(args: Map<*, *>, deadline: Long): Map<String, Any?> {
        if (args["revision"] != revision || clock() >= expires) throw ReportFailure("stale")
        val tokens = if (args["all"] == true) items.keys.toList() else listOf(args["token"] as? String ?: "")
        var deleted = 0
        var status = "deleted"
        for (token in tokens) {
            try {
                val item = selected(mapOf("revision" to revision, "token" to token), deadline)
                erase(File(root, item.name), deadline, 0, intArrayOf(0))
                items = items - token
                deleted++
            } catch (error: ReportFailure) { status = error.status }
              catch (_: Throwable) { status = "io" }
        }
        return mapOf("status" to status, "deleted" to deleted, "remaining" to items.size)
    }

    fun export(args: Map<*, *>, deadline: Long): ByteArray {
        val item = selected(args, deadline)
        val summary = gson.toJson(item.summary).toByteArray(Charsets.UTF_8)
        if (summary.size > 8192) throw ReportFailure("limited")
        if (args["kind"] == "summary") return summary
        if (args["kind"] != "raw" || item.summary["rawAvailable"] != true) throw ReportFailure("unavailable")
        val report = read(item.name) ?: throw ReportFailure("integrity")
        val raw = report.raw ?: throw ReportFailure("unavailable")
        guard(deadline)
        return ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                for ((name, bytes) in listOf("summary.json" to summary, "raw.bin" to raw)) {
                    zip.putNextEntry(ZipEntry(name))
                    zip.write(bytes)
                    zip.closeEntry()
                }
            }
            if (output.size() > 2 * 1024 * 1024) throw ReportFailure("limited")
        }.toByteArray()
    }

    private fun summary(file: File, bytes: Long): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>("state" to "corrupt", "bytes" to bytes, "rawAvailable" to false)
        runCatching {
            if (!file.name.matches(Regex("[0-9a-f]{64}")) || !OsConstants.S_ISDIR(Os.lstat(file.path).st_mode)) return result
            val metadata = File(file, "metadata.json")
            val stat = Os.lstat(metadata.path)
            if (metadata.canonicalFile != metadata.absoluteFile || !OsConstants.S_ISREG(stat.st_mode) ||
                stat.st_size > CrashReportStore.META_LIMIT) return result
            val fd = Os.open(metadata.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
            val contents = FileInputStream(fd).use { CrashBuildIdentity.prefix(it, CrashReportStore.META_LIMIT + 1) }
            if (contents.size > CrashReportStore.META_LIMIT) return result
            val json = gson.fromJson(String(contents, Charsets.UTF_8), JsonObject::class.java)
            if (number(json, "schema") != 1L) { result["state"] = "unknown_schema"; return result }
            if (text(json, "id") != file.name || text(json, "source") !in CrashReportStore.SOURCES ||
                number(json, "savedAt") == null || !json["identity"].isJsonObject || !json["event"].isJsonObject || !json["raw"].isJsonObject) return result
            val raw = json.getAsJsonObject("raw")
            val size = number(raw, "bytes")?.takeIf { it <= CrashReportStore.RAW_LIMIT } ?: return result
            val format = text(raw, "format")?.takeIf { it in setOf("none", "utf8_exception", "system_trace", "native_protobuf") } ?: return result
            val truncated = raw["truncated"]?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isBoolean }?.asBoolean ?: return result
            if (format == "none" && size != 0L) return result
            val part = File(file, "raw.bin")
            val exists = part.exists()
            val regular = exists && part.canonicalFile == part.absoluteFile && OsConstants.S_ISREG(Os.lstat(part.path).st_mode)
            val available = size > 0 && regular && part.length() == size && hex(text(raw, "sha256"), 64) != null
            val names = file.list()?.toSet() ?: return result
            if (names.any { it != "metadata.json" && it != "raw.bin" }) return result
            result["state"] = if (size == 0L && (!exists || regular && part.length() == 0L)) "metadata_only" else if (available) "unverified" else "missing_raw"
            result["source"] = text(json, "source")
            result["savedAt"] = number(json, "savedAt")
            result["format"] = format
            result["rawBytes"] = size
            result["truncated"] = truncated
            result["rawAvailable"] = available
            val identity = json.getAsJsonObject("identity")
            for (name in listOf("api", "versionCode")) number(identity, name)?.let { result[name] = it }
            text(identity, "versionName")?.takeIf { it.matches(Regex("[0-9]{1,6}(\\.[0-9]{1,6}){2}")) }?.let { result["versionName"] = it }
            text(identity, "abi")?.takeIf { it in setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64") }?.let { result["abi"] = it }
            hex(text(identity, "apkSha256"), 64)?.let { result["apkSha256"] = it }
            val process = text(identity, "processName")
            val pkg = text(identity, "package")
            if (pkg in setOf("com.follow.clash", "com.follow.clash.dev") && process == pkg) result["process"] = "main"
            val ids = identity["buildIds"]?.takeIf { it.isJsonObject }?.asJsonObject
            for (library in listOf("libclash.so", "libcore.so", "librust_api.so", "libapp.so", "libflutter.so")) {
                hex(ids?.let { text(it, "$library:gnu") }, null)?.let { result["$library:gnu"] = it }
                goId(ids?.let { text(it, "$library:go") })?.let { result["$library:go"] = it }
            }
            val event = json.getAsJsonObject("event")
            number(event, "reason")?.takeIf { it <= 20 }?.let { result["reason"] = it }
        }
        return result
    }

    private fun stamp(file: File, deadline: Long): Pair<String, Long> {
        val pieces = StringBuilder()
        var bytes = 0L
        fun visit(current: File, depth: Int, count: IntArray) {
            guard(deadline)
            if (depth > 8 || ++count[0] > 256) throw ReportFailure("limited")
            val stat = Os.lstat(current.path)
            pieces.append(current.name).append(':').append(stat.st_dev).append(':').append(stat.st_ino)
                .append(':').append(stat.st_mode).append(':').append(stat.st_size).append(':').append(stat.st_mtime).append(';')
            if (OsConstants.S_ISDIR(stat.st_mode)) {
                if (current.canonicalFile != current.absoluteFile) throw IOException()
                val children = current.listFiles() ?: throw IOException()
                if (children.size > 256) throw ReportFailure("limited")
                children.sortedBy { it.name }.forEach { visit(it, depth + 1, count) }
            } else {
                bytes += stat.st_size.coerceAtLeast(0)
                if (depth == 1 && current.name == "metadata.json" && OsConstants.S_ISREG(stat.st_mode)) {
                    val fd = Os.open(current.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
                    FileInputStream(fd).use { pieces.append(CrashReportStore.digest(CrashBuildIdentity.prefix(it, CrashReportStore.META_LIMIT + 1))) }
                }
            }
        }
        visit(file, 0, intArrayOf(0))
        return CrashReportStore.digest(pieces.toString().toByteArray()) to bytes
    }

    private fun erase(file: File, deadline: Long, depth: Int, count: IntArray) {
        guard(deadline)
        if (depth > 8 || ++count[0] > 256) throw ReportFailure("limited")
        if (OsConstants.S_ISDIR(Os.lstat(file.path).st_mode)) {
            if (file.canonicalFile != file.absoluteFile) throw IOException()
            val children = file.listFiles() ?: throw IOException()
            if (children.size > 256) throw ReportFailure("limited")
            children.forEach { erase(it, deadline, depth + 1, count) }
        }
        guard(deadline)
        if (!remove(file)) throw IOException()
    }

    private fun guard(deadline: Long) {
        checkRoot()
        if (clock() >= deadline) throw ReportFailure("deadline")
    }

    private fun text(json: JsonObject, key: String): String? = json[key]?.takeIf {
        it.isJsonPrimitive && it.asJsonPrimitive.isString
    }?.asString

    private fun number(json: JsonObject, key: String): Long? = json[key]?.takeIf {
        it.isJsonPrimitive && it.asJsonPrimitive.isNumber && it.asString.matches(Regex("0|[1-9][0-9]{0,18}"))
    }?.asString?.toLongOrNull()

    private fun hex(value: String?, length: Int?): String? = value?.takeIf {
        it.length in 2..128 && (length == null || it.length == length) && it.matches(Regex("[0-9a-f]+"))
    }

    private fun goId(value: String?): String? {
        if (value == null || value.length !in setOf(41, 83)) return null
        val parts = value.split('/')
        return value.takeIf {
            parts.size in setOf(2, 4) && parts.all { it.matches(Regex("[A-Za-z0-9_-]{20}")) }
        }
    }
}
