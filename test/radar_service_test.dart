import 'package:dew_point_tracker/services/radar_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RadarService CONUS timeline (NEXRAD + HRRR forecast)', () {
    // Serves the IEM HRRR metadata with a run initialized 90 minutes ago —
    // roughly the freshness of a real processed run.
    RadarService serviceWithHrrrRun(DateTime initUtc) {
      final iso = '${initUtc.toIso8601String().split('.').first}Z';
      return RadarService(
        client: MockClient((request) async {
          if (request.url.path.contains('/hrrr/refd_1080.json')) {
            return http.Response(
                '{"model_init_utc": "$iso", "forecast_minute": 1080.0}', 200);
          }
          return http.Response('not found', 404);
        }),
      );
    }

    test('builds past NEXRAD frames plus future HRRR frames', () async {
      final init = DateTime.now().toUtc().subtract(const Duration(minutes: 90));
      final timeline = await serviceWithHrrrRun(init).loadTimeline(
        centerLatitude: 39.7, // Denver — inside CONUS
        centerLongitude: -104.9,
        forecastHours: 6,
      );

      expect(timeline.isNexrad, isTrue);

      final past =
          timeline.frames.where((f) => f.kind == RadarFrameKind.past).toList();
      final forecast = timeline.frames.where((f) => f.isForecast).toList();
      expect(past, hasLength(13)); // 1 h of history + current, 5-min steps.
      expect(forecast, isNotEmpty);

      final now = DateTime.now();
      for (final f in past) {
        // Archive URLs pin an explicit UTC scan time (never the rolling
        // "-mXXm" aliases, whose imagery drifts under a fixed time label),
        // aligned to the composite's 5-minute cadence and never future.
        final match = RegExp(r'ridge::USCOMP-N0Q-(\d{12})/')
            .firstMatch(f.tileUrlTemplate);
        expect(match, isNotNull,
            reason: 'past frames must use timestamped USCOMP tiles');
        expect(int.parse(match!.group(1)!) % 5, 0);
        expect(f.time.isAfter(now), isFalse);
      }
      for (final f in forecast) {
        expect(f.time.isAfter(now), isTrue,
            reason: 'forecast frames must be in the future');
        expect(f.tileUrlTemplate, contains('hrrr::REFD-F'));
        // Explicit run stamp (YYYYMMDDHHMM), never the "latest run" alias.
        expect(f.tileUrlTemplate, isNot(contains('-0/')));
      }

      // Frames run oldest → newest with "now" pointing at the latest
      // non-future frame.
      final times = timeline.frames.map((f) => f.time).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue);
      }
      expect(timeline.frames[timeline.nowIndex].isForecast, isFalse);

      // 30-minute forecast spacing out to ~6 hours ahead.
      expect(forecast.length, inInclusiveRange(11, 12));
      for (var i = 1; i < forecast.length; i++) {
        expect(forecast[i].time.difference(forecast[i - 1].time).inMinutes, 30);
      }
    });

    test('a failed HRRR metadata fetch still yields the live timeline',
        () async {
      final service = RadarService(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      final timeline = await service.loadTimeline(
        centerLatitude: 39.7,
        centerLongitude: -104.9,
        forecastHours: 6,
      );
      expect(timeline.frames, hasLength(13));
      expect(timeline.frames.any((f) => f.isForecast), isFalse);
    });

    test('longer ranges sample coarser so the frame count stays flat',
        () async {
      final init = DateTime.now().toUtc().subtract(const Duration(minutes: 90));
      final timeline = await serviceWithHrrrRun(init).loadTimeline(
        centerLatitude: 39.7,
        centerLongitude: -104.9,
        pastHours: 3,
        forecastHours: 18,
      );

      final past =
          timeline.frames.where((f) => f.kind == RadarFrameKind.past).toList();
      final forecast = timeline.frames.where((f) => f.isForecast).toList();

      // 3 h of history at 15-min steps — same ~13 frames as 1 h at 5-min.
      expect(past, hasLength(13));
      for (var i = 1; i < past.length; i++) {
        expect(past[i].time.difference(past[i - 1].time).inMinutes, 15);
      }

      // 18 h of forecast at 75-min steps, capped at HRRR minute 1080.
      expect(forecast.length, lessThanOrEqualTo(16));
      for (var i = 1; i < forecast.length; i++) {
        expect(forecast[i].time.difference(forecast[i - 1].time).inMinutes, 75);
      }
      for (final f in forecast) {
        final match =
            RegExp(r'REFD-F(\d{4})-').firstMatch(f.tileUrlTemplate)!;
        final minute = int.parse(match.group(1)!);
        expect(minute, lessThanOrEqualTo(1080));
        expect(minute % 15, 0, reason: 'HRRR only has 15-min steps');
      }
    });

    test('RainViewer nowcast bridges observed radar into the HRRR forecast',
        () async {
      final now = DateTime.now();
      int epoch(Duration fromNow) =>
          now.add(fromNow).millisecondsSinceEpoch ~/ 1000;
      final init = now.toUtc().subtract(const Duration(minutes: 90));
      final iso = '${init.toIso8601String().split('.').first}Z';

      final service = RadarService(
        client: MockClient((request) async {
          if (request.url.path.contains('/hrrr/refd_1080.json')) {
            return http.Response('{"model_init_utc": "$iso"}', 200);
          }
          if (request.url.host == 'api.rainviewer.com') {
            return http.Response(
                '{"host": "https://tilecache.rainviewer.com", "radar": {'
                '"past": [{"time": ${epoch(const Duration(minutes: -10))}, "path": "/v2/radar/p1"}],'
                '"nowcast": ['
                '{"time": ${epoch(const Duration(minutes: 20))}, "path": "/v2/radar/n1"},'
                '{"time": ${epoch(const Duration(minutes: 40))}, "path": "/v2/radar/n2"}'
                ']}}',
                200);
          }
          return http.Response('not found', 404);
        }),
      );

      final timeline = await service.loadTimeline(
        centerLatitude: 39.7,
        centerLongitude: -104.9,
        forecastHours: 6,
      );

      // Both nowcast frames are in, but RainViewer's *past* frames are not —
      // NEXRAD owns the history inside CONUS.
      final nowcast = timeline.frames
          .where((f) => f.kind == RadarFrameKind.nowcast)
          .toList();
      expect(nowcast, hasLength(2));
      expect(
        timeline.frames.any((f) =>
            f.kind == RadarFrameKind.past && f.tileDimension == 512),
        isFalse,
      );

      // HRRR only takes over after the nowcast ends — no model frame may
      // overlap (or precede) the extrapolation window.
      final lastNowcast = nowcast.last.time;
      for (final f in timeline.frames.where((f) => f.isForecast)) {
        expect(f.time.isAfter(lastNowcast), isTrue);
      }
    });

    test('forecast steps are clamped to HRRR range (minute 1080)', () async {
      // A stale run from 17 hours ago leaves under an hour of forecast room.
      final init =
          DateTime.now().toUtc().subtract(const Duration(hours: 17));
      final timeline = await serviceWithHrrrRun(init).loadTimeline(
        centerLatitude: 39.7,
        centerLongitude: -104.9,
        forecastHours: 6,
      );
      final forecast = timeline.frames.where((f) => f.isForecast);
      expect(forecast.length, lessThanOrEqualTo(2));
      for (final f in forecast) {
        final match =
            RegExp(r'REFD-F(\d{4})-').firstMatch(f.tileUrlTemplate)!;
        expect(int.parse(match.group(1)!), lessThanOrEqualTo(1080));
      }
    });
  });

  test('isInConus distinguishes US from elsewhere', () {
    expect(RadarService.isInConus(39.7, -104.9), isTrue); // Denver
    expect(RadarService.isInConus(51.5, -0.1), isFalse); // London
    expect(RadarService.isInConus(64.8, -147.7), isFalse); // Fairbanks, AK
  });
}
