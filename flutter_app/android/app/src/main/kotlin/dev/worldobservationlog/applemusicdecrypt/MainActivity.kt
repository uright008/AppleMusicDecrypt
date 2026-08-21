package dev.worldobservationlog.applemusicdecrypt

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.worldobservationlog.applemusicdecrypt/media_store",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveAudio") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.error(
                    "UNSUPPORTED_ANDROID",
                    "MediaStore saving requires Android 10 or newer",
                    null,
                )
                return@setMethodCallHandler
            }
            val displayName = call.argument<String>("displayName")
            val mimeType = call.argument<String>("mimeType")
            val relativePath = call.argument<String>("relativePath")
            val bytes = call.argument<ByteArray>("bytes")
            if (displayName.isNullOrBlank() ||
                mimeType.isNullOrBlank() ||
                relativePath.isNullOrBlank() ||
                bytes == null
            ) {
                result.error("INVALID_ARGUMENT", "Missing audio output data", null)
                return@setMethodCallHandler
            }
            val cleanPath = relativePath.replace('\\', '/').trim()
            if (displayName.contains('/') ||
                displayName.contains('\\') ||
                cleanPath.startsWith('/') ||
                cleanPath.split('/').any { it == ".." }
            ) {
                result.error("INVALID_ARGUMENT", "Unsafe audio output path", null)
                return@setMethodCallHandler
            }

            val resolver = applicationContext.contentResolver
            var uri: android.net.Uri? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                    put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                    put(
                        MediaStore.Audio.Media.RELATIVE_PATH,
                        "${Environment.DIRECTORY_MUSIC}/${cleanPath.trim('/')}"
                    )
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
                uri = resolver.insert(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: error("MediaStore insert failed")
                resolver.openOutputStream(uri, "w")?.use { output ->
                    output.write(bytes)
                    output.flush()
                } ?: error("MediaStore output stream is unavailable")
                val published = ContentValues().apply {
                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                }
                resolver.update(uri, published, null, null)
                result.success(uri.toString())
            } catch (error: Exception) {
                if (uri != null) resolver.delete(uri, null, null)
                result.error("MEDIA_STORE_WRITE_FAILED", error.message, null)
            }
        }
    }
}
