import 'package:flutter/material.dart';

import '../models/weather_code.dart';

/// A sky palette: a base vertical gradient plus two drifting accent "blobs"
/// that animate behind the frosted glass to evoke a liquid-glass surface.
class SkyPalette {
  const SkyPalette({
    required this.background,
    required this.blobA,
    required this.blobB,
  });

  final List<Color> background;
  final Color blobA;
  final Color blobB;

  static const SkyPalette _clearDay = SkyPalette(
    background: [Color(0xFF1B5FB8), Color(0xFF3D93D6), Color(0xFF73C2F0)],
    blobA: Color(0xFFFFD27A),
    blobB: Color(0xFF6FD0FF),
  );
  static const SkyPalette _clearNight = SkyPalette(
    background: [Color(0xFF080E2A), Color(0xFF1A2154), Color(0xFF2B1E54)],
    blobA: Color(0xFF3D52B0),
    blobB: Color(0xFF6B45B8),
  );
  static const SkyPalette _partlyDay = SkyPalette(
    background: [Color(0xFF35639C), Color(0xFF5C92C2), Color(0xFF9AC2DD)],
    blobA: Color(0xFFFFE0A3),
    blobB: Color(0xFF8FC4E8),
  );
  static const SkyPalette _partlyNight = SkyPalette(
    background: [Color(0xFF101736), Color(0xFF243056), Color(0xFF38406B)],
    blobA: Color(0xFF44539B),
    blobB: Color(0xFF5E5A9E),
  );
  static const SkyPalette _cloudy = SkyPalette(
    background: [Color(0xFF3F4F61), Color(0xFF61728A), Color(0xFF8A9AAC)],
    blobA: Color(0xFF93A6BC),
    blobB: Color(0xFF5C6E84),
  );
  static const SkyPalette _cloudyNight = SkyPalette(
    background: [Color(0xFF1B2230), Color(0xFF2E3A4C), Color(0xFF44525F)],
    blobA: Color(0xFF49586C),
    blobB: Color(0xFF34404F),
  );
  static const SkyPalette _rain = SkyPalette(
    background: [Color(0xFF243A52), Color(0xFF375570), Color(0xFF577791)],
    blobA: Color(0xFF4C8FB0),
    blobB: Color(0xFF2E4D68),
  );
  static const SkyPalette _rainNight = SkyPalette(
    background: [Color(0xFF111B28), Color(0xFF1F3346), Color(0xFF324B61)],
    blobA: Color(0xFF2C5772),
    blobB: Color(0xFF22384B),
  );
  static const SkyPalette _snow = SkyPalette(
    background: [Color(0xFF566B81), Color(0xFF8093A8), Color(0xFFBBCBD9)],
    blobA: Color(0xFFE6F0F7),
    blobB: Color(0xFF9FB4C6),
  );
  static const SkyPalette _snowNight = SkyPalette(
    background: [Color(0xFF1E2A38), Color(0xFF35465A), Color(0xFF566476)],
    blobA: Color(0xFF7387A0),
    blobB: Color(0xFF3F4F62),
  );
  static const SkyPalette _fog = SkyPalette(
    background: [Color(0xFF505C66), Color(0xFF79848E), Color(0xFFA9B2BA)],
    blobA: Color(0xFFC3CBD2),
    blobB: Color(0xFF727D87),
  );
  static const SkyPalette _thunder = SkyPalette(
    background: [Color(0xFF1B162E), Color(0xFF332A52), Color(0xFF463A66)],
    blobA: Color(0xFF6D58B6),
    blobB: Color(0xFF8E5AC0),
  );

  static SkyPalette of(WeatherCategory category, bool isDay) {
    switch (category) {
      case WeatherCategory.clear:
        return isDay ? _clearDay : _clearNight;
      case WeatherCategory.partlyCloudy:
        return isDay ? _partlyDay : _partlyNight;
      case WeatherCategory.cloudy:
        return isDay ? _cloudy : _cloudyNight;
      case WeatherCategory.fog:
        return isDay ? _fog : _cloudyNight;
      case WeatherCategory.drizzle:
      case WeatherCategory.rain:
        return isDay ? _rain : _rainNight;
      case WeatherCategory.snow:
        return isDay ? _snow : _snowNight;
      case WeatherCategory.thunderstorm:
        return _thunder;
    }
  }

  /// A calm default used before any weather has loaded.
  static const SkyPalette loading = SkyPalette(
    background: [Color(0xFF1A2A52), Color(0xFF2C3E70), Color(0xFF49568F)],
    blobA: Color(0xFF4863B8),
    blobB: Color(0xFF6A56B0),
  );
}

class AppTheme {
  static ThemeData build() {
    const base = ColorScheme.dark(
      primary: Color(0xFF8FD0FF),
      secondary: Color(0xFFFFD27A),
      surface: Color(0xFF1A2238),
    );

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Roboto',
      textTheme: const TextTheme().apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );

    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontWeight: FontWeight.w200,
          letterSpacing: -2,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelLarge: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
