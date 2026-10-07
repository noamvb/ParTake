import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

String _feed(String title, String paragraph) =>
    '<rss><channel><item><title>$title</title>'
    '<link>https://www.pm.gc.ca/itinerary</link>'
    '<description>$paragraph</description></item></channel></rss>';

void main() {
  final fixture = File('test/fixtures/pm_news_20261007.xml').readAsStringSync();

  test('fixture Wednesday attendance and feed count', () {
    final entries = parsePmQuestionPeriods(fixture);
    expect(entries, hasLength(2));
    expect(entries.first.day, DateTime.utc(2026, 10, 7));
    expect(entries.first.startsAt, DateTime.utc(2026, 10, 7, 18, 15));
    expect(entries.first.timeLabel, '2:15 p.m.');
    expect(
      entries.first.link,
      Uri.parse(
        'https://www.pm.gc.ca/en/news/media-advisories/2026/10/06/wednesday-october-7-2026',
      ),
    );
  });

  test('fixture Monday attendance follows Wednesday', () {
    final qp = parsePmQuestionPeriods(fixture)[1];
    expect(qp.day, DateTime.utc(2026, 10, 5));
    expect(qp.startsAt, DateTime.utc(2026, 10, 5, 18, 15));
  });

  test('Friday attendance without time uses Standing Orders', () {
    final qp = parsePmQuestionPeriods(
      _feed(
        'Friday, October 9, 2026',
        '&lt;p&gt;The Prime Minister will attend Question Period.&lt;/p&gt;',
      ),
    ).single;
    expect(qp.startsAt, DateTime.utc(2026, 10, 9, 15, 15));
    expect(qp.timeLabel, '11:15 a.m.');
  });

  test('non-date title mentioning Question Period is ignored', () {
    expect(
      parsePmQuestionPeriods(
        _feed(
          'Statement by Prime Minister Carney',
          '&lt;p&gt;The Prime Minister will attend Question Period.&lt;/p&gt;',
        ),
      ),
      isEmpty,
    );
  });

  test('winter attendance uses EST and normalises nbsp', () {
    final qp = parsePmQuestionPeriods(
      _feed(
        'Tuesday, December 8, 2026',
        '&lt;p&gt;&lt;strong&gt;2:15&amp;nbsp;p.m. &lt;/strong&gt;'
            'The Prime Minister will attend Question Period.&lt;/p&gt;',
      ),
    ).single;
    expect(qp.startsAt, DateTime.utc(2026, 12, 8, 19, 15));
    expect(qp.timeLabel, '2:15 p.m.');
  });

  test('client reads default feed with OpenParliament user agent', () async {
    final client = PmItineraryClient(
      httpClient: MockClient((request) async {
        expect(request.url, PmItineraryClient.defaultFeed);
        expect(
          request.headers['User-Agent'],
          'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
        );
        return http.Response.bytes(
          utf8.encode(fixture),
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    expect(await client.questionPeriods(), hasLength(2));
    client.close();
  });

  test('client throws on HTTP 503', () async {
    final client = PmItineraryClient(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(fixture),
          503,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      client.questionPeriods(),
      throwsA(isA<ParlVuFormatException>()),
    );
    client.close();
  });
}
