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
  PmQuestionPeriod qp(
    DateTime day,
    DateTime start, [
    String label = '2:15 p.m.',
  ]) => PmQuestionPeriod(
    day: day,
    startsAt: start,
    timeLabel: label,
    link: Uri.parse('https://www.pm.gc.ca/itinerary'),
  );

  test('PM alert ids are stable and distinct', () {
    expect(pmHeadsUpId(DateTime.utc(2026, 10, 7)), 1900522014);
    expect(pmLiveId(DateTime.utc(2026, 10, 7)), 1900522015);
  });

  test('PM heads ups filter past distant and notified attendances', () {
    final clock = DateTime.utc(2026, 10, 6, 22, 15);
    final upcoming = qp(
      DateTime.utc(2026, 10, 8),
      clock.add(const Duration(hours: 20)),
    );
    expect(
      pmHeadsUps(
        [
          upcoming,
          qp(DateTime.utc(2026, 10, 6), clock),
          qp(DateTime.utc(2026, 10, 9), clock.add(const Duration(hours: 40))),
          qp(DateTime.utc(2026, 10, 7), clock.add(const Duration(hours: 20))),
        ],
        clock,
        {'2026-10-07'},
      ),
      [upcoming],
    );
  });

  test('PM heads up body uses Ottawa today and tomorrow', () {
    final attendance = qp(
      DateTime.utc(2026, 10, 7),
      DateTime.utc(2026, 10, 7, 18, 15),
    );
    expect(
      pmHeadsUpBody(attendance, DateTime.utc(2026, 10, 6, 21, 30)),
      'Tomorrow at 2:15 p.m.',
    );
    expect(
      pmHeadsUpBody(attendance, DateTime.utc(2026, 10, 7, 13)),
      'Today at 2:15 p.m.',
    );
  });

  test('PM heads up body uses weekday beyond tomorrow', () {
    final attendance = qp(
      DateTime.utc(2026, 10, 9),
      DateTime.utc(2026, 10, 9, 15, 15),
      '11:15 a.m.',
    );
    expect(
      pmHeadsUpBody(attendance, DateTime.utc(2026, 10, 7, 13)),
      'Friday at 11:15 a.m.',
    );
  });

  test('PM check notifies live chamber rather than committee', () {
    final chamber = event(1, 'HoC Sitting No. 1', EventStatus.live, now);
    final outcome = decidePmCheck(
      events: [event(2, 'FEWO', EventStatus.notStarted, now), chamber],
      startsAt: now,
      now: now,
      alreadyNotified: false,
    );
    expect((outcome as NotifyLive).event, same(chamber));
  });

  test('PM check retries when only committee is live', () {
    final clock = now.add(const Duration(minutes: 5));
    final outcome = decidePmCheck(
      events: [event(2, 'FEWO', EventStatus.live, now)],
      startsAt: now,
      now: clock,
      alreadyNotified: false,
    );
    expect((outcome as CheckAgain).at, clock.add(const Duration(minutes: 2)));
  });

  test('PM check stops at thirty minutes or when notified', () {
    final outcome = decidePmCheck(
      events: [],
      startsAt: now,
      now: now.add(const Duration(minutes: 30)),
      alreadyNotified: false,
    );
    expect((outcome as StopChecking).reason, 'gave up after 30 minutes');
    final notified = decidePmCheck(
      events: [event(1, 'HoC Sitting No. 1', EventStatus.live, now)],
      startsAt: now,
      now: now,
      alreadyNotified: true,
    );
    expect((notified as StopChecking).reason, 'already notified');
  });
}
