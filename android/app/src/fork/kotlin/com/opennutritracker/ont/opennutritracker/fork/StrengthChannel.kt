package com.opennutritracker.ont.opennutritracker.fork

import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * How strength is going in the current phase, as Go Hevier reports it (seam S183, D29; Hevier's
 * D95). `read` answers a map of the provider's row, or null when there is nothing to trust: Go
 * Hevier missing or not signed with OpenBite's key, or no row. Columns are read by name, as more
 * may be added, and this reads only those it uses. The develop build reads Go Hevier's debug
 * package, signed with the same debug key.
 */
class StrengthChannel(private val context: Context, engine: FlutterEngine) {
    private val scope = CoroutineScope(Dispatchers.Main)

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "openbite/strength")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") return@setMethodCallHandler result.notImplemented()
                scope.launch { result.success(withContext(Dispatchers.IO) { read() }) }
            }
    }

    private fun read(): Map<String, Any?>? {
        val hevier = if (context.packageName.endsWith(".develop")) {
            "ch.duartesantos.opengym.hevier.test"
        } else {
            "ch.duartesantos.opengym.hevier"
        }
        val authority = "$hevier.strength"
        return try {
            val manager = context.packageManager
            val provider = manager.resolveContentProvider(authority, 0)?.packageName ?: return null
            if (manager.checkSignatures(context.packageName, provider) !=
                PackageManager.SIGNATURE_MATCH
            ) {
                return null
            }
            context.contentResolver
                .query(Uri.parse("content://$authority/current"), null, null, null, null)
                ?.use { if (it.moveToFirst()) row(it) else null }
        } catch (e: SecurityException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    private fun row(cursor: Cursor): Map<String, Any?> {
        fun text(name: String) = cursor.getColumnIndex(name).takeIf { it >= 0 && !cursor.isNull(it) }
            ?.let { cursor.getString(it) }
        fun whole(name: String) = cursor.getColumnIndex(name).takeIf { it >= 0 && !cursor.isNull(it) }
            ?.let { cursor.getLong(it) }
        fun real(name: String) = cursor.getColumnIndex(name).takeIf { it >= 0 && !cursor.isNull(it) }
            ?.let { cursor.getDouble(it) }
        return mapOf(
            "trend" to text("trend"),
            "level" to text("level"),
            "muscles" to text("muscles"),
            "phase" to text("phase"),
            "sets_7d" to whole("sets_7d"),
            "sets_week_avg" to real("sets_week_avg"),
            "sessions_7d" to whole("sessions_7d"),
            "sessions_week_avg" to real("sessions_week_avg"),
            "last_workout_at" to whole("last_workout_at"),
        )
    }
}
