import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/alerts/alert_logic.dart';

void main() {
  final now = DateTime.utc(2026, 9, 23, 18);
  ListingEvent event(
    int id,
    String title,
    EventStatus status,
    DateTime start,
  ) => ListingEvent(
    id: id,
    foreignKey: null,
    title: title,
    description: '',
    location: '',
    scheduledStart: start,
    scheduledEnd: null,
    actualStart: null,
    actualEnd: null,
    status: status,
    statusCode: status.code ?? 0,
    statusText: status.name,
  );

  test('planAlarms includes followed future event only', () {
    final fewo = event(
      1,
      'FEWO Meeting No. 47',
      EventStatus.notStarted,
      now.add(const Duration(hours: 2)),
    );
    final ethi = event(
      2,
      'ETHI Meeting No. 49',
      EventStatus.notStarted,
      now.add(const Duration(hours: 2)),
    );
    expect(planAlarms([fewo, ethi], {'FEWO'}, now), [
      AlarmPlan(eventId: 1, title: fewo.title, at: fewo.scheduledStart),
    ]);
  });

  test('planAlarms skips unsuitable statuses, past, and outside horizon', () {
    final start = now.add(const Duration(hours: 1));
    final events = [
      event(1, 'FEWO live', EventStatus.live, start),
      event(2, 'FEWO ended', EventStatus.ended, start),
      event(3, 'FEWO cancelled', EventStatus.cancelled, start),
      event(
        4,
        'FEWO past',
        EventStatus.notStarted,
        now.subtract(const Duration(minutes: 1)),
      ),
      event(
        5,
        'FEWO far',
        EventStatus.notStarted,
        now.add(const Duration(hours: 37)),
      ),
      event(
        6,
        'FEWO soon',
        EventStatus.notStarted,
        now.add(const Duration(hours: 35)),
      ),
    ];
    expect(planAlarms(events, {'FEWO'}, now).map((p) => p.eventId), [6]);
  });

  test('planAlarms maps chamber and Question Period to HOC', () {
    final sitting = event(
      1,
      'HoC Sitting No. 1',
      EventStatus.notStarted,
      now.add(const Duration(hours: 1)),
    );
    final qp = event(
      2,
      'Question Period for HoC Sitting No. 1',
      EventStatus.notStarted,
      now.add(const Duration(hours: 1)),
    );
    expect(planAlarms([sitting, qp], {'HOC'}, now).map((p) => p.title), [
      sitting.title,
      qp.title,
    ]);
  });

  test('liveToNotify selects followed live and paused not notified', () {
    final live = event(1, 'FEWO live', EventStatus.live, now);
    final paused = event(2, 'ETHI paused', EventStatus.paused, now);
    final ended = event(3, 'FEWO ended', EventStatus.ended, now);
    final other = event(4, 'HESA live', EventStatus.live, now);
    expect(
      liveToNotify(
        [live, paused, ended, other],
        {'FEWO', 'ETHI'},
        {},
      ).map((e) => e.id),
      [1, 2],
    );
    expect(
      liveToNotify([live, paused], {'FEWO', 'ETHI'}, {1}).map((e) => e.id),
      [2],
    );
  });

  test('decideCheck live notifies carrying row', () {
    final row = event(1, 'FEWO live', EventStatus.live, now);
    final outcome = decideCheck(
      row: row,
      scheduledStart: now,
      now: now,
      alreadyNotified: false,
    );
    expect(outcome, isA<NotifyLive>());
    expect((outcome as NotifyLive).event, same(row));
  });

  test('decideCheck retries two minutes after still-not-started', () {
    final start = now.subtract(const Duration(minutes: 10));
    final outcome = decideCheck(
      row: event(1, 'FEWO', EventStatus.notStarted, start),
      scheduledStart: start,
      now: now,
      alreadyNotified: false,
    );
    expect((outcome as CheckAgain).at, now.add(const Duration(minutes: 2)));
  });

  test('decideCheck gives up at 60 minutes but retries at 59', () {
    final start = now.subtract(const Duration(minutes: 60));
    expect(
      decideCheck(
        row: event(1, 'FEWO', EventStatus.notStarted, start),
        scheduledStart: start,
        now: now,
        alreadyNotified: false,
      ),
      isA<StopChecking>(),
    );
    expect(
      decideCheck(
        row: event(
          1,
          'FEWO',
          EventStatus.notStarted,
          start.add(const Duration(minutes: 1)),
        ),
        scheduledStart: start.add(const Duration(minutes: 1)),
        now: now,
        alreadyNotified: false,
      ),
      isA<CheckAgain>(),
    );
  });

  test('decideCheck stops for cancelled, in camera, and ended', () {
    for (final status in [
      EventStatus.cancelled,
      EventStatus.inCamera,
      EventStatus.ended,
    ]) {
      expect(
        decideCheck(
          row: event(1, 'FEWO', status, now),
          scheduledStart: now,
          now: now,
          alreadyNotified: false,
        ),
        isA<StopChecking>(),
      );
    }
  });

  test('decideCheck stops for vanished or already notified event', () {
    expect(
      decideCheck(
        row: null,
        scheduledStart: now,
        now: now,
        alreadyNotified: false,
      ),
      isA<StopChecking>(),
    );
    expect(
      decideCheck(
        row: event(1, 'FEWO', EventStatus.live, now),
        scheduledStart: now,
        now: now,
        alreadyNotified: true,
      ),
      isA<StopChecking>(),
    );
  });

  test('AlarmPlan equality compares all fields', () {
    final a = AlarmPlan(eventId: 1, title: 'FEWO', at: now);
    final b = AlarmPlan(eventId: 1, title: 'FEWO', at: now);
    final c = AlarmPlan(
      eventId: 1,
      title: 'FEWO',
      at: now.add(const Duration(minutes: 1)),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
