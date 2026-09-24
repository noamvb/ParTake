import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../player/player_controller.dart';

class PartakeAudioHandler extends BaseAudioHandler with SeekHandler {
  PartakeAudioHandler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  PlayerController? _controller;
  String _title = '';
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  DateTime? _lastPositionPublish;
  bool? _lastPlaying;
  PlayerPhase? _lastPhase;

  void attach(PlayerController controller, {required String title}) {
    final previous = _controller;
    if (previous != null) detach(previous);
    _controller = controller;
    _title = title;
    controller.addListener(_controllerChanged);
    // PlayerController's engine listener updates its state before this listener
    // observes engine events, including media button changes.
    _playingSubscription = controller.engine.playingStream.listen((_) {
      _publishState();
    });
    _durationSubscription = controller.engine.durationStream.listen((_) {
      _publishMediaItem(title);
      _publishState();
    });
    _publishMediaItem(title);
    _publishState(force: true);
  }

  void detach(PlayerController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_controllerChanged);
    unawaited(_playingSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    _playingSubscription = null;
    _durationSubscription = null;
    _controller = null;
    _lastPlaying = null;
    _lastPhase = null;
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
        updatePosition: Duration.zero,
      ),
    );
  }

  void _controllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    _publishMediaItem(_title);
    _publishState();
  }

  void _publishMediaItem(String title) {
    final controller = _controller;
    if (controller == null) return;
    final event = controller.event;
    mediaItem.add(
      MediaItem(
        id: '${event?.id ?? controller.detail?.id ?? ''}',
        title: event?.title ?? title,
        album: 'ParTake',
        duration: controller.isLive ? null : controller.duration,
      ),
    );
  }

  void _publishState({bool force = false}) {
    final controller = _controller;
    if (controller == null) return;
    final changed =
        controller.playing != _lastPlaying || controller.phase != _lastPhase;
    final position = controller.position;
    final now = _now();
    final positionDue =
        _lastPositionPublish == null ||
        now.difference(_lastPositionPublish!) >= const Duration(seconds: 1);
    if (!force && !changed && !positionDue) return;
    _lastPlaying = controller.playing;
    _lastPhase = controller.phase;
    _lastPositionPublish = now;
    final processingState = switch (controller.phase) {
      PlayerPhase.loading => AudioProcessingState.loading,
      PlayerPhase.ready => AudioProcessingState.ready,
      PlayerPhase.error => AudioProcessingState.error,
    };
    playbackState.add(
      PlaybackState(
        processingState: processingState,
        playing: controller.playing,
        controls: [
          MediaControl.rewind,
          controller.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        updatePosition: position,
      ),
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller != null && !controller.playing) {
      await controller.togglePlay();
    }
  }

  @override
  Future<void> pause() async {
    final controller = _controller;
    if (controller != null && controller.playing) {
      await controller.togglePlay();
    }
  }

  @override
  Future<void> seek(Duration position) async => _controller?.seek(position);

  @override
  Future<void> rewind() async =>
      _controller?.seekRelative(const Duration(seconds: -30));

  @override
  Future<void> fastForward() async =>
      _controller?.seekRelative(const Duration(seconds: 30));

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller != null && controller.playing) {
      await controller.togglePlay();
    }
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: controller?.position ?? Duration.zero,
      ),
    );
  }
}

Future<PartakeAudioHandler?> initBackgroundAudio() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  return AudioService.init(
    builder: PartakeAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.noamvb.partake.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
