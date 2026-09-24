import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

void main() {
  group('parliamentTime', () {
    test('converts Ottawa summer time to UTC', () {
      expect(
        parliamentTime('2026-09-23T14:01:29.0000000'),
        DateTime.utc(2026, 9, 23, 18, 1, 29),
      );
    });

    test('converts Ottawa winter time to UTC', () {
      expect(
        parliamentTime('2026-01-28 14:00:00'),
        DateTime.utc(2026, 1, 28, 19),
      );
    });

    test('keeps milliseconds', () {
      expect(
        parliamentTime('2026-09-23T16:30:43.712'),
        DateTime.utc(2026, 9, 23, 20, 30, 43, 712),
      );
    });

    test('returns a plain UTC DateTime so toLocal uses the device zone', () {
      final t = parliamentTime('2026-09-23T14:01:29');
      expect(t.runtimeType, DateTime(0).runtimeType);
      expect(t.isUtc, isTrue);
      expect(t.toLocal(), DateTime.utc(2026, 9, 23, 18, 1, 29).toLocal());
    });

    test('rejects other shapes', () {
      expect(() => parliamentTime('23/09/2026'), throwsFormatException);
    });
  });

  test('offsetOf adds PreRoll to time since the recorded start', () {
    final stream = StreamVariant(
      language: AudioLanguage.floor,
      url: Uri.parse('https://example.invalid/playlist.m3u8'),
      tag: 'Floor Video',
      audioOnly: false,
      isLive: false,
      isSd: false,
      preRoll: const Duration(seconds: 30),
      duration: null,
      enableCc: false,
    );
    final event = EventDetail(
      id: 1,
      recordingStart: DateTime.utc(2026, 9, 23, 20, 30, 39),
      streams: [stream],
      captions: const {},
    );
    final caption = DateTime.utc(2026, 9, 23, 20, 30, 43, 712);
    final offset = event.offsetOf(caption, stream);
    expect(offset, const Duration(seconds: 34, milliseconds: 712));
    expect(event.wallClockAt(offset, stream), caption);
  });

  test('committeeCode and number come from the title', () {
    ListingEvent event(String title) => ListingEvent(
      id: 1,
      foreignKey: null,
      title: title,
      description: '',
      location: '',
      scheduledStart: DateTime.utc(2026),
      scheduledEnd: null,
      actualStart: null,
      actualEnd: null,
      status: EventStatus.ended,
      statusCode: -1,
      statusText: 'Adjourned',
    );
    expect(event('HESA Meeting No. 35-2').committeeCode, 'HESA');
    expect(event('HESA Meeting No. 35-2').number, 35);
    expect(event('HoC Sitting No. 142').committeeCode, isNull);
    expect(event('HoC Sitting No. 142').isChamber, isTrue);
    final qp = event('Question Period for HoC Sitting No. 142');
    expect(qp.isChamber, isTrue);
    expect(qp.isQuestionPeriod, isTrue);
    expect(qp.committeeCode, isNull);
    expect(qp.number, 142);
    expect(event('FEWO Meeting No. 47').isQuestionPeriod, isFalse);
  });
}
