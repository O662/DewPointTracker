import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../radar_config.dart';
import '../services/forecast_key_store.dart';
import '../services/radar_service.dart';
import '../state/weather_controller.dart';
import '../widgets/glass_card.dart';
import 'forecast_setup_sheet.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, required this.controller});

  final WeatherController controller;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final RadarService _service = RadarService();
  final ForecastKeyStore _keyStore = ForecastKeyStore();
  final MapController _map = MapController();

  // RainViewer only renders radar tiles up to zoom 7; above that its server
  // returns a "Zoom Level Not Supported" placeholder image. We cap native fetches
  // here and let flutter_map upscale for deeper zooms.
  static const int radarMaxNativeZoom = 7;
  // Tomorrow.io serves precipitation tiles up to zoom 12, at a finer native
  // resolution than RainViewer. We cap a little below to conserve free-tier
  // API usage and upscale beyond.
  static const int forecastMaxNativeZoom = 10;
  // Above this zoom the upscaled radar starts looking blocky, so we surface a
  // little explanatory notice.
  static const double pixelNoticeZoom = 8.5;
  // Smooth the radar's blocky data cells into fluid, rounded contours — WITHOUT
  // the hazy look of a plain blur. This is a two-step "gooey" filter: a small
  // blur first rounds off the square corners, then an alpha-contrast colour
  // matrix snaps that softened edge back to a crisp line. The precipitation
  // stays vivid and sharp-edged — only the shape changes, from stair-stepped
  // pixels to smooth shorelines. Purely cosmetic; it doesn't add real detail.
  // Tunables:
  //   • _radarRoundingRadius — how far corners get rounded (bigger = smoother).
  //   • _radarEdgeGain       — edge crispness (bigger = harder line, less feather).
  //   • _radarEdgePivot      — 0..1 alpha cut point (lower = shapes merge/grow more).
  static const double _radarRoundingRadius = 2.5;
  static const double _radarEdgeGain = 16;
  static const double _radarEdgePivot = 0.45;

  static final ui.ImageFilter _radarSmoothFilter = ui.ImageFilter.compose(
    // 2) Re-crisp the blurred edge: keep RGB untouched, steepen the alpha ramp
    //    so the soft falloff becomes a clean (still lightly anti-aliased) line.
    outer: const ui.ColorFilter.matrix(<double>[
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, _radarEdgeGain, (0.5 - _radarEdgeGain * _radarEdgePivot) * 255,
    ]),
    // 1) Round the blocky corners.
    inner: ui.ImageFilter.blur(
      sigmaX: _radarRoundingRadius,
      sigmaY: _radarRoundingRadius,
      tileMode: TileMode.decal,
    ),
  );
  // Accent for forecast (future) frames.
  static const Color forecastAccent = Color(0xFFFFC15E);

  List<RadarFrame> _frames = [];
  int _index = 0;
  int _nowIndex = 0;
  bool _playing = false;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  // Indices whose tile layers are mounted (so their tiles download & stay
  // resident). We start with just the current frame for a fast first paint,
  // then background-prefetch the rest via [_prefetchTimer] for instant
  // scrubbing/playback. Mounting all ~20 frames at once was the load bottleneck.
  final Set<int> _mounted = <int>{};
  Timer? _prefetchTimer;
  bool _showPixelNotice = false;
  bool _pixelNoticeExpanded = false;

  String _apiKey = '';
  bool _promptDismissed = false;

  bool get _forecastEnabled => _apiKey.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _apiKey = await _keyStore.loadKey();
    _promptDismissed = await _keyStore.isPromptDismissed();
    if (!mounted) return;
    await _loadFrames();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prefetchTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  LatLng get _center {
    final lat = widget.controller.latitude;
    final lon = widget.controller.longitude;
    if (lat != null && lon != null) return LatLng(lat, lon);
    return const LatLng(39.5, -98.35); // Continental US fallback.
  }

  bool get _hasFix =>
      widget.controller.latitude != null && widget.controller.longitude != null;

  Future<void> _loadFrames() async {
    _prefetchTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final timeline = await _service.loadTimeline(
        tomorrowApiKey: _apiKey,
        forecastHours: kForecastHoursAhead,
      );
      if (!mounted) return;
      setState(() {
        _frames = timeline.frames;
        _nowIndex = timeline.nowIndex;
        _index = timeline.nowIndex; // Open on the current time.
        _loading = false;
        _mounted
          ..clear()
          ..add(timeline.nowIndex); // Paint the current frame first…
      });
      _schedulePrefetch(); // …then quietly fetch the rest of the timeline.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load radar data.';
        _loading = false;
      });
    }
  }

  /// Mounts the remaining frames a short beat after the current one is on
  /// screen, so their tiles download in the background. This keeps the first
  /// paint fast (one frame's tiles, not the whole timeline's at once) while
  /// still making scrubbing and playback instant once prefetch completes.
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    if (_mounted.length >= _frames.length) return;
    _prefetchTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _frames.length; i++) {
          _mounted.add(i);
        }
      });
    });
  }

  void _togglePlay() {
    if (_frames.isEmpty) return;
    setState(() => _playing = !_playing);
    _timer?.cancel();
    if (_playing) {
      _timer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % _frames.length;
          _mounted.add(_index); // In case playback outruns the prefetch.
        });
      });
    }
  }

  Future<void> _openForecastSetup() async {
    _timer?.cancel();
    if (_playing) setState(() => _playing = false);

    final result = await showForecastSetupSheet(context, initialKey: _apiKey);
    if (result == null || !mounted) return;

    if (result.isEmpty) {
      await _keyStore.clearKey();
      _apiKey = await _keyStore.loadKey(); // may fall back to a --dart-define key
    } else {
      await _keyStore.saveKey(result);
      _apiKey = result;
      _promptDismissed = false;
    }
    if (!mounted) return;

    await _loadFrames();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_forecastEnabled
            ? 'Forecast radar enabled'
            : 'Forecast radar turned off'),
      ),
    );
  }

  void _dismissPrompt() {
    setState(() => _promptDismissed = true);
    _keyStore.dismissPrompt();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: _hasFix ? 7.5 : 4,
            minZoom: 3,
            maxZoom: 15,
            backgroundColor: const Color(0xFF0E1320),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onPositionChanged: (camera, _) {
              final show = camera.zoom > pixelNoticeZoom;
              if (show != _showPixelNotice) {
                setState(() {
                  _showPixelNotice = show;
                  if (!show) _pixelNoticeExpanded = false;
                });
              }
            },
          ),
          children: [
            TileLayer(
              // Base map WITHOUT labels — the place names live in a separate
              // overlay above the radar so towns/cities stay readable over the
              // clouds (see the labels layer below).
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.dewpoint.dew_point_tracker',
              maxZoom: 19,
            ),
            ..._radarLayers(),
            // Town / city labels, drawn on top of the radar so names remain
            // legible over precipitation. These tiles are transparent except
            // for the text, so the radar shows through everywhere else.
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.dewpoint.dew_point_tracker',
              maxZoom: 19,
            ),
            if (_hasFix)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 26,
                    height: 26,
                    child: const _LocationDot(),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                children: [
                  _TopBar(
                    label: widget.controller.locationLabel ?? 'Radar',
                    onRecenter: () => _map.move(_center, _hasFix ? 7.5 : 4),
                    onSettings: _openForecastSetup,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _showPixelNotice
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _PixelNotice(
                              expanded: _pixelNoticeExpanded,
                              onToggle: () => setState(() =>
                                  _pixelNoticeExpanded = !_pixelNoticeExpanded),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: (!_forecastEnabled &&
                            !_promptDismissed &&
                            !_loading &&
                            _error == null)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _ForecastAskCard(
                              onSetup: _openForecastSetup,
                              onDismiss: _dismissPrompt,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 110,
          child: _buildControls(),
        ),
      ],
    );
  }

  /// Builds one tile layer per frame and keeps them all mounted at once.
  ///
  /// Mounting every frame lets its tiles download once up front and stay
  /// resident, so scrubbing or playing the timeline switches instantly instead
  /// of showing a blank map while the next frame's tiles load. Only the active
  /// frame is visible — the rest sit at zero opacity (still loading/cached).
  List<Widget> _radarLayers() {
    final layers = <Widget>[];
    for (var i = 0; i < _frames.length; i++) {
      // Skip frames we haven't mounted yet — their tiles get fetched lazily
      // (current frame first, the rest via the background prefetch) so the
      // radar paints fast instead of downloading the whole timeline up front.
      if (!_mounted.contains(i)) continue;
      final frame = _frames[i];
      final isForecast = frame.isForecast;
      final baseOpacity = isForecast ? 0.62 : 0.72;
      layers.add(
        Opacity(
          opacity: i == _index ? baseOpacity : 0.0,
          // Smooth the blocky data cells into fluid contours. Wrapping only the
          // radar tiles (not the basemap or the labels above) keeps roads and
          // place names crisp while the precipitation reads as smooth shapes.
          // Opacity short-circuits painting at 0, so this filter only ever runs
          // on the single visible frame.
          child: ImageFiltered(
            imageFilter: _radarSmoothFilter,
            child: TileLayer(
              key: ValueKey(frame.tileUrlTemplate),
              urlTemplate: frame.tileUrlTemplate,
              userAgentPackageName: 'com.dewpoint.dew_point_tracker',
              // RainViewer past/nowcast top out at zoom 7 (above which its
              // server returns a "Zoom Level Not Supported" placeholder);
              // Tomorrow.io forecast goes finer. Cap native fetches accordingly
              // and upscale.
              maxNativeZoom:
                  isForecast ? forecastMaxNativeZoom : radarMaxNativeZoom,
              tileProvider: NetworkTileProvider(
                // Forecast tiles are stable per timestamp, so let them cache
                // (fewer API calls when looping). RainViewer frames are
                // ephemeral — don't cache them (avoids "fallback freshness age"
                // log spam).
                cachingProvider:
                    isForecast ? null : const DisabledMapCachingProvider(),
                // Radar tiles legitimately error sometimes: RainViewer past
                // frames expire mid-session, and Tomorrow.io rejects a bad key
                // or out-of-range timestamp. By default flutter_map then tries
                // to DECODE the error response body (JSON/HTML text) as an
                // image, which floods logcat with native "Failed to decode
                // image" errors. Skip that, and just treat a failed tile as
                // absent — a missing precip tile is fine to silently drop.
                attemptDecodeOfHttpErrorResponses: false,
                silenceExceptions: true,
              ),
              // No fade: the active frame is already loaded, so it swaps in
              // fully drawn. That reads as weather moving across the map rather
              // than one frame cross-fading into the next.
              tileDisplay: const TileDisplay.instantaneous(),
            ),
          ),
        ),
      );
    }
    return layers;
  }

  String _relativeLabel(RadarFrame f) {
    final mins = f.time.difference(DateTime.now()).inMinutes;
    if (mins.abs() <= 5) return 'now';
    final m = mins.abs();
    final text = m >= 60
        ? (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m')
        : '${m}m';
    return mins > 0 ? 'in $text' : '$text ago';
  }

  Widget _kindChip(RadarFrame f) {
    String text;
    Color color;
    if (_index == _nowIndex) {
      text = 'LIVE';
      color = const Color(0xFF35D29A);
    } else if (f.kind == RadarFrameKind.forecast) {
      text = 'FORECAST';
      color = forecastAccent;
    } else if (f.kind == RadarFrameKind.nowcast) {
      text = 'NOWCAST';
      color = const Color(0xFF4FB0E8);
    } else {
      text = 'PAST';
      color = Colors.white.withValues(alpha: 0.7);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    if (_loading) {
      return const _StatusPill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 10),
            Text('Loading radar…', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    if (_error != null || _frames.isEmpty) {
      return _StatusPill(
        child: GestureDetector(
          onTap: _loadFrames,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(_error ?? 'No radar frames', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final frame = _frames[_index];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      borderRadius: 26,
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlay,
            icon: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('h:mm a').format(frame.time),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeLabel(frame),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const Spacer(),
                    _kindChip(frame),
                  ],
                ),
                const SizedBox(height: 2),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                    thumbColor: frame.isForecast ? forecastAccent : Colors.white,
                  ),
                  child: Slider(
                    value: _index.toDouble(),
                    min: 0,
                    max: (_frames.length - 1).toDouble(),
                    onChanged: (v) {
                      _timer?.cancel();
                      setState(() {
                        _playing = false;
                        _index = v.round();
                        _mounted.add(_index); // Load the scrubbed-to frame now.
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.onRecenter,
    required this.onSettings,
  });

  final String label;
  final VoidCallback onRecenter;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GlassPill(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.radar_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onSettings,
          child: const GlassPill(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.tune_rounded, size: 20, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onRecenter,
          child: const GlassPill(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.my_location_rounded, size: 20, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// A dismissible card that asks whether the user wants to enable forecast radar.
class _ForecastAskCard extends StatelessWidget {
  const _ForecastAskCard({required this.onSetup, required this.onDismiss});

  final VoidCallback onSetup;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.satellite_alt_rounded,
                  size: 20, color: Color(0xFFFFC15E)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'See the future?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Add forecast radar to see up to 6 hours of predicted rain & snow. '
            "It's free with a Tomorrow.io key.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSetup,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC15E),
                  foregroundColor: const Color(0xFF1A1300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Set it up',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact, tappable notice that appears when the user has zoomed in past the
/// radar's native resolution. Tapping expands an explanation.
class _PixelNotice extends StatelessWidget {
  const _PixelNotice({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GestureDetector(
          onTap: onToggle,
          child: GlassCard(
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: Colors.white.withValues(alpha: 0.9)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Radar is lower-res at this zoom',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Live radar imagery is only produced up to about zoom 7. '
                        'Beyond that it gets stretched to fit, so it can look '
                        'blocky. Zoom out a little for sharper detail.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: GlassPill(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: child,
      ),
    );
  }
}

class _LocationDot extends StatelessWidget {
  const _LocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4FB0E8),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4FB0E8).withValues(alpha: 0.8),
            blurRadius: 14,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}
