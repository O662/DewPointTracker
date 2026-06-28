import 'package:shared_preferences/shared_preferences.dart';

import '../radar_config.dart';

/// Persists the user's Tomorrow.io API key (and whether they've been asked about
/// forecast radar) on-device via shared_preferences.
class ForecastKeyStore {
  static const _keyPref = 'tomorrow_api_key';
  static const _dismissedPref = 'forecast_prompt_dismissed';

  /// The effective key: the user-entered key if present, otherwise any key
  /// supplied at build time via --dart-define (see [kTomorrowApiKey]).
  Future<String> loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = (prefs.getString(_keyPref) ?? '').trim();
    return stored.isNotEmpty ? stored : kTomorrowApiKey;
  }

  Future<void> saveKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPref, key.trim());
    // Re-enabling clears any earlier "not now" so the card behaves sensibly.
    await prefs.setBool(_dismissedPref, false);
  }

  Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
  }

  Future<bool> isPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissedPref) ?? false;
  }

  Future<void> dismissPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedPref, true);
  }
}
