import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/units.dart';
import '../models/weather_data.dart';
import '../state/weather_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_sky.dart';
import '../widgets/dew_point_gauge.dart';
import '../widgets/glass_card.dart';
import '../widgets/hourly_strip.dart';
import '../widgets/weather_glyph.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    final weather = controller.weather;
    final palette = weather == null
        ? SkyPalette.loading
        : SkyPalette.of(weather.condition.category, weather.isDay);

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSky(palette: palette),
        SafeArea(
          bottom: false,
          child: _buildBody(context),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (controller.status == LoadStatus.error && controller.weather == null) {
      return _ErrorState(controller: controller);
    }
    if (controller.weather == null) {
      return const _LoadingState();
    }
    return _ReadyState(controller: controller);
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              'Finding your weather…',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_rounded, size: 44, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                controller.errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
              ),
              const SizedBox(height: 22),
              FilledButton.tonal(
                onPressed: controller.isLoading ? null : controller.load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    final weather = controller.weather!;
    final unit = controller.unit;

    return RefreshIndicator(
      onRefresh: controller.load,
      color: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          _TopBar(controller: controller),
          const SizedBox(height: 18),
          _Hero(weather: weather, unit: unit),
          const SizedBox(height: 22),
          _HiLo(weather: weather, unit: unit),
          const SizedBox(height: 18),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.opacity_rounded,
                        size: 16, color: Colors.white.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Text(
                      'DEW POINT',
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
                DewPointGauge(dewPointC: weather.dewPointC, unit: unit),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Metrics(weather: weather, unit: unit),
          const SizedBox(height: 18),
          HourlyStrip(hours: weather.hourly, unit: unit),
          const SizedBox(height: 18),
          _Footer(weather: weather),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on_rounded, size: 20, color: Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            controller.locationLabel ?? 'My location',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        GlassPill(
          child: GestureDetector(
            onTap: controller.toggleUnit,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _unitText('°F', controller.unit == TempUnit.fahrenheit),
                Text(' | ',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                _unitText('°C', controller.unit == TempUnit.celsius),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _unitText(String label, bool active) => Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
        ),
      );
}

class _Hero extends StatefulWidget {
  const _Hero({required this.weather, required this.unit});

  final WeatherData weather;
  final TempUnit unit;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weather;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _float,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -6 * (0.5 - (_float.value - 0.5).abs()) * 2),
            child: child,
          ),
          child: WeatherGlyph(
            category: w.condition.category,
            isDay: w.isDay,
            size: 140,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.unit.format(w.temperatureC),
            style: const TextStyle(
              fontSize: 104,
              fontWeight: FontWeight.w200,
              height: 1.0,
              letterSpacing: -3,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          w.condition.label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Feels like ${widget.unit.formatWithUnit(w.apparentTemperatureC)}',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

class _HiLo extends StatelessWidget {
  const _HiLo({required this.weather, required this.unit});

  final WeatherData weather;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassPill(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _item(Icons.arrow_upward_rounded, 'High', unit.format(weather.highC)),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: Colors.white.withValues(alpha: 0.25),
              ),
              _item(Icons.arrow_downward_rounded, 'Low', unit.format(weather.lowC)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.weather, required this.unit});

  final WeatherData weather;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final imperial = unit == TempUnit.fahrenheit;
    final wind = imperial
        ? '${(weather.windSpeedKmh * 0.621371).round()} mph'
        : '${weather.windSpeedKmh.round()} km/h';
    final precip = imperial
        ? '${(weather.precipitationMm / 25.4).toStringAsFixed(2)} in'
        : '${weather.precipitationMm.toStringAsFixed(1)} mm';

    final tiles = [
      _Metric(Icons.thermostat_rounded, 'Feels like',
          unit.formatWithUnit(weather.apparentTemperatureC)),
      _Metric(Icons.water_drop_rounded, 'Humidity', '${weather.humidity}%'),
      _Metric(Icons.air_rounded, 'Wind', wind),
      _Metric(Icons.grain_rounded, 'Precip', precip),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(child: tiles[i]),
          if (i != tiles.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Updated ${DateFormat('h:mm a').format(weather.observedAt)} · Open-Meteo',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
