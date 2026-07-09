import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// A resolved device location plus an optional human-readable label.
class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

/// Thrown when a location cannot be determined. [openSettings] hints the UI
/// that the user must change a permission in system settings.
class LocationException implements Exception {
  const LocationException(this.message, {this.openSettings = false});

  final String message;
  final bool openSettings;

  @override
  String toString() => message;
}

class LocationService {
  /// Resolves the device's current position, requesting permission if needed,
  /// and attempts a reverse-geocode for a friendly place name.
  Future<LocationResult> current() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'Location services are turned off. Enable them to see local weather.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is permanently denied. Allow it in settings.',
        openSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Location permission was denied. Grant access to see local weather.',
      );
    }

    // A fresh fix can hang for a long time indoors or with a weak GPS signal,
    // which previously left the app stuck on "Finding your weather…". Bound
    // the wait and fall back to the last known position — for weather, a fix
    // from a little while ago is far better than no weather at all.
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown == null) {
        throw const LocationException(
          'Could not get a location fix. Try again, or search for a city.',
        );
      }
      position = lastKnown;
    }

    final label = await _reverseGeocode(position.latitude, position.longitude);

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      label: label,
    );
  }

  /// Reverse geocoding is only available on Android/iOS. On other platforms (or
  /// on failure) we fall back to a coordinate label.
  Future<String> _reverseGeocode(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final city = p.locality?.isNotEmpty == true
            ? p.locality
            : (p.subAdministrativeArea?.isNotEmpty == true
                ? p.subAdministrativeArea
                : p.administrativeArea);
        if (city != null && city.isNotEmpty) return city;
      }
    } catch (_) {
      // Plugin unsupported on this platform, or lookup failed — ignore.
    }
    return '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}';
  }
}
