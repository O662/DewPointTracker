import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where a radar frame sits relative to the present moment.
enum RadarFrameKind { past, nowcast, forecast }

/// A single radar frame, already resolved to a flutter_map tile URL template
/// plus the tile parameters that template needs to render correctly.
class RadarFrame {
  const RadarFrame({
    required this.time,
    required this.tileUrlTemplate,
    required this.kind,
    this.tileDimension = 256,
    this.zoomOffset = 0,
    this.maxNativeZoom = 12,
  });

  /// Local time of this frame.
  final DateTime time;

  /// flutter_map-compatible template ({z}/{x}/{y} placeholders).
  final String tileUrlTemplate;

  final RadarFrameKind kind;

  /// Pixel size of the source tiles (512 for RainViewer's sharper variant).
  final int tileDimension;

  /// Added to the camera zoom to get the URL zoom (−1 for 512px tiles).
  final double zoomOffset;

  /// Deepest tile zoom fetched; flutter_map upscales beyond it (bilinear).
  ///
  /// For the IEM sources this is deliberately capped at the zoom where one
  /// source data cell ≈ one tile pixel. IEM rasterizes each NEXRAD (~550 m)
  /// or HRRR (~3 km) cell as a hard square, so deeper tiles carry no extra
  /// detail — just bigger squares. Fetching at the cap and letting the GPU's
  /// bilinear upscale interpolate *between cells* renders smooth gradients
  /// (the same trick TWC-style apps use) instead of giant pixels.
  final int maxNativeZoom;

  bool get isForecast => kind == RadarFrameKind.forecast;
}

/// A full radar timeline plus the index of the "now" frame (the latest frame at
/// or before the current time).
class RadarTimeline {
  const RadarTimeline({
    required this.frames,
    required this.nowIndex,
    required this.isNexrad,
  });

  final List<RadarFrame> frames;
  final int nowIndex;

  /// True when the past frames come from the US NEXRAD composite (vs the
  /// global RainViewer mosaic).
  final bool isNexrad;

  bool get isEmpty => frames.isEmpty;
}

class RadarService {
  RadarService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _iemBase =
      'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0';

  /// Rough continental-US bounding box — where the NWS NEXRAD composite has
  /// coverage. Outside it (including Alaska/Hawaii) the radar falls back to
  /// RainViewer's global mosaic.
  static bool isInConus(double latitude, double longitude) =>
      latitude >= 21 && latitude <= 53 && longitude >= -130 && longitude <= -62;

  /// Builds a unified timeline:
  ///   • Inside the continental US: NWS NEXRAD composite ([pastHours] of
  ///     history + current) — crisp, full-resolution, no key, and built
  ///     locally so it needs no timeline API call — plus HRRR model
  ///     forecast reflectivity (up to [forecastHours] ahead), also free and
  ///     keyless via the same Iowa State Mesonet tile cache.
  ///   • Elsewhere: RainViewer past (~2h) + nowcast (~30m) — global, free —
  ///     where both ranges are whatever the API serves, not configurable.
  Future<RadarTimeline> loadTimeline({
    double? centerLatitude,
    double? centerLongitude,
    int pastHours = 1,
    int forecastHours = 8,
  }) async {
    final useNexrad =
        isInConus(centerLatitude ?? 39.5, centerLongitude ?? -98.35);

    final frames =
        useNexrad ? _nexradFrames(pastHours) : await _rainViewerFrames();

    if (useNexrad) {
      // Bridge observation → model: HRRR is a *prediction*, so a storm that
      // is on radar right now can simply be absent from its first frames —
      // storms visibly "disappeared" crossing from past to future. The
      // RainViewer nowcast extrapolates the echoes actually observed, so the
      // first ~30 minutes of future stay continuous with the past frames;
      // HRRR takes over after the nowcast ends.
      var modelStart = DateTime.now();
      try {
        final nowcast = (await _rainViewerFrames())
            .where((f) =>
                f.kind == RadarFrameKind.nowcast && f.time.isAfter(modelStart))
            .toList();
        frames.addAll(nowcast);
        for (final f in nowcast) {
          if (f.time.isAfter(modelStart)) modelStart = f.time;
        }
      } catch (_) {
        // Nowcast is a bonus; HRRR just starts at "now" without it.
      }
      try {
        final hrrr = await _hrrrForecastFrames(forecastHours);
        frames.addAll(hrrr.where((f) => f.time.isAfter(modelStart)));
      } catch (_) {
        // Forecast frames are a bonus — if the HRRR metadata fetch fails,
        // the live/past timeline still works.
      }
    }

    frames.sort((a, b) => a.time.compareTo(b.time));

    // "Now" = the latest frame at or before the current time.
    final now = DateTime.now();
    var nowIndex = 0;
    for (var i = 0; i < frames.length; i++) {
      if (!frames[i].time.isAfter(now)) nowIndex = i;
    }

    return RadarTimeline(
      frames: frames,
      nowIndex: nowIndex,
      isNexrad: useNexrad,
    );
  }

