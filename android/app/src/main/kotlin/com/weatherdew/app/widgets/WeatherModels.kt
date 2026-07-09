package com.weatherdew.app.widgets

import com.weatherdew.app.R
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit

/** One hour of forecast, in the target location's local time. */
data class HourEntry(val time: LocalDateTime, val tempC: Double, val code: Int)

/** One day of forecast (today first). */
data class DayEntry(val date: LocalDate, val hiC: Double, val loC: Double, val code: Int)

/**
 * A cached weather snapshot for the widgets — the native mirror of the app's
 * WeatherData model, fetched from the same Open-Meteo endpoint.
 */
data class Snapshot(
    val label: String,
    val tempC: Double,
    val feelsC: Double,
    val dewC: Double,
    val humidity: Int,
    val windKmh: Double,
    val isDay: Boolean,
    val code: Int,
    val hourly: List<HourEntry>,
    val daily: List<DayEntry>,
    val fetchedAt: Long,
) {
    fun toJson(): String {
        val o = JSONObject()
        o.put("label", label)
        o.put("tempC", tempC)
        o.put("feelsC", feelsC)
        o.put("dewC", dewC)
        o.put("hum", humidity)
        o.put("wind", windKmh)
        o.put("isDay", isDay)
        o.put("code", code)
        o.put("fetchedAt", fetchedAt)
        o.put("hourly", JSONArray().apply {
            hourly.forEach {
                put(JSONObject()
                    .put("t", it.time.toString())
                    .put("temp", it.tempC)
                    .put("c", it.code))
            }
        })
        o.put("daily", JSONArray().apply {
            daily.forEach {
                put(JSONObject()
                    .put("d", it.date.toString())
                    .put("hi", it.hiC)
                    .put("lo", it.loC)
                    .put("c", it.code))
            }
        })
        return o.toString()
    }

    companion object {
        fun fromJson(raw: String?): Snapshot? {
            if (raw.isNullOrEmpty()) return null
            return runCatching {
                val o = JSONObject(raw)
                val hours = o.getJSONArray("hourly")
                val days = o.getJSONArray("daily")
                Snapshot(
                    label = o.optString("label", ""),
                    tempC = o.getDouble("tempC"),
                    feelsC = o.getDouble("feelsC"),
                    dewC = o.getDouble("dewC"),
                    humidity = o.optInt("hum", 50),
                    windKmh = o.optDouble("wind", 0.0),
                    isDay = o.getBoolean("isDay"),
                    code = o.getInt("code"),
                    fetchedAt = o.getLong("fetchedAt"),
                    hourly = (0 until hours.length()).map { i ->
                        val h = hours.getJSONObject(i)
                        HourEntry(LocalDateTime.parse(h.getString("t")),
                            h.getDouble("temp"), h.getInt("c"))
                    },
                    daily = (0 until days.length()).map { i ->
                        val d = days.getJSONObject(i)
                        DayEntry(LocalDate.parse(d.getString("d")),
                            d.getDouble("hi"), d.getDouble("lo"), d.getInt("c"))
                    },
                )
            }.getOrNull()
        }
    }
}

/** Broad visual grouping of a WMO code — mirrors lib/models/weather_code.dart. */
enum class SkyCategory { CLEAR, PARTLY, CLOUDY, FOG, DRIZZLE, RAIN, SNOW, THUNDER }

object Conditions {
    fun category(code: Int): SkyCategory = when (code) {
        0, 1 -> SkyCategory.CLEAR
        2 -> SkyCategory.PARTLY
        3 -> SkyCategory.CLOUDY
        45, 48 -> SkyCategory.FOG
        51, 53, 55, 56, 57 -> SkyCategory.DRIZZLE
        61, 63, 65, 66, 67, 80, 81, 82 -> SkyCategory.RAIN
        71, 73, 75, 77, 85, 86 -> SkyCategory.SNOW
        95, 96, 99 -> SkyCategory.THUNDER
        else -> SkyCategory.CLOUDY
    }

    /** Human label — mirrors WeatherCondition.fromCode in the app. */
    fun label(code: Int): String = when (code) {
        0 -> "Clear sky"
        1 -> "Mainly clear"
        2 -> "Partly cloudy"
        3 -> "Overcast"
        45 -> "Fog"
        48 -> "Rime fog"
        51 -> "Light drizzle"
        53 -> "Drizzle"
        55 -> "Dense drizzle"
        56, 57 -> "Freezing drizzle"
        61 -> "Light rain"
        63 -> "Rain"
        65 -> "Heavy rain"
        66 -> "Freezing rain"
        67 -> "Heavy freezing rain"
        71 -> "Light snow"
        73 -> "Snow"
        75 -> "Heavy snow"
        77 -> "Snow grains"
        80 -> "Light showers"
        81 -> "Showers"
        82 -> "Violent showers"
        85 -> "Snow showers"
        86 -> "Heavy snow showers"
        95 -> "Thunderstorm"
        96 -> "Thunderstorm, hail"
        99 -> "Severe thunderstorm"
        else -> "Unknown"
    }

