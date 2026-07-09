import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_data.dart';

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches weather from the free, key-less Open-Meteo forecast API.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherData> fetch({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': [
        'temperature_2m',
        'relative_humidity_2m',
        'apparent_temperature',
        'is_day',
        'precipitation',
        'weather_code',
        'wind_speed_10m',
        'dew_point_2m',
      ].join(','),
      'daily': [
        'temperature_2m_max',
        'temperature_2m_min',
        'weather_code',
        'sunrise',
        'sunset',
        'precipitation_probability_max',
      ].join(','),
      'hourly': 'temperature_2m,weather_code,dew_point_2m',
      'timezone': 'auto',
      // 14 days feeds the two-week forecast card; the hourly strip still
      // only shows the next 24h of the (now longer) hourly series.
      'forecast_days': '14',
    });

    http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const WeatherException(
          'Could not reach the weather service. Check your connection.');
    }

    if (response.statusCode != 200) {
      throw WeatherException(
          'Weather service error (${response.statusCode}). Try again shortly.');
    }

    WeatherData data;
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      data = WeatherData.fromOpenMeteo(json);
    } catch (_) {
      throw const WeatherException('Received malformed weather data.');
    }

    // Two-model consensus for the daily outlook: the primary call resolves
    // to NOAA's GFS for the US, whose day-5+ temperatures can run several
    // degrees from other providers. Averaging with ECMWF (independently the
    // most skillful global model) cuts the worst-case misses. Best-effort —
    // a failed second call leaves the single-model outlook.
    try {
      data = await _blendDailyWithEcmwf(data, latitude, longitude);
    } catch (_) {}

    return data;
  }

  Future<WeatherData> _blendDailyWithEcmwf(
    WeatherData data,
    double latitude,
    double longitude,
  ) async {
    if (data.daily.isEmpty) return data;

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'daily': 'temperature_2m_max,temperature_2m_min',
      'models': 'ecmwf_ifs025',
      'timezone': 'auto',
      'forecast_days': '14',
    });
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return data;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>? ?? const {};
    final times = (daily['time'] as List<dynamic>?) ?? const [];
    final highs = (daily['temperature_2m_max'] as List<dynamic>?) ?? const [];
    final lows = (daily['temperature_2m_min'] as List<dynamic>?) ?? const [];

    // Match by calendar date — the two calls can disagree on array offsets.
    final byDate = <String, (double, double)>{};
    for (var i = 0; i < times.length; i++) {
      final high = i < highs.length ? highs[i] : null;
      final low = i < lows.length ? lows[i] : null;
      if (high is num && low is num) {
        byDate[times[i] as String] = (high.toDouble(), low.toDouble());
      }
    }
    if (byDate.isEmpty) return data;

    String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    return data.withDaily([
      for (final day in data.daily)
        switch (byDate[dateKey(day.date)]) {
          (final high, final low) => DailyForecast(
              date: day.date,
              highC: (day.highC + high) / 2,
              lowC: (day.lowC + low) / 2,
              condition: day.condition,
              precipProbability: day.precipProbability,
            ),
          null => day,
        },
    ]);
  }
}
