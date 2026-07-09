import 'dart:convert';

/// A user-selected place to show weather for (instead of the device location).
class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.region,
    required this.latitude,
    required this.longitude,
  });

  /// City / town name, e.g. "Springfield".
  final String name;

  /// Disambiguating context, e.g. "Missouri" or "France". May be empty.
  final String region;

  final double latitude;
  final double longitude;

  /// Stable identity for favorites/equality — coordinates rounded to ~100 m so
  /// the same city from different searches matches itself.
  String get id =>
      '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';

  /// Short label for tight UI spots (the top bar).
  String get label => name;

  /// Full label for search results, e.g. "Springfield, Missouri".
  String get fullLabel => region.isEmpty ? name : '$name, $region';

  Map<String, dynamic> toJson() => {
        'name': name,
        'region': region,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        name: json['name'] as String,
        region: json['region'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );

  String encode() => jsonEncode(toJson());

  static SavedPlace? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return SavedPlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String encodeList(List<SavedPlace> places) =>
      jsonEncode([for (final p in places) p.toJson()]);

  static List<SavedPlace> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final entry in list.cast<Map<String, dynamic>>())
          SavedPlace.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }
}
