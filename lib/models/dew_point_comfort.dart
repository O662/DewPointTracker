import 'package:flutter/material.dart';

import 'units.dart';

/// Human-comfort classification of a dew point value. The bands are the
/// meteorological standard, expressed in Fahrenheit, and are independent of the
/// user's chosen display unit.
enum DewPointComfort {
  dry(
    label: 'Dry',
    blurb: 'Crisp and arid air',
    color: Color(0xFF4FB0E8),
  ),
  comfortable(
    label: 'Comfortable',
    blurb: 'Pleasant and easy',
    color: Color(0xFF35D29A),
  ),
  sticky(
    label: 'Sticky',
    blurb: 'A little humid',
    color: Color(0xFFD8D24B),
  ),
  muggy(
    label: 'Muggy',
    blurb: 'Noticeably humid',
    color: Color(0xFFF2A33C),
  ),
  oppressive(
    label: 'Oppressive',
    blurb: 'Heavy, sweaty air',
    color: Color(0xFFEE6C4D),
  ),
  miserable(
    label: 'Miserable',
    blurb: 'Tropical and draining',
    color: Color(0xFFE3415E),
  );

  const DewPointComfort({
    required this.label,
    required this.blurb,
    required this.color,
  });

  final String label;
  final String blurb;
  final Color color;

  /// Classify a dew point given in Celsius.
  static DewPointComfort fromCelsius(double dewPointC) {
    final f = celsiusToFahrenheit(dewPointC);
    if (f < 50) return DewPointComfort.dry;
    if (f < 60) return DewPointComfort.comfortable;
    if (f < 65) return DewPointComfort.sticky;
    if (f < 70) return DewPointComfort.muggy;
    if (f < 75) return DewPointComfort.oppressive;
    return DewPointComfort.miserable;
  }
}

/// Lower / upper bounds (in °F) used to lay out the comfort gauge.
const double dewPointGaugeMinF = 35;
const double dewPointGaugeMaxF = 80;

/// Normalised position (0..1) of a Celsius dew point along the comfort gauge.
double dewPointGaugePosition(double dewPointC) {
  final f = celsiusToFahrenheit(dewPointC);
  final t = (f - dewPointGaugeMinF) / (dewPointGaugeMaxF - dewPointGaugeMinF);
  return t.clamp(0.0, 1.0);
}

/// The ordered colours that make up the gauge gradient.
const List<Color> dewPointGaugeColors = [
  Color(0xFF4FB0E8),
  Color(0xFF35D29A),
  Color(0xFFD8D24B),
  Color(0xFFF2A33C),
  Color(0xFFEE6C4D),
  Color(0xFFE3415E),
];
