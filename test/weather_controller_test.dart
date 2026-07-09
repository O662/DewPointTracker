import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dew_point_tracker/models/saved_place.dart';
import 'package:dew_point_tracker/models/weather_code.dart';
import 'package:dew_point_tracker/models/weather_data.dart';
import 'package:dew_point_tracker/services/location_service.dart';
import 'package:dew_point_tracker/services/weather_service.dart';
import 'package:dew_point_tracker/state/weather_controller.dart';

WeatherData _weather() => WeatherData(
      temperatureC: 20,
      apparentTemperatureC: 20,
      dewPointC: 10,
      humidity: 50,
      windSpeedKmh: 5,
      precipitationMm: 0,
      isDay: true,
      condition: WeatherCondition.fromCode(0),
      highC: 25,
      lowC: 15,
      sunrise: null,
      sunset: null,
      hourly: const [],
      observedAt: DateTime.now(),
    );

class _FakeWeatherService extends WeatherService {
  int fetchCount = 0;

  @override
  Future<WeatherData> fetch({
    required double latitude,
    required double longitude,
  }) async {
    fetchCount++;
    return _weather();
  }
}

class _FakeLocationService extends LocationService {
  @override
  Future<LocationResult> current() async =>
      const LocationResult(latitude: 40.0, longitude: -90.0, label: 'Home');
}

const springfield = SavedPlace(
    name: 'Springfield', region: 'Missouri', latitude: 37.2, longitude: -93.3);
const paris =
    SavedPlace(name: 'Paris', region: 'France', latitude: 48.9, longitude: 2.3);

WeatherController _controller() => WeatherController(
      weatherService: _FakeWeatherService(),
      locationService: _FakeLocationService(),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('slots & selection', () {
    test('starts with just the device slot', () async {
      final c = _controller();
      await c.load();
      expect(c.slots.length, 1);
      expect(c.slots.single.isDevice, isTrue);
      expect(c.activeIndex, 0);
      expect(c.weather, isNotNull);
    });

    test('selecting a non-favorite place adds a transient page', () async {
      final c = _controller();
      await c.load();
      await c.selectPlace(springfield);
      expect(c.slots.length, 2);
      expect(c.activeIndex, 1);
      expect(c.locationLabel, 'Springfield');
      expect(c.usingSavedPlace, isTrue);
    });

    test('swiping pages switches the active location', () async {
      final c = _controller();
      await c.load();
      c.toggleFavorite(springfield);
      expect(c.slots.length, 2);

      c.setActivePage(1);
      expect(c.place?.id, springfield.id);
      c.setActivePage(0);
      expect(c.place, isNull);
    });
  });

  group('favorites', () {
    test('toggle adds then removes, and persists', () async {
      final c = _controller();
      await c.load();
      c.toggleFavorite(springfield);
      c.toggleFavorite(paris);
      expect(c.favorites.length, 2);
      // Device slot + two favorites.
      expect(c.slots.length, 3);

      // A fresh controller restores the same favorites from prefs.
      final c2 = _controller();
      await c2.load();
      expect(c2.favorites.map((f) => f.name), ['Springfield', 'Paris']);

      c.toggleFavorite(springfield);
      expect(c.favorites.map((f) => f.name), ['Paris']);
    });

    test('favoriting the viewed transient place absorbs its page', () async {
      final c = _controller();
      await c.load();
      await c.selectPlace(springfield);
      expect(c.slots.length, 2);

      c.toggleFavorite(springfield);
      expect(c.slots.length, 2); // transient became the favorite page
      expect(c.activeIndex, 1);
      expect(c.place?.id, springfield.id);
    });

    test('unfavoriting the viewed place keeps its page as transient', () async {
      final c = _controller();
      await c.load();
      c.toggleFavorite(springfield);
      await c.selectPlace(springfield);

      c.toggleFavorite(springfield);
      expect(c.favorites, isEmpty);
      expect(c.slots.length, 2); // still viewable until you navigate away
      expect(c.place?.id, springfield.id);
    });
  });

  group('radar range settings', () {
    test('defaults, clamps, and persists', () async {
      final c = _controller();
      await c.load();
      expect(c.radarPastHours, 1);
      expect(c.radarFutureHours, 8);

      c.setRadarRange(pastHours: 3, futureHours: 40); // future over the max
      expect(c.radarPastHours, 3);
      expect(c.radarFutureHours, 18); // clamped to the HRRR ceiling

      // Persistence is fire-and-forget; let both prefs writes land before
      // restoring into a fresh controller.
      await pumpEventQueue();
      final c2 = _controller();
      await c2.load();
      expect(c2.radarPastHours, 3);
      expect(c2.radarFutureHours, 18);
    });
  });

  group('profanity filter', () {
    test('defaults on, toggles, and persists', () async {
      final c = _controller();
      await c.load();
      expect(c.profanityFilter, isTrue);

      c.setProfanityFilter(false);
      expect(c.profanityFilter, isFalse);

      await pumpEventQueue();
      final c2 = _controller();
      await c2.load();
      expect(c2.profanityFilter, isFalse);
    });
  });

  group('card order', () {
    test('moveCard reorders and persists', () async {
      final c = _controller();
      await c.load();
      c.moveCard(0, 2);
      expect(c.cardOrder, ['dewpoint', 'metrics', 'hilo', 'hourly', 'daily']);

      final c2 = _controller();
      await c2.load();
      expect(c2.cardOrder, ['dewpoint', 'metrics', 'hilo', 'hourly', 'daily']);
    });

    test('restore drops unknown ids and appends new ones', () async {
      SharedPreferences.setMockInitialValues({
        'home_card_order': ['hourly', 'bogus', 'hilo'],
      });
      final c = _controller();
      await c.load();
      expect(c.cardOrder, ['hourly', 'hilo', 'dewpoint', 'metrics', 'daily']);
    });
  });
}
