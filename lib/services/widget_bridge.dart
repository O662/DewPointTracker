import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dew_point_comfort.dart';

/// Feeds the Android home-screen widgets. The widgets are rendered natively
/// (so they can refresh via WorkManager without launching Flutter); this
/// bridge hands them everything they can't derive on their own:
///
///  * the comfort-band labels, colors and blurb pools (single source of truth
///    stays in [DewPointComfort]),
///  * the last successful device GPS fix (background location access is
///    restricted, so the widgets reuse the app's most recent fix),
///  * a "sync now" nudge over a method channel whenever the app fetches fresh
///    weather or the user changes a widget-visible setting.
///
/// Every method is a silent no-op off Android (web, desktop, unit tests).
class WidgetBridge {
  static const _channel = MethodChannel('weatherdew/widgets');
  static const _blurbsKey = 'widget_blurbs';
  static const _lastFixKey = 'widget_last_fix';

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Write the comfort-band data (labels, colors, blurb pools) where the
  /// native renderer can read it. Called once per app launch so widget blurbs
  /// stay in lockstep with the app's.
  static Future<void> writeComfortBands() async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = [
        for (final band in DewPointComfort.values)
          {
            'label': band.label,
            'color': _hex(band.color),
            'clean': band.blurbs,
            'spicy': band.spicyBlurbs,
          },
      ];
      await prefs.setString(_blurbsKey, jsonEncode(payload));
    } catch (_) {}
  }

  /// Remember the device location the app last resolved, for widgets in
  /// "my location" mode.
  static Future<void> saveLastFix({
    required double latitude,
    required double longitude,
    required String label,
  }) async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastFixKey,
        jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'label': label,
        }),
      );
    } catch (_) {}
  }

  /// Ask the native side to refresh all home-screen widgets now (and keep the
  /// periodic background refresh scheduled while any widgets exist).
  static Future<void> sync() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('sync');
    } catch (_) {
      // Channel missing (tests, hot restart edge) — widgets catch up on
      // their own periodic refresh.
    }
  }

  static String _hex(Color c) {
    final argb = c.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }
}
