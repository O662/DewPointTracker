import 'package:flutter_test/flutter_test.dart';

import 'package:weather_dew/models/dew_point_comfort.dart';

void main() {
  group('blurb pools', () {
    test('every band has multiple clean and spicy blurbs', () {
      for (final band in DewPointComfort.values) {
        expect(band.blurbs.length, greaterThan(1), reason: band.name);
        expect(band.spicyBlurbs.length, greaterThan(1), reason: band.name);
      }
    });

    test('default draws from the clean pool, allowProfanity from spicy', () {
      final day = DateTime(2026, 7, 9);
      for (final band in DewPointComfort.values) {
        expect(band.blurbs, contains(band.blurb(when: day)));
        expect(
          band.spicyBlurbs,
          contains(band.blurb(allowProfanity: true, when: day)),
        );
      }
    });

    test('is stable within a day and rotates through the pool daily', () {
      const band = DewPointComfort.muggy;
      final morning = DateTime(2026, 7, 9, 6);
      final night = DateTime(2026, 7, 9, 23);
      expect(band.blurb(when: morning), band.blurb(when: night));

      // Over pool.length consecutive days every blurb appears once.
      final seen = {
        for (var d = 0; d < band.blurbs.length; d++)
          band.blurb(when: DateTime(2026, 7, 9 + d)),
      };
      expect(seen, band.blurbs.toSet());
    });
  });
}
