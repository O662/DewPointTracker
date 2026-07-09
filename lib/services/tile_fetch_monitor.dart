import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Watches tile HTTP traffic so the UI can show a truthful "map is loading"
/// signal — the indicator reflects real in-flight downloads, not a guess.
///
/// Pass [client] to every tile layer's `NetworkTileProvider(httpClient: …)`.
/// flutter_map never closes externally supplied clients, so one monitor can
/// safely back all layers for the lifetime of the screen.
class TileFetchMonitor {
  TileFetchMonitor() {
    client = _CountingClient(http.Client(), _onDelta);
  }

  late final http.Client client;

  /// True while any tile request is in flight. The trailing edge is held for
  /// a beat so the indicator doesn't flicker between tiles of the same batch.
  final ValueNotifier<bool> busy = ValueNotifier(false);

  int _inFlight = 0;
  Timer? _settle;

  void _onDelta(int delta) {
    _inFlight += delta;
    if (_inFlight > 0) {
      _settle?.cancel();
      _settle = null;
      busy.value = true;
    } else {
      _settle ??= Timer(const Duration(milliseconds: 350), () {
        _settle = null;
        if (_inFlight == 0) busy.value = false;
      });
    }
  }

  void dispose() {
    _settle?.cancel();
    client.close();
    busy.dispose();
  }
}

/// An [http.Client] wrapper that reports +1 when a request starts and −1 once
/// its body finishes downloading (or fails) — each request exactly once.
class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner, this._onDelta);

  final http.Client _inner;
  final void Function(int delta) _onDelta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      _onDelta(-1);
    }

    _onDelta(1);
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (_) {
      finish();
      rethrow;
    }
    // Stay "in flight" until the body is fully read — headers arriving is not
    // the same as the tile being on screen.
    return http.StreamedResponse(
      response.stream.transform(
        StreamTransformer.fromHandlers(
          handleDone: (sink) {
            finish();
            sink.close();
          },
          handleError: (error, stackTrace, sink) {
            finish();
            sink.addError(error, stackTrace);
          },
        ),
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
