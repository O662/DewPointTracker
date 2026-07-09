import 'package:weather_dew/models/saved_place.dart';
import 'package:weather_dew/services/place_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SavedPlace', () {
    test('encode/decode round-trips', () {
      const place = SavedPlace(
        name: 'Springfield',
        region: 'Missouri',
        latitude: 37.21533,
        longitude: -93.29824,
      );
      final decoded = SavedPlace.decode(place.encode())!;
      expect(decoded.name, 'Springfield');
      expect(decoded.region, 'Missouri');
      expect(decoded.latitude, closeTo(37.21533, 1e-9));
      expect(decoded.longitude, closeTo(-93.29824, 1e-9));
    });

    test('decode tolerates junk', () {
      expect(SavedPlace.decode(null), isNull);
      expect(SavedPlace.decode(''), isNull);
      expect(SavedPlace.decode('not json'), isNull);
      expect(SavedPlace.decode('{"name": 5}'), isNull);
    });

    test('fullLabel handles empty region', () {
      const noRegion =
          SavedPlace(name: 'Atlantis', region: '', latitude: 0, longitude: 0);
      expect(noRegion.fullLabel, 'Atlantis');
      const withRegion = SavedPlace(
          name: 'Paris', region: 'France', latitude: 0, longitude: 0);
      expect(withRegion.fullLabel, 'Paris, France');
    });
  });

  group('PlaceSearchService', () {
    PlaceSearchService serviceReturning(String body, {int status = 200}) {
      return PlaceSearchService(
        client: MockClient((_) async => http.Response(body, status)),
      );
    }

    test('parses results with US and non-US regions', () async {
      const body = '''
      {"results": [
        {"name": "Springfield", "latitude": 37.2, "longitude": -93.3,
         "country_code": "US", "country": "United States", "admin1": "Missouri"},
        {"name": "London", "latitude": 42.98, "longitude": -81.25,
         "country_code": "CA", "country": "Canada", "admin1": "Ontario"}
      ]}''';
      final results = await serviceReturning(body).search('spring');
      expect(results, hasLength(2));
      expect(results[0].fullLabel, 'Springfield, Missouri');
      expect(results[1].fullLabel, 'London, Ontario, Canada');
    });

    test('returns empty list when API has no results field', () async {
      final results =
          await serviceReturning('{"generationtime_ms": 0.5}').search('zzzz');
      expect(results, isEmpty);
    });

    test('short queries skip the network entirely', () async {
      final service = PlaceSearchService(
        client: MockClient((_) async => throw StateError('should not fetch')),
      );
      expect(await service.search('a'), isEmpty);
      expect(await service.search('  '), isEmpty);
    });

    test('throws on server error', () {
      expect(
        serviceReturning('oops', status: 500).search('spring'),
        throwsException,
      );
    });
  });
}