    fun emoji(code: Int, isDay: Boolean): String = when (category(code)) {
        SkyCategory.CLEAR -> if (isDay) "☀️" else "🌙"
        SkyCategory.PARTLY -> if (isDay) "⛅" else "☁️"
        SkyCategory.CLOUDY -> "☁️"
        SkyCategory.FOG -> "🌫️"
        SkyCategory.DRIZZLE -> "🌦️"
        SkyCategory.RAIN -> "🌧️"
        SkyCategory.SNOW -> "🌨️"
        SkyCategory.THUNDER -> "⛈️"
    }

    /** Background gradient matching the app's SkyPalette for this condition. */
    fun backgroundRes(code: Int, isDay: Boolean): Int = when (category(code)) {
        SkyCategory.CLEAR ->
            if (isDay) R.drawable.bg_sky_clear_day else R.drawable.bg_sky_clear_night
        SkyCategory.PARTLY ->
            if (isDay) R.drawable.bg_sky_partly_day else R.drawable.bg_sky_partly_night
        SkyCategory.CLOUDY ->
            if (isDay) R.drawable.bg_sky_cloudy_day else R.drawable.bg_sky_cloudy_night
        SkyCategory.FOG ->
            if (isDay) R.drawable.bg_sky_fog else R.drawable.bg_sky_cloudy_night
        SkyCategory.DRIZZLE, SkyCategory.RAIN ->
            if (isDay) R.drawable.bg_sky_rain_day else R.drawable.bg_sky_rain_night
        SkyCategory.SNOW ->
            if (isDay) R.drawable.bg_sky_snow_day else R.drawable.bg_sky_snow_night
        SkyCategory.THUNDER -> R.drawable.bg_sky_thunder
    }

    /** The app approximates per-hour day/night by clock time (hourly_strip.dart). */
    fun isDaytimeHour(hour: Int): Boolean = hour in 6..18
}

/**
 * A dew point comfort band. Labels, colors and blurb pools are written by the
 * Dart side (WidgetBridge) so they can never drift from the app; the
 * classification thresholds are the meteorological standard and live here too.
 */
data class ComfortBand(
    val index: Int,
    val label: String,
    val color: Int,
    val clean: List<String>,
    val spicy: List<String>,
)

object Comfort {
    // Fallbacks mirror lib/models/dew_point_comfort.dart (used only until the
    // app has run once and written the full pools).
    val fallbackLabels =
        listOf("Dry", "Comfortable", "Sticky", "Muggy", "Oppressive", "Miserable")
    val gaugeColors = intArrayOf(
        0xFF4FB0E8.toInt(), 0xFF35D29A.toInt(), 0xFFD8D24B.toInt(),
        0xFFF2A33C.toInt(), 0xFFEE6C4D.toInt(), 0xFFE3415E.toInt(),
    )

    fun fallbackBands(): List<ComfortBand> = fallbackLabels.mapIndexed { i, label ->
        ComfortBand(i, label, gaugeColors[i], emptyList(), emptyList())
    }

    fun indexFor(dewC: Double): Int {
        val f = dewC * 9 / 5 + 32
        return when {
            f < 50 -> 0
            f < 60 -> 1
            f < 65 -> 2
            f < 70 -> 3
            f < 75 -> 4
            else -> 5
        }
    }

    /** Normalised 0..1 position along the 35–80 °F comfort gauge. */
    fun gaugePosition(dewC: Double): Float {
        val f = dewC * 9 / 5 + 32
        return (((f - 35) / (80 - 35)).toFloat()).coerceIn(0f, 1f)
    }

    /**
     * Today's blurb for a band — the same daily rotation as
     * DewPointComfort.blurb so the widget and the app always agree.
     */
    fun blurb(band: ComfortBand, spicyAllowed: Boolean): String? {
        val pool = if (spicyAllowed) band.spicy else band.clean
        if (pool.isEmpty()) return null
        val days = ChronoUnit.DAYS.between(LocalDate.of(2024, 1, 1), LocalDate.now())
        return pool[((days + band.index * 3) % pool.size).toInt()]
    }
}
