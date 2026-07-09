package com.weatherdew.app.widgets

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.Locale
import kotlin.math.ln

/**
 * Minimal native client for the same key-less Open-Meteo endpoint the app
 * uses (lib/services/weather_service.dart), so widgets can refresh in the
 * background without launching Flutter.
 */
object OpenMeteo {
    fun fetch(target: WidgetStore.Target): Snapshot {
        val url = URL(
            "https://api.open-meteo.com/v1/forecast" +
                // Locale.US: the query must use dot decimals in every locale.
                "?latitude=%.4f&longitude=%.4f"
                    .format(Locale.US, target.latitude, target.longitude) +
                "&current=temperature_2m,relative_humidity_2m,apparent_temperature," +
                "is_day,weather_code,dew_point_2m,wind_speed_10m" +
                "&hourly=temperature_2m,weather_code" +
                "&daily=temperature_2m_max,temperature_2m_min,weather_code" +
                "&timezone=auto&forecast_days=7"
        )
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 15_000
        try {
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            return parse(body, target.label)
        } finally {
            conn.disconnect()
        }
    }

    internal fun parse(body: String, label: String): Snapshot {
        val root = JSONObject(body)
        val current = root.getJSONObject("current")

        val tempC = current.getDouble("temperature_2m")
        val dewC = if (current.has("dew_point_2m") && !current.isNull("dew_point_2m")) {
            current.getDouble("dew_point_2m")
        } else {
            magnusDewPoint(tempC, current.optDouble("relative_humidity_2m", 50.0))
        }
        // Location-local "now" anchors the hourly strip, matching the app.
        val now = LocalDateTime.parse(current.getString("time"))

        val hourlyJson = root.getJSONObject("hourly")
        val times = hourlyJson.getJSONArray("time")
        val temps = hourlyJson.getJSONArray("temperature_2m")
        val codes = hourlyJson.getJSONArray("weather_code")
        val hourly = buildList {
            for (i in 0 until times.length()) {
                val t = runCatching { LocalDateTime.parse(times.getString(i)) }
                    .getOrNull() ?: continue
                if (t.isBefore(now.minusHours(1))) continue
                if (temps.isNull(i)) continue
                add(HourEntry(t, temps.getDouble(i), codes.optInt(i, 0)))
                if (size >= 24) break
            }
        }

        val dailyJson = root.getJSONObject("daily")
        val dTimes = dailyJson.getJSONArray("time")
        val dHi = dailyJson.getJSONArray("temperature_2m_max")
        val dLo = dailyJson.getJSONArray("temperature_2m_min")
        val dCodes = dailyJson.getJSONArray("weather_code")
        val daily = buildList {
            for (i in 0 until dTimes.length()) {
                val d = runCatching { LocalDate.parse(dTimes.getString(i)) }
                    .getOrNull() ?: continue
                if (dHi.isNull(i) || dLo.isNull(i)) continue
                add(DayEntry(d, dHi.getDouble(i), dLo.getDouble(i), dCodes.optInt(i, 0)))
            }
        }

        return Snapshot(
            label = label,
            tempC = tempC,
            feelsC = current.getDouble("apparent_temperature"),
            dewC = dewC,
            humidity = current.optDouble("relative_humidity_2m", 50.0).toInt(),
            windKmh = current.optDouble("wind_speed_10m", 0.0),
            isDay = current.optInt("is_day", 1) == 1,
            code = current.optInt("weather_code", 0),
            hourly = hourly,
            daily = daily,
            fetchedAt = System.currentTimeMillis(),
        )
    }

    /** Magnus-Tetens fallback, mirroring computeDewPointCelsius in the app. */
    private fun magnusDewPoint(tempC: Double, relativeHumidity: Double): Double {
        val a = 17.625
        val b = 243.04
        val rh = relativeHumidity.coerceIn(1.0, 100.0)
        val gamma = ln(rh / 100) + (a * tempC) / (b + tempC)
        return (b * gamma) / (a - gamma)
    }
}
