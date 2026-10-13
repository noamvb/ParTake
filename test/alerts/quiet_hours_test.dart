import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/alerts/quiet_hours.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 19, hour, minute);

  test('1 quiet window is 22:00 up to 08:00 local', () {
    expect(isQuietTime(at(21, 59)), isFalse);
    expect(isQuietTime(at(22)), isTrue);
    expect(isQuietTime(at(23, 59)), isTrue);
    expect(isQuietTime(at(0)), isTrue);
    expect(isQuietTime(at(7, 59)), isTrue);
    expect(isQuietTime(at(8)), isFalse);
    expect(isQuietTime(at(12)), isFalse);
  });
  test('2 a server quiet flag makes daytime quiet too', () {
    expect(quietFor(at(12), serverQuiet: true), isTrue);
    expect(quietFor(at(12)), isFalse);
  });
  test('3 night details use the silent channel', () {
    final android = notificationDetails(at(23, 30)).android!;
    expect(android.channelId, 'partake_quiet');
    expect(android.playSound, isFalse);
    expect(android.enableVibration, isFalse);
    expect(android.importance, Importance.low);
  });
  test('4 daytime details use the live channel', () {
    final android = notificationDetails(at(12)).android!;
    expect(android.channelId, 'partake_live');
    expect(android.importance, Importance.high);
  });
  test('5 quiet channel is silent and low importance', () {
    expect(quietChannel.id, 'partake_quiet');
    expect(quietChannel.playSound, isFalse);
    expect(quietChannel.enableVibration, isFalse);
    expect(quietChannel.importance, Importance.low);
  });
}
