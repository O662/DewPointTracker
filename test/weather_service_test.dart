import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dew_point_tracker/services/weather_service.dart';

Map<String, dynamic> _mainJson() => {
      'current': {
        'time': '2026-07-09T12:00',
        'temperature_2m': 25.0,
        'relative_humidity_2m': 60,
        'apparent_temperature': 26.0,
        'is_day': 1,
        'precipitation': 0.0,
        'weather_code': 0,
        'wind_speed_10m': 10.0,
        'dew_point_2m': 16.0,
      },
      'daily': {
        'time': ['2026-07-09', '2026-07-10'],
        'temperature_2m_max': [30.0, 28.0],
        'temperature_2m_min': [18.0, 16.0],
        'weather_code': [0, 3],
        'sunrise': ['2026-07-09T05:50'],
        'sunset': ['2026-07-09T20:30'],
        'precipitation_probability_max': [5, 40],
      },
      'hourly': {
        'time': ['2026-07-09T12:00'],
        'temperature_2m': [25.0],
        'weather_code': [0],
      },
    };

Map<String, dynamic> _ecmwfJson() => {
      'daily': {
        'time': ['2026-07-09', '2026-07-10'],
        'temperature_2m_max': [26.0, 24.0], // 4 °C cooler than the main model
        'temperature_2m_min': [16.0, 14.0],
      },
    };

void main() {
  test('daily highs/lows are the GFS+ECMWF average', () async {
    final service = WeatherService(
      client: MockClient((request) async {
        final isEcmwf = request.url.queryParameters['models'] == 'ecmwf_ifs025';
        return http.Response(
            jsonEncode(isEcmwf ? _ecmwfJson() : _mainJson()), 200);
      }),
    );

    final data = await service.fetch(latitude: 37.2, longitude: -93.3);
    expect(data.daily[0].highC, 28.0); // (30 + 26) / 2
    expect(data.daily[0].lowC, 17.0); // (18 + 16) / 2
    expect(data.daily[1].highC, 26.0);
    // Non-temperature fields stay from the primary model.
    expect(data.daily[1].precipProbability, 40);
    // Today's headline high/low are short-range and stay single-model.
    expect(data.highC, 30.0);
  });

  test('a failed ECMWF call keeps the single-model outlook', () async {
    final service = WeatherService(
      client: MockClient((request) async {
        if (request.url.queryParameters['models'] == 'ecmwf_ifs025') {
          return http.Response('oops', 500);
        }
        return http.Response(jsonEncode(_mainJson()), 200);
      }),
    );

    final data = await service.fetch(latitude: 37.2, longitude: -93.3);
    expect(data.daily[0].highC, 30.0);
    expect(data.daily[1].lowC, 16.0);
  });
}
