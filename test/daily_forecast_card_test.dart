import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_dew/models/units.dart';
import 'package:weather_dew/models/weather_code.dart';
import 'package:weather_dew/models/weather_data.dart';
import 'package:weather_dew/widgets/daily_forecast_card.dart';

List<DailyForecast> _days(int count) => [
      for (var i = 0; i < count; i++)
        DailyForecast(
          date: DateTime(2026, 7, 9).add(Duration(days: i)),
          highC: 30 - i.toDouble(),
          lowC: 18 - i.toDouble(),
          condition: WeatherCondition.fromCode(0),
          precipProbability: i * 5,
        ),
    ];

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0E1320),
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  testWidgets('collapses to 7 days and expands to the full two weeks',
      (tester) async {
    await tester.pumpWidget(
        _host(DailyForecastCard(days: _days(14), unit: TempUnit.fahrenheit)));

    // 7 rows: Today + 6 dated days; day 8 hidden until expanded.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Wed 15'), findsOneWidget); // day 7 (last collapsed row)
    expect(find.text('Thu 16'), findsNothing); // day 8
    expect(find.text('THIS WEEK'), findsOneWidget);

    await tester.tap(find.text('Show 2 weeks'));
    await tester.pumpAndSettle();

    expect(find.text('Thu 16'), findsOneWidget);
    expect(find.text('Wed 22'), findsOneWidget); // day 14
    expect(find.text('NEXT 2 WEEKS'), findsOneWidget);

    // The expanded card is taller than the test viewport; bring the collapse
    // button on-screen before tapping it.
    await tester.ensureVisible(find.text('Show less'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Thu 16'), findsNothing);
  });

  testWidgets('a week or less shows no expander', (tester) async {
    await tester.pumpWidget(
        _host(DailyForecastCard(days: _days(7), unit: TempUnit.fahrenheit)));
    expect(find.text('Show 2 weeks'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
  });
}
