package com.opennutritracker.ont.opennutritracker.fork

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest

/**
 * The in-app updater's last step (D16), after openGym-Hevier's InstallPlugin: an APK the Dart
 * side downloaded into the cache directory is streamed through SHA-256, refused (and deleted)
 * when it does not match the release's checksum, and handed to Android's installer, which also
 * refuses an APK not signed with the installed app's key. Registered by seam S76 in MainActivity.
 *
 * `install` takes `fileName` and `sha256`. Errors are `missing`, `mismatch` or `io`.
 */
class UpdateInstallChannel(private val context: Context, engine: FlutterEngine) {
    private val scope = CoroutineScope(Dispatchers.Main)

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "openbite/update_install")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") return@setMethodCallHandler result.notImplemented()
                val file = File(context.cacheDir, call.argument<String>("fileName") ?: "")
                val expected = call.argument<String>("sha256") ?: ""
                scope.launch {
                    try {
                        if (!file.isFile) return@launch result.error("missing", null, null)
                        val actual = withContext(Dispatchers.IO) { sha256(file) }
                        if (!actual.equals(expected, ignoreCase = true)) {
                            file.delete()
                            return@launch result.error("mismatch", null, null)
                        }
                        val uri = FileProvider.getUriForFile(
                            context, "${context.packageName}.forkupdate", file
                        )
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("io", e.javaClass.simpleName, null)
                    }
                }
            }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(1 shl 16)
        file.inputStream().use { input ->
            while (true) {
                val n = input.read(buffer)
                if (n <= 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

/** The updater's own FileProvider class, so it never merges with a plugin's (S76). */
class UpdateFileProvider : FileProvider()
