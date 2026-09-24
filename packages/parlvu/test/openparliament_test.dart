import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/src/openparliament.dart';
import 'package:parlvu/src/models.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('parses first speech and next page', () {
    final page = parseSpeechPage(fixture('op_speeches_ethi49_p1.json'));
    expect(page.nextUrl, isNotNull);
    expect(page.speeches.first.bucketTime, DateTime.utc(2026, 7, 7, 15));
    expect(page.speeches.first.speaker, startsWith('The Chair'));
    expect(
      page.speeches.first.textEn,
      startsWith('I call this meeting to order. There is a point of order.'),
    );
  });

  test(
    'parses both pages',
    () => expect(
      parseSpeechPage(fixture('op_speeches_ethi49_p1.json')).speeches.length +
          parseSpeechPage(fixture('op_speeches_ethi49_p2.json'))
              .speeches
              .length,
      108,
    ),
  );

  test('decodes speech HTML text', () {
    final page = parseSpeechPage(
      jsonEncode({
        'objects': [
          {
            'time': '2026-07-07 11:00:00',
            'attribution': {'en': 'A'},
            'content': {
              'en': '<p>Fish &amp; chips&#39; &lt;b&gt;</p><p>next</p>',
            },
            'url': '/x/',
          },
        ],
      }),
    );
    expect(page.speeches.single.textEn, "Fish & chips' <b> next");
  });

  test('parses ETHI 49 paragraph languages and paired text', () {
    final speeches = parseSpeechPage(fixture('op_speeches_ethi49_p1.json'))
        .speeches;
    // URLs identify the source_id 13595381 and 13595409 fixture records.
    final lapointe = speeches.singleWhere(
      (s) => s.url.endsWith('/linda-lapointe-3/'),
    );
    final chair = speeches.singleWhere((s) => s.url.endsWith('/the-chair-23/'));
    expect(lapointe.paragraphs, hasLength(2));
    expect(
      lapointe.paragraphs.map((p) => p.language),
      everyElement(AudioLanguage.french),
    );
    expect(
      lapointe.paragraphs.first.textFr,
      startsWith("Monsieur le président, j'invoque le Règlement."),
    );
    expect(chair.paragraphs, hasLength(3));
    expect(chair.paragraphs.map((p) => p.language), [
      AudioLanguage.french,
      AudioLanguage.english,
      AudioLanguage.english,
    ]);
    expect(chair.paragraphs.first.textEn, 'Thank you, Mr. Hardy.');
  });

  test('counts ETHI 49 paragraph languages across both pages', () {
    final paragraphs = [
      ...parseSpeechPage(fixture('op_speeches_ethi49_p1.json')).speeches,
      ...parseSpeechPage(fixture('op_speeches_ethi49_p2.json')).speeches,
    ].expand((s) => s.paragraphs);
    expect(
      paragraphs.where((p) => p.language == AudioLanguage.english).length,
      251,
    );
    expect(
      paragraphs.where((p) => p.language == AudioLanguage.french).length,
      126,
    );
  });

  test('rejects malformed and incomplete speech pages', () {
    expect(
      () => parseSpeechPage('<html>'),
      throwsA(isA<ParlVuFormatException>()),
    );
    expect(
      () => parseSpeechPage('{"objects":[{}]}'),
      throwsA(isA<ParlVuFormatException>()),
    );
  });

  test('house debate request has required query and user agent', () async {
    late http.Request request;
    final client = OpenParliamentClient(
      httpClient: MockClient((r) async {
        request = r;
        return http.Response(
          '{"objects": [], "pagination": {"next_url": null}}',
          200,
        );
      }),
    );
    expect(await client.houseDebate(DateTime.utc(2026, 9, 22)), isEmpty);
    expect(request.url.path, '/speeches/');
    expect(request.url.queryParameters, {
      'document': '/debates/2026/9/22/',
      'format': 'json',
      'limit': '100',
    });
    expect(
      request.headers['user-agent'],
      'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
    );
  });

  test('loads and caches committee meeting speeches', () async {
    var committeeGets = 0;
    final mock = MockClient((r) async {
      final p = r.url.path;
      if (p == '/committees/meetings/') {
        return http.Response(
          fixture('op_meetings_20260707.json'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (p == '/committees/ethics/') {
        committeeGets++;
        return http.Response(
          fixture('op_committee_ethics.json'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (r.url.queryParameters['offset'] == '100') {
        return http.Response(
          fixture('op_speeches_ethi49_p2.json'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (p == '/speeches/') {
        return http.Response(
          fixture('op_speeches_ethi49_p1.json'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final client = OpenParliamentClient(httpClient: mock);
    expect(
      (await client.committeeMeeting(
        acronym: 'ETHI',
        ottawaDate: DateTime.utc(2026, 7, 7),
        number: 49,
      )).length,
      108,
    );
    expect(
      (await client.committeeMeeting(
        acronym: 'ETHI',
        ottawaDate: DateTime.utc(2026, 7, 7),
        number: 49,
      )).length,
      108,
    );
    expect(committeeGets, 1);
  });

  test('returns no meeting for another committee', () async {
    final client = OpenParliamentClient(
      httpClient: MockClient(
        (r) async => http.Response(
          r.url.path == '/committees/meetings/'
              ? fixture('op_meetings_20260707.json')
              : fixture('op_committee_ethics.json'),
          200,
        ),
      ),
    );
    expect(
      await client.committeeMeeting(
        acronym: 'FEWO',
        ottawaDate: DateTime.utc(2026, 7, 7),
        number: 49,
      ),
      isEmpty,
    );
  });

  test('reports HTTP errors', () async {
    final client = OpenParliamentClient(
      httpClient: MockClient((_) async => http.Response('', 503)),
    );
    expect(
      () => client.committeeMeeting(
        acronym: 'ETHI',
        ottawaDate: DateTime.utc(2026, 7, 7),
        number: 49,
      ),
      throwsA(
        isA<OpenParliamentHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });
}
