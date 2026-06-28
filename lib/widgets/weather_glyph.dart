import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/weather_code.dart';

/// A crisp, custom-painted weather icon that scales to any size and adds a soft
/// glow. Driven by [WeatherCategory] and whether it is day or night.
class WeatherGlyph extends StatelessWidget {
  const WeatherGlyph({
    super.key,
    required this.category,
    required this.isDay,
    this.size = 120,
  });

  final WeatherCategory category;
  final bool isDay;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(category: category, isDay: isDay),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.category, required this.isDay});

  final WeatherCategory category;
  final bool isDay;

  static const _sunA = Color(0xFFFFE08A);
  static const _sunB = Color(0xFFFFB24D);
  static const _moonColor = Color(0xFFE9F1FF);
  static const _cloud = Color(0xFFF3F7FC);
  static const _cloudDim = Color(0xFFD8E0EA);
  static const _drop = Color(0xFF9FD4F5);
  static const _bolt = Color(0xFFFFD45A);

  @override
  void paint(Canvas canvas, Size size) {
    switch (category) {
      case WeatherCategory.clear:
        isDay ? _sun(canvas, size, Offset(size.width * 0.5, size.height * 0.46))
              : _moon(canvas, size, Offset(size.width * 0.5, size.height * 0.46));
        break;
      case WeatherCategory.partlyCloudy:
        if (isDay) {
          _sun(canvas, size, Offset(size.width * 0.66, size.height * 0.34),
              scale: 0.7);
        } else {
          _moon(canvas, size, Offset(size.width * 0.66, size.height * 0.34),
              scale: 0.7);
        }
        _cloudShape(canvas, size, yOffset: 0.06, color: _cloud);
        break;
      case WeatherCategory.cloudy:
        _cloudShape(canvas, size, color: _cloudDim);
        _cloudShape(canvas, size,
            xOffset: -0.12, yOffset: -0.1, scale: 0.7, color: _cloud);
        break;
      case WeatherCategory.fog:
        _cloudShape(canvas, size, yOffset: -0.08, color: _cloud);
        _fogLines(canvas, size);
        break;
      case WeatherCategory.drizzle:
        _cloudShape(canvas, size, yOffset: -0.08, color: _cloud);
        _drops(canvas, size, count: 2);
        break;
      case WeatherCategory.rain:
        _cloudShape(canvas, size, yOffset: -0.08, color: _cloud);
        _drops(canvas, size, count: 3);
        break;
      case WeatherCategory.snow:
        _cloudShape(canvas, size, yOffset: -0.08, color: _cloud);
        _flakes(canvas, size);
        break;
      case WeatherCategory.thunderstorm:
        _cloudShape(canvas, size, yOffset: -0.08, color: _cloudDim);
        _boltShape(canvas, size);
        break;
    }
  }

  void _sun(Canvas canvas, Size size, Offset center, {double scale = 1}) {
    final r = size.height * 0.17 * scale;
    final glow = Paint()
      ..color = _sunB.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, r * 1.5, glow);

    final rayPaint = Paint()
      ..color = _sunA
      ..strokeWidth = size.height * 0.035 * scale
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final inner = center + Offset(math.cos(a), math.sin(a)) * (r * 1.5);
      final outer = center + Offset(math.cos(a), math.sin(a)) * (r * 2.1);
      canvas.drawLine(inner, outer, rayPaint);
    }

    final body = Paint()
      ..shader = RadialGradient(colors: const [_sunA, _sunB]).createShader(
        Rect.fromCircle(center: center, radius: r),
      );
    canvas.drawCircle(center, r, body);
  }

  void _moon(Canvas canvas, Size size, Offset center, {double scale = 1}) {
    final r = size.height * 0.18 * scale;
    final glow = Paint()
      ..color = _moonColor.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(center, r * 1.3, glow);

    // Crescent: full disc minus an offset disc.
    final disc = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    final cut = Path()
      ..addOval(Rect.fromCircle(
          center: center + Offset(r * 0.55, -r * 0.35), radius: r));
    final crescent = Path.combine(PathOperation.difference, disc, cut);
    canvas.drawPath(crescent, Paint()..color = _moonColor);
  }

  void _cloudShape(
    Canvas canvas,
    Size size, {
    double xOffset = 0,
    double yOffset = 0,
    double scale = 1,
    required Color color,
  }) {
    final w = size.width;
    final h = size.height;
    final dx = w * xOffset;
    final dy = h * yOffset;

    Offset c(double fx, double fy) => Offset(w * fx + dx, h * fy + dy);
    double s(double f) => h * f * scale;

    final path = Path()
      ..addRRect(RRect.fromLTRBR(
        w * 0.20 + dx,
        h * 0.58 + dy,
        w * 0.80 + dx,
        h * 0.80 + dy,
        Radius.circular(s(0.13)),
      ))
      ..addOval(Rect.fromCircle(center: c(0.34, 0.58), radius: s(0.15)))
      ..addOval(Rect.fromCircle(center: c(0.52, 0.47), radius: s(0.21)))
      ..addOval(Rect.fromCircle(center: c(0.66, 0.56), radius: s(0.16)));

    final glow = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path.shift(const Offset(0, 6)), glow);
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drops(Canvas canvas, Size size, {required int count}) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _drop
      ..strokeWidth = size.height * 0.04
      ..strokeCap = StrokeCap.round;
    final xs = count == 3
        ? [0.38, 0.52, 0.66]
        : count == 2
            ? [0.44, 0.6]
            : [0.52];
    for (final fx in xs) {
      final top = Offset(w * fx, h * 0.80);
      final bottom = Offset(w * (fx - 0.04), h * 0.92);
      canvas.drawLine(top, bottom, paint);
    }
  }

  void _flakes(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = _cloud;
    for (final p in [
      Offset(w * 0.40, h * 0.86),
      Offset(w * 0.54, h * 0.92),
      Offset(w * 0.66, h * 0.85),
    ]) {
      canvas.drawCircle(p, size.height * 0.028, paint);
    }
  }

  void _fogLines(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _cloud.withValues(alpha: 0.85)
      ..strokeWidth = size.height * 0.045
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.82 + i * 0.06);
      final inset = w * (0.26 + i * 0.03);
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), paint);
    }
  }

  void _boltShape(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.54, h * 0.78)
      ..lineTo(w * 0.44, h * 0.90)
      ..lineTo(w * 0.52, h * 0.90)
      ..lineTo(w * 0.46, h * 1.0)
      ..lineTo(w * 0.62, h * 0.86)
      ..lineTo(w * 0.53, h * 0.86)
      ..close();
    final glow = Paint()
      ..color = _bolt.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, Paint()..color = _bolt);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.category != category || old.isDay != isDay;
}
