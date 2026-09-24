import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';

import '../fakes.dart';

ListingEvent _event(String title) => ListingEvent(
  id: 1,
  foreignKey: null,
  title: title,
  description: '',
  location: '',
  scheduledStart: DateTime.utc(2026, 9, 23, 18),
  scheduledEnd: null,
  actualStart: null,
  actualEnd: null,
  status: EventStatus.ended,
  statusCode: -1,
  statusText: 'Adjourned',
);

void main() {
  test('followKeyOf groups chamber sittings and Question Period', () {
    expect(followKeyOf(_event('HoC Sitting No. 142')), 'HOC');
    expect(
      followKeyOf(_event('Question Period for HoC Sitting No. 142')),
      'HOC',
    );
    expect(followKeyOf(_event('FEWO Meeting No. 47')), 'FEWO');
  });

  test('WatchRecord JSON uses the literal stored shape', () {
    final record = WatchRecord.fromJson({
      'eventId': 45750,
      'title': 'FEWO Meeting No. 47',
      'eventDate': '2026-09-23',
      'positionMs': 61000,
      'durationMs': 7757000,
      'updatedAt': '2026-09-23T22:00:00.000Z',
    });
    expect(record.eventDate, DateTime.utc(2026, 9, 23));
    expect(record.position, const Duration(seconds: 61));
    expect(record.toJson(), {
      'eventId': 45750,
      'title': 'FEWO Meeting No. 47',
      'eventDate': '2026-09-23',
      'positionMs': 61000,
      'durationMs': 7757000,
      'updatedAt': '2026-09-23T22:00:00.000Z',
    });
  });

  test('finished at 95% or within the last two minutes', () {
    WatchRecord at(int minutes, int total) => WatchRecord(
      eventId: 1,
      title: 't',
      eventDate: DateTime.utc(2026, 9, 23),
      position: Duration(minutes: minutes),
      duration: Duration(minutes: total),
      updatedAt: DateTime.utc(2026, 9, 23),
    );
    expect(at(50, 100).finished, isFalse);
    expect(at(95, 100).finished, isTrue);
    expect(at(179, 180).finished, isTrue);
  });

  test('FakeLibrary hides finished records from continueWatching', () async {
    final library = FakeLibrary();
    await library.saveProgress(
      WatchRecord(
        eventId: 1,
        title: 'done',
        eventDate: DateTime.utc(2026, 9, 23),
        position: const Duration(minutes: 99),
        duration: const Duration(minutes: 100),
        updatedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    expect(library.record(1), isNotNull);
    expect(library.continueWatching, isEmpty);
  });
}
