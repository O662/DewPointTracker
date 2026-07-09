package com.dewpoint.dew_point_tracker.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Schedules the WorkManager jobs that keep the widgets fresh without the app
 * being open. WorkManager persists across reboots, so a placed widget keeps
 * updating (roughly every 30 minutes, batched by the OS) indefinitely.
 */
object WidgetUpdater {
    private const val PERIODIC_WORK = "dewpoint_widget_refresh"
    private const val ONESHOT_WORK = "dewpoint_widget_refresh_now"

    private val widgetClasses = listOf(
        DewPointWidget::class.java,
        CurrentWidget::class.java,
        HourlyWidget::class.java,
        DailyWidget::class.java,
        LargeWidget::class.java,
    )

    fun hasWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return widgetClasses.any {
            manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty()
        }
    }

    private val networkRequired =
        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    fun ensureScheduled(context: Context) {
        val request = PeriodicWorkRequestBuilder<WidgetUpdateWorker>(30, TimeUnit.MINUTES)
            .setConstraints(networkRequired)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun refreshNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<WidgetUpdateWorker>()
            .setConstraints(networkRequired)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(ONESHOT_WORK, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancelIfUnused(context: Context) {
        if (!hasWidgets(context)) {
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK)
        }
    }

    /** Entry point for the app's method channel ("widgets changed, catch up"). */
    fun syncFromApp(context: Context) {
        if (hasWidgets(context)) {
            ensureScheduled(context)
            refreshNow(context)
        } else {
            cancelIfUnused(context)
        }
    }
}

/** Fetches fresh weather for the widgets' target location and redraws them. */
class WidgetUpdateWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        val target = WidgetStore.target(context)
        if (target == null) {
            // App has never resolved a location; widgets show the empty state.
            WidgetRenderer.renderAll(context)
            return Result.success()
        }
        return try {
            WidgetStore.saveSnapshot(context, OpenMeteo.fetch(target))
            WidgetRenderer.renderAll(context)
            Result.success()
        } catch (e: Exception) {
            // Keep showing the cached snapshot; retry a couple of times, then
            // let the next periodic run try again.
            WidgetRenderer.renderAll(context)
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }
}
