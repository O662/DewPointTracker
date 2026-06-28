import 'package:flutter/foundation.dart';

import '../models/units.dart';
import '../models/weather_data.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

enum LoadStatus { idle, loading, ready, error }

/// Owns the weather/location fetch lifecycle and the chosen display unit.
class WeatherController extends ChangeNotifier {
  WeatherController({
    WeatherService? weatherService,
    LocationService? locationService,
  })  : _weatherService = weatherService ?? WeatherService(),
        _locationService = locationService ?? LocationService();

  final WeatherService _weatherService;
  final LocationService _locationService;

  LoadStatus status = LoadStatus.idle;
  WeatherData? weather;
  String? locationLabel;
  double? latitude;
  double? longitude;
  String errorMessage = '';
  bool permissionBlocked = false;
  TempUnit unit = TempUnit.fahrenheit;

  bool get isLoading => status == LoadStatus.loading;

  /// Resolve location then fetch weather. Safe to call repeatedly (refresh).
  Future<void> load() async {
    status = LoadStatus.loading;
    errorMessage = '';
    permissionBlocked = false;
    notifyListeners();

    try {
      final location = await _locationService.current();
      latitude = location.latitude;
      longitude = location.longitude;
      locationLabel = location.label;

      weather = await _weatherService.fetch(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      status = LoadStatus.ready;
    } on LocationException catch (e) {
      errorMessage = e.message;
      permissionBlocked = e.openSettings;
      status = LoadStatus.error;
    } on WeatherException catch (e) {
      errorMessage = e.message;
      status = LoadStatus.error;
    } catch (e) {
      errorMessage = 'Something went wrong while loading weather.';
      status = LoadStatus.error;
    }
    notifyListeners();
  }

  void toggleUnit() {
    unit =
        unit == TempUnit.fahrenheit ? TempUnit.celsius : TempUnit.fahrenheit;
    notifyListeners();
  }
}
