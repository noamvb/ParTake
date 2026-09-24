import 'dart:async';

import 'package:partake/platform/live_captions.dart';

class FakeLiveCaptions implements LiveCaptionFeed {
  final _controller = StreamController<String?>.broadcast();

  @override
  Stream<String?> get text => _controller.stream;

  void emit(String? value) => _controller.add(value);

  @override
  void dispose() => _controller.close();
}
