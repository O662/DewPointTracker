import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dew_point_tracker/models/saved_place.dart';
import 'package:dew_point_tracker/models/weather_code.dart';
import 'package:dew_point_tracker/models/weather_data.dart';
import 'package:dew_point_tracker/screens/home_screen.dart';
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
      hourly: [
        for (var i = 0; i < 24; i++)
          HourlyForecast(
            time: DateTime(2026, 7, 8, 12).add(Duration(hours: i)),
            temperatureC: 18 + (i % 6).toDouble(),
            condition: WeatherCondition.fromCode(0),
            dewPointC: 10 + (i % 4).toDouble(),
          ),
      ],
      observedAt: DateTime(2026, 7, 8, 12),
    );

class _FakeWeatherService extends WeatherService {
  @override
  Future<WeatherData> fetch({
    required double latitude,
    required double longitude,
  }) async =>
      _weather();
}

class _FakeLocationService extends LocationService {
  @override
  Future<LocationResult> current() async =>
      const LocationResult(latitude: 40.0, longitude: -90.0, label: 'Home');
}

const springfield = SavedPlace(
    name: 'Springfield', region: 'Missouri', latitude: 37.2, longitude: -93.3);

void main() {
  testWidgets('swiping the weather page cycles through favorites',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = WeatherController(
      weatherService: _FakeWeatherService(),
      locationService: _FakeLocationService(),
    );
    // The fakes complete via microtasks only (no real timers), so these
    // finish under the test binding's fake async without extra pumping.
    await controller.load();
    controller.toggleFavorite(springfield);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // RootShell wraps the screen in a ListenableBuilder; mirror that.
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => HomeScreen(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    // Device-location page is first.
    expect(find.text('Home'), findsOneWidget);
    expect(controller.activeIndex, 0);

    // The 24h graph card sits below the fold; scroll the page to reach it.
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('NEXT 24 HOURS'), findsOneWidget);
    await tester.drag(find.byType(ReorderableListView), const Offset(0, 600));
    await tester.pump();

    // Swipe left → the favorite's page becomes active.
    // (pumpAndSettle can't be used: the hero glyph floats forever.)
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.place?.id, springfield.id);
    expect(find.text('Springfield'), findsOneWidget);

    controller.dispose();
  });
}
