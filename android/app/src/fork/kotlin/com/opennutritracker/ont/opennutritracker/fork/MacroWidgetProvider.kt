package com.opennutritracker.ont.opennutritracker.fork

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import com.opennutritracker.ont.opennutritracker.R
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.NumberFormat
import java.time.LocalDateTime

/**
 * OpenBite's home-screen widget (seam S50): today's energy, protein, carbs and fat against their
 * goals, as the app's Home last saved them (`lib/fork/widget/macro_widget.dart`). Upstream has an
 * iOS widget only. Shows a prompt to open the app while there is nothing saved, or once upstream's
 * calorie snapshot is cleared (a profile wiped or switched away); after the logical day ends it
 * shows nothing eaten against the same goals until the app is opened again.
 */
class MacroWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val figures = read(widgetData)
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fork_macro_widget)
            open?.let { views.setOnClickPendingIntent(R.id.fork_widget_root, it) }
            if (figures == null) {
                views.setViewVisibility(R.id.fork_widget_figures, View.GONE)
                views.setViewVisibility(R.id.fork_widget_empty, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.fork_widget_figures, View.VISIBLE)
                views.setViewVisibility(R.id.fork_widget_empty, View.GONE)
                show(views, R.id.fork_widget_energy, R.id.fork_widget_energy_bar,
                    figures.getJSONArray("energy"), figures.getString("energyUnit"), "")
                show(views, R.id.fork_widget_protein, R.id.fork_widget_protein_bar,
                    figures.getJSONArray("protein"), "g", "Protein ")
                show(views, R.id.fork_widget_carbs, R.id.fork_widget_carbs_bar,
                    figures.getJSONArray("carbs"), "g", "Carbs ")
                show(views, R.id.fork_widget_fat, R.id.fork_widget_fat_bar,
                    figures.getJSONArray("fat"), "g", "Fat ")
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** The saved figures, eaten zeroed when their day is over; null when there are none. */
    private fun read(data: SharedPreferences): JSONObject? {
        if (data.getString(CALORIE_SNAPSHOT, null) == null) return null
        val json = data.getString(STORAGE_KEY, null) ?: return null
        return try {
            val figures = JSONObject(json)
            val today = LocalDateTime.now()
                .minusMinutes(figures.optLong("offsetMinutes", 0))
                .toLocalDate()
                .toString()
            if (figures.getString("day") != today) {
                for (key in listOf("energy", "protein", "carbs", "fat")) {
                    figures.getJSONArray(key).put(0, 0)
                }
            }
            figures
        } catch (e: Exception) {
            null
        }
    }

    private fun show(
        views: RemoteViews,
        text: Int,
        bar: Int,
        figures: org.json.JSONArray,
        unit: String,
        label: String,
    ) {
        val eaten = figures.getInt(0)
        val goal = figures.getInt(1)
        val number = NumberFormat.getIntegerInstance()
        views.setTextViewText(
            text,
            "$label${number.format(eaten)} / ${number.format(goal)} $unit",
        )
        views.setProgressBar(bar, if (goal > 0) goal else 1, eaten.coerceAtMost(goal), false)
    }

    companion object {
        const val STORAGE_KEY = "openbite_macro_widget"
        const val CALORIE_SNAPSHOT = "ont_calorie_snapshot"
    }
}
