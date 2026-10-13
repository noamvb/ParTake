import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../alerts/quiet_hours.dart';
import 'watch_client.dart';

@immutable
class WatchAlertVideo {
  const WatchAlertVideo({
    required this.event,
    required this.offsetS,
    required this.live,
  });
  final String event;
  final double? offsetS;
  final bool live;

  factory WatchAlertVideo.fromJson(Map<String, dynamic> json) =>
      WatchAlertVideo(
        event: json['event'] as String,
        offsetS: (json['offset_s'] as num?)?.toDouble(),
        live: json['live'] as bool,
      );
}

@immutable
class WatchAlert {
  const WatchAlert({
    required this.id,
    required this.at,
    required this.kind,
    required this.follow,
    required this.title,
    required this.body,
    required this.video,
    required this.division,
  });
  final String id;
  final DateTime at;
  final String kind;
  final String follow;
  final String title;
  final String body;
  final WatchAlertVideo? video;
  final Map<String, dynamic>? division;

  factory WatchAlert.fromJson(Map<String, dynamic> json) => WatchAlert(
    id: json['id'] as String,
    at: DateTime.parse(json['at'] as String).toUtc(),
    kind: json['kind'] as String,
    follow: json['follow'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    video: json['video'] == null
        ? null
        : WatchAlertVideo.fromJson(json['video'] as Map<String, dynamic>),
    division: json['division'] as Map<String, dynamic>?,
  );
}

/// The Deck on Tailscale; the background isolate cannot see the app's
/// WatchFollows, so it falls back to the same default the app uses.
const deckDefaultAddress = 'http://100.98.120.41:8797';

const _staleAfter = Duration(minutes: 30);
const _shownKeep = 200;

/// Fetches Deck alerts newer than `watch.alertsSince` and shows each fresh,
/// unseen one. The first run only records the clock, so a fresh install never
/// replays history. Returns the number of alerts shown.
Future<int> syncDeckAlerts({
  required SharedPreferences prefs,
  required WatchClient Function(Uri address) clientFor,
  required Future<void> Function(WatchAlert alert, NotificationDetails details)
  show,
  required DateTime Function() now,
}) async {
  final address = prefs.getString('watch.address') ?? deckDefaultAddress;
  final uri = Uri.tryParse(address);
  if (address.isEmpty || uri == null || !uri.hasAuthority) return 0;
  final clock = now().toUtc();
  final since = DateTime.tryParse(prefs.getString('watch.alertsSince') ?? '');
  if (since == null) {
    await prefs.setString('watch.alertsSince', isoUtcSeconds(clock));
    return 0;
  }
  final client = clientFor(uri);
  final List<WatchAlert> alerts;
  try {
    alerts = await client.alerts(since: since);
  } finally {
    client.close();
  }
  alerts.sort((a, b) => a.at.compareTo(b.at));
  final shown = (prefs.getStringList('watch.alertsShown') ?? <String>[])
      .toList();
  final current = now();
  var count = 0;
  for (final alert in alerts) {
    if (shown.contains(alert.id)) continue;
    if (clock.difference(alert.at) > _staleAfter) continue;
    await show(alert, notificationDetails(current.toLocal()));
    count++;
    shown.add(alert.id);
    await prefs.setStringList(
      'watch.alertsShown',
      shown
          .skip(shown.length > _shownKeep ? shown.length - _shownKeep : 0)
          .toList(),
    );
  }
  if (alerts.isNotEmpty) {
    final newest = alerts.last.at;
    if (newest.isAfter(since)) {
      await prefs.setString('watch.alertsSince', isoUtcSeconds(newest));
    }
  }
  return count;
}
