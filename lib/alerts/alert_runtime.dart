import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:parlvu/parlvu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'alert_logic.dart';

const _channel = AndroidNotificationChannel(
  'partake_live',
  'Live proceedings',
  description: 'Alerts when followed proceedings go live.',
  importance: Importance.high,
);
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
final StreamController<int> _taps = StreamController<int>.broadcast();

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class AlertRuntime {
  static const syncTaskName = 'partake.sync';
  static const notifiedKey = 'alerts.notified';

  static Future<void> initialize() async {
    if (!_isAndroid) return;
    WidgetsFlutterBinding.ensureInitialized();
    await AndroidAlarmManager.initialize();
    await _initializeNotifications();
    await Workmanager().initialize(alertTaskDispatcher);
    await Workmanager().registerPeriodicTask(
      'partake.periodic-sync',
      syncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> syncNow() async {
    if (!_isAndroid) return;
    await _safe('sync', _syncNow);
  }

  static Future<int?> launchEventId() async {
    if (!_isAndroid) return null;
    try {
      final details = await _notifications.getNotificationAppLaunchDetails();
      return int.tryParse(details?.notificationResponse?.payload ?? '');
    } catch (error) {
      debugPrint('ParTake alerts: launch details failed: $error');
      return null;
    }
  }

  static Stream<int> get tappedEventIds => _taps.stream;
}

@pragma('vm:entry-point')
void alertTaskDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await _safe('periodic callback', () async {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      if (task == AlertRuntime.syncTaskName) await _syncNow();
    });
    return true;
  });
}

@pragma('vm:entry-point')
Future<void> alertAlarmCallback(int id, Map<String, dynamic> params) async {
  await _safe('alarm $id', () async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _checkAlarm(id, params);
  });
}

Future<void> _initializeNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _notifications.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (response) {
      final id = int.tryParse(response.payload ?? '');
      if (id != null) _taps.add(id);
    },
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
}

Future<void> _syncNow() async {
  await _initializeNotifications();
  final now = DateTime.now().toUtc();
  final today = parliamentDate(now);
  final tomorrow = today.add(const Duration(days: 1));
  final client = ParlVuClient();
  try {
    final events = await client.eventsBetween(
      today,
      tomorrow,
      includeUpcoming: true,
    );
    final prefs = await _freshPrefs();
    final follows = (prefs.getStringList('follows') ?? <String>[]).toSet();
    final notified = _readIds(prefs.getStringList(AlertRuntime.notifiedKey));
    for (final event in liveToNotify(events, follows, notified)) {
      await _notify(event);
    }

    final plans = planAlarms(events, follows, now);
    final newIds = plans.map((plan) => plan.eventId).toSet();
    final oldIds = _readIds(prefs.getStringList('alerts.scheduled'));
    for (final id in oldIds.difference(newIds)) {
      await AndroidAlarmManager.cancel(id);
    }
    for (final plan in plans) {
      await AndroidAlarmManager.oneShotAt(
        plan.at,
        plan.eventId,
        alertAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
        params: {
          'eventId': plan.eventId,
          'title': plan.title,
          'scheduledStart': plan.at.toIso8601String(),
        },
      );
    }
    await prefs.setStringList(
      'alerts.scheduled',
      newIds.map((id) => id.toString()).toList(),
    );
  } finally {
    client.close();
  }
}

Future<void> _checkAlarm(int id, Map<String, dynamic> params) async {
  await _initializeNotifications();
  final prefs = await _freshPrefs();
  final notified = _readIds(prefs.getStringList(AlertRuntime.notifiedKey));
  final scheduledValue = params['scheduledStart']?.toString();
  final scheduledStart = DateTime.tryParse(scheduledValue ?? '')?.toUtc();
  if (scheduledStart == null) {
    await _removeScheduled(prefs, id);
    return;
  }
  final now = DateTime.now().toUtc();
  final today = parliamentDate(now);
  final client = ParlVuClient();
  try {
    final events = await client.eventsBetween(
      today,
      today,
      includeUpcoming: true,
    );
    ListingEvent? row;
    for (final event in events) {
      if (event.id == id) {
        row = event;
        break;
      }
    }
    final outcome = decideCheck(
      row: row,
      scheduledStart: scheduledStart,
      now: now,
      alreadyNotified: notified.contains(id),
    );
    if (outcome case NotifyLive(:final event)) {
      await _notify(event);
      await _removeScheduled(prefs, id);
    } else if (outcome case CheckAgain(:final at)) {
      await AndroidAlarmManager.oneShotAt(
        at,
        id,
        alertAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
        params: params,
      );
    } else {
      await _removeScheduled(prefs, id);
    }
  } finally {
    client.close();
  }
}

Future<void> _notify(ListingEvent event) async {
  final prefs = await _freshPrefs();
  final notified = _readIdList(prefs.getStringList(AlertRuntime.notifiedKey));
  if (notified.contains(event.id)) return;
  await _notifications.show(
    id: event.id,
    title: '${event.title} is live',
    body: 'Tap to watch on ParTake.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'partake_live',
        'Live proceedings',
        channelDescription: 'Alerts when followed proceedings go live.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: event.id.toString(),
  );
  notified.add(event.id);
  final trimmed = notified.toList()..sort();
  await prefs.setStringList(
    AlertRuntime.notifiedKey,
    trimmed
        .skip(trimmed.length > 200 ? trimmed.length - 200 : 0)
        .map((id) => id.toString())
        .toList(),
  );
}

Future<void> _removeScheduled(SharedPreferences prefs, int id) async {
  final ids = _readIds(prefs.getStringList('alerts.scheduled'))..remove(id);
  await prefs.setStringList(
    'alerts.scheduled',
    ids.map((value) => '$value').toList(),
  );
}

List<int> _readIdList(List<String>? values) =>
    (values ?? const <String>[]).map(int.tryParse).whereType<int>().toList();

Set<int> _readIds(List<String>? values) => _readIdList(values).toSet();

Future<void> _safe(String label, Future<void> Function() action) async {
  try {
    await action();
  } catch (error, stack) {
    debugPrint('ParTake alerts: $label failed: $error\n$stack');
  }
}

/// SharedPreferences caches per isolate, and android_alarm_manager_plus keeps
/// its background isolate alive between alarms: reload so follows and
/// notified ids written by the app (or another isolate) are seen.
Future<SharedPreferences> _freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}
