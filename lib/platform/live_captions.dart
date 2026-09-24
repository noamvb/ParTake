import 'live_captions_stub.dart'
    if (dart.library.js_interop) 'live_captions_web.dart'
    as platform;

abstract class LiveCaptionFeed {
  /// Current live caption text, or null when no cue is active. Emits on change.
  Stream<String?> get text;
  void dispose();
}

LiveCaptionFeed createLiveCaptionFeed() => platform.createLiveCaptionFeed();
