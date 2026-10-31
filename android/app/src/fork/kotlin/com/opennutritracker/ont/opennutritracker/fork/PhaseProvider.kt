package com.opennutritracker.ont.opennutritracker.fork

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/**
 * Whether the user is cutting, maintaining or bulking, for Go Hevier (seam S182, D28), as Home last
 * saved it (`lib/fork/phase/shared_phase.dart`). Read-only, and only for apps signed with OpenBite's
 * key, which hold the permission `<application id>.permission.READ_PHASE`.
 *
 * Query `content://<application id>.phase/current`: one row of [COLUMNS], read by name as more may
 * be added, or no row while there is nothing to share (no profile set up, or it was wiped or
 * switched away, until Home loads again). `phase` is `cutting`, `maintaining` or `bulking`;
 * `rate_kg_per_week` is negative to lose; `target_kcal` is the day's target before activity;
 * `updated_at` is when Home saved it, in milliseconds since the epoch, for a reader to tell an app
 * no longer in use.
 */
class PhaseProvider : ContentProvider() {
    override fun onCreate() = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cursor = MatrixCursor(COLUMNS)
        val data = HomeWidgetPlugin.getData(context ?: return cursor)
        if (data.getString(MacroWidgetProvider.CALORIE_SNAPSHOT, null) == null) return cursor
        val json = data.getString(STORAGE_KEY, null) ?: return cursor
        try {
            val saved = JSONObject(json)
            cursor.addRow(
                arrayOf<Any>(
                    saved.getString("phase"),
                    saved.getDouble("rateKgPerWeek"),
                    saved.getInt("targetKcal"),
                    saved.getLong("updatedAt"),
                ),
            )
        } catch (e: org.json.JSONException) {
            return cursor
        }
        return cursor
    }

    override fun getType(uri: Uri) = "vnd.android.cursor.item/vnd.openbite.phase"

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("read-only")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("read-only")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("read-only")

    companion object {
        const val STORAGE_KEY = "openbite_shared_phase"
        val COLUMNS = arrayOf("phase", "rate_kg_per_week", "target_kcal", "updated_at")
    }
}
