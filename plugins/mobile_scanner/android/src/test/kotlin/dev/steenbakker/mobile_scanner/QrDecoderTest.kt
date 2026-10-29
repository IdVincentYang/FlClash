package dev.steenbakker.mobile_scanner

import android.graphics.BitmapFactory
import android.graphics.Rect
import com.google.zxing.GrayscaleLuminanceSource
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Config
import java.nio.ByteBuffer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class QrDecoderTest {
    private fun fixture(name: String) = javaClass.getResourceAsStream("/qr/$name.png")!!.use { it.readBytes() }

    @Test fun independentCleanFixturesDecodeIncludingLongAndUnicode() {
        val expected = org.json.JSONObject(javaClass.getResourceAsStream("/qr/expected.json")!!.use { it.reader().readText() })
        for (name in expected.keys()) {
            val values = QrDecoder.image(fixture(name)) {}
            assertEquals(name, listOf(expected.getString(name)), values.map { it["rawValue"] })
            assertTrue(values.all { it["format"] == 256 && it["type"] == 7 })
            assertTrue(values.all { it.keys == setOf("rawValue", "format", "type") })
        }
        assertEquals(2048, expected.getString("long").length)
    }

    @Test fun mixedCodesAndExifImagesUseActualBitmapReader() {
        val values = QrDecoder.image(fixture("multiple")) {}.map { it["rawValue"] }.toSet()
        assertEquals(setOf("synthetic QR text, not a subscription", "https://example.invalid/subscription?token=SYNTHETIC-T09"),values)
        for (orientation in listOf(2,6)) {
            val bytes = fixture("exif_$orientation")
            val actual = androidx.exifinterface.media.ExifInterface(java.io.ByteArrayInputStream(bytes))
                .getAttributeInt(androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION,1)
            assertEquals(orientation,actual)
            assertEquals("https://example.invalid/subscription?token=SYNTHETIC-T09",QrDecoder.image(bytes) {}.single()["rawValue"])
        }
    }

    @Test fun damagedAndEmptyInputFailWithoutReturningPrefix() {
        for (input in listOf(byteArrayOf(), byteArrayOf(1,2,3), fixture("url").copyOf(20))) {
            assertThrows(Exception::class.java) { QrDecoder.image(input) {} }
        }
        assertTrue(QrDecoder.decode(GrayscaleLuminanceSource(64, 64, ByteArray(4096) { 255.toByte() })).isEmpty())
    }

    @Test fun cancelledBeforeOrAfterReadDoesNotDecode() {
        var checks = 0
        assertThrows(QrFailure::class.java) {
            QrDecoder.image(fixture("url")) { if (++checks == 2) throw QrFailure("qr_cancelled") }
        }
        assertEquals(2, checks)
    }

    @Test fun strideCropAndRotationFollowKnownPixelOracle() {
        val input = ByteBuffer.wrap(byteArrayOf(9, 1, 9, 2, 9, 3, 9, 8, 4, 8, 5, 8, 6, 8))
        input.position(1)
        val expected = mapOf(
            0 to listOf(1,2,3,4,5,6), 90 to listOf(4,1,5,2,6,3),
            180 to listOf(6,5,4,3,2,1), 270 to listOf(3,6,2,5,1,4),
        )
        for ((rotation, pixels) in expected) {
            val source = QrDecoder.luminance(input.duplicate(), 3,2,7,2,rotation,Rect(0,0,3,2),null,false)
            assertEquals(pixels, source.matrix.map { it.toInt() and 255 })
        }
        val crop = QrDecoder.luminance(input.duplicate(),3,2,7,2,0,Rect(1,0,3,2),null,false)
        assertEquals(listOf(2,3,5,6),crop.matrix.map { it.toInt() and 255 })
    }

    @Test fun actualCameraLuminanceConsumerFiltersOutsideThenAcceptsInside() {
        val bitmap = BitmapFactory.decodeByteArray(fixture("url"),0,fixture("url").size)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
        val raw = ByteArray(pixels.size) { (pixels[it] and 255).toByte() }
        val windowOutside = listOf(0f,0f,0.05f,0.05f)
        val tiny = QrDecoder.luminance(ByteBuffer.wrap(raw),bitmap.width,bitmap.height,bitmap.width,1,0,Rect(0,0,bitmap.width,bitmap.height),windowOutside,false)
        assertTrue(QrDecoder.decode(tiny).isEmpty())
        val full = QrDecoder.luminance(ByteBuffer.wrap(raw),bitmap.width,bitmap.height,bitmap.width,1,90,Rect(0,0,bitmap.width,bitmap.height),null,false)
        assertEquals("https://example.invalid/subscription?token=SYNTHETIC-T09",QrDecoder.decode(full).single()["rawValue"])
        bitmap.recycle()
    }
}
