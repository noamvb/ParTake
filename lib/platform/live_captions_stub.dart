import 'live_captions.dart';

LiveCaptionFeed createLiveCaptionFeed() => _StubLiveCaptionFeed();

class _StubLiveCaptionFeed implements LiveCaptionFeed {
  @override
  Stream<String?> get text => const Stream<String?>.empty();

  @override
  void dispose() {}
}
