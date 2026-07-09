import 'package:flutter_test/flutter_test.dart';

import 'package:dew_point_tracker/models/weather_data.dart';

Map<String, dynamic> _json() => {
      'current': {
        'time': '2026-07-08T12:00',
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
        'time': ['2026-07-08', '2026-07-09', '2026-07-10'],
        'temperature_2m_max': [30.0, 28.0, 26.0],
        'temperature_2m_min': [18.0, 17.0, 15.0],
        'weather_code': [0, 3, 61],
        'sunrise': ['2026-07-08T05:50'],
        'sunset': ['2026-07-08T20:30'],
        'precipitation_probability_max': [5, null, 80],
      },
      'hourly': {
        'time': ['2026-07-08T12:00', '2026-07-08T13:00'],
        'temperature_2m': [25.0, 26.0],
        'weather_code': [0, 1],
        'dew_point_2m': [16.0, null],
      },
    };

void main() {
  test('parses the daily outlook with precip probability', () {
    final data = WeatherData.fromOpenMeteo(_json());
    expect(data.daily.length, 3);
    expect(data.daily[0].highC, 30.0);
    expect(data.daily[0].lowC, 18.0);
    expect(data.daily[0].precipProbability, 5);
    expect(data.daily[1].precipProbability, isNull); // API can return null
    expect(data.daily[2].precipProbability, 80);
  });

  test('parses hourly dew point, tolerating gaps', () {
    final data = WeatherData.fromOpenMeteo(_json());
    expect(data.hourly.first.dewPointC, 16.0);
    expect(data.hourly.last.dewPointC, isNull);
  });

  test('missing daily arrays yield an empty outlook, not a crash', () {
    final json = _json();
    (json['daily'] as Map<String, dynamic>)
      ..remove('precipitation_probability_max')
      ..['time'] = <dynamic>[];
    // High/low still come from the (now separate) first-day lists.
    (json['daily'] as Map<String, dynamic>)['temperature_2m_max'] = [30.0];
    (json['daily'] as Map<String, dynamic>)['temperature_2m_min'] = [18.0];
    final data = WeatherData.fromOpenMeteo(json);
    expect(data.daily, isEmpty);
    expect(data.highC, 30.0);
  });
}
