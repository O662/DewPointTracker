package com.weatherdew.app.widgets

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reads the state the Flutter app shares through SharedPreferences (the
 * shared_preferences plugin writes to "FlutterSharedPreferences" with a
 * "flutter." key prefix) and owns the widgets' own snapshot cache.
 */
object WidgetStore {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val CACHE_PREFS = "weather_widget_cache"
    private const val KEY_SNAPSHOT = "snapshot"

    /** Where the widgets should fetch weather for. */
    data class Target(val latitude: Double, val longitude: Double, val label: String)

    private fun flutter(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    private fun cache(context: Context): SharedPreferences =
        context.getSharedPreferences(CACHE_PREFS, Context.MODE_PRIVATE)

    /**
     * The location the app is currently viewing: the selected place if one is
     * set, otherwise the last device GPS fix the app resolved. Null until the
     * app has run at least once.
     */
    fun target(context: Context): Target? {
        val prefs = flutter(context)
        prefs.getString("flutter.selected_place", null)?.let { raw ->
            runCatching {
                val o = JSONObject(raw)
                return Target(
                    o.getDouble("latitude"),
                    o.getDouble("longitude"),
                    o.optString("name", ""),
                )
            }
        }
        prefs.getString("flutter.widget_last_fix", null)?.let { raw ->
            runCatching {
                val o = JSONObject(raw)
                return Target(
                    o.getDouble("latitude"),
                    o.getDouble("longitude"),
                    o.optString("label", ""),
                )
            }
        }
        return null
    }

    fun useFahrenheit(context: Context): Boolean =
        runCatching { flutter(context).getString("flutter.temp_unit", null) != "c" }
            .getOrDefault(true)

    /** True when the app's profanity filter is off (uncensored blurb pool). */
    fun allowSpicy(context: Context): Boolean =
        runCatching { !flutter(context).getBoolean("flutter.profanity_filter", true) }
            .getOrDefault(false)

    /** Comfort bands as written by WidgetBridge; fallbacks before first run. */
    fun bands(context: Context): List<ComfortBand> {
        val raw = flutter(context).getString("flutter.widget_blurbs", null)
            ?: return Comfort.fallbackBands()
        return runCatching {
            val arr = JSONArray(raw)
            require(arr.length() == Comfort.fallbackLabels.size)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                ComfortBand(
                    index = i,
                    label = o.getString("label"),
                    color = Color.parseColor(o.getString("color")),
                    clean = o.getJSONArray("clean").toStringList(),
                    spicy = o.getJSONArray("spicy").toStringList(),
                )
            }
        }.getOrDefault(Comfort.fallbackBands())
    }

    fun cachedSnapshot(context: Context): Snapshot? =
        Snapshot.fromJson(cache(context).getString(KEY_SNAPSHOT, null))

    fun saveSnapshot(context: Context, snapshot: Snapshot) {
        cache(context).edit().putString(KEY_SNAPSHOT, snapshot.toJson()).apply()
    }

    private fun JSONArray.toStringList(): List<String> =
        (0 until length()).map { getString(it) }
}
