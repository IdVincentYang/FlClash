package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.net.Uri
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class QrActivity : Activity(), LifecycleOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry
    fun resumeForTest() { registry.currentState = Lifecycle.State.RESUMED }
}

class QrLocalProvider(private val image: File, private val gate: CountDownLatch? = null, private val waitAt: String = "open", private val declared: Long = image.length()) : ContentProvider() {
    fun waitDescription() = waitAt
    val entered = CountDownLatch(1)
    override fun onCreate() = true
    private fun waitForGate() {
        entered.countDown()
        while (gate?.count == 1L) try { gate.await() } catch (_: InterruptedException) {}
    }
    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        if (waitAt == "open") waitForGate()
        val pfd = ParcelFileDescriptor.open(image, ParcelFileDescriptor.MODE_READ_ONLY)
        return object : AssetFileDescriptor(pfd,0,declared) {
            override fun createInputStream(): java.io.FileInputStream {
                val input = super.createInputStream()
                return object : java.io.FileInputStream(input.fd) {
                    override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                        if (waitAt == "read") waitForGate()
                        return input.read(bytes, offset, length)
                    }
                }
            }
            override fun close() {
                if (waitAt == "close") waitForGate()
                super.close()
            }
        }
    }
    override fun query(uri: Uri, projection: Array<String>?, selection: String?, args: Array<String>?, sort: String?): Cursor? = null
    override fun getType(uri: Uri) = "image/png"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?) = 0
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class QrGalleryTest {
    private lateinit var activity: QrActivity
    private lateinit var binding: ActivityPluginBinding
    private lateinit var gallery: QrGallery
    private lateinit var image: File
    private var blockedGate: CountDownLatch? = null

    private class Reply : MethodChannel.Result {
        var done = false
        var value: Any? = null
        var code: String? = null
        override fun success(value: Any?) { check(!done);done = true;this.value = value }
        override fun error(code: String, message: String?, details: Any?) { check(!done);done = true;this.code = code;assertEquals(code,message);assertNull(details) }
        override fun notImplemented() { error("unimplemented","unimplemented",null) }
    }

    private fun invoke(method: String, args: Map<String, Any>) = Reply().also { gallery.call(MethodCall(method,args),it) }
    private fun pumpUntil(predicate: () -> Boolean) {
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!predicate() && System.nanoTime() < end) { shadowOf(Looper.getMainLooper()).idle();Thread.sleep(1) }
        assertTrue("worker failed to reach barrier",predicate())
    }
    private fun launch(client: Long): Pair<Reply, Int> {
        val result = invoke("pickQrImage",mapOf("clientId" to client))
        pumpUntil { QrGalleryQuota.active.get()?.phase == "picking" || result.done }
        assertFalse(result.done)
        return result to QrGalleryQuota.active.get()!!.code
    }
    private fun selected(code: Int) = gallery.onActivityResult(code,Activity.RESULT_OK,Intent().setData(Uri.parse("content://qr-test/image")))

    @Before fun setup() {
        activity = Robolectric.buildActivity(QrActivity::class.java).setup().get()
        activity.resumeForTest()
        binding = mock(ActivityPluginBinding::class.java)
        `when`(binding.activity).thenReturn(activity)
        gallery = QrGallery(binding)
        image = File.createTempFile("qr-fixture", ".png", activity.cacheDir)
        image.writeBytes(javaClass.getResourceAsStream("/qr/url.png")!!.use { it.readBytes() })
        register(QrLocalProvider(image))
    }
    private fun register(provider: QrLocalProvider) {
        provider.attachInfo(activity, android.content.pm.ProviderInfo().apply {
            authority = "qr-test"
            applicationInfo = activity.applicationInfo
        })
        ShadowContentResolver.registerProviderInternal("qr-test",provider)
    }
    @After fun cleanup() {
        gallery.dispose()
        blockedGate?.countDown()
        pumpUntil { QrGalleryQuota.active.get() == null }
        image.delete()
    }

    @Test fun realProviderDecodeAndOneTimeHandle() {
        val (pick,code) = launch(1)
        assertEquals("qr_busy",invoke("pickQrImage",mapOf("clientId" to 1L)).code)
        assertTrue(selected(code))
        pumpUntil { pick.done }
        assertEquals(code,pick.value)
        val decode = invoke("decodeQrImage",mapOf("handle" to code))
        val duplicate = invoke("decodeQrImage",mapOf("handle" to code))
        assertEquals("qr_busy",duplicate.code)
        pumpUntil { decode.done }
        assertNull(decode.code)
        val values = (decode.value as Map<*,*>)["data"] as List<*>
        assertEquals("https://example.invalid/subscription?token=SYNTHETIC-T09",(values.single() as Map<*,*>)["rawValue"])
    }

    @Test fun cancelledAThenBDoesNotAcceptLateA() {
        val (a,codeA) = launch(1)
        invoke("cancelQrImage",mapOf("clientId" to 1L))
        assertTrue(a.done);assertNull(a.value)
        val (b,codeB) = launch(2)
        assertNotEquals(codeA,codeB)
        assertTrue(selected(codeA))
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(b.done)
        selected(codeB)
        pumpUntil { b.done }
        assertEquals(codeB,b.value)
    }

    @Test fun detachedHandlerCannotDeliverOldResultToReplacement() {
        val (a,codeA) = launch(1)
        gallery.dispose()
        assertTrue(a.done)
        gallery = QrGallery(binding)
        val (b,codeB) = launch(1)
        selected(codeA)
        assertFalse(b.done)
        selected(codeB)
        pumpUntil { b.done }
    }

    @Test fun stalledProviderTimesOutAndCannotGrowWorkersOrBlockCameraQuota() {
        val gate = CountDownLatch(1);blockedGate = gate
        val provider = QrLocalProvider(image,gate)
        register(provider)
        val (pick,code) = launch(1);selected(code);pumpUntil { pick.done }
        val decode = invoke("decodeQrImage",mapOf("handle" to code))
        assertTrue("phase=${provider.waitDescription()}; reply=${decode.code}",provider.entered.await(3,TimeUnit.SECONDS))
        shadowOf(Looper.getMainLooper()).idleFor(5,TimeUnit.SECONDS)
        assertEquals("qr_timeout",decode.code)
        gallery.dispose();gallery = QrGallery(binding)
        assertEquals("qr_busy",invoke("pickQrImage",mapOf("clientId" to 1L)).code)
        val camera = QrCameraWork.acquire();assertNotNull(camera);camera!!.close()
        gate.countDown()
        pumpUntil { QrGalleryQuota.active.get() == null }
        val (next,_) = launch(2)
        assertFalse(next.done)
    }

    @Test fun controlledReadAndCloseStayQuarantinedUntilActualExit() {
        for (phase in listOf("read", "close")) {
            val gate = CountDownLatch(1);blockedGate = gate
            val provider = QrLocalProvider(image,gate,phase)
            val current = QrFlight(activity.applicationContext, 1) { uri, _ -> provider.openAssetFile(uri,"r") }
            current.phase = "decoding"
            current.uri = Uri.parse("content://qr-test/image")
            val reply = Reply()
            current.receiver = { value, error -> if (error == null) reply.success(value) else reply.error(error,error,null) }
            assertTrue(QrGalleryQuota.active.compareAndSet(null,current))
            current.work { current.read();current.finish("must not deliver") }
            assertTrue(phase,provider.entered.await(3,TimeUnit.SECONDS))
            current.cancel("qr_timeout")
            assertEquals("qr_timeout",reply.code)
            gallery.dispose();gallery = QrGallery(binding)
            assertEquals("qr_busy",invoke("pickQrImage",mapOf("clientId" to 1L)).code)
            val camera = QrCameraWork.acquire();assertNotNull(camera);camera!!.close()
            gate.countDown()
            pumpUntil { QrGalleryQuota.active.get() == null }
        }
    }

    @Test fun declaredOversizeAndTruncationNeverReturnDecodedPrefix() {
        var client = 1L
        for (size in listOf(image.length()+1, QrFlight.MAX_INPUT.toLong()+1)) {
            register(QrLocalProvider(image,declared=size))
            val (pick,code)=launch(client++);selected(code);pumpUntil { pick.done }
            val decode=invoke("decodeQrImage",mapOf("handle" to code))
            pumpUntil { decode.done }
            assertNotNull(decode.code);assertNull(decode.value)
            pumpUntil { QrGalleryQuota.active.get()==null }
        }
    }

    @Test fun arbitraryNetworkUriIsRejectedBeforeReading() {
        val (pick,code)=launch(1)
        gallery.onActivityResult(code,Activity.RESULT_OK,Intent().setData(Uri.parse("https://example.invalid/image")))
        assertEquals("qr_invalid_image",pick.code)
    }

    @Test fun selectedHandleExpiresAndUnknownCodeCannotParseData() {
        val (pick,code) = launch(1)
        assertFalse(gallery.onActivityResult(15,Activity.RESULT_OK,Intent().setData(Uri.parse("content://qr-test/image"))))
        assertFalse(pick.done)
        selected(code);pumpUntil { pick.done }
        shadowOf(Looper.getMainLooper()).idleFor(5,TimeUnit.SECONDS)
        assertNull(invoke("decodeQrImage",mapOf("handle" to code)).value)
        assertNull(QrGalleryQuota.active.get())
    }

    @Test fun restoresInterruptedAtomicFileBackupBeforeAllocating() {
        val dir = java.nio.file.Files.createTempDirectory("qr-sequence").toFile()
        try {
            val file = File(dir,"qr_launch_sequence")
            java.io.DataOutputStream(File(file.path+".bak").outputStream()).use { it.writeLong(QrCodeSequence.FIRST.toLong()+42) }
            assertEquals(QrCodeSequence.FIRST+42,QrCodeSequence(dir).reserve())
            assertEquals(QrCodeSequence.FIRST+43,QrCodeSequence(dir).reserve())
        } finally { dir.deleteRecursively() }
    }

    @Test fun orphanedIncompleteReservationFailsClosed() {
        val dir = java.nio.file.Files.createTempDirectory("qr-sequence").toFile()
        try {
            File(dir,"qr_launch_sequence.new").writeBytes(byteArrayOf(1,2))
            assertEquals("qr_unavailable",assertThrows(QrFailure::class.java) { QrCodeSequence(dir).reserve() }.code)
        } finally { dir.deleteRecursively() }
    }

    @Test fun committedCounterSurvivesReadbackOrPostCommitFailureWithApi24Semantics() {
        for (failure in listOf("readback", "commit")) {
            val dir = java.nio.file.Files.createTempDirectory("qr-sequence").toFile()
            try {
                val base = File(dir,"qr_launch_sequence")
                val backup = File(base.path+".bak")
                var committed = false
                var rollbacks = 0
                val legacy = object : android.util.AtomicFile(base) {
                    override fun openRead(): java.io.FileInputStream {
                        if (committed && failure == "readback") throw java.io.IOException("synthetic readback failure")
                        if (backup.exists()) check(backup.renameTo(base))
                        return base.inputStream()
                    }
                    override fun startWrite(): java.io.FileOutputStream {
                        if (base.exists()) check(base.renameTo(backup))
                        return base.outputStream()
                    }
                    override fun finishWrite(stream: java.io.FileOutputStream) {
                        stream.fd.sync();stream.close();backup.delete();committed = true
                        if (failure == "commit") throw java.io.IOException("synthetic post-commit failure")
                    }
                    override fun failWrite(stream: java.io.FileOutputStream) {
                        rollbacks++;stream.close();base.delete();backup.renameTo(base)
                    }
                }
                java.io.DataOutputStream(base.outputStream()).use { it.writeLong(QrCodeSequence.FIRST.toLong()+42) }
                assertEquals("qr_unavailable",assertThrows(QrFailure::class.java) { QrCodeSequence(dir,legacy).reserve() }.code)
                assertEquals(0,rollbacks)
                assertEquals(failure,QrCodeSequence.FIRST+43,QrCodeSequence(dir).reserve())
            } finally { dir.deleteRecursively() }
        }
    }

    @Test fun sequenceExhaustionAndMalformedTailFailClosed() {
        val dir = java.nio.file.Files.createTempDirectory("qr-sequence").toFile()
        try {
            val file = File(dir,"qr_launch_sequence")
            java.io.DataOutputStream(file.outputStream()).use { it.writeLong(QrCodeSequence.LAST.toLong()) }
            assertEquals(QrCodeSequence.LAST,QrCodeSequence(dir).reserve())
            assertEquals("qr_unavailable",assertThrows(QrFailure::class.java) { QrCodeSequence(dir).reserve() }.code)
            java.io.DataOutputStream(file.outputStream()).use { it.writeLong(QrCodeSequence.FIRST.toLong());it.writeByte(7) }
            assertEquals("qr_unavailable",assertThrows(QrFailure::class.java) { QrCodeSequence(dir).reserve() }.code)
        } finally { dir.deleteRecursively() }
    }

    @Test fun nativeSequencePersistsWithoutReusingCancelledNumbers() {
        val dir = java.nio.file.Files.createTempDirectory("qr-sequence").toFile()
        try {
            val a = QrCodeSequence(dir).reserve()
            assertEquals(a+1,QrCodeSequence(dir).reserve())
            File(dir,"qr_launch_sequence").writeBytes(byteArrayOf(1,2))
            assertEquals("qr_unavailable",assertThrows(QrFailure::class.java) { QrCodeSequence(dir).reserve() }.code)
        } finally { dir.deleteRecursively() }
    }
}
