import 'dart:async';

import 'package:partake/platform/live_captions.dart';

class FakeLiveCaptions implements LiveCaptionFeed, FollowsCaptionStream {
  final _controller = StreamController<String?>.broadcast();
  final followed = <Uri?>[];

  @override
  void follow(Uri? url) => followed.add(url);

  @override
  Stream<String?> get text => _controller.stream;

  void emit(String? value) => _controller.add(value);

  @override
  void dispose() => _controller.close();
}
