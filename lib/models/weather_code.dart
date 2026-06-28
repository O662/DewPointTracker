/// Broad visual grouping of a WMO weather code, used to pick an icon glyph and
/// background palette.
enum WeatherCategory {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
}

/// A decoded WMO weather interpretation code.
class WeatherCondition {
  const WeatherCondition({
    required this.code,
    required this.category,
    required this.label,
  });

  final int code;
  final WeatherCategory category;
  final String label;

  static WeatherCondition fromCode(int code) {
    switch (code) {
      case 0:
        return const WeatherCondition(
            code: 0, category: WeatherCategory.clear, label: 'Clear sky');
      case 1:
        return const WeatherCondition(
            code: 1, category: WeatherCategory.clear, label: 'Mainly clear');
      case 2:
        return const WeatherCondition(
            code: 2,
            category: WeatherCategory.partlyCloudy,
            label: 'Partly cloudy');
      case 3:
        return const WeatherCondition(
            code: 3, category: WeatherCategory.cloudy, label: 'Overcast');
      case 45:
        return const WeatherCondition(
            code: 45, category: WeatherCategory.fog, label: 'Fog');
      case 48:
        return const WeatherCondition(
            code: 48, category: WeatherCategory.fog, label: 'Rime fog');
      case 51:
        return const WeatherCondition(
            code: 51,
            category: WeatherCategory.drizzle,
            label: 'Light drizzle');
      case 53:
        return const WeatherCondition(
            code: 53, category: WeatherCategory.drizzle, label: 'Drizzle');
      case 55:
        return const WeatherCondition(
            code: 55,
            category: WeatherCategory.drizzle,
            label: 'Dense drizzle');
      case 56:
        return const WeatherCondition(
            code: 56,
            category: WeatherCategory.drizzle,
            label: 'Freezing drizzle');
      case 57:
        return const WeatherCondition(
            code: 57,
            category: WeatherCategory.drizzle,
            label: 'Freezing drizzle');
      case 61:
        return const WeatherCondition(
            code: 61, category: WeatherCategory.rain, label: 'Light rain');
      case 63:
        return const WeatherCondition(
            code: 63, category: WeatherCategory.rain, label: 'Rain');
      case 65:
        return const WeatherCondition(
            code: 65, category: WeatherCategory.rain, label: 'Heavy rain');
      case 66:
        return const WeatherCondition(
            code: 66, category: WeatherCategory.rain, label: 'Freezing rain');
      case 67:
        return const WeatherCondition(
            code: 67,
            category: WeatherCategory.rain,
            label: 'Heavy freezing rain');
      case 71:
        return const WeatherCondition(
            code: 71, category: WeatherCategory.snow, label: 'Light snow');
      case 73:
        return const WeatherCondition(
            code: 73, category: WeatherCategory.snow, label: 'Snow');
      case 75:
        return const WeatherCondition(
            code: 75, category: WeatherCategory.snow, label: 'Heavy snow');
      case 77:
        return const WeatherCondition(
            code: 77, category: WeatherCategory.snow, label: 'Snow grains');
      case 80:
        return const WeatherCondition(
            code: 80, category: WeatherCategory.rain, label: 'Light showers');
      case 81:
        return const WeatherCondition(
            code: 81, category: WeatherCategory.rain, label: 'Showers');
      case 82:
        return const WeatherCondition(
            code: 82,
            category: WeatherCategory.rain,
            label: 'Violent showers');
      case 85:
        return const WeatherCondition(
            code: 85, category: WeatherCategory.snow, label: 'Snow showers');
      case 86:
        return const WeatherCondition(
            code: 86,
            category: WeatherCategory.snow,
            label: 'Heavy snow showers');
      case 95:
        return const WeatherCondition(
            code: 95,
            category: WeatherCategory.thunderstorm,
            label: 'Thunderstorm');
      case 96:
        return const WeatherCondition(
            code: 96,
            category: WeatherCategory.thunderstorm,
            label: 'Thunderstorm, hail');
      case 99:
        return const WeatherCondition(
            code: 99,
            category: WeatherCategory.thunderstorm,
            label: 'Severe thunderstorm');
      default:
        return WeatherCondition(
            code: code, category: WeatherCategory.cloudy, label: 'Unknown');
    }
  }
}
