import 'package:flutter/material.dart';

import '../radar_config.dart';
import '../state/weather_controller.dart';
import '../widgets/glass_card.dart';

/// App settings. Currently: how far the radar timeline reaches into the past
/// and the future. Changes apply immediately and persist.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A2440), Color(0xFF0E1320)],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.radar_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text(
                            'RADAR TIMELINE',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _HoursSlider(
                        label: 'Past',
                        hours: controller.radarPastHours,
                        min: kMinRadarPastHours,
                        max: kMaxRadarPastHours,
                        onChanged: (h) =>
                            controller.setRadarRange(pastHours: h),
                      ),
                      const SizedBox(height: 6),
                      _HoursSlider(
                        label: 'Forecast',
                        hours: controller.radarFutureHours,
                        min: kMinRadarFutureHours,
                        max: kMaxRadarFutureHours,
                        onChanged: (h) =>
                            controller.setRadarRange(futureHours: h),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Forecast radar comes from the HRRR model and covers '
                        'the continental US only (up to 18 h out). Outside '
                        'the US the radar shows a short ~30 min nowcast '
                        'regardless. Longer ranges use bigger time steps '
                        'between frames.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text(
                            'DEW POINT BLURBS',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Profanity filter',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Keeps the comfort blurbs family-friendly. '
                                  'Turn off and they stop holding back.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: controller.profanityFilter,
                            onChanged: controller.setProfanityFilter,
                            activeTrackColor: const Color(0xFF4FB0E8),
                            inactiveTrackColor:
                                Colors.white.withValues(alpha: 0.18),
                            inactiveThumbColor: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoursSlider extends StatelessWidget {
  const _HoursSlider({
    required this.label,
    required this.hours,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int hours;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF4FB0E8),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF4FB0E8).withValues(alpha: 0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: hours.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '$hours h',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