  /// Formats a UTC time the way IEM tile paths expect (YYYYMMDDHHMM).
  static String _utcStamp(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}';
  }

  /// NWS NEXRAD composite via the Iowa State Mesonet tile cache (free, no
  /// key): the classic green/yellow/red radar, CONUS-only, a new composite
  /// every 5 minutes. Frames use the archive form (`ridge::USCOMP-N0Q-<UTC>`)
  /// with an explicit scan time rather than the rolling "-mXXm" aliases: a
  /// rolling URL serves *different* imagery depending on when each tile
  /// happens to download, which let frames silently show newer weather than
  /// their time label claimed (and made every frame uncacheable).
  List<RadarFrame> _nexradFrames(int pastHours) {
    // Give IEM a moment to finish rendering a slot before trusting it — a
    // not-yet-generated timestamp answers 503, which silenceExceptions would
    // hide as a blank "current" frame.
    final safeNow = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    final newest = DateTime.utc(safeNow.year, safeNow.month, safeNow.day,
        safeNow.hour, safeNow.minute - safeNow.minute % 5);

    // Composites exist every 5 minutes, but longer histories sample coarser
    // so the frame count (≈13 mounted tile layers) stays flat: 1h→5-min
    // steps, 2h→10, 3h→15, 6h→30.
    final totalMinutes = pastHours.clamp(1, 18) * 60;
    final step = (((totalMinutes / 12).ceil() + 4) ~/ 5) * 5;

    return [
      for (var m = (totalMinutes ~/ step) * step; m >= 0; m -= step)
        RadarFrame(
          time: newest.subtract(Duration(minutes: m)).toLocal(),
          tileUrlTemplate:
              '$_iemBase/ridge::USCOMP-N0Q-${_utcStamp(newest.subtract(Duration(minutes: m)))}'
              '/{z}/{x}/{y}.png',
          kind: RadarFrameKind.past,
          // N0Q's ~550 m grid ≈ 1 tile px at zoom 8 (mid-CONUS latitudes).
          maxNativeZoom: 8,
        ),
    ];
  }

  /// RainViewer past + nowcast (global coverage, lower resolution).
  Future<List<RadarFrame>> _rainViewerFrames() async {
    final uri = Uri.https('api.rainviewer.com', '/public/weather-maps.json');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Radar service error (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final host = json['host'] as String;
    final radar = json['radar'] as Map<String, dynamic>;

    // 512px tiles carry roughly double the linear detail of the 256px ones at
    // the same URL zoom (the server still tops out at URL zoom 7). Rendered
    // with tileDimension 512 + zoomOffset -1, geometry stays identical while
    // effective resolution doubles, so native data reaches camera zoom 8.
    String rvTemplate(String path) => '$host$path/512/{z}/{x}/{y}/4/1_1.png';

    final frames = <RadarFrame>[];
    void addRainViewer(String key, RadarFrameKind kind) {
      for (final entry in (radar[key] as List<dynamic>? ?? const [])) {
        final m = entry as Map<String, dynamic>;
        frames.add(RadarFrame(
          time: DateTime.fromMillisecondsSinceEpoch(
              (m['time'] as num).toInt() * 1000),
          tileUrlTemplate: rvTemplate(m['path'] as String),
          kind: kind,
          tileDimension: 512,
          zoomOffset: -1,
          maxNativeZoom: 8,
        ));
      }
    }

    addRainViewer('past', RadarFrameKind.past);
    addRainViewer('nowcast', RadarFrameKind.nowcast);
    return frames;
  }

  /// Where the latest processed HRRR run is advertised. The IEM renders HRRR
  /// forecast reflectivity as tiles under the same cache as NEXRAD — free, no
  /// key — and this small JSON names the newest model initialization time.
  static const _hrrrMetaUrl =
      'https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/refd_1080.json';

  /// HRRR model forecast reflectivity (CONUS-only, free, keyless).
  ///
  /// The model produces a frame every 15 minutes out to 18 hours; we sample
  /// from the first step after "now" to [hours] ahead at a spacing that keeps
  /// the frame count (and mounted tile layers) roughly constant: ≤4h→15-min
  /// steps, 8h→30, 12h→45, 18h→75.
  Future<List<RadarFrame>> _hrrrForecastFrames(int hours) async {
    final response = await _client
        .get(Uri.parse(_hrrrMetaUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HRRR metadata error (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final init = DateTime.parse(json['model_init_utc'] as String).toUtc();

    // Tile paths name the run explicitly (YYYYMMDDHHMM). The IEM docs advise
    // this over the "latest run" alias so cached tiles can never mix runs.
    final runLabel = _utcStamp(init);

    final now = DateTime.now().toUtc();
    final sinceInit = now.difference(init).inMinutes;
    final lastStep = sinceInit + hours * 60;

    // Spacing: smallest multiple of the model's 15-min cadence that keeps
    // the range under ~16 frames (minimum 15).
    var spacing = (((hours * 60 / 16).ceil() + 14) ~/ 15) * 15;
    if (spacing < 15) spacing = 15;

    final out = <RadarFrame>[];
    // First forecast step strictly after "now"; HRRR tops out at forecast
    // minute 1080 (18 hours).
    for (var step = (sinceInit ~/ spacing + 1) * spacing;
        step <= lastStep && step <= 1080;
        step += spacing) {
      out.add(RadarFrame(
        time: init.add(Duration(minutes: step)).toLocal(),
        tileUrlTemplate:
            '$_iemBase/hrrr::REFD-F${step.toString().padLeft(4, '0')}-$runLabel'
            '/{z}/{x}/{y}.png',
        kind: RadarFrameKind.forecast,
        // HRRR's ~3 km grid ≈ 1.5 tile px at zoom 6 (mid-CONUS latitudes).
        maxNativeZoom: 6,
      ));
    }
    return out;
  }
}
