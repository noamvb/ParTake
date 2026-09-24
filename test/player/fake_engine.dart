import 'dart:async';

import 'package:partake/player/media_engine.dart';

class FakeEngine implements MediaEngine {
  final opened = <({Uri url, Duration? start})>[];
  final seeks = <Duration>[];
  final rates = <double>[];
  var plays = 0;
  var pauses = 0;
  Duration currentPosition = Duration.zero;
  Duration currentDuration = Duration.zero;
  bool isPlaying = true;

  /// Whether [open] starts playback, as media_kit's `play: true` should.
  /// The web player sometimes comes up paused after replacing its element.
  bool playOnOpen = true;
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  void emitPosition(Duration d) {
    currentPosition = d;
    _positions.add(d);
  }

  void emitDuration(Duration d) {
    currentDuration = d;
    _durations.add(d);
  }

  void emitError(String e) => _errors.add(e);
  @override
  Future<void> open(Uri url, {Duration? start}) async {
    opened.add((url: url, start: start));
    if (start != null) currentPosition = start;
    isPlaying = playOnOpen;
  }

  @override
  Future<void> play() async {
    plays++;
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    currentPosition = p;
  }

  @override
  Future<void> setRate(double r) async => rates.add(r);
  @override
  Duration get position => currentPosition;
  @override
  Duration get duration => currentDuration;
  @override
  bool get playing => isPlaying;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<String> get errorStream => _errors.stream;
  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _playing.close();
    await _buffering.close();
    await _errors.close();
  }
}
