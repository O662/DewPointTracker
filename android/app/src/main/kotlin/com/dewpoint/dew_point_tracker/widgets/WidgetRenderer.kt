package com.dewpoint.dew_point_tracker.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import android.widget.RemoteViews
import com.dewpoint.dew_point_tracker.MainActivity
import com.dewpoint.dew_point_tracker.R
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Builds and pushes RemoteViews for every placed widget from the cached
 * snapshot. Each instance is rendered against its own size (from the widget
 * options), so resizing a widget re-buckets its layout, trims forecast
 * columns that no longer fit, and redraws the gauge at the right width.
 */
object WidgetRenderer {

    private data class State(
        val snapshot: Snapshot,
        val useF: Boolean,
        val spicy: Boolean,
        val bands: List<ComfortBand>,
    )

    /** Reported min-height (dp) above which the small widgets use their
     *  expanded layout — roughly "two or more launcher rows". */
    private const val BIG_HEIGHT_DP = 100

    private val hourFormat = DateTimeFormatter.ofPattern("h a", Locale.getDefault())
    private val dayFormat = DateTimeFormatter.ofPattern("EEE", Locale.getDefault())
    private val updatedFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault())

    /** Redraw every placed widget from the cached snapshot + current settings. */
    fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val snapshot = WidgetStore.cachedSnapshot(context)
        val state = snapshot?.let {
            State(
                it,
                WidgetStore.useFahrenheit(context),
                WidgetStore.allowSpicy(context),
                WidgetStore.bands(context),
            )
        }

        renderType(context, manager, DewPointWidget::class.java) { w, h ->
            buildDewPoint(context, state, w, h)
        }
        renderType(context, manager, CurrentWidget::class.java) { w, h ->
            buildCurrent(context, state, w, h)
        }
        renderType(context, manager, HourlyWidget::class.java) { w, h ->
            buildHourly(context, state, w, h)
        }
        renderType(context, manager, DailyWidget::class.java) { w, h ->
            buildDaily(context, state, w, h)
        }
        renderType(context, manager, LargeWidget::class.java) { w, _ ->
            buildLarge(context, state, w)
        }
    }

    private fun renderType(
        context: Context,
        manager: AppWidgetManager,
        cls: Class<*>,
        build: (widthDp: Int, heightDp: Int) -> RemoteViews,
    ) {
        for (id in manager.getAppWidgetIds(ComponentName(context, cls))) {
            val options = manager.getAppWidgetOptions(id)
            val w = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
            val h = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
            manager.updateAppWidget(id, build(w, h))
        }
    }

    // -------------------------------------------------------------------
    // Individual widgets
    // -------------------------------------------------------------------

    private fun buildDewPoint(
        context: Context, state: State?, widthDp: Int, heightDp: Int,
    ): RemoteViews {
        val s = state ?: return empty(context)
        val big = heightDp >= BIG_HEIGHT_DP
        val layout = if (big) R.layout.widget_dew_point_big else R.layout.widget_dew_point
        val views = base(context, layout, s)
        val band = s.bands[Comfort.indexFor(s.snapshot.dewC)]
        views.setTextViewText(R.id.dew_value, temp(s.snapshot.dewC, s.useF))
        views.setTextViewText(R.id.comfort_label, band.label)
        views.setTextColor(R.id.comfort_label, band.color)
        views.setTextViewText(R.id.feels, "Feels like ${temp(s.snapshot.feelsC, s.useF)}")
        if (big) {
            views.setTextViewText(R.id.blurb, Comfort.blurb(band, s.spicy) ?: "")
            val gaugeWidthDp = (if (widthDp > 0) widthDp else 220) - 32
            views.setImageViewBitmap(
                R.id.gauge,
                gaugeBitmap(context, gaugeWidthDp, s.snapshot.dewC, band.color),
            )
        }
        return views
    }

    private fun buildCurrent(
        context: Context, state: State?, widthDp: Int, heightDp: Int,
    ): RemoteViews {
        val s = state ?: return empty(context)
        val snap = s.snapshot
        val big = heightDp >= BIG_HEIGHT_DP
        val layout = if (big) R.layout.widget_current_big else R.layout.widget_current
        val views = base(context, layout, s)
        views.setImageViewBitmap(
            R.id.glyph,
            GlyphRenderer.bitmap(context, snap.code, snap.isDay, if (big) 56 else 42),
        )
        views.setTextViewText(R.id.temp, temp(snap.tempC, s.useF))
        views.setTextViewText(R.id.cond, Conditions.label(snap.code))
        views.setTextViewText(R.id.loc, snap.label)
        if (big) {
            val today = snap.daily.firstOrNull()
            val hiLo = today?.let {
                "  •  H ${temp(it.hiC, s.useF)} / L ${temp(it.loC, s.useF)}"
            } ?: ""
            views.setTextViewText(
                R.id.metrics1, "Feels like ${temp(snap.feelsC, s.useF)}$hiLo")
            val wind = if (s.useF) {
                "${(snap.windKmh * 0.621371).roundToInt()} mph"
            } else {
                "${snap.windKmh.roundToInt()} km/h"
            }
            views.setTextViewText(
                R.id.metrics2, "Humidity ${snap.humidity}%  •  Wind $wind")
        }
        return views
    }

    private val hourlyColIds = intArrayOf(
        R.id.h0_col, R.id.h1_col, R.id.h2_col, R.id.h3_col, R.id.h4_col, R.id.h5_col)
    private val hourlyTimeIds = intArrayOf(
        R.id.h0_time, R.id.h1_time, R.id.h2_time, R.id.h3_time, R.id.h4_time, R.id.h5_time)
    private val hourlyIconIds = intArrayOf(
        R.id.h0_icon, R.id.h1_icon, R.id.h2_icon, R.id.h3_icon, R.id.h4_icon, R.id.h5_icon)
    private val hourlyTempIds = intArrayOf(
        R.id.h0_temp, R.id.h1_temp, R.id.h2_temp, R.id.h3_temp, R.id.h4_temp, R.id.h5_temp)

    private fun buildHourly(
        context: Context, state: State?, widthDp: Int, heightDp: Int,
    ): RemoteViews {
        val s = state ?: return empty(context)
        val views = base(context, R.layout.widget_hourly, s)
        // A column needs ~44dp to stay readable; drop trailing hours as the
        // widget narrows (down to its 2-cell minimum).
        val cols = if (widthDp > 0) (widthDp / 44).coerceIn(2, 6) else 6
        trimColumns(views, hourlyColIds, cols)
        fillHours(context, views, s, hourlyTimeIds, hourlyIconIds, hourlyTempIds,
            startIndex = 0)
        return views
    }

    private val dailyColIds =
        intArrayOf(R.id.d0_col, R.id.d1_col, R.id.d2_col, R.id.d3_col, R.id.d4_col)
    private val dailyDayIds =
        intArrayOf(R.id.d0_day, R.id.d1_day, R.id.d2_day, R.id.d3_day, R.id.d4_day)
    private val dailyIconIds =
        intArrayOf(R.id.d0_icon, R.id.d1_icon, R.id.d2_icon, R.id.d3_icon, R.id.d4_icon)
    private val dailyHiIds =
        intArrayOf(R.id.d0_hi, R.id.d1_hi, R.id.d2_hi, R.id.d3_hi, R.id.d4_hi)
    private val dailyLoIds =
        intArrayOf(R.id.d0_lo, R.id.d1_lo, R.id.d2_lo, R.id.d3_lo, R.id.d4_lo)

    private fun buildDaily(
        context: Context, state: State?, widthDp: Int, heightDp: Int,
    ): RemoteViews {
        val s = state ?: return empty(context)
        val views = base(context, R.layout.widget_daily, s)
        val cols = if (widthDp > 0) (widthDp / 50).coerceIn(2, 5) else 5
        trimColumns(views, dailyColIds, cols)
        for (i in dailyDayIds.indices) {
            val day = s.snapshot.daily.getOrNull(i)
            if (day == null) {
                views.setViewVisibility(dailyColIds[i], View.GONE)
                continue
            }
            val label =
                if (day.date == LocalDate.now()) "Today" else dayFormat.format(day.date)
            views.setTextViewText(dailyDayIds[i], label)
            views.setImageViewBitmap(
                dailyIconIds[i], GlyphRenderer.bitmap(context, day.code, true, 24))
            views.setTextViewText(dailyHiIds[i], temp(day.hiC, s.useF))
            views.setTextViewText(dailyLoIds[i], temp(day.loC, s.useF))
        }
        return views
    }

    private val largeTimeIds = intArrayOf(
        R.id.l0_time, R.id.l1_time, R.id.l2_time, R.id.l3_time, R.id.l4_time)
    private val largeIconIds = intArrayOf(
        R.id.l0_icon, R.id.l1_icon, R.id.l2_icon, R.id.l3_icon, R.id.l4_icon)
    private val largeTempIds = intArrayOf(
        R.id.l0_temp, R.id.l1_temp, R.id.l2_temp, R.id.l3_temp, R.id.l4_temp)

    private fun buildLarge(context: Context, state: State?, widthDp: Int): RemoteViews {
        val s = state ?: return empty(context)
        val views = base(context, R.layout.widget_large, s)
        val snap = s.snapshot
        val band = s.bands[Comfort.indexFor(snap.dewC)]

        views.setTextViewText(R.id.loc, snap.label)
        val updated = Instant.ofEpochMilli(snap.fetchedAt)
            .atZone(ZoneId.systemDefault()).toLocalTime()
        views.setTextViewText(R.id.updated, "Updated ${updatedFormat.format(updated)}")

        views.setImageViewBitmap(
            R.id.glyph, GlyphRenderer.bitmap(context, snap.code, snap.isDay, 52))
        views.setTextViewText(R.id.temp, temp(snap.tempC, s.useF))
        views.setTextViewText(R.id.cond, Conditions.label(snap.code))
        views.setTextViewText(R.id.feels, "Feels like ${temp(snap.feelsC, s.useF)}")

        views.setTextViewText(R.id.comfort_label, band.label)
        views.setTextColor(R.id.comfort_label, band.color)
        val unitSuffix = if (s.useF) "°F" else "°C"
        views.setTextViewText(
            R.id.dew_value,
            "Dew point ${temp(snap.dewC, s.useF).dropLast(1)}$unitSuffix",
        )
        views.setTextViewText(R.id.blurb, Comfort.blurb(band, s.spicy) ?: "")

        // Draw the gauge at (roughly) the widget's current width so the thumb
        // circle isn't distorted by fitXY scaling.
        val gaugeWidthDp = (if (widthDp > 0) widthDp else 300) - 32
        views.setImageViewBitmap(
            R.id.gauge,
            gaugeBitmap(context, gaugeWidthDp, snap.dewC, band.color),
        )

        // The header already shows "now", so the strip starts at the next hour.
        fillHours(context, views, s, largeTimeIds, largeIconIds, largeTempIds,
            startIndex = 1)
        return views
    }

    // -------------------------------------------------------------------
    // Shared pieces
    // -------------------------------------------------------------------

    /** Inflate a layout and apply the condition background + tap-to-open. */
    private fun base(context: Context, layout: Int, state: State): RemoteViews {
        val views = RemoteViews(context.packageName, layout)
        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            Conditions.backgroundRes(state.snapshot.code, state.snapshot.isDay),
        )
        views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
        return views
    }

    private fun empty(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_empty)
        views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
        return views
    }

    private fun openApp(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun trimColumns(views: RemoteViews, colIds: IntArray, visible: Int) {
        for (i in colIds.indices) {
            views.setViewVisibility(
                colIds[i], if (i < visible) View.VISIBLE else View.GONE)
        }
    }

    private fun fillHours(
        context: Context,
        views: RemoteViews,
        state: State,
        timeIds: IntArray,
        iconIds: IntArray,
        tempIds: IntArray,
        startIndex: Int,
    ) {
        for (i in timeIds.indices) {
            val hour = state.snapshot.hourly.getOrNull(startIndex + i)
            if (hour == null) {
                views.setTextViewText(timeIds[i], "")
                views.setTextViewText(tempIds[i], "")
                continue
            }
            val label = if (startIndex + i == 0) "Now" else hourFormat.format(hour.time)
            views.setTextViewText(timeIds[i], label)
            views.setImageViewBitmap(
                iconIds[i],
                GlyphRenderer.bitmap(
                    context, hour.code, Conditions.isDaytimeHour(hour.time.hour), 24),
            )
            views.setTextViewText(tempIds[i], temp(hour.tempC, state.useF))
        }
    }

    private fun temp(celsius: Double, useF: Boolean): String {
        val v = if (useF) celsius * 9 / 5 + 32 else celsius
        return "${v.roundToInt()}°"
    }

    /** The comfort gauge: gradient track + white thumb ringed in the band color. */
    private fun gaugeBitmap(
        context: Context,
        widthDp: Int,
        dewC: Double,
        thumbColor: Int,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val w = (widthDp.coerceAtLeast(120) * density).toInt()
        val h = (22 * density).toInt()
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val trackHeight = 10 * density
        val top = (h - trackHeight) / 2
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, w.toFloat(), 0f,
                Comfort.gaugeColors, null, Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRoundRect(
            RectF(0f, top, w.toFloat(), top + trackHeight),
            trackHeight / 2, trackHeight / 2, track,
        )

        val thumbRadius = 9 * density
        val cx = (Comfort.gaugePosition(dewC) * w)
            .coerceIn(thumbRadius, w - thumbRadius)
        val cy = h / 2f
        canvas.drawCircle(cx, cy, thumbRadius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE })
        canvas.drawCircle(cx, cy, thumbRadius - 1.5f * density,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 3 * density
                color = thumbColor
            })
        return bitmap
    }
}
