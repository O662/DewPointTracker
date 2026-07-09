import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/units.dart';
import '../models/weather_data.dart';
import '../state/weather_controller.dart';
import 'location_search_sheet.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_sky.dart';
import '../widgets/daily_forecast_card.dart';
import '../widgets/dew_point_gauge.dart';
import '../widgets/glass_card.dart';
import '../widgets/hourly_strip.dart';
import '../widgets/weather_glyph.dart';

/// The weather page: one swipeable page per location (device location first,
/// then favorites), each a scroll of long-press-reorderable glass cards.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final WeatherController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pages =
      PageController(initialPage: widget.controller.activeIndex);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncPage);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPage);
    _pages.dispose();
    super.dispose();
  }

  /// When the active location changes outside the pager (search sheet, "use
  /// my location", un/favoriting), bring the PageView to it.
  void _syncPage() {
    if (!mounted || !_pages.hasClients) return;
    final current = _pages.page;
    if (current == null) return;
    // Parked pages sit on whole numbers; don't fight a finger mid-swipe.
    if ((current - current.round()).abs() > 0.01) return;
    final target = widget.controller.activeIndex;
    if (current.round() != target) {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
          child: PageView.builder(
            controller: _pages,
            itemCount: controller.slots.length,
            onPageChanged: controller.setActivePage,
            itemBuilder: (context, i) => _LocationPage(
              // Keyed by location so page state follows its slot when the
              // list shifts (favorite added/removed).
              key: ValueKey(controller.slots[i].key),
              controller: controller,
              slot: controller.slots[i],
            ),
          ),
        ),
      ],
    );
  }
}

/// One location's page: loading / error / weather content for its slot.
class _LocationPage extends StatefulWidget {
  const _LocationPage({super.key, required this.controller, required this.slot});

  final WeatherController controller;
  final WeatherSlot slot;

  @override
  State<_LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<_LocationPage> {
  @override
  void initState() {
    super.initState();
    // PageView builds the neighbor page as a swipe starts — fetch then, so
    // the data is often ready by the time the page settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final slot = widget.slot;
      if (slot.status == LoadStatus.idle && slot.weather == null) {
        widget.controller.refreshSlot(slot);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    if (slot.weather == null && slot.status == LoadStatus.error) {
      return _ErrorState(controller: widget.controller, slot: slot);
    }
    if (slot.weather == null) {
      return const _LoadingState();
    }
    return _ReadyState(controller: widget.controller, slot: slot);
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
  const _ErrorState({required this.controller, required this.slot});

  final WeatherController controller;
  final WeatherSlot slot;

  @override
  Widget build(BuildContext context) {
    final busy = slot.status == LoadStatus.loading;
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
                slot.errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
              ),
              const SizedBox(height: 22),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () => controller.refreshSlot(slot, force: true),
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              // Location problems shouldn't dead-end the app — weather for a
              // searched city works without any location permission.
              TextButton(
                onPressed: busy
                    ? null
                    : () => openLocationSearch(context, controller),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.85),
                ),
                child: const Text('Search for a city instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.controller, required this.slot});

  final WeatherController controller;
  final WeatherSlot slot;

  Widget _card(String id, WeatherData weather, TempUnit unit) => switch (id) {
        'hilo' => _HiLo(weather: weather, unit: unit),
        'dewpoint' => _DewPointCard(
            weather: weather,
            unit: unit,
            allowProfanity: !controller.profanityFilter,
          ),
        'metrics' => _Metrics(weather: weather, unit: unit),
        'hourly' => HourlyStrip(hours: weather.hourly, unit: unit),
        'daily' => DailyForecastCard(days: weather.daily, unit: unit),
        _ => const SizedBox.shrink(),
      };

  /// The lifted card scales up slightly while dragging so it reads as picked
  /// up, without a Material elevation square behind the glass.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.035 * Curves.easeOut.transform(animation.value),
        child: child,
      ),
      child: Material(color: Colors.transparent, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weather = slot.weather!;
    final unit = controller.unit;
    final order = controller.cardOrder;

    return RefreshIndicator(
      onRefresh: () => controller.refreshSlot(slot, force: true),
      color: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      child: ReorderableListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        buildDefaultDragHandles: false,
        proxyDecorator: _dragProxy,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          controller.moveCard(oldIndex, newIndex);
        },
        header: Column(
          children: [
            _TopBar(controller: controller, slot: slot),
            if (controller.slots.length > 1) ...[
              const SizedBox(height: 12),
              _PageDots(controller: controller),
            ],
            const SizedBox(height: 18),
            _Hero(weather: weather, unit: unit),
            const SizedBox(height: 22),
          ],
        ),
        footer: _Footer(weather: weather),
        children: [
          for (var i = 0; i < order.length; i++)
            ReorderableDelayedDragStartListener(
              key: ValueKey(order[i]),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _card(order[i], weather, unit),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dots under the top bar showing which location page is active. The first
/// page (device location) gets a navigation-arrow glyph instead of a dot.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeIndex;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < controller.slots.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.5),
            child: i == 0
                ? Icon(
                    Icons.near_me_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: active == 0 ? 1 : 0.4),
                  )
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white
                          .withValues(alpha: active == i ? 1 : 0.35),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.slot});

  final WeatherController controller;
  final WeatherSlot slot;

  @override
  Widget build(BuildContext context) {
    final place = slot.place;
    return Row(
      children: [
        // Tapping the place name opens search — the label doubles as the
        // location switcher, with a chevron as the affordance.
        Expanded(
          child: GestureDetector(
            onTap: () => openLocationSearch(context, controller),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  slot.isDevice
                      ? Icons.location_on_rounded
                      : Icons.place_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    slot.label ?? place?.label ?? 'My location',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (place != null) ...[
          // Star the viewed place right from the page.
          GestureDetector(
            onTap: () => controller.toggleFavorite(place),
            behavior: HitTestBehavior.opaque,
            child: Icon(
              controller.isFavorite(place)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 24,
              color: controller.isFavorite(place)
                  ? const Color(0xFFFFD54F)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 10),
        ],
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
        const SizedBox(width: 10),
        // Settings lives in the top-right corner (the °F/°C pill sits to
        // its left).
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsScreen(controller: controller),
            ),
          ),
          behavior: HitTestBehavior.opaque,
          child: Icon(
            Icons.settings_rounded,
            size: 24,
            color: Colors.white.withValues(alpha: 0.85),
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

class _DewPointCard extends StatelessWidget {
  const _DewPointCard({
    required this.weather,
    required this.unit,
    required this.allowProfanity,
  });

  final WeatherData weather;
  final TempUnit unit;
  final bool allowProfanity;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
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
          DewPointGauge(
            dewPointC: weather.dewPointC,
            unit: unit,
            allowProfanity: allowProfanity,
          ),
        ],
      ),
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
      // GlassCard's inner Stack aligns content top-left; center the column so
      // the icon and text sit in the middle of the tile.
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
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
