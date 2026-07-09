import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/saved_place.dart';

/// Searches for places by name using the free, key-less Open-Meteo geocoding
/// API (same provider as the weather data).
class PlaceSearchService {
  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<SavedPlace>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': trimmed,
      'count': '8',
      'language': 'en',
      'format': 'json',
    });

    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Place search failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as List<dynamic>? ?? const [];

    return [
      for (final entry in results.cast<Map<String, dynamic>>())
        SavedPlace(
          name: entry['name'] as String,
          region: _region(entry),
          latitude: (entry['latitude'] as num).toDouble(),
          longitude: (entry['longitude'] as num).toDouble(),
        ),
    ];
  }

  /// "Missouri" for US results, "Ontario, Canada" style elsewhere — enough to
  /// tell same-named places apart in the results list.
  static String _region(Map<String, dynamic> entry) {
    final admin1 = entry['admin1'] as String? ?? '';
    final country = entry['country'] as String? ?? '';
    final isUs = (entry['country_code'] as String? ?? '') == 'US';
    if (isUs) return admin1;
    if (admin1.isEmpty) return country;
    if (country.isEmpty) return admin1;
    return '$admin1, $country';
  }
}
