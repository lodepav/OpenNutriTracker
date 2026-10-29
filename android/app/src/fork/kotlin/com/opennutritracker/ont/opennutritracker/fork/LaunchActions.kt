package com.opennutritracker.ont.opennutritracker.fork

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.opennutritracker.ont.opennutritracker.MainActivity
import com.opennutritracker.ont.opennutritracker.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Launcher shortcuts and shares into the app (S167). Both reach [LaunchActionActivity], which
 * passes them on to [MainActivity] in the app's own task, so a running app is reused rather than
 * a second Flutter engine started inside the sharing app's task. A shared image is copied into
 * the cache first: the read grant belongs to this activity, not to MainActivity.
 */
object LaunchActions {
    const val EXTRA_KIND = "openbite.launch.kind"
    const val EXTRA_PATH = "openbite.launch.path"
    const val EXTRA_TEXT = "openbite.launch.text"
    private const val ACTION_SHORTCUT = "openbite.action.SHORTCUT"

    /** The launcher's long-press menu; dynamic because the app id differs by flavour. */
    fun publishShortcuts(context: Context) {
        val shortcuts = listOf(
            Triple("scan", "Scan barcode", R.drawable.fork_shortcut_scan),
            Triple("photo", "Photo log", R.drawable.fork_shortcut_photo),
            Triple("quickAdd", "Quick add", R.drawable.fork_shortcut_quick_add),
            Triple("weighIn", "Weigh in", R.drawable.fork_shortcut_weigh_in),
        ).mapIndexed { rank, (kind, label, icon) ->
            ShortcutInfoCompat.Builder(context, kind)
                .setShortLabel(label)
                .setIcon(IconCompat.createWithResource(context, icon))
                .setRank(rank)
                .setIntent(
                    Intent(context, LaunchActionActivity::class.java)
                        .setAction(ACTION_SHORTCUT)
                        .putExtra(EXTRA_KIND, kind)
                )
                .build()
        }
        try {
            ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
        } catch (_: Exception) {
            // A launcher that refuses them leaves the app as it was.
        }
    }

    /**
     * What [intent] asks of the app, as the Dart side reads it; null for an ordinary start.
     * MainActivity is exported, so any app can send these extras: a path is passed on only inside
     * [sharedDir], since the photo reader deletes the file it is given.
     */
    fun payload(context: Context, intent: Intent?): Map<String, String>? {
        val kind = intent?.getStringExtra(EXTRA_KIND) ?: return null
        return buildMap {
            put("kind", kind)
            intent.getStringExtra(EXTRA_PATH)
                ?.takeIf { isShared(context, it) }
                ?.let { put("path", it) }
            intent.getStringExtra(EXTRA_TEXT)?.let { put("text", it) }
        }
    }

    private fun isShared(context: Context, path: String): Boolean = try {
        File(path).canonicalPath.startsWith(sharedDir(context).canonicalPath + File.separator)
    } catch (_: Exception) {
        false
    }

    fun isShortcut(intent: Intent) = intent.action == ACTION_SHORTCUT

    /** Where shared images wait for the photo reader, which deletes each once read. */
    fun sharedDir(context: Context) = File(context.cacheDir, "fork_shared")
}

/** Takes a shortcut or a share, hands it to [MainActivity], and closes. */
class LaunchActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val intent = intent
        val type = intent.type.orEmpty()
        when {
            LaunchActions.isShortcut(intent) -> {
                val kind = intent.getStringExtra(LaunchActions.EXTRA_KIND)
                if (kind == null) finish() else forward { putExtra(LaunchActions.EXTRA_KIND, kind) }
            }
            intent.action == Intent.ACTION_SEND && type.startsWith("image/") -> {
                val uri = sharedUri(intent) ?: return finish()
                // Off the main thread: a picture from a cloud gallery may still be downloading.
                Thread {
                    val file = copy(uri)
                    runOnUiThread {
                        if (file == null) finish() else forward {
                            putExtra(LaunchActions.EXTRA_KIND, "sharedPhoto")
                            putExtra(LaunchActions.EXTRA_PATH, file.path)
                        }
                    }
                }.start()
            }
            intent.action == Intent.ACTION_SEND && type == "text/plain" -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
                if (text.isNullOrEmpty()) finish() else forward {
                    putExtra(LaunchActions.EXTRA_KIND, "sharedText")
                    // A meal or a recipe link, not a book.
                    putExtra(LaunchActions.EXTRA_TEXT, text.take(4000))
                }
            }
            else -> finish()
        }
    }

    private fun forward(extras: Intent.() -> Unit) {
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                .apply(extras)
        )
        finish()
    }

    @Suppress("DEPRECATION")
    private fun sharedUri(intent: Intent): Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)

    /** Into the cache, replacing any share not read yet; null when it cannot be read. */
    private fun copy(uri: Uri): File? {
        // a file:// share could name this app's own private files
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        return try {
            val dir = LaunchActions.sharedDir(this)
            dir.deleteRecursively()
            dir.mkdirs()
            val file = File(dir, "shared_${System.currentTimeMillis()}")
            contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { input.copyTo(it) }
            } ?: return null
            file
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Hands a launch's action to Dart: pulled once the main screen is up (a cold start's intent is
 * known before the engine is), pushed for one that reaches a running app. Registered by S167 in
 * MainActivity, which passes on [onNewIntent].
 */
class LaunchActionChannel(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "openbite/launch")
    private var pending: Map<String, String>? = take(activity.intent)

    init {
        LaunchActions.publishShortcuts(activity.applicationContext)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "consume") return@setMethodCallHandler result.notImplemented()
            result.success(pending)
            pending = null
        }
    }

    fun onNewIntent(intent: Intent) {
        val payload = take(intent) ?: return
        pending = payload
        channel.invokeMethod("launch", null)
    }

    /** Read once: a recreated activity keeps its intent, which must not log twice. */
    private fun take(intent: Intent?): Map<String, String>? {
        val payload = LaunchActions.payload(activity, intent) ?: return null
        intent?.removeExtra(LaunchActions.EXTRA_KIND)
        return payload
    }
}
