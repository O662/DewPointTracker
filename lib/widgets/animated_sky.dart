import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A full-bleed animated backdrop: a vertical base gradient with two soft light
/// "blobs" drifting slowly behind it. Palette changes cross-fade smoothly.
class AnimatedSky extends StatefulWidget {
  const AnimatedSky({super.key, required this.palette});

  final SkyPalette palette;

  @override
  State<AnimatedSky> createState() => _AnimatedSkyState();
}

class _AnimatedSkyState extends State<AnimatedSky>
    with TickerProviderStateMixin {
  late final AnimationController _drift;
  late final AnimationController _transition;
  late SkyPalette _current;
  late SkyPalette _previous;

  @override
  void initState() {
    super.initState();
    _current = widget.palette;
    _previous = widget.palette;
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.palette != oldWidget.palette) {
      _previous = _current;
      _current = widget.palette;
      _transition.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_drift, _transition]),
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_transition.value);
        final bg = [
          for (var i = 0; i < 3; i++)
            Color.lerp(_previous.background[i], _current.background[i], t)!,
        ];
        final blobA = Color.lerp(_previous.blobA, _current.blobA, t)!;
        final blobB = Color.lerp(_previous.blobB, _current.blobB, t)!;
        final phase = _drift.value * 2 * math.pi;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: bg,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _blob(
                color: blobA,
                alignment: Alignment(
                  0.55 * math.sin(phase),
                  -0.45 + 0.25 * math.cos(phase * 0.9),
                ),
                scale: 1.5,
              ),
              _blob(
                color: blobB,
                alignment: Alignment(
                  -0.5 * math.cos(phase * 0.8),
                  0.35 + 0.3 * math.sin(phase * 0.7),
                ),
                scale: 1.7,
              ),
              // Bottom vignette keeps glass + nav legible.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x33000000)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _blob({
    required Color color,
    required Alignment alignment,
    required double scale,
  }) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: scale,
        heightFactor: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.72],
            ),
          ),
        ),
      ),
    );
  }
}
