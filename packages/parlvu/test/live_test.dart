import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

void main() {
  test('lists recent events and fetches a recent recording', () async {
    final client = ParlVuClient();
    try {
      final now = parliamentDate(DateTime.now());
      final events = await client.eventsBetween(
        now.subtract(const Duration(days: 6)),
        now,
      );
      expect(events, isNotEmpty);
      final ended =
          events.where((event) => event.status == EventStatus.ended).toList()
            ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      expect(ended, isNotEmpty);
      final detail = await client.eventDetail(ended.first.id);
      expect(detail.streams, isNotEmpty);
    } finally {
      client.close();
    }
  }, tags: ['live']);
}
