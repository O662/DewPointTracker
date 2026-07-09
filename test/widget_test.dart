import 'package:flutter_test/flutter_test.dart';

import 'package:weather_dew/models/dew_point_comfort.dart';
import 'package:weather_dew/models/units.dart';

void main() {
  group('DewPointComfort.fromCelsius', () {
    test('classifies a dry dew point', () {
      // 40°F ≈ 4.4°C
      expect(DewPointComfort.fromCelsius(4.4), DewPointComfort.dry);
    });

    test('classifies a comfortable dew point', () {
      // 57°F ≈ 13.9°C
      expect(DewPointComfort.fromCelsius(13.9), DewPointComfort.comfortable);
    });

    test('classifies a muggy dew point', () {
      // 68°F ≈ 20°C
      expect(DewPointComfort.fromCelsius(20), DewPointComfort.muggy);
    });

    test('classifies a miserable dew point', () {
      // 78°F ≈ 25.6°C
      expect(DewPointComfort.fromCelsius(25.6), DewPointComfort.miserable);
    });
  });

  group('gauge position', () {
    test('clamps within 0..1', () {
      expect(dewPointGaugePosition(-40), 0.0);
      expect(dewPointGaugePosition(40), 1.0);
    });
  });

  group('computeDewPointCelsius', () {
    test('equals temperature at 100% humidity', () {
      final dew = computeDewPointCelsius(20, 100);
      expect(dew, closeTo(20, 0.5));
    });

    test('is below temperature at lower humidity', () {
      expect(computeDewPointCelsius(25, 40), lessThan(25));
    });
  });

  group('TempUnit', () {
    test('formats Celsius value in Fahrenheit', () {
      expect(TempUnit.fahrenheit.formatWithUnit(0), '32°F');
    });

    test('formats Celsius value in Celsius', () {
      expect(TempUnit.celsius.formatWithUnit(21.4), '21°C');
    });
  });
}
