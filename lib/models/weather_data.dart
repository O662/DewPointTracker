import 'dew_point_comfort.dart';
import 'units.dart';
import 'weather_code.dart';

/// A single hour in the forecast strip.
class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.temperatureC,
    required this.condition,
    this.dewPointC,
  });

  final DateTime time;
  final double temperatureC;
  final WeatherCondition condition;

  /// Hourly dew point when the API provides it.
  final double? dewPointC;
}

/// One day in the two-week forecast card.
class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.highC,
    required this.lowC,
    required this.condition,
    this.precipProbability,
  });

  final DateTime date;
  final double highC;
  final double lowC;
  final WeatherCondition condition;

  /// Max precipitation probability for the day, 0–100, when available.
  final int? precipProbability;
}

/// A full weather snapshot for a location. All temperatures are stored in
/// Celsius; convert at display time via [TempUnit].
class WeatherData {
  const WeatherData({
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.dewPointC,
    required this.humidity,
    required this.windSpeedKmh,
    required this.precipitationMm,
    required this.isDay,
    required this.condition,
    required this.highC,
    required this.lowC,
    required this.sunrise,
    required this.sunset,
    required this.hourly,
    required this.observedAt,
    this.daily = const [],
  });

  final double temperatureC;
  final double apparentTemperatureC;
  final double dewPointC;
  final int humidity;
  final double windSpeedKmh;
  final double precipitationMm;
  final bool isDay;
  final WeatherCondition condition;
  final double highC;
  final double lowC;
  final DateTime? sunrise;
  final DateTime? sunset;
  final List<HourlyForecast> hourly;
  final DateTime observedAt;

  /// Day-by-day outlook (today first), as far out as the API provides (~14d).
  final List<DailyForecast> daily;

  DewPointComfort get comfort => DewPointComfort.fromCelsius(dewPointC);

  /// The same snapshot with a replacement daily outlook (used when the daily
  /// temperatures are blended with a second model after the main fetch).
  WeatherData withDaily(List<DailyForecast> newDaily) => WeatherData(
        temperatureC: temperatureC,
        apparentTemperatureC: apparentTemperatureC,
        dewPointC: dewPointC,
        humidity: humidity,
        windSpeedKmh: windSpeedKmh,
        precipitationMm: precipitationMm,
        isDay: isDay,
        condition: condition,
        highC: highC,
        lowC: lowC,
        sunrise: sunrise,
        sunset: sunset,
        hourly: hourly,
        observedAt: observedAt,
        daily: newDaily,
      );

  factory WeatherData.fromOpenMeteo(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;

    double asDouble(dynamic v) => (v as num).toDouble();

    final tempC = asDouble(current['temperature_2m']);
    final humidity = (current['relative_humidity_2m'] as num).toInt();

    // Prefer the API dew point; fall back to a Magnus-Tetens estimate.
    final rawDew = current['dew_point_2m'];
    final dewC = rawDew is num
        ? rawDew.toDouble()
        : computeDewPointCelsius(tempC, humidity.toDouble());

    DateTime? parseFirst(String key) {
      final list = daily[key] as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      return DateTime.tryParse(list.first as String);
    }

    final highList = daily['temperature_2m_max'] as List<dynamic>;
    final lowList = daily['temperature_2m_min'] as List<dynamic>;

    return WeatherData(
      temperatureC: tempC,
      apparentTemperatureC: asDouble(current['apparent_temperature']),
      dewPointC: dewC,
      humidity: humidity,
      windSpeedKmh: asDouble(current['wind_speed_10m']),
      precipitationMm: asDouble(current['precipitation']),
      isDay: (current['is_day'] as num).toInt() == 1,
      condition: WeatherCondition.fromCode((current['weather_code'] as num).toInt()),
      highC: asDouble(highList.first),
      lowC: asDouble(lowList.first),
      sunrise: parseFirst('sunrise'),
      sunset: parseFirst('sunset'),
      hourly: _parseHourly(json),
      observedAt: DateTime.tryParse(current['time'] as String? ?? '') ??
          DateTime.now(),
      daily: _parseDaily(daily),
    );
  }

  static List<DailyForecast> _parseDaily(Map<String, dynamic> daily) {
    final times = (daily['time'] as List<dynamic>?) ?? const [];
    final highs = (daily['temperature_2m_max'] as List<dynamic>?) ?? const [];
    final lows = (daily['temperature_2m_min'] as List<dynamic>?) ?? const [];
    final codes = (daily['weather_code'] as List<dynamic>?) ?? const [];
    final probs =
        (daily['precipitation_probability_max'] as List<dynamic>?) ?? const [];

    final parsed = <DailyForecast>[];
    for (var i = 0; i < times.length; i++) {
      final date = DateTime.tryParse(times[i] as String);
      final high = i < highs.length ? highs[i] : null;
      final low = i < lows.length ? lows[i] : null;
      if (date == null || high is! num || low is! num) continue;
      final prob = i < probs.length ? probs[i] : null;
      parsed.add(DailyForecast(
        date: date,
        highC: high.toDouble(),
        lowC: low.toDouble(),
        condition: WeatherCondition.fromCode(
            i < codes.length && codes[i] is num ? (codes[i] as num).toInt() : 0),
        precipProbability: prob is num ? prob.toInt() : null,
      ));
    }
    return parsed;
  }

  static List<HourlyForecast> _parseHourly(Map<String, dynamic> json) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    if (hourly == null) return const [];

    final times = (hourly['time'] as List<dynamic>?) ?? const [];
    final temps = (hourly['temperature_2m'] as List<dynamic>?) ?? const [];
    final codes = (hourly['weather_code'] as List<dynamic>?) ?? const [];
    final dews = (hourly['dew_point_2m'] as List<dynamic>?) ?? const [];

    final parsed = <HourlyForecast>[];
    for (var i = 0; i < times.length; i++) {
      final time = DateTime.tryParse(times[i] as String);
      if (time == null || i >= temps.length) continue;
      final dew = i < dews.length ? dews[i] : null;
      parsed.add(HourlyForecast(
        time: time,
        temperatureC: (temps[i] as num).toDouble(),
        condition: WeatherCondition.fromCode(
            i < codes.length ? (codes[i] as num).toInt() : 0),
        dewPointC: dew is num ? dew.toDouble() : null,
      ));
    }

    // Keep the next 24 hours from the most recent past hour.
    final now = DateTime.now();
    final startIndex = parsed.indexWhere(
        (h) => h.time.isAfter(now.subtract(const Duration(hours: 1))));
    final from = startIndex < 0 ? 0 : startIndex;
    return parsed.sublist(from, (from + 24).clamp(0, parsed.length));
  }
}
