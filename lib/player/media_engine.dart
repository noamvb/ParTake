import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../platform/live_proxy.dart';
import '../platform/mpv_clock.dart';
import '../platform/video_ready.dart';
import 'player_controller.dart';

abstract class MediaEngine {
  Future<void> open(Uri url, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Duration get position;
  Duration get duration;
  bool get playing;
  Future<double?> mediaClock();

  /// Wall clock at position zero of a live stream played over its whole DVR
  /// window (Android), or null.
  DateTime? get liveWindowStart;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;
  Future<void> dispose();
}

class MediaKitEngine implements MediaEngine {
  MediaKitEngine() : player = Player() {
    _liveProxy?.edgeStream.listen((_) {
      if (_live) _durations.add(duration);
    });
    player.stream.duration.listen((_) => _durations.add(duration));
  }

  final Player player;
  static const _headers = {
    'User-Agent': 'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
  };
  final LiveProxy? _liveProxy = createLiveProxy(_headers);
  final StreamController<Duration> _durations = StreamController.broadcast();
  bool _live = false;

  @override
  Future<void> open(Uri url, {Duration? start}) async {
    if (!kIsWeb) {
      // mpv keeps only ~30-50 s of a plain live playlist; serve it the whole
      // DVR window as a seekable EVENT playlist, read from its first segment
      // (live_start_index=0) so ffmpeg's seek arithmetic starts there too.
      final previousStart = _live ? _liveProxy?.windowStart : null;
      Uri? proxied;
      try {
        proxied = await _liveProxy?.start(url);
      } catch (_) {
        proxied = null;
      }
      _live = proxied != null;
      await setMpvProperty(
        player,
        'demuxer-lavf-o',
        _live ? 'live_start_index=0' : '',
      );
      final edge = _liveProxy?.edge ?? Duration.zero;
      final at = _live
          ? liveStartPosition(
              edge: edge,
              requested: start,
              previousWindowStart: previousStart,
              windowStart: _liveProxy?.windowStart,
            )
          : start;
      await player.open(
        Media((proxied ?? url).toString(), httpHeaders: _headers, start: at),
        play: true,
      );
      return;
    }
    // Browsers forbid setting User-Agent, and media_kit's hls.js path ignores
    // Media.start, so seek once the stream reports a duration.
    // On a reopen media_kit reuses its <video> element but detaches it while
    // loading; the play() it issues then is aborted and the element stays
    // paused (seen 2026-09-24). Seek and play once it is attached and ready.
    final ready = armVideoReady();
    await player.open(Media(url.toString()), play: true);
    await ready();
    if (start != null && start > Duration.zero) {
      if (player.state.duration == Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => Duration.zero,
            );
      }
      await player.seek(start);
    }
    await player.play();
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration =>
      _live ? _liveProxy?.edge ?? Duration.zero : player.state.duration;
  @override
  bool get playing => player.state.playing;
  @override
  Future<double?> mediaClock() => readMpvClock(player);
  @override
  DateTime? get liveWindowStart => _live ? _liveProxy?.windowStart : null;

  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;
  @override
  Stream<String> get errorStream => player.stream.error.where(
    // Reopening a stream on the web replaces the <video> element; the old
    // element's pending play() is aborted. Not a playback failure.
    (e) => !e.contains('play() request was interrupted'),
  );
  @override
  Future<void> dispose() async {
    await _liveProxy?.close();
    await _durations.close();
    await player.dispose();
  }
}

/// Where a live stream opens: [requested] (a position in the previous live
/// stream, when switching language) moved into this stream's timeline, whose
/// window may start at a different wall clock; else short of the live edge.
@visibleForTesting
Duration liveStartPosition({
  required Duration edge,
  Duration? requested,
  DateTime? previousWindowStart,
  DateTime? windowStart,
}) {
  final nearEdge = edge > PlayerController.liveEdgeMargin
      ? edge - PlayerController.liveEdgeMargin
      : Duration.zero;
  if (requested == null) return nearEdge;
  var at = requested;
  if (previousWindowStart != null && windowStart != null) {
    at -= windowStart.difference(previousWindowStart);
  }
  if (at < Duration.zero) return Duration.zero;
  return at > nearEdge ? nearEdge : at;
}
