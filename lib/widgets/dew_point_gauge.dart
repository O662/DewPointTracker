import 'package:flutter/material.dart';

import '../models/dew_point_comfort.dart';
import '../models/units.dart';

/// A horizontal comfort gauge: a banded gradient track from "Dry" to
/// "Miserable" with a glass thumb at the current dew point, plus the active
/// comfort label and reading.
class DewPointGauge extends StatelessWidget {
  const DewPointGauge({
    super.key,
    required this.dewPointC,
    required this.unit,
  });

  final double dewPointC;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final comfort = DewPointComfort.fromCelsius(dewPointC);
    final position = dewPointGaugePosition(dewPointC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8, bottom: 5),
              decoration: BoxDecoration(
                color: comfort.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: comfort.color.withValues(alpha: 0.6), blurRadius: 10),
                ],
              ),
            ),
            Text(
              comfort.label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              unit.formatWithUnit(dewPointC),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          comfort.blurb,
          style: TextStyle(
            fontSize: 13.5,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            const thumb = 24.0;
            final width = constraints.maxWidth;
            final centerX = (position * width).clamp(thumb / 2, width - thumb / 2);
            return SizedBox(
              height: thumb,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(colors: dewPointGaugeColors),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: centerX - thumb / 2,
                    top: 0,
                    child: _Thumb(color: comfort.color, size: thumb),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _scaleLabel('Dry'),
            _scaleLabel('Comfort'),
            _scaleLabel('Muggy'),
            _scaleLabel('Severe'),
          ],
        ),
      ],
    );
  }

  Widget _scaleLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.55),
          fontWeight: FontWeight.w500,
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color, width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
