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

/**
 * OpenBite's trend-weight widget (seam S50): the smoothed weight and its change over a week, as
 * Home last saved them (`lib/fork/widget/macro_widget.dart`), already in the user's unit. Asks
 * for a weigh-in while there is no trend, or once upstream's calorie snapshot is cleared.
 */
class WeightWidgetProvider : HomeWidgetProvider() {
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
                1,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fork_weight_widget)
            open?.let { views.setOnClickPendingIntent(R.id.fork_weight_root, it) }
            if (figures == null) {
                views.setTextViewText(R.id.fork_weight_trend, "—")
                views.setTextViewText(R.id.fork_weight_change, "Log a weigh-in in OpenBite")
            } else {
                views.setTextViewText(R.id.fork_weight_trend, figures.getString("trend"))
                val change = figures.optString("change", "")
                views.setTextViewText(R.id.fork_weight_change, change)
                views.setViewVisibility(
                    R.id.fork_weight_change,
                    if (change.isEmpty() || change == "null") View.GONE else View.VISIBLE,
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun read(data: SharedPreferences): JSONObject? {
        if (data.getString(MacroWidgetProvider.CALORIE_SNAPSHOT, null) == null) return null
        val json = data.getString(STORAGE_KEY, null) ?: return null
        return try {
            JSONObject(json)
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        const val STORAGE_KEY = "openbite_weight_widget"
    }
}
