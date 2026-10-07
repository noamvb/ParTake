import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import '../platform/background_audio.dart';
import '../platform/live_captions.dart';
import '../platform/pip.dart';
import '../ui/open_request.dart';
import 'media_engine.dart';
import 'player_controller.dart';
import 'segment_captions.dart';

typedef PlayerVideoBuilder = Widget Function(MediaEngine engine);

/// The live caption source when none is injected: the web reads the <video>
/// element's caption track; natively ParTake decodes the SD segments itself
/// (media_kit's Android mpv has no CEA-608 decoder).
LiveCaptionFeed defaultLiveCaptionFeed(MediaEngine engine) =>
    kIsWeb ? createLiveCaptionFeed() : SegmentCaptionFeed(engine: engine);

/// Playback outlives its full-screen route while the user browses the app.
class PlayerSession extends ChangeNotifier {
  PlayerSession({
    required this.request,
    required EventSource source,
    required Library library,
    MediaEngine Function()? engineFactory,
    LiveCaptionFeed Function()? liveCaptionsFactory,
    this.videoBuilder,
    this.audioHandler,
    this.pip,
    this.resumeAfterMove = kIsWeb,
  }) {
    engine = engineFactory?.call() ?? MediaKitEngine();
    _liveCaptions =
        liveCaptionsFactory?.call() ?? defaultLiveCaptionFeed(engine);
    controller = PlayerController(
      source: source,
      library: library,
      engine: engine,
      liveCaptions: _liveCaptions,
      audioOnlySwapsStream: !kIsWeb,
    )..addListener(_changed);
    audioHandler?.attach(controller, title: request.title);
    // Android shrinks the activity; browsers pop out only the video element.
    if (pip?.available == true && !kIsWeb) {
      _pipSubscription = pip!.active.listen((active) {
        if (_closed || active == _pipActive) return;
        _pipActive = active;
        notifyListeners();
      });
    }
    _playingSubscription = engine.playingStream.listen((playing) {
      if (!playing && _resumeUntil != null) {
        final resume = DateTime.now().isBefore(_resumeUntil!);
        _resumeUntil = null;
        if (resume && !_closed) unawaited(engine.play());
      }
      _changed();
    });
    _opening = controller.open(request);
  }

  final OpenRequest request;
  final PlayerVideoBuilder? videoBuilder;
  final PartakeAudioHandler? audioHandler;
  final PipControl? pip;

  /// Resume playback that stops right after a minimize or expand. A browser
  /// pauses the <video> element while it moves between the full player and
  /// the mini player, because it is briefly out of the document.
  final bool resumeAfterMove;
  DateTime? _resumeUntil;

  void _guardMove() {
    if (resumeAfterMove && controller.playing) {
      _resumeUntil = DateTime.now().add(const Duration(seconds: 2));
    }
  }

  late final MediaEngine engine;
  late final PlayerController controller;
  late final LiveCaptionFeed _liveCaptions;
  late final Future<void> _opening;
  StreamSubscription<bool>? _pipSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _pipActive = false;
  bool _autoPip = false;
  bool _minimized = false;
  bool _closed = false;
  Future<void>? _closing;

  bool get minimized => _minimized;
  bool get pipActive => _pipActive;
  bool get closed => _closed;

  void minimize() {
    if (_closed || _minimized) return;
    _guardMove();
    _minimized = true;
    notifyListeners();
  }

  void expand() {
    if (_closed || !_minimized) return;
    _guardMove();
    _minimized = false;
    notifyListeners();
  }

  void _changed() {
    if (_closed) return;
    final feed = _liveCaptions;
    if (feed is FollowsCaptionStream) {
      final stream = controller.detail?.streams.where(
        (s) =>
            s.language == controller.language &&
            s.isSd &&
            !s.audioOnly &&
            s.isLive,
      );
      final url =
          controller.isLive &&
              controller.captionsOn &&
              controller.language != AudioLanguage.floor &&
              stream != null &&
              stream.isNotEmpty
          ? stream.first.url
          : null;
      if (url != _followedCaptionUrl) {
        _followedCaptionUrl = url;
        (feed as FollowsCaptionStream).follow(url);
      }
    }
    _syncAutoEnter();
    notifyListeners();
  }

  Uri? _followedCaptionUrl;

  void _syncAutoEnter() {
    final pip = this.pip;
    if (pip?.available != true) return;
    final shouldAutoEnter =
        controller.playing &&
        controller.stream != null &&
        !controller.audioOnly;
    if (_autoPip == shouldAutoEnter) return;
    _autoPip = shouldAutoEnter;
    unawaited(pip!.setAutoEnter(shouldAutoEnter));
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    if (pip?.available == true) unawaited(pip!.setAutoEnter(false));
    audioHandler?.detach(controller);
    controller.removeListener(_changed);
    _liveCaptions.dispose();
    _closing = _finishClose();
    notifyListeners();
    return _closing!;
  }

  Future<void> _finishClose() async {
    await _pipSubscription?.cancel();
    await _playingSubscription?.cancel();
    // An event opened by a notification may still be loading when closed.
    await _opening;
    await controller.close();
  }

  VideoController? _videoController;

  /// The video surface with captions; [compact] sizes captions for the
  /// mini player.
  Widget video({bool compact = false}) {
    Widget child;
    if (videoBuilder != null) {
      child = videoBuilder!(engine);
    } else if (engine is MediaKitEngine) {
      // One VideoController per engine: the screen rebuilds on every
      // position tick, and a new controller per build recreates the texture.
      _videoController ??= VideoController((engine as MediaKitEngine).player);
      child = Video(
        controller: _videoController!,
        controls: AdaptiveVideoControls,
        // media_kit pauses on backgrounding by default, which silences the
        // background audio the media session is keeping alive.
        pauseUponEnteringBackgroundMode: false,
      );
    } else {
      child = const SizedBox.expand();
    }
    // Audio only covers the video surface rather than unmounting it: a
    // browser pauses a <video> element as soon as it leaves the document.
    // The Stack is unconditional so toggling keeps the video's tree slot.
    child = Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (controller.audioOnly)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.headphones, color: Colors.white, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'Audio only - keeps playing in the background',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (controller.captionText != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.all(compact ? 6 : 20),
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
                    : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.black.withValues(alpha: .7),
                child: Text(
                  controller.captionText!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 11 : 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
