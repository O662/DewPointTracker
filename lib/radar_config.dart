/// Configuration for the radar timeline.
///
/// To enable the 6–8 hour FORECAST radar, get a free API key from
/// https://www.tomorrow.io/weather-api/ and either:
///   • paste it into [_defaultTomorrowApiKey] below, or
///   • pass it at launch:  flutter run --dart-define=TOMORROW_API_KEY=your_key
///
/// Leave it blank to keep the app fully free / no-key (it will just show the
/// past 2 hours of RainViewer radar + any short nowcast).
library;

const String _defaultTomorrowApiKey = '';

const String kTomorrowApiKey = String.fromEnvironment(
  'TOMORROW_API_KEY',
  defaultValue: _defaultTomorrowApiKey,
);

/// How many hours ahead to request forecast frames. Tomorrow.io's
/// `precipitationIntensity` layer only forecasts up to 6 hours out, so that is
/// the effective ceiling for this field.
const int kForecastHoursAhead = 6;
