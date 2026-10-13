import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Every notification the app posts goes through [notificationDetails], so
/// nothing makes a sound or vibrates between 22:00 and 08:00.
const loudChannel = AndroidNotificationChannel(
  'partake_live',
  'Live proceedings',
  description: 'Alerts when followed proceedings go live.',
  importance: Importance.high,
);

const quietChannel = AndroidNotificationChannel(
  'partake_quiet',
  'Night (silent)',
  description:
      'Alerts that arrive between 22:00 and 08:00, shown without sound.',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

/// True between 22:00 and 08:00 on the device clock; [local] is wall time.
bool isQuietTime(DateTime local) {
  final minutes = local.hour * 60 + local.minute;
  return minutes >= 22 * 60 || minutes < 8 * 60;
}

/// Quiet when the server says so (`quiet: "1"` in a push) or the clock does.
bool quietFor(DateTime local, {bool serverQuiet = false}) =>
    serverQuiet || isQuietTime(local);

NotificationDetails notificationDetails(
  DateTime local, {
  bool serverQuiet = false,
}) {
  if (quietFor(local, serverQuiet: serverQuiet)) {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'partake_quiet',
        'Night (silent)',
        channelDescription:
            'Alerts that arrive between 22:00 and 08:00, shown without sound.',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        silent: true,
        icon: '@drawable/ic_stat_partake',
      ),
    );
  }
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      'partake_live',
      'Live proceedings',
      channelDescription: 'Alerts when followed proceedings go live.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_partake',
    ),
  );
}
