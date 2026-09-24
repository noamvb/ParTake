import 'package:media_kit/media_kit.dart';

import 'mpv_clock_stub.dart'
    if (dart.library.io) 'mpv_clock_native.dart'
    as platform;

/// The stream's raw PTS clock in seconds (mpv `time-pos` +
/// `demuxer-start-time`), or null where mpv is not the engine (the web).
Future<double?> readMpvClock(Player player) => platform.readMpvClock(player);
