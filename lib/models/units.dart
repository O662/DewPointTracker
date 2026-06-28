import 'dart:math' as math;

/// Temperature unit used for display. All weather data is fetched and stored
/// internally in Celsius; conversion happens only at the presentation layer.
enum TempUnit {
  celsius,
  fahrenheit;

  String get symbol => this == TempUnit.celsius ? '°C' : '°F';

  /// Convert a Celsius value into this unit.
  double fromCelsius(double celsius) {
    return this == TempUnit.celsius ? celsius : celsius * 9 / 5 + 32;
  }

  /// Format a Celsius value into a rounded string in this unit, without the
  /// degree symbol (e.g. "72").
  String formatValue(double celsius) {
    return fromCelsius(celsius).round().toString();
  }

  /// Format a Celsius value with the degree symbol (e.g. "72°").
  String format(double celsius) => '${formatValue(celsius)}°';

  /// Format a Celsius value with the full unit (e.g. "72°F").
  String formatWithUnit(double celsius) => '${formatValue(celsius)}$symbol';
}

double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

/// Magnus-Tetens approximation of the dew point from temperature and relative
/// humidity. Used as a fallback when the API does not return a dew point.
/// Inputs in Celsius / percent, result in Celsius.
double computeDewPointCelsius(double tempC, double relativeHumidity) {
  const a = 17.625;
  const b = 243.04;
  final rh = relativeHumidity.clamp(1.0, 100.0);
  final gamma = math.log(rh / 100) + (a * tempC) / (b + tempC);
  return (b * gamma) / (a - gamma);
}
