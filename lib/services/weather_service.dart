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
      ].join(','),
      'hourly': 'temperature_2m,weather_code',
      'timezone': 'auto',
      'forecast_days': '2',
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

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return WeatherData.fromOpenMeteo(json);
    } catch (_) {
      throw const WeatherException('Received malformed weather data.');
    }
  }
}
