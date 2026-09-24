import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../platform/video_ready.dart';

abstract class MediaEngine {
  Future<void> open(Uri url, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Duration get position;
  Duration get duration;
  bool get playing;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;
  Future<void> dispose();
}

class MediaKitEngine implements MediaEngine {
  MediaKitEngine() : player = Player();

  final Player player;
  static const _headers = {
    'User-Agent': 'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
  };

  @override
  Future<void> open(Uri url, {Duration? start}) async {
    if (!kIsWeb) {
      await player.open(
        Media(url.toString(), httpHeaders: _headers, start: start),
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
  Duration get duration => player.state.duration;
  @override
  bool get playing => player.state.playing;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
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
  Future<void> dispose() => player.dispose();
}
