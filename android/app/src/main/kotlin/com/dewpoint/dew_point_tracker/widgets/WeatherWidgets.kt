package com.dewpoint.dew_point_tracker.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle

/**
 * Shared behavior for all five home-screen widgets: render immediately from
 * the cached snapshot, keep the periodic background refresh alive while any
 * widget is placed, and kick off a fresh fetch.
 */
abstract class BaseWeatherWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WidgetRenderer.renderAll(context)
        WidgetUpdater.ensureScheduled(context)
        WidgetUpdater.refreshNow(context)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdater.ensureScheduled(context)
    }

    override fun onDisabled(context: Context) {
        WidgetUpdater.cancelIfUnused(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // Resize: redraw so the large widget's gauge matches the new width.
        WidgetRenderer.renderAll(context)
    }
}

/** Dew point + comfort band + feels-like. */
class DewPointWidget : BaseWeatherWidget()

/** Current temperature + sky conditions. */
class CurrentWidget : BaseWeatherWidget()

/** The next 6 hours. */
class HourlyWidget : BaseWeatherWidget()

/** The next 5 days. */
class DailyWidget : BaseWeatherWidget()

/** Conditions + dew point gauge and blurb + the next 3 hours. */
class LargeWidget : BaseWeatherWidget()
