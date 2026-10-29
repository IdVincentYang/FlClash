package dev.steenbakker.mobile_scanner

import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Looper
import androidx.camera.core.ImageInfo
import androidx.camera.core.ImageProxy
import io.flutter.view.TextureRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class MobileScannerTest {
    @Test fun unsupportedOptionsAreRejectedBeforeCameraCreation() {
        val activity = Robolectric.buildActivity(QrActivity::class.java).setup().get()
        val messenger = mock(io.flutter.plugin.common.BinaryMessenger::class.java)
        val textures = mock(TextureRegistry::class.java)
        val handler = MobileScannerHandler(activity,BarcodeHandler(messenger),messenger,MobileScannerPermissions(),{},textures)
        val binding = mock(io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding::class.java)
        for (options in listOf(mapOf("formats" to listOf(1)),mapOf("formats" to listOf(256),"returnImage" to true),mapOf("formats" to listOf(256),"autoZoom" to true))) {
            val reply = mock(io.flutter.plugin.common.MethodChannel.Result::class.java)
            handler.onMethodCall(io.flutter.plugin.common.MethodCall("start",options),reply)
            verify(reply).error("qr_unsupported","qr_unsupported",null)
        }
        verifyNoInteractions(textures)
        handler.dispose(binding)
    }

    private data class StartCallbacks(
        val success: MobileScannerStartedCallback,
        val failure: (Exception) -> Unit,
    )

    private class StartFixture {
        val starts = mutableListOf<StartCallbacks>()
        private val activity = Robolectric.buildActivity(QrActivity::class.java).setup().get()
        private val scanner = mock(MobileScanner::class.java, org.mockito.stubbing.Answer<Any?> { call ->
            if (call.method.name == "start") starts.add(StartCallbacks(call.getArgument(5),call.getArgument(6)))
            RETURNS_DEFAULTS.answer(call)
        })
        var handler = newHandler()
        private fun newHandler(): MobileScannerHandler {
            val messenger = mock(io.flutter.plugin.common.BinaryMessenger::class.java)
            return MobileScannerHandler(activity,BarcodeHandler(messenger),messenger,MobileScannerPermissions(),{},mock(TextureRegistry::class.java)).also {
                ReflectionHelpers.setField(it,"mobileScanner",scanner)
            }
        }
        fun start() = mock(io.flutter.plugin.common.MethodChannel.Result::class.java).also {
            handler.onMethodCall(io.flutter.plugin.common.MethodCall("start",mapOf("formats" to listOf(256))),it)
        }
        fun dispose() = handler.dispose(mock(io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding::class.java))
        fun replaceHandler() { dispose();handler = newHandler() }
        fun success(index: Int) {
            starts[index].success(dev.steenbakker.mobile_scanner.objects.MobileScannerStartParameters(
                width=320.0,height=240.0,naturalDeviceOrientation="PORTRAIT_UP",sensorOrientation=90,
                handlesCropAndRotation=true,currentTorchState=-1,id=7,numberOfCameras=1,cameraDirection=1))
        }
        fun idle() = shadowOf(Looper.getMainLooper()).idle()
    }

    @Test fun duplicatePendingStartRetainsAUntilItsSuccessOrFailure() {
        for (success in listOf(true,false)) {
            val fixture = StartFixture()
            try {
                val a = fixture.start()
                val b = fixture.start()
                assertEquals(1,fixture.starts.size)
                verify(b,times(1)).error("qr_busy","qr_busy",null);verifyNoMoreInteractions(b)
                verifyNoInteractions(a)
                if (success) fixture.success(0) else fixture.starts[0].failure(NoCamera())
                fixture.idle()
                if (success) verify(a,times(1)).success(any()) else verify(a,times(1)).error(anyString(),anyString(),isNull())
                verifyNoMoreInteractions(a)
                assertNull(ReflectionHelpers.getField<Any?>(fixture.handler,"pendingStart"))
            } finally { fixture.dispose() }
        }
    }

    @Test fun stoppedOrDisposedARepliesOnceAndCannotClearOrCompleteC() {
        for (replace in listOf(false,true)) {
            val fixture = StartFixture()
            try {
                val a = fixture.start()
                if (replace) fixture.replaceHandler() else {
                    val stop = mock(io.flutter.plugin.common.MethodChannel.Result::class.java)
                    fixture.handler.onMethodCall(io.flutter.plugin.common.MethodCall("stop",null),stop)
                    verify(stop).success(null)
                }
                verify(a,times(1)).error("qr_cancelled","qr_cancelled",null)
                val c = fixture.start()
                assertEquals(2,fixture.starts.size)
                val pendingC = ReflectionHelpers.getField<Any?>(fixture.handler,"pendingStart")
                fixture.success(0);fixture.starts[0].failure(NoCamera());fixture.idle()
                verifyNoMoreInteractions(a);verifyNoInteractions(c)
                assertSame(pendingC,ReflectionHelpers.getField<Any?>(fixture.handler,"pendingStart"))
                fixture.success(1);fixture.idle()
                verify(c,times(1)).success(any());verifyNoMoreInteractions(c)
                assertNull(ReflectionHelpers.getField<Any?>(fixture.handler,"pendingStart"))
            } finally { fixture.dispose() }
        }
    }

    @Test fun realAnalyzerClosesEveryFrameAndDoesNotDeduplicateOutsideWindow() {
        val activity = Robolectric.buildActivity(QrActivity::class.java).setup().get()
        val captures = mutableListOf<List<Map<String,Any?>>>()
        val scanner = MobileScanner(activity,mock(TextureRegistry::class.java),
            { values, bytes, _, _ -> assertNull(bytes); captures.add(values) },
            { fail(it) },DeviceOrientationListener(activity))
        ReflectionHelpers.setField(scanner,"active",true)
        val bytes = javaClass.getResourceAsStream("/qr/url.png")!!.use { it.readBytes() }
        val bitmap = BitmapFactory.decodeByteArray(bytes,0,bytes.size)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
        fun frame(): ImageProxy {
            val frame = mock(ImageProxy::class.java)
            val plane = mock(ImageProxy.PlaneProxy::class.java)
            val info = mock(ImageInfo::class.java)
            `when`(frame.width).thenReturn(bitmap.width);`when`(frame.height).thenReturn(bitmap.height)
            `when`(frame.cropRect).thenReturn(Rect(0,0,bitmap.width,bitmap.height))
            `when`(frame.planes).thenReturn(arrayOf(plane));`when`(frame.imageInfo).thenReturn(info)
            `when`(plane.buffer).thenReturn(ByteBuffer.wrap(ByteArray(pixels.size) { (pixels[it] and 255).toByte() }))
            `when`(plane.rowStride).thenReturn(bitmap.width);`when`(plane.pixelStride).thenReturn(1)
            return frame
        }
        scanner.scanWindow = listOf(0f,0f,0.05f,0.05f)
        val outside = frame();scanner.captureOutput.analyze(outside);shadowOf(Looper.getMainLooper()).idle()
        assertTrue(captures.isEmpty());verify(outside,times(1)).close()
        scanner.scanWindow = null
        val inside = frame();scanner.captureOutput.analyze(inside);shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1,captures.size);verify(inside,times(1)).close()
        val duplicate = frame();scanner.captureOutput.analyze(duplicate);shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1,captures.size);verify(duplicate,times(1)).close()
        val late = frame();scanner.captureOutput.analyze(late);scanner.dispose();shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1,captures.size);verify(late,times(1)).close()
        bitmap.recycle()
    }

    @Test fun cameraLeaseCannotBeReplacedUntilActualWorkerExit() {
        val lease = QrCameraWork.acquire()!!
        val entered = CountDownLatch(1);val release = CountDownLatch(1);val exited = CountDownLatch(1)
        try {
            lease.execute { entered.countDown();release.await();exited.countDown() }
            assertTrue(entered.await(3,TimeUnit.SECONDS))
            lease.close()
            assertNull(QrCameraWork.acquire())
        } finally { release.countDown() }
        assertTrue(exited.await(3,TimeUnit.SECONDS))
        var replacement: QrCameraWork.Lease? = null
        val end = System.nanoTime()+TimeUnit.SECONDS.toNanos(3)
        while (replacement == null && System.nanoTime()<end) { replacement=QrCameraWork.acquire();Thread.yield() }
        assertNotNull(replacement);replacement!!.close()
    }
}
