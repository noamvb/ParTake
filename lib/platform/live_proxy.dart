import 'live_proxy_stub.dart'
    if (dart.library.io) 'live_proxy_io.dart'
    as platform;

/// Serves a live HLS stream to mpv as a growing EVENT playlist (see
/// LivePlaylist) from a loopback HTTP server.
abstract class LiveProxy {
  /// Local URL for mpv, or null when [url] is not a live stream.
  Future<Uri?> start(Uri url);

  /// Live edge of the proxied playlist, from its first segment.
  Duration get edge;

  /// Wall clock at position zero of the proxied playlist, if known.
  DateTime? get windowStart;
  Stream<Duration> get edgeStream;
  Future<void> close();
}

/// Null where mpv is not the engine (the web: hls.js keeps the window).
LiveProxy? createLiveProxy(Map<String, String> headers) =>
    platform.createLiveProxy(headers);
