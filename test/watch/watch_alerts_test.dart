import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:partake/watch/watch_alerts.dart';
import 'package:partake/watch/watch_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_watch_server.dart';

/// One alert object as `GET /api/alerts` sends it (api.md "## Alerts").
Map<String, dynamic> alertJson(String id, DateTime at) => {
  'id': id,
  'at': isoUtcSeconds(at),
  'kind': 'mp_speaking',
  'follow': 'f_mno234',
  'title': 'Title $id',
  'body': 'Body $id',
  'video': null,
  'division': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const address = 'http://deck.test:8797';

  test('6 WatchAlert.fromJson reads every field of the api.md object', () {
    final alert = WatchAlert.fromJson(
      jsonDecode(
        '{"id": "a_33c1", "at": "2026-10-19T15:02:40Z", "kind": "bill_vote", '
        '"follow": "f_bill_c37", "title": "Vote called on Bill C-37", '
        '"body": "Third reading. Members are being called in.", '
        '"video": {"event": "45901", "offset_s": 4410.0, "live": true}, '
        '"division": null}',
      ) as Map<String, dynamic>,
    );
    expect(alert.id, 'a_33c1');
    expect(alert.at, DateTime.utc(2026, 10, 19, 15, 2, 40));
    expect(alert.at.isUtc, isTrue);
    expect(alert.kind, 'bill_vote');
    expect(alert.follow, 'f_bill_c37');
    expect(alert.title, 'Vote called on Bill C-37');
    expect(alert.body, 'Third reading. Members are being called in.');
    expect(alert.video!.event, '45901');
    expect(alert.video!.offsetS, 4410.0);
    expect(alert.video!.live, isTrue);
    expect(alert.division, isNull);
  });

  test('7 alerts(since:) GETs /watch/api/alerts with since in UTC', () async {
    final server = FakeWatchServer();
    server.alertsAnswer = (_) async => http.Response(
      jsonEncode([alertJson('a_1', DateTime.utc(2026, 10, 19, 15, 2, 40))]),
      200,
    );
    final client = server.client(Uri.parse(address), 't0k');
    final alerts = await client.alerts(since: DateTime.utc(2026, 10, 19, 15));
    expect(server.alertsRequests, hasLength(1));
    final url = server.alertsRequests.single;
    expect(url.path, '/watch/api/alerts');
    expect(url.queryParameters, {'since': '2026-10-19T15:00:00Z'});
    // On the wire the colons are percent-encoded; they decode to the above.
    expect(url.query, 'since=2026-10-19T15%3A00%3A00Z');
    expect(alerts.single.id, 'a_1');
  });

  test('8 first run records the clock and shows nothing', () async {
    final now = DateTime.utc(2026, 10, 19, 15, 10);
    SharedPreferences.setMockInitialValues({'watch.address': address});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeWatchServer();
    server.alertsAnswer = (_) async => http.Response(
      jsonEncode([
        alertJson('a_old', now.subtract(const Duration(minutes: 1))),
      ]),
      200,
    );
    final shown = <WatchAlert>[];
    final count = await syncDeckAlerts(
      prefs: prefs,
      clientFor: (uri) => server.client(uri, ''),
      show: (alert, details) async => shown.add(alert),
      now: () => now,
    );
    expect(count, 0);
    expect(shown, isEmpty);
    expect(server.alertsRequests, isEmpty);
    expect(prefs.getString('watch.alertsSince'), '2026-10-19T15:10:00Z');
  });

  test(
    '9 fresh alerts show oldest first, once, and advance the clock',
    () async {
      final now = DateTime.utc(2026, 10, 19, 15, 10);
      final first = DateTime.utc(2026, 10, 19, 15, 2, 40);
      final second = DateTime.utc(2026, 10, 19, 15, 5);
      SharedPreferences.setMockInitialValues({
        'watch.address': address,
        'watch.alertsSince': '2026-10-19T15:00:00Z',
      });
      final prefs = await SharedPreferences.getInstance();
      final server = FakeWatchServer();
      // Newest first on the wire: the sync must still show oldest first.
      server.alertsAnswer = (_) async => http.Response(
        jsonEncode([alertJson('a_2', second), alertJson('a_1', first)]),
        200,
      );
      final shown = <String>[];
      Future<int> run() => syncDeckAlerts(
        prefs: prefs,
        clientFor: (uri) => server.client(uri, ''),
        show: (alert, details) async => shown.add(alert.id),
        now: () => now,
      );
      expect(await run(), 2);
      expect(shown, ['a_1', 'a_2']);
      expect(prefs.getString('watch.alertsSince'), '2026-10-19T15:05:00Z');
      expect(await run(), 0);
      expect(shown, ['a_1', 'a_2']);
      expect(server.alertsRequests, hasLength(2));
    },
  );

  test(
    '10 at night the details are silent and stale alerts are dropped',
    () async {
      final now = DateTime(2026, 10, 19, 23, 30);
      final fresh = now.toUtc().subtract(const Duration(minutes: 2));
      final stale = now.toUtc().subtract(const Duration(minutes: 31));
      SharedPreferences.setMockInitialValues({
        'watch.address': address,
        'watch.alertsSince': isoUtcSeconds(
          now.toUtc().subtract(const Duration(hours: 1)),
        ),
      });
      final prefs = await SharedPreferences.getInstance();
      final server = FakeWatchServer();
      server.alertsAnswer = (_) async => http.Response(
        jsonEncode([alertJson('a_stale', stale), alertJson('a_fresh', fresh)]),
        200,
      );
      final shown = <(WatchAlert, NotificationDetails)>[];
      final count = await syncDeckAlerts(
        prefs: prefs,
        clientFor: (uri) => server.client(uri, ''),
        show: (alert, details) async => shown.add((alert, details)),
        now: () => now,
      );
      expect(count, 1);
      expect(shown.map((s) => s.$1.id), ['a_fresh']);
      expect(shown.single.$2.android!.channelId, 'partake_quiet');
    },
  );
}
