import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

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
    await player.open(Media(url.toString()), play: true);
    if (start != null && start > Duration.zero) {
      await player.stream.duration.firstWhere((d) => d > Duration.zero);
      await player.seek(start);
    }
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
  Stream<String> get errorStream => player.stream.error;
  @override
  Future<void> dispose() => player.dispose();
}
