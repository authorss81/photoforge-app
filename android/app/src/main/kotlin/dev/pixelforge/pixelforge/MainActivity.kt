package dev.pixelforge.pixelforge

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private var photoPickerResult: MethodChannel.Result? = null

    /// System Photo Picker. Needs no permission and returns only what the
    /// user selected. Capped so one enthusiastic selection cannot OOM the app;
    /// the batch memory guard handles the rest.
    private val pickImagesLauncher = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(20),
    ) { uris: List<Uri> ->
        val result = photoPickerResult
        photoPickerResult = null
        if (result == null) return@registerForActivityResult
        if (uris.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return@registerForActivityResult
        }
        try {
            result.success(
                uris.mapNotNull { uri ->
                    try {
                        readPickedFile(uri)
                    } catch (e: Exception) {
                        null
                    }
                },
            )
        } catch (e: Exception) {
            result.error("PICK", e.message, null)
        }
    }

    private fun readPickedFile(uri: Uri): Map<String, Any>? {
        val name = contentResolver.query(uri, null, null, null, null)?.use { c ->
            val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (c.moveToFirst() && i >= 0) c.getString(i) else null
        } ?: "image";
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: return null
        return mapOf("name" to name, "bytes" to bytes)
    }
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pixelforge/system_picker",
        ).setMethodCallHandler { call, result ->
            if (call.method != "pickImages") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // Photo Picker needs API 30 for PickMultipleVisualMedia through
            // this contract on all devices; below that the Dart side falls
            // back to the file picker instead of failing here.
            if (Build.VERSION.SDK_INT < 30) {
                result.error(
                    "UNSUPPORTED",
                    "System photo picker needs Android 11 (API 30)+",
                    null,
                )
                return@setMethodCallHandler
            }
            if (photoPickerResult != null) {
                result.error("BUSY", "a pick is already in progress", null)
                return@setMethodCallHandler
            }
            photoPickerResult = result
            try {
                pickImagesLauncher.launch(
                    PickVisualMediaRequest(
                        ActivityResultContracts.PickVisualMedia.ImageOnly,
                    ),
                )
            } catch (e: Exception) {
                photoPickerResult = null
                result.error("PICK", e.message, null)
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
