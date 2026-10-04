package dev.pixelforge.pixelforge

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
    private var backgroundChannel: MethodChannel? = null

    /// URIs shared into the app that Dart has not collected yet.
    private val pendingShared = mutableListOf<Uri>()

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
        collectSharedIntent(intent)
        handleCancelExtra(intent)
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
            "dev.pixelforge/background",
        ).also { backgroundChannel = it }
            .setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val total = call.argument<Int>("total") ?: 1
                    val intent = Intent(this, BatchService::class.java).apply {
                        putExtra(
                            BatchService.EXTRA_COMMAND,
                            BatchService.COMMAND_PROGRESS,
                        )
                        putExtra(BatchService.EXTRA_DONE, 0)
                        putExtra(BatchService.EXTRA_TOTAL, total)
                    }
                    if (Build.VERSION.SDK_INT >= 26) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "progress" -> {
                    val done = call.argument<Int>("done") ?: 0
                    val total = call.argument<Int>("total") ?: 1
                    val intent = Intent(this, BatchService::class.java).apply {
                        putExtra(
                            BatchService.EXTRA_COMMAND,
                            BatchService.COMMAND_PROGRESS,
                        )
                        putExtra(BatchService.EXTRA_DONE, done)
                        putExtra(BatchService.EXTRA_TOTAL, total)
                    }
                    startService(intent)
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, BatchService::class.java).apply {
                        putExtra(
                            BatchService.EXTRA_COMMAND,
                            BatchService.COMMAND_STOP,
                        )
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pixelforge/shared_content",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedImages" -> {
                    try {
                        val out = pendingShared.mapNotNull { readPickedFile(it) }
                        pendingShared.clear()
                        result.success(out)
                    } catch (e: Exception) {
                        result.error("SHARE", e.message, null)
                    }
                }
                "saveToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "image"
                    if (bytes == null) {
                        result.error("ARG", "missing image bytes", null)
                    } else {
                        try {
                            result.success(saveToGallery(bytes, name))
                        } catch (e: Exception) {
                            result.error("SAVE", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectSharedIntent(intent)
        handleCancelExtra(intent)
    }

    /// The notification's cancel action reopens this activity with an extra
    /// instead of talking to Dart from a receiver, which cannot reach the
    /// Flutter engine cleanly. Dart listens for the onCancel call below.
    private fun handleCancelExtra(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_CANCEL_BATCH, false) == true) {
            intent.removeExtra(EXTRA_CANCEL_BATCH)
            backgroundChannel?.invokeMethod("onCancel", null)
        }
    }

    companion object {
        const val EXTRA_CANCEL_BATCH = "pixelforge_cancel_batch"
    }

    /// Stashes shared image URIs for Dart to collect. Reading happens lazily
    /// on collection so a large share does not block the launch.
    private fun collectSharedIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val uri = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (uri != null && pendingShared.size < 20) pendingShared.add(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val uris = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(
                        Intent.EXTRA_STREAM, Uri::class.java,
                    )
                } else {
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (uris != null) {
                    for (u in uris) {
                        if (pendingShared.size >= 20) break
                        if (u != null) pendingShared.add(u)
                    }
                }
            }
        }
    }

    /// Writes into MediaStore, which needs no permission on API 29+. Below
    /// that a write would need storage permission, which this app will not
    /// request, so it fails with a message saying exactly that.
    private fun saveToGallery(bytes: ByteArray, name: String): String {
        if (Build.VERSION.SDK_INT < 29) {
            throw Exception(
                "Saving to the gallery needs Android 10 (API 29)+ without a " +
                    "storage permission, which this app does not request",
            )
        }
        val ext = name.substringAfterLast('.', "jpg").lowercase()
        val mime = when (ext) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            else -> "image/jpeg"
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/PixelForge",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values,
        ) ?: throw Exception("MediaStore refused the insert")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("MediaStore would not open the file")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
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
