import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/units.dart';
import '../models/weather_data.dart';
import 'glass_card.dart';
import 'weather_glyph.dart';

const _precipColor = Color(0xFF0D5C9E);

/// Day-by-day outlook: one row per day with the condition glyph, rain chance,
/// and the day's low→high span drawn as a bar positioned within the whole
/// period's temperature range (so hot and cold days are comparable at a
/// glance). Shows a week by default — the skillful part of the forecast —
/// with an expander for the full two weeks.
class DailyForecastCard extends StatefulWidget {
  const DailyForecastCard({super.key, required this.days, required this.unit});

  final List<DailyForecast> days;
  final TempUnit unit;

  @override
  State<DailyForecastCard> createState() => _DailyForecastCardState();
}

class _DailyForecastCardState extends State<DailyForecastCard> {
  static const _collapsedDays = 7;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return const SizedBox.shrink();

    // Scale the bars to the FULL period even when collapsed, so expanding
    // doesn't make the first week's bars jump.
    final periodMin =
        days.map((d) => d.lowC).reduce((a, b) => a < b ? a : b);
    final periodMax =
        days.map((d) => d.highC).reduce((a, b) => a > b ? a : b);

    final canExpand = days.length > _collapsedDays;
    final visible =
        _expanded || !canExpand ? days : days.sublist(0, _collapsedDays);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                _expanded ? 'NEXT 2 WEEKS' : 'THIS WEEK',
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
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++)
                  _DayRow(
                    day: visible[i],
                    label: i == 0
                        ? 'Today'
                        : DateFormat('EEE d').format(visible[i].date),
                    unit: widget.unit,
                    periodMinC: periodMin,
                    periodMaxC: periodMax,
                  ),
              ],
            ),
          ),
          if (canExpand)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.8),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                ),
                label: Text(_expanded ? 'Show less' : 'Show 2 weeks'),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.label,
    required this.unit,
    required this.periodMinC,
    required this.periodMaxC,
  });

  final DailyForecast day;
  final String label;
  final TempUnit unit;
  final double periodMinC;
  final double periodMaxC;

  @override
  Widget build(BuildContext context) {
    final prob = day.precipProbability ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          WeatherGlyph(
            category: day.condition.category,
            isDay: true,
            size: 26,
          ),
          // Rain chance column keeps its width even when empty so the
          // temperature bars stay vertically aligned across rows.
          SizedBox(
            width: 40,
            child: prob >= 5
                ? Text(
                    '$prob%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _precipColor,
                    ),
                  )
                : null,
          ),
          SizedBox(
            width: 34,
            child: Text(
              unit.format(day.lowC),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _RangeBar(
              lowC: day.lowC,
              highC: day.highC,
              periodMinC: periodMinC,
              periodMaxC: periodMaxC,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              unit.format(day.highC),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The day's low→high span on a track spanning the whole period's range.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.lowC,
    required this.highC,
    required this.periodMinC,
    required this.periodMaxC,
  });

  final double lowC;
  final double highC;
  final double periodMinC;
  final double periodMaxC;

  @override
  Widget build(BuildContext context) {
    final range = (periodMaxC - periodMinC).clamp(1.0, double.infinity);
    final startFrac = ((lowC - periodMinC) / range).clamp(0.0, 1.0);
    final endFrac = ((highC - periodMinC) / range).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // A one-degree day still gets a visible dot of a bar.
        final left = startFrac * width;
        final barWidth = ((endFrac - startFrac) * width).clamp(5.0, width);
        return SizedBox(
          height: 5,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                left: left.clamp(0.0, width - barWidth),
                width: barWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
