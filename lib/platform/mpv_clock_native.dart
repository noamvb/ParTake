import 'package:media_kit/media_kit.dart';

Future<double?> readMpvClock(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) return null;
  final values = await Future.wait([
    native.getProperty('time-pos'),
    native.getProperty('demuxer-start-time'),
  ]);
  final position = double.tryParse(values[0]);
  final start = double.tryParse(values[1]);
  return position == null || start == null ? null : position + start;
}
