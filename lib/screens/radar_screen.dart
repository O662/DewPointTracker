import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../services/radar_service.dart';
import '../services/tile_fetch_monitor.dart';
import '../state/weather_controller.dart';
import '../widgets/glass_card.dart';
import 'location_search_sheet.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, required this.controller});

  final WeatherController controller;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final RadarService _service = RadarService();
  final MapController _map = MapController();
  // One shared HTTP client behind every tile layer (base map, labels, radar),
  // so the top-bar glow can pulse while ANY map imagery is downloading.
  final TileFetchMonitor _fetchMonitor = TileFetchMonitor();

  // Keep the map's zoom ceiling near the radar's usable range. At the old cap
  // of 15 the radar was stretched 128×+ — an unreadable smear that could also
  // fail to rasterize (radar vanished entirely at max zoom). Zoom 12 is
  // street-map-legible, keeps NEXRAD's bilinear upscale (native cap 8, one
  // ~550 m cell per tile pixel) smooth rather than smeared, and keeps the
  // RainViewer fallback to a tolerable upscale.
  static const double mapMaxZoom = 12;
  // Above this zoom the RainViewer fallback starts looking blocky, so we
  // surface a little explanatory notice. (NEXRAD is native all the way to the
  // zoom cap, so the notice is skipped in the US.)
  static const double pixelNoticeZoom = 8.5;
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
  // Whether the current timeline uses the US NEXRAD composite (crisp, native
  // to the zoom cap) or the RainViewer global fallback.
  bool _useNexrad = false;
  // Live camera zoom readout for the top-right indicator pill.
  late String _zoomLabel = (_hasFix ? 7.5 : 4.0).toStringAsFixed(1);

  // How often the timeline silently re-syncs (NEXRAD regenerates every ~5
  // minutes, RainViewer publishes new frames roughly every 10).
  static const Duration _timelineRefreshEvery = Duration(minutes: 5);
  Timer? _staleTimer;

  // True while the user is actively panning/zooming. During a gesture only
  // the visible radar frame stays mounted: with the whole timeline mounted, a
  // pinch used to kick off new-zoom tile fetches for ~20 layers at once —
  // hundreds of simultaneous downloads/decodes, enough main-thread work to
  // freeze the loading pulse (and the gesture itself). Once the camera
  // settles, the other frames re-mount via the staggered prefetch.
  bool _interacting = false;
  Timer? _interactionSettle;

  // Follow the weather location: when the user picks a different place (or the
  // first GPS fix arrives), recenter the map there.
  bool _mapReady = false;
  double? _followedLat;
  double? _followedLon;

  // Rebuild the timeline when the Settings page changes the radar range.
  int? _followedPastHours;
  int? _followedFutureHours;

  // Last camera position that was fully finite. flutter_map's multi-finger
  // gesture math can emit a NaN/Infinity camera in rare edge cases (the
  // fleaflet #2199 family — 8.3.1 fixed one instance, not all); a non-finite
  // camera makes every TileLayer throw "Infinity or NaN toInt" while
  // computing its tile range. We watch every camera change and snap back to
  // this position before the bad camera reaches the tile layers.
  LatLng? _lastGoodCenter;
  double? _lastGoodZoom;

  @override
  void initState() {
    super.initState();
    _followedLat = widget.controller.latitude;
    _followedLon = widget.controller.longitude;
    _followedPastHours = widget.controller.radarPastHours;
    _followedFutureHours = widget.controller.radarFutureHours;
    widget.controller.addListener(_onControllerChanged);
    _staleTimer = Timer.periodic(_timelineRefreshEvery, (_) {
      // Only refresh while parked on the live frame — never yank the timeline
      // out from under a scrub, playback, or an in-progress gesture.
      if (!mounted || _loading || _playing || _interacting) return;
      if (_index != _nowIndex) return;
      _loadFrames(silent: true);
    });
    _loadFrames();
  }

  void _onControllerChanged() {
    // Radar range changed in Settings → rebuild the timeline with it.
    final past = widget.controller.radarPastHours;
    final future = widget.controller.radarFutureHours;
    if (past != _followedPastHours || future != _followedFutureHours) {
      _followedPastHours = past;
      _followedFutureHours = future;
      if (!_loading) _loadFrames();
    }

    final lat = widget.controller.latitude;
    final lon = widget.controller.longitude;
    if (lat == null || lon == null) return;
    if (lat == _followedLat && lon == _followedLon) return;
    _followedLat = lat;
    _followedLon = lon;
    if (_mapReady) _map.move(LatLng(lat, lon), 7.5);
    // Crossing in/out of the continental US switches the radar source
    // (NEXRAD ↔ RainViewer), so the timeline must be rebuilt.
    if (!_loading && RadarService.isInConus(lat, lon) != _useNexrad) {
      _loadFrames();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prefetchTimer?.cancel();
    _staleTimer?.cancel();
    _interactionSettle?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _map.dispose();
    _fetchMonitor.dispose();
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

  /// [silent] refreshes the timeline in place (periodic re-sync) without
  /// flashing the loading pill or resetting what's on screen mid-look.
  Future<void> _loadFrames({bool silent = false}) async {
    _prefetchTimer?.cancel();
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final timeline = await _service.loadTimeline(
        centerLatitude: widget.controller.latitude,
        centerLongitude: widget.controller.longitude,
        pastHours: widget.controller.radarPastHours,
        forecastHours: widget.controller.radarFutureHours,
      );
      if (!mounted) return;
      setState(() {
        _frames = timeline.frames;
        _nowIndex = timeline.nowIndex;
        _index = timeline.nowIndex; // Open on the current time.
        _useNexrad = timeline.isNexrad;
        // The low-res notice is RainViewer-only; drop it if we just switched
        // to NEXRAD while zoomed in (onPositionChanged only fires on moves).
        if (_useNexrad && _showPixelNotice) {
          _showPixelNotice = false;
          _pixelNoticeExpanded = false;
        }
        _loading = false;
        _error = null;
        _mounted
          ..clear()
          ..add(timeline.nowIndex); // Paint the current frame first…
      });
      _schedulePrefetch(); // …then quietly fetch the rest of the timeline.
    } catch (_) {
      if (!mounted || silent) return; // A failed re-sync keeps the old frames.
      setState(() {
        _error = 'Could not load radar data.';
        _loading = false;
      });
    }
  }

  /// Mounts the remaining frames in small batches — nearest to the frame on
  /// screen first — so their tiles download in the background. This keeps the
  /// first paint fast (one frame's tiles, not the whole timeline's in a single
  /// burst) while still making scrubbing and playback instant once prefetch is
  /// done, and it prioritises the frames the user is most likely to look at.
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    if (_mounted.length >= _frames.length) return;
    final queue = [
      for (var i = 0; i < _frames.length; i++)
        if (!_mounted.contains(i)) i,
    ]..sort(
        (a, b) => (a - _index).abs().compareTo((b - _index).abs()),
      );
    var cursor = 0;
    _prefetchTimer =
        Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (!mounted || cursor >= queue.length) {
        timer.cancel();
        return;
      }
      setState(() {
        for (var n = 0; n < 3 && cursor < queue.length; n++) {
          _mounted.add(queue[cursor++]);
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

  /// Collapses the radar stack to just the visible frame for the duration of
  /// a pan/zoom gesture, then rebuilds the timeline mounts once the camera
  /// has been still for a beat. (Zoomed tiles have to be re-downloaded either
  /// way — this just stops ~20 invisible layers from doing it mid-gesture.)
  void _onGestureActivity() {
    _interactionSettle?.cancel();
    _interactionSettle = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _interacting = false);
      _schedulePrefetch(); // Re-mount the rest of the timeline in batches.
    });
    if (_interacting) return;
    _prefetchTimer?.cancel();
    setState(() {
      _interacting = true;
      _mounted
        ..clear()
        ..add(_index);
    });
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
            maxZoom: mapMaxZoom,
            backgroundColor: const Color(0xFF0E1320),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _mapReady = true;
              // Seed the sanitizer so recovery works even if the very first
              // gesture is the one that produces a non-finite camera.
              _lastGoodCenter = _map.camera.center;
              _lastGoodZoom = _map.camera.zoom;
            },
            onPositionChanged: (camera, hasGesture) {
              // Camera sanitizer: a NaN/Infinity camera (rare flutter_map
              // pinch edge case) would crash every TileLayer's tile-range
              // math this frame. Restore the last finite position instead —
              // this runs before the layers rebuild, so nothing downstream
              // ever sees the poisoned camera.
              if (!camera.zoom.isFinite ||
                  !camera.center.latitude.isFinite ||
                  !camera.center.longitude.isFinite) {
                final center = _lastGoodCenter;
                final zoom = _lastGoodZoom;
                if (center != null && zoom != null) {
                  _map.move(center, zoom);
                }
                return;
              }
              _lastGoodCenter = camera.center;
              _lastGoodZoom = camera.zoom;

              if (hasGesture) _onGestureActivity();
              final zoomLabel = camera.zoom.toStringAsFixed(1);
              // The IEM sources upscale smoothly past their native caps —
              // the low-res notice only applies to the RainViewer fallback.
              final show = !_useNexrad && camera.zoom > pixelNoticeZoom;
              if (show != _showPixelNotice || zoomLabel != _zoomLabel) {
                setState(() {
                  _zoomLabel = zoomLabel;
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
              tileProvider:
                  NetworkTileProvider(httpClient: _fetchMonitor.client),
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
              tileProvider:
                  NetworkTileProvider(httpClient: _fetchMonitor.client),
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
                  ValueListenableBuilder<bool>(
                    valueListenable: _fetchMonitor.busy,
                    builder: (context, fetching, _) => _TopBar(
                      label: widget.controller.locationLabel ?? 'Radar',
                      // Pulse while the timeline is being fetched OR any map
                      // tile is still downloading — so "is it stuck or just
                      // loading?" is answered by the glow.
                      busy: fetching || _loading,
                      onSearch: () =>
                          openLocationSearch(context, widget.controller),
                      onRecenter: () => _map.move(_center, _hasFix ? 7.5 : 4),
                    ),
                  ),
                  // Live zoom-level readout, updated as the camera moves.
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GlassPill(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_in_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _zoomLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
      final baseOpacity = frame.isForecast ? 0.62 : 0.78;
      final layer = TileLayer(
        // Every radar URL now embeds an explicit timestamp (scan time or
        // model run), so the template itself is a sufficient identity — a
        // timeline refresh swaps templates and only new frames remount.
        key: ValueKey(frame.tileUrlTemplate),
        urlTemplate: frame.tileUrlTemplate,
        userAgentPackageName: 'com.dewpoint.dew_point_tracker',
        // Each frame carries its own tile geometry: the IEM sources are
        // plain 256px tiles capped at the zoom where one data cell ≈ one
        // tile pixel (NEXRAD 8, HRRR 6); RainViewer uses 512px tiles with
        // zoomOffset -1 (double detail, native to camera zoom 8).
        // flutter_map upscales past each cap with bilinear filtering, which
        // interpolates between data cells — the smooth TWC-style look.
        tileDimension: frame.tileDimension,
        zoomOffset: frame.zoomOffset,
        maxNativeZoom: frame.maxNativeZoom,
        // Radar layers skip the default one-tile pan margin: with a whole
        // timeline of layers resident, that margin multiplies into dozens of
        // extra offscreen downloads per camera move for imagery the user may
        // never scrub to. Soft precip edges make the pop-in invisible anyway.
        panBuffer: 0,
        tileProvider: NetworkTileProvider(
          httpClient: _fetchMonitor.client,
          // Radar tiles legitimately error sometimes: RainViewer past frames
          // expire mid-session, and a just-published NEXRAD scan time can
          // briefly 503. By default flutter_map then tries to DECODE the
          // error response body (JSON/HTML text) as an image, which floods
          // logcat with native "Failed to decode image" errors. Skip that,
          // and just treat a failed tile as absent — a missing precip tile
          // is fine to silently drop.
          attemptDecodeOfHttpErrorResponses: false,
          silenceExceptions: true,
        ),
        // No fade: the active frame is already loaded, so it swaps in fully
        // drawn. That reads as weather moving across the map rather than one
        // frame cross-fading into the next.
        tileDisplay: const TileDisplay.instantaneous(),
      );
      // Opacity short-circuits painting at 0, so only the single visible
      // frame is ever drawn. (Smoothing past native resolution needs no
      // screen-space filter: each frame's maxNativeZoom is capped where one
      // data cell ≈ one tile pixel, so the bilinear tile upscale interpolates
      // between cells instead of magnifying hard squares — an earlier
      // squares-plus-Gaussian-blur pass read as blurry AND blocky at once.)
      layers.add(
        Opacity(
          opacity: i == _index ? baseOpacity : 0.0,
          child: layer,
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
    required this.busy,
    required this.onSearch,
    required this.onRecenter,
  });

  final String label;

  /// While true the location pill pulses with a soft glow — the "map is
  /// loading" indicator.
  final bool busy;

  final VoidCallback onSearch;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The place pill doubles as the location switcher, same as on Home.
        Expanded(
          child: GestureDetector(
            onTap: onSearch,
            child: _PulsingGlow(
              active: busy,
              child: GlassPill(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar_rounded,
                        size: 18, color: Colors.white),
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
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
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

/// Wraps a pill with a soft, breathing glow while [active] — the radar's
/// "still loading" heartbeat. The glow eases out (rather than snapping off)
/// when loading finishes.
class _PulsingGlow extends StatefulWidget {
  const _PulsingGlow({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  static const Color _glow = Color(0xFF4FB0E8);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _pulse.repeat(reverse: true);
    } else {
      // Fade the glow out smoothly from wherever the pulse currently is.
      _pulse.animateBack(0, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: t == 0
                ? const []
                : [
                    BoxShadow(
                      color: _glow.withValues(alpha: 0.20 + 0.35 * t),
                      blurRadius: 12 + 10 * t,
                      spreadRadius: 0.5 + 2.5 * t,
                    ),
                  ],
          ),
          child: child,
        );
      },
      child: widget.child,
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
                        'Live radar imagery is only produced up to about zoom 8. '
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
