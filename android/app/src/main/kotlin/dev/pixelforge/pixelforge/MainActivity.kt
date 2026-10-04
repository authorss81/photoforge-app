package dev.pixelforge.pixelforge

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pixelforge/native_decoder",
        ).setMethodCallHandler { call, result ->
            if (call.method == "decodeImage") {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("ARG", "missing image bytes", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(decodeToPng(bytes))
                } catch (e: Exception) {
                    result.error("DECODE", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /// Decodes with the platform ImageDecoder and returns lossless PNG bytes.
    /// PNG round-trips through the Dart pipeline with no quality loss and no
    /// pixel-format negotiation, which is worth far more than the extra copy.
    private fun decodeToPng(bytes: ByteArray): ByteArray {
        if (Build.VERSION.SDK_INT < 28) {
            throw Exception(
                "This format needs Android 9 (API 28) or newer for platform decoding",
            )
        }
        val bitmap = ImageDecoder.decodeBitmap(
            ImageDecoder.createSource(ByteBuffer.wrap(bytes)),
        )
        val out = ByteArrayOutputStream()
        try {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        } finally {
            bitmap.recycle()
        }
        return out.toByteArray()
    }
}
