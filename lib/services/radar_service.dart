import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where a radar frame sits relative to the present moment.
enum RadarFrameKind { past, nowcast, forecast }

/// A single radar frame, already resolved to a flutter_map tile URL template.
class RadarFrame {
  const RadarFrame({
    required this.time,
    required this.tileUrlTemplate,
    required this.kind,
  });

  /// Local time of this frame.
  final DateTime time;

  /// flutter_map-compatible template ({z}/{x}/{y} placeholders).
  final String tileUrlTemplate;

  final RadarFrameKind kind;

  bool get isForecast => kind == RadarFrameKind.forecast;
}

/// A full radar timeline plus the index of the "now" frame (the latest frame at
/// or before the current time).
class RadarTimeline {
  const RadarTimeline({required this.frames, required this.nowIndex});

  final List<RadarFrame> frames;
  final int nowIndex;

  bool get isEmpty => frames.isEmpty;
}

class RadarService {
  RadarService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Builds a unified timeline:
  ///   • RainViewer past (~2h) + nowcast (~30m) — free, always included.
  ///   • Tomorrow.io forecast (hourly, up to [forecastHours]) — only when a
  ///     [tomorrowApiKey] is supplied.
  Future<RadarTimeline> loadTimeline({
    String tomorrowApiKey = '',
    int forecastHours = 8,
  }) async {
    final frames = <RadarFrame>[];

    // 1) RainViewer past + nowcast.
    final uri = Uri.https('api.rainviewer.com', '/public/weather-maps.json');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Radar service error (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final host = json['host'] as String;
    final radar = json['radar'] as Map<String, dynamic>;

    String rvTemplate(String path) => '$host$path/256/{z}/{x}/{y}/4/1_1.png';

    void addRainViewer(String key, RadarFrameKind kind) {
      for (final entry in (radar[key] as List<dynamic>? ?? const [])) {
        final m = entry as Map<String, dynamic>;
        frames.add(RadarFrame(
          time: DateTime.fromMillisecondsSinceEpoch(
              (m['time'] as num).toInt() * 1000),
          tileUrlTemplate: rvTemplate(m['path'] as String),
          kind: kind,
        ));
      }
    }

    addRainViewer('past', RadarFrameKind.past);
    addRainViewer('nowcast', RadarFrameKind.nowcast);

    // 2) Tomorrow.io forecast (optional).
    if (tomorrowApiKey.isNotEmpty) {
      frames.addAll(_tomorrowForecast(tomorrowApiKey, forecastHours));
    }

    frames.sort((a, b) => a.time.compareTo(b.time));

    // "Now" = the latest frame at or before the current time.
    final now = DateTime.now();
    var nowIndex = 0;
    for (var i = 0; i < frames.length; i++) {
      if (!frames[i].time.isAfter(now)) nowIndex = i;
    }

    return RadarTimeline(frames: frames, nowIndex: nowIndex);
  }

  /// Generates hourly Tomorrow.io forecast frames at the top of each hour.
  List<RadarFrame> _tomorrowForecast(String apiKey, int hours) {
    final out = <RadarFrame>[];
    final nowUtc = DateTime.now().toUtc();
    final topOfHour =
        DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, nowUtc.hour);

    for (var h = 1; h <= hours; h++) {
      final t = topOfHour.add(Duration(hours: h));
      // Tomorrow.io expects a raw ISO 8601 timestamp in the path, e.g.
      // .../precipitationIntensity/2026-06-25T18:00:00Z.png
      final iso = '${t.toIso8601String().split('.').first}Z';
      final template =
          'https://api.tomorrow.io/v4/map/tile/{z}/{x}/{y}/precipitationIntensity/'
          '$iso.png?apikey=$apiKey';
      out.add(RadarFrame(
        time: t.toLocal(),
        tileUrlTemplate: template,
        kind: RadarFrameKind.forecast,
      ));
    }
    return out;
  }
}
