package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.AtomicFile
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal class QrFailure(val code: String) : Exception(code)

internal class QrCodeSequence(
    directory: File,
    private val file: AtomicFile = AtomicFile(File(directory, "qr_launch_sequence")),
) {
    fun reserve(): Int = try {
        reserveChecked()
    } catch (_: Exception) {
        throw QrFailure("qr_unavailable")
    }

    private fun reserveChecked(): Int {
        val next = try {
            file.openRead().use { input ->
                java.io.DataInputStream(input).let { data ->
                    val value = data.readLong()
                    if (data.read() != -1) throw IOException()
                    value
                }
            }
        } catch (error: java.io.FileNotFoundException) {
            if (listOf(file.baseFile, File(file.baseFile.path + ".bak"), File(file.baseFile.path + ".new")).any { it.exists() }) throw error
            FIRST.toLong()
        }
        if (next !in FIRST.toLong()..LAST.toLong()) throw QrFailure("qr_unavailable")
        val stream = file.startWrite()
        try {
            java.io.DataOutputStream(stream).writeLong(next + 1)
            stream.fd.sync()
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
        try {
            file.finishWrite(stream)
        } finally {
            stream.close()
        }
        val persisted = file.openRead().use { java.io.DataInputStream(it).readLong() }
        if (persisted != next + 1) throw IOException()
        return next.toInt()
    }

    companion object {
        const val FIRST = 0x6F000000
        const val LAST = 0x6FFFFFFF
    }
}

internal class QrFlight(
    val context: Context,
    val client: Long,
    private val openAsset: (Uri, CancellationSignal) -> AssetFileDescriptor? = { uri, signal ->
        context.contentResolver.openAssetFileDescriptor(uri, "r", signal)
    },
) {
    var code = -1
    var uri: Uri? = null
    var phase = "preparing"
    var receiver: ((Any?, String?) -> Unit)? = null
    var prepared: (() -> Unit)? = null
    private val closeFailed = AtomicBoolean(false)
    @Volatile var deadline = SystemClock.elapsedRealtime() + 5000
    val revoked = AtomicBoolean(false)
    val signal = CancellationSignal()
    private val working = AtomicBoolean(false)
    private val cleaning = AtomicBoolean(false)
    private val resource = AtomicReference<AssetFileDescriptor?>()
    private val inputStream = AtomicReference<java.io.FileInputStream?>()
    private val thread = AtomicReference<Thread?>()
    private val cleanupStarted = AtomicBoolean(false)

    fun checkpoint() {
        if (revoked.get()) throw QrFailure("qr_cancelled")
        if (SystemClock.elapsedRealtime() >= deadline) throw QrFailure("qr_timeout")
    }

    fun work(block: () -> Unit) {
        if (!working.compareAndSet(false, true)) throw QrFailure("qr_busy")
        val task = Thread({
            try {
                checkpoint()
                block()
            } catch (e: QrFailure) {
                finish(null, e.code)
            } catch (_: Exception) {
                finish(null, "qr_invalid_image")
            } catch (_: OutOfMemoryError) {
                finish(null, "qr_unavailable")
            } finally {
                try { closeInput() } catch (_: Exception) { closeFailed.set(true); finish(null, "qr_unavailable") }
                synchronized(this) {
                    thread.set(null)
                    working.set(false)
                    releaseIfDone()
                }
                QrGalleryQuota.main.post {
                    val callback = prepared
                    prepared = null
                    if (!revoked.get()) callback?.invoke()
                }
            }
        }, "qr-gallery")
        thread.set(task)
        task.start()
    }

    fun read(): ByteArray {
        checkpoint()
        val descriptor = openAsset(uri!!, signal)
            ?: throw QrFailure("qr_invalid_image")
        resource.set(descriptor)
        checkpoint()
        val expected = descriptor.declaredLength
        if (expected > MAX_INPUT) throw QrFailure("qr_image_too_large")
        val input = descriptor.createInputStream()
        inputStream.set(input)
        checkpoint()
        val bytes = ByteArrayOutputStream()
        val buffer = ByteArray(32 * 1024)
        while (true) {
            checkpoint()
            val count = input.read(buffer, 0, minOf(buffer.size, MAX_INPUT + 1 - bytes.size()))
            checkpoint()
            if (count < 0) break
            if (count == 0) throw QrFailure("qr_invalid_image")
            if (bytes.size() + count > MAX_INPUT) throw QrFailure("qr_image_too_large")
            bytes.write(buffer, 0, count)
        }
        if (expected >= 0 && bytes.size().toLong() != expected) throw QrFailure("qr_invalid_image")
        closeInput()
        checkpoint()
        return bytes.toByteArray()
    }

    fun finish(value: Any?, error: String? = null) {
        QrGalleryQuota.main.post {
            if (revoked.get()) return@post
            if (SystemClock.elapsedRealtime() >= deadline) {
                cancel("qr_timeout")
                return@post
            }
            val reply = receiver
            receiver = null
            reply?.invoke(value, error)
            if (phase == "decoding" || error != null) cancel()
        }
    }

    fun cancel(error: String = "qr_cancelled") {
        val cleanup: Boolean
        synchronized(this) {
            if (!revoked.compareAndSet(false, true)) return
            cleanup = working.get() && cleanupStarted.compareAndSet(false, true)
            if (cleanup) cleaning.set(true)
        }
        uri = null
        prepared = null
        val reply = receiver
        receiver = null
        reply?.invoke(null, error)
        thread.get()?.interrupt()
        if (cleanup) {
            Thread({
                try {
                    closeInput()
                    signal.cancel()
                } catch (_: Exception) { closeFailed.set(true) }
                finally {
                    synchronized(this) {
                        cleaning.set(false)
                        releaseIfDone()
                    }
                }
            }, "qr-gallery-cleanup").start()
        }
        releaseIfDone()
    }

    private fun closeInput() {
        try {
            try { inputStream.getAndSet(null)?.close() }
            finally { resource.getAndSet(null)?.close() }
        }
        catch (error: Exception) { closeFailed.set(true); throw error }
    }

    @Synchronized private fun releaseIfDone() {
        if (revoked.get() && !working.get() && !cleaning.get() && !closeFailed.get()) QrGalleryQuota.active.compareAndSet(this, null)
    }

    companion object { const val MAX_INPUT = 32 * 1024 * 1024 }
}

internal object QrGalleryQuota {
    val main = Handler(Looper.getMainLooper())
    val active = AtomicReference<QrFlight?>()
}

internal class QrGallery(private val binding: ActivityPluginBinding) : PluginRegistry.ActivityResultListener {
    private val activity: Activity get() = binding.activity
    private val contract = ActivityResultContracts.PickVisualMedia()
    private var flight: QrFlight? = null
    private var disposed = false
    private var lastClient = 0L
    private fun foreground() = !disposed && (activity as? LifecycleOwner)?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED) == true

    init { binding.addActivityResultListener(this) }

    fun call(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickQrImage" -> pick(call.argument<Number>("clientId")?.toLong() ?: -1, result)
            "decodeQrImage" -> decode(call.argument<Number>("handle")?.toInt() ?: -1, result)
            "cancelQrImage" -> {
                if (flight?.client == call.argument<Number>("clientId")?.toLong()) {
                    flight?.cancel()
                    flight = null
                }
                result.success(null)
            }
        }
    }

    private fun reply(result: MethodChannel.Result): (Any?, String?) -> Unit = { value, error ->
        if (error == null) result.success(value) else if (error == "qr_cancelled") result.success(null)
        else result.error(error, error, null)
    }

    private fun arm(current: QrFlight) {
        val deadline = current.deadline
        QrGalleryQuota.main.postDelayed({
            if (current.deadline == deadline && !current.revoked.get()) current.cancel("qr_timeout")
        }, 5000)
    }

    private fun pick(client: Long, result: MethodChannel.Result) {
        if (flight?.client == client && flight?.revoked?.get() == false) {
            result.error("qr_busy", "qr_busy", null)
            return
        }
        if (!foreground() || client <= 0 || client <= lastClient) {
            result.error("qr_cancelled", "qr_cancelled", null)
            return
        }
        val current = QrFlight(activity.applicationContext, client)
        if (!QrGalleryQuota.active.compareAndSet(null, current)) {
            result.error("qr_busy", "qr_busy", null)
            return
        }
        lastClient = client
        flight = current
        current.receiver = reply(result)
        arm(current)
        current.prepared = {
            if (flight === current && !current.revoked.get()) {
                if (!foreground()) current.cancel() else try {
                    current.checkpoint()
                    current.phase = "picking"
                    current.deadline = Long.MAX_VALUE
                    val request = PickVisualMediaRequest.Builder()
                        .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly).build()
                    activity.startActivityForResult(contract.createIntent(activity, request), current.code)
                } catch (_: Exception) { current.cancel("qr_unavailable") }
            }
        }
        current.work {
            current.code = QrCodeSequence(current.context.noBackupFilesDir).reserve()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode !in QrCodeSequence.FIRST..QrCodeSequence.LAST) return false
        val current = flight
        if (current == null || current.code != requestCode || current.phase != "picking" || current.revoked.get()) return true
        val uri = contract.parseResult(resultCode, data)
        if (uri == null) { current.cancel(); return true }
        if (uri.scheme != "content") { current.cancel("qr_invalid_image"); return true }
        current.uri = uri
        current.phase = "selected"
        current.deadline = SystemClock.elapsedRealtime() + 5000
        current.finish(current.code)
        arm(current)
        return true
    }

    private fun decode(handle: Int, result: MethodChannel.Result) {
        val current = flight
        if (!foreground() || current == null || current.code != handle || current.revoked.get()) {
            result.error("qr_cancelled", "qr_cancelled", null)
            return
        }
        if (current.phase != "selected") { result.error("qr_busy", "qr_busy", null); return }
        try { current.checkpoint() } catch (_: Exception) { current.cancel("qr_timeout"); result.error("qr_timeout", "qr_timeout", null); return }
        current.phase = "decoding"
        current.deadline = SystemClock.elapsedRealtime() + 5000
        current.receiver = reply(result)
        arm(current)
        current.work {
            val bytes = current.read()
            val values = QrDecoder.image(bytes, current::checkpoint)
            current.finish(mapOf("data" to values))
        }
    }

    fun dispose() {
        disposed = true
        flight?.cancel()
        flight = null
        binding.removeActivityResultListener(this)
    }
}
