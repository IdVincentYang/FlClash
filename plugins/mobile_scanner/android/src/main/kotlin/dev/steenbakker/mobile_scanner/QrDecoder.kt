package dev.steenbakker.mobile_scanner

import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.GrayscaleLuminanceSource
import com.google.zxing.NotFoundException
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import java.io.ByteArrayInputStream
import java.nio.ByteBuffer

internal object QrDecoder {
    fun decode(source: GrayscaleLuminanceSource): List<Map<String, Any?>> {
        val reader = QRCodeMultiReader()
        return try {
            reader.decodeMultiple(BinaryBitmap(HybridBinarizer(source)),
                mapOf(DecodeHintType.TRY_HARDER to true)).map { result ->
                mapOf("rawValue" to result.text, "format" to 256, "type" to 7)
            }
        } catch (_: NotFoundException) {
            emptyList()
        } finally {
            reader.reset()
        }
    }

    fun luminance(
        input: ByteBuffer, width: Int, height: Int, rowStride: Int, pixelStride: Int,
        rotation: Int, crop: android.graphics.Rect, window: List<Float>?, invert: Boolean,
    ): GrayscaleLuminanceSource {
        require(width > 0 && height > 0 && width.toLong() * height <= 16_000_000)
        require(rowStride > 0 && pixelStride > 0 && rotation in listOf(0, 90, 180, 270))
        require(crop.left >= 0 && crop.top >= 0 && crop.right <= width && crop.bottom <= height && !crop.isEmpty)
        val w = crop.width()
        val h = crop.height()
        val uprightWidth = if (rotation % 180 == 0) w else h
        val uprightHeight = if (rotation % 180 == 0) h else w
        val pixels = ByteArray(w * h)
        val origin = input.position()
        for (y in 0 until h) for (x in 0 until w) {
            val offset = origin.toLong() + (crop.top + y).toLong() * rowStride + (crop.left + x).toLong() * pixelStride
            require(offset < input.limit())
            val dx = when (rotation) { 90 -> h - 1 - y; 180 -> w - 1 - x; 270 -> y; else -> x }
            val dy = when (rotation) { 90 -> x; 180 -> h - 1 - y; 270 -> w - 1 - x; else -> y }
            val value = input.get(offset.toInt()).toInt() and 255
            pixels[dy * uprightWidth + dx] = (if (invert) 255 - value else value).toByte()
        }
        val source = GrayscaleLuminanceSource(uprightWidth, uprightHeight, pixels)
        if (window == null) return source
        require(window.size == 4 && window.all { it.isFinite() && it in 0f..1f })
        val left = (window[0] * uprightWidth).toInt()
        val top = (window[1] * uprightHeight).toInt()
        val right = (window[2] * uprightWidth).toInt()
        val bottom = (window[3] * uprightHeight).toInt()
        require(right > left && bottom > top)
        return source.crop(left, top, right - left, bottom - top) as GrayscaleLuminanceSource
    }

    fun image(bytes: ByteArray, checkpoint: () -> Unit): List<Map<String, Any?>> {
        checkpoint()
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        require(options.outWidth > 0 && options.outHeight > 0 && options.outWidth.toLong() * options.outHeight <= 64_000_000)
        options.inSampleSize = 1
        while ((options.outWidth.toLong() + options.inSampleSize - 1) / options.inSampleSize *
            ((options.outHeight.toLong() + options.inSampleSize - 1) / options.inSampleSize) > 4_000_000) {
            options.inSampleSize *= 2
        }
        options.inJustDecodeBounds = false
        checkpoint()
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: throw IllegalArgumentException()
        try {
            checkpoint()
            require(bitmap.width.toLong() * bitmap.height <= 4_000_000)
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val source = RGBLuminanceSource(bitmap.width, bitmap.height, pixels)
            val orientation = ByteArrayInputStream(bytes).use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
            val gray = source.matrix
            val w = source.width
            val h = source.height
            val swap = orientation in 5..8
            val outputWidth = if (swap) h else w
            val output = ByteArray(gray.size)
            for (y in 0 until h) for (x in 0 until w) {
                val dx = when (orientation) { 2, 3 -> w - 1 - x; 5, 8 -> y; 6, 7 -> h - 1 - y; else -> x }
                val dy = when (orientation) { 3, 4 -> h - 1 - y; 5, 6 -> x; 7, 8 -> w - 1 - x; else -> y }
                output[dy * outputWidth + dx] = gray[y * w + x]
            }
            checkpoint()
            return decode(GrayscaleLuminanceSource(outputWidth, if (swap) w else h, output)).also { checkpoint() }
        } finally {
            bitmap.recycle()
        }
    }
}
