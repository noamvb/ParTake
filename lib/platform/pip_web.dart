import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pip.dart';

PipControl createPipControl() => _WebPipControl();

class _WebPipControl implements PipControl {
  final StreamController<bool> _states = StreamController<bool>.broadcast();
  web.HTMLVideoElement? _video;
  Timer? _bindingTimer;

  @override
  bool get available => web.document.pictureInPictureEnabled;

  @override
  Stream<bool> get active {
    _bindVideo();
    _bindingTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _bindVideo();
    });
    return _states.stream;
  }

  void _bindVideo() {
    if (_video != null) return;
    final video = web.document.querySelector('video') as web.HTMLVideoElement?;
    if (video == null) return;
    _video = video;
    _bindingTimer?.cancel();
    _states.add(web.document.pictureInPictureElement == video);
    video.addEventListener(
      'enterpictureinpicture',
      ((web.Event _) => _states.add(true)).toJS,
    );
    video.addEventListener(
      'leavepictureinpicture',
      ((web.Event _) => _states.add(false)).toJS,
    );
  }

  @override
  Future<void> enter() async {
    _bindVideo();
    final video = _video;
    if (video != null) await video.requestPictureInPicture().toDart;
  }

  @override
  Future<void> setAutoEnter(bool on) async {}
}
