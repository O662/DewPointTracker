import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/units.dart';
import '../models/weather_data.dart';
import 'glass_card.dart';
import 'weather_glyph.dart';

/// A horizontally scrolling strip of the next 24 hours.
class HourlyStrip extends StatelessWidget {
  const HourlyStrip({super.key, required this.hours, required this.unit});

  final List<HourlyForecast> hours;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                'NEXT 24 HOURS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hours.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, i) {
                final hour = hours[i];
                final label = i == 0 ? 'Now' : DateFormat('h a').format(hour.time);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    WeatherGlyph(
                      category: hour.condition.category,
                      isDay: _isDaytime(hour.time),
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      unit.format(hour.temperatureC),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // We don't have per-hour day/night from the API; approximate by clock time.
  bool _isDaytime(DateTime t) => t.hour >= 6 && t.hour < 19;
}
