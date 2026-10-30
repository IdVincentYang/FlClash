package com.follow.clash

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.zip.ZipFile

internal object CrashBuildIdentity {
    private val libraries = listOf("libclash.so", "libcore.so", "librust_api.so", "libapp.so", "libflutter.so")
    private val summaryLibraries = libraries.take(3)

    fun read(apk: File, supported: List<String>, bits64: Boolean, deadline: Long,
             clock: () -> Long): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>("apkSha256" to null, "abi" to null,
            "buildIds" to emptyMap<String, String>(), "buildStatus" to "unavailable")
        if (apk.length() > 256L * 1024 * 1024 || !apk.isFile) return result
        val hash = MessageDigest.getInstance("SHA-256")
        apk.inputStream().use { stream ->
            val buffer = ByteArray(64 * 1024)
            var bytes = 0L
            while (true) {
                if (clock() >= deadline) return result
                val count = stream.read(buffer)
                if (count < 0) break
                bytes += count
                if (bytes > 256L * 1024 * 1024) return result
                hash.update(buffer, 0, count)
            }
        }
        result["apkSha256"] = hex(hash.digest())
        ZipFile(apk).use { zip ->
            val matches = supported.filter { (it.contains("64") == bits64) &&
                zip.getEntry("lib/$it/libflutter.so") != null }
            if (matches.size != 1) { result["buildStatus"] = "abi_unknown"; return result }
            val abi = matches.single()
            result["abi"] = abi
            val ids = linkedMapOf<String, String>()
            for (name in libraries) {
                if (clock() >= deadline) { result["buildStatus"] = "deadline"; break }
                val entry = zip.getEntry("lib/$abi/$name") ?: continue
                zip.getInputStream(entry).use { stream ->
                    notes(prefix(stream, 256 * 1024)).forEach { (kind, value) -> ids["$name:$kind"] = value }
                }
            }
            result["buildIds"] = ids
            if (result["buildStatus"] != "deadline") result["buildStatus"] = "observed"
        }
        return result
    }

    fun notes(bytes: ByteArray): Map<String, String> = runCatching {
        if (bytes.size < 64 || !bytes.copyOfRange(0, 4).contentEquals(byteArrayOf(127, 69, 76, 70)) || bytes[5] != 1.toByte()) return emptyMap()
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val wide = bytes[4] == 2.toByte()
        if (!wide && bytes[4] != 1.toByte()) return emptyMap()
        fun integer(at: Int) = b.getInt(at).toLong() and 0xffffffffL
        fun offset(at: Int) = if (wide) b.getLong(at) else integer(at)
        val ph = offset(if (wide) 32 else 28)
        val size = b.getShort(if (wide) 54 else 42).toInt() and 65535
        val count = b.getShort(if (wide) 56 else 44).toInt() and 65535
        if (count > 128 || size < (if (wide) 56 else 32) || ph < 0 || ph + count.toLong() * size > bytes.size) return emptyMap()
        val ids = linkedMapOf<String, String>()
        for (i in 0 until count) {
            val at = (ph + i * size).toInt()
            if (b.getInt(at) != 4) continue
            var note = offset(at + if (wide) 8 else 4)
            val end = note + offset(at + if (wide) 32 else 16)
            if (note < 0 || end < note || end > bytes.size) continue
            var notes = 0
            while (note + 12 <= end && notes++ < 128) {
                val nameLength = integer(note.toInt()); val length = integer(note.toInt() + 4)
                val type = b.getInt(note.toInt() + 8)
                note += 12
                if (nameLength < 1 || note + ((nameLength + 3) and -4L) + length > end) break
                val owner = if (nameLength <= 16) String(bytes, note.toInt(), nameLength.toInt(), Charsets.US_ASCII).trimEnd('\u0000') else ""
                note += (nameLength + 3) and -4L
                if (length in 1..128) {
                    val value = bytes.copyOfRange(note.toInt(), (note + length).toInt())
                    if (owner == "GNU" && type == 3) ids["gnu"] = hex(value)
                    if (owner == "Go" && type == 4) ids["go"] = String(value, Charsets.US_ASCII)
                }
                note += (length + 3) and -4L
            }
        }
        ids
    }.getOrDefault(emptyMap())

    fun encode(identity: Map<String, Any?>): ByteArray {
        val out = ByteArrayOutputStream()
        val data = DataOutputStream(out)
        data.writeInt(0x46435231)
        data.writeLong((identity["versionCode"] as? Number)?.toLong() ?: -1)
        data.writeShort((identity["api"] as? Number)?.toInt() ?: 0)
        data.writeBoolean(identity["is64Bit"] == true)
        fun field(value: String?, limit: Int) {
            val bytes = value?.toByteArray(Charsets.UTF_8) ?: byteArrayOf()
            val accepted = if (bytes.size <= limit) bytes else byteArrayOf()
            data.writeByte(accepted.size); data.write(accepted)
        }
        field(identity["versionName"] as? String, 32)
        field(identity["abi"] as? String, 16)
        val hash = (identity["apkSha256"] as? String)?.let(::unhex) ?: byteArrayOf()
        data.writeByte(hash.size); data.write(hash)
        val ids = identity["buildIds"] as? Map<*, *> ?: emptyMap<String, String>()
        for (name in summaryLibraries) {
            val id = (ids["$name:gnu"] as? String)?.let(::unhex) ?: byteArrayOf()
            val accepted = if (id.size <= 32 && out.size() + id.size + (3 - summaryLibraries.indexOf(name)) <= 128) id else byteArrayOf()
            data.writeByte(accepted.size); data.write(accepted)
        }
        check(out.size() <= 128)
        return out.toByteArray()
    }

    fun decode(bytes: ByteArray?): Map<String, Any?> = runCatching {
        if (bytes == null || bytes.size > 128) return emptyMap()
        val data = DataInputStream(ByteArrayInputStream(bytes))
        if (data.readInt() != 0x46435231) return emptyMap()
        val result = linkedMapOf<String, Any?>("versionCode" to data.readLong(), "api" to data.readUnsignedShort(), "is64Bit" to data.readBoolean())
        fun field(limit: Int): ByteArray {
            val length = data.readUnsignedByte()
            require(length <= limit && length <= data.available())
            return ByteArray(length).also { data.readFully(it) }
        }
        result["versionName"] = String(field(32), Charsets.UTF_8).ifEmpty { null }
        result["abi"] = String(field(16), Charsets.UTF_8).ifEmpty { null }
        val hash = field(32); require(hash.isEmpty() || hash.size == 32)
        result["apkSha256"] = hash.takeIf { it.isNotEmpty() }?.let(::hex)
        val ids = linkedMapOf<String, String>()
        summaryLibraries.forEach { name -> field(32).takeIf { it.isNotEmpty() }?.let { ids["$name:gnu"] = hex(it) } }
        require(data.available() == 0 && (result["versionCode"] as Long) >= 0 && (result["api"] as Int) >= 30)
        result["buildIds"] = ids
        result["buildStatus"] = "process_summary"
        result
    }.getOrDefault(emptyMap())

    fun prefix(stream: InputStream, limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (out.size() < limit) {
            val n = stream.read(buffer, 0, minOf(buffer.size, limit - out.size()))
            if (n < 0) break
            if (n == 0) throw java.io.IOException("empty read")
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun unhex(value: String): ByteArray? = runCatching {
        require(value.length % 2 == 0 && value.length <= 128)
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }.getOrNull()
}
