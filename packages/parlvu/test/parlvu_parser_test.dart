import 'dart:io';

import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('parses listing events in week order', () {
    final events = parseListing(fixture('listing_20260923.json'));
    expect(events, hasLength(10));
    expect(events.map((e) => e.id), [
      45728,
      45801,
      45806,
      45750,
      45768,
      45773,
      45785,
      45777,
      45787,
      45774,
    ]);
  });
  test('maps chamber listing fields', () {
    final event = parseListing(fixture('listing_20260923.json')).first;
    expect(event.title, 'HoC Sitting No. 142');
    expect(event.foreignKey, '13597182');
    expect(event.scheduledStart, DateTime.utc(2026, 9, 23, 18));
    expect(event.actualStart, DateTime.utc(2026, 9, 23, 18, 1, 29));
    expect(event.scheduledEnd, DateTime.utc(2026, 9, 23, 23));
    expect(event.status, EventStatus.ended);
    expect(event.statusCode, -1);
    expect(event.statusText, 'Adjourned');
    expect(event.isChamber, isTrue);
  });
  test('maps null foreign key and committee listing fields', () {
    final event = parseListing(fixture('listing_20260923.json'))
        .singleWhere((e) => e.id == 45806);
    expect(event.title, 'HESA Meeting No. 35-2');
    expect(event.foreignKey, isNull);
    expect(event.committeeCode, 'HESA');
    expect(event.actualStart, DateTime.utc(2026, 9, 23, 20, 38, 55));
  });
  test('preserves unknown and known status codes', () {
    const json =
        '{"Weeks":[{"ContentEntityDatas":[{"Id":1,"Title":"x","ScheduledStart":"2026-09-23T14:00:00","EntityStatus":999},{"Id":2,"Title":"y","ScheduledStart":"2026-09-23T14:00:00","EntityStatus":1}]}]}';
    final events = parseListing(json);
    expect(events.first.status, EventStatus.unknown);
    expect(events.first.statusCode, 999);
    expect(events.last.status, EventStatus.live);
  });
  test('rejects malformed listing shapes and required fields', () {
    for (final body in [
      '<!DOCTYPE html><html>502 Bad Gateway</html>',
      '[]',
      '{"Weeks":"x"}',
      '{"Weeks":[{"ContentEntityDatas":[{"Title":"x","ScheduledStart":"2026-09-23T14:00:00","EntityStatus":1}]}]}',
    ]) {
      expect(() => parseListing(body), throwsA(isA<ParlVuFormatException>()));
    }
    const missingStart =
        '{"Weeks":[{"ContentEntityDatas":[{"Id":1,"Title":"x","EntityStatus":1}]}]}';
    expect(
      () => parseListing(missingStart),
      throwsA(
        isA<ParlVuFormatException>().having(
          (error) => error.message,
          'message',
          contains('missing ScheduledStart'),
        ),
      ),
    );
  });
  test('parses FEWO streams', () {
    final detail = parseEventPage(
      fixture('event_fewo_13596766.html'),
      id: 45750,
    );
    expect(detail.recordingStart, DateTime.utc(2026, 9, 23, 20, 30, 39));
    expect(detail.streams, hasLength(6));
    expect(detail.streams.map((s) => s.tag), [
      'Floor Video',
      'French Video',
      'English Video',
      'Floor Audio',
      'French Audio',
      'English Audio',
    ]);
    for (final stream in detail.streams) {
      expect(stream.preRoll, const Duration(seconds: 30));
      expect(stream.duration, const Duration(seconds: 7757));
      expect(stream.isLive, isFalse);
    }
    expect(detail.streams.take(3).every((s) => !s.audioOnly), isTrue);
    expect(detail.streams.skip(3).every((s) => s.audioOnly), isTrue);
    expect(detail.streams[2].enableCc, isTrue);
    expect(detail.streams[0].enableCc, isFalse);
    expect(
      detail.streams.first.url.toString(),
      startsWith(
        'https://parlvuvod01.azureedge.net/pvvodhoc-fl/_definst_/mp4:',
      ),
    );
  });
  test('parses FEWO captions and trims text', () {
    final captions = parseEventPage(
      fixture('event_fewo_13596766.html'),
      id: 45750,
    ).captions;
    final en = captions[AudioLanguage.english]!;
    expect(en, hasLength(3481));
    expect(captions[AudioLanguage.french], hasLength(3397));
    expect(en.first.begin, DateTime.utc(2026, 9, 23, 20, 30, 43, 712));
    expect(en.first.end, DateTime.utc(2026, 9, 23, 20, 30, 47, 148));
    expect(en.first.text, '>> Voice of Interpreter: Welcome');
    expect(en.last.text, 'Excellent.');
  });
  test('parses HESA SD streams and captions', () {
    final detail = parseEventPage(
      fixture('event_null_fk_45806.html'),
      id: 45806,
    );
    expect(detail.streams, hasLength(9));
    expect(detail.streams.where((s) => s.isSd), hasLength(3));
    expect(detail.streams.first.duration, const Duration(seconds: 4900));
    expect(detail.captions[AudioLanguage.english], hasLength(34));
    expect(detail.captions[AudioLanguage.french], hasLength(165));
    expect(detail.recordingStart, DateTime.utc(2026, 9, 23, 20, 38, 55));
  });
  test('parses INDU audio only streams without captions', () {
    final detail = parseEventPage(
      fixture('event_indu_audio_13597667.html'),
      id: 45768,
    );
    expect(detail.streams, hasLength(3));
    expect(detail.streams.every((s) => s.audioOnly), isTrue);
    expect(detail.captions, isEmpty);
    expect(detail.streams.first.duration, const Duration(seconds: 6351));
  });
  test('chooses preferred language and quality', () {
    expect(
      parseEventPage(
        fixture('event_fewo_13596766.html'),
        id: 45750,
      ).preferredStream(AudioLanguage.english)!.tag,
      'English Video',
    );
    expect(
      parseEventPage(
        fixture('event_null_fk_45806.html'),
        id: 45806,
      ).preferredStream(AudioLanguage.french)!.tag,
      'French Video',
    );
    expect(
      parseEventPage(
        fixture('event_indu_audio_13597667.html'),
        id: 45768,
      ).preferredStream(AudioLanguage.english)!.tag,
      'English Audio',
    );
  });
  test('names unavailable page data in format errors', () {
    final html = fixture('event_fewo_13596766.html');
    expect(
      () => parseEventPage(
        html.replaceFirst('var availableStreams', 'var somethingElse'),
        id: 1,
      ),
      throwsA(
        isA<ParlVuFormatException>().having(
          (e) => e.message,
          'message',
          contains('availableStreams'),
        ),
      ),
    );
    expect(
      () => parseEventPage(html.replaceFirst('\tccItems:', '\tccGone:'), id: 1),
      throwsA(
        isA<ParlVuFormatException>().having(
          (e) => e.message,
          'message',
          contains('ccItems'),
        ),
      ),
    );
  });
}
