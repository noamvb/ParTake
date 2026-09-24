import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/services/parlvu_event_source.dart';

String fixture(String name) =>
    File('packages/parlvu/test/fixtures/$name').readAsStringSync();
final t0 = DateTime.utc(2026, 9, 23, 22);

void main() {
  test(
    'today listing expires after 60 seconds and refresh bypasses cache',
    () async {
      var now = t0, requests = 0;
      final source = ParlVuEventSource(
        parlvu: ParlVuClient(
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('GetUpcomingEvents')) {
              return http.Response('{"ContentEntityDatas":[]}', 200);
            }
            requests++;
            return http.Response(fixture('listing_20260923.json'), 200);
          }),
        ),
        openParliament: OpenParliamentClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        now: () => now,
      );
      final date = DateTime.utc(2026, 9, 23);
      await source.day(date);
      await source.day(date);
      expect(requests, 1);
      now = now.add(const Duration(seconds: 61));
      await source.day(date);
      expect(requests, 2);
      await source.day(date, refresh: true);
      expect(requests, 3);
    },
  );

  test(
    'past listing lives forever and concurrent misses share fetch',
    () async {
      var now = DateTime.utc(2026, 9, 25), requests = 0;
      Completer<http.Response>? pending;
      final source = ParlVuEventSource(
        parlvu: ParlVuClient(
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('GetUpcomingEvents')) {
              return http.Response('{"ContentEntityDatas":[]}', 200);
            }
            requests++;
            if (request.url.queryParameters['fromDate'] == '20260926') {
              return pending!.future;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(fixture('listing_20260923.json'), 200);
          }),
        ),
        openParliament: OpenParliamentClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        now: () => now,
      );
      await source.day(DateTime.utc(2026, 9, 23));
      await source.day(DateTime.utc(2026, 9, 23, 10));
      expect(requests, 1);
      pending = Completer<http.Response>();
      final first = source.day(DateTime.utc(2026, 9, 26));
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(minutes: 11));
      final second = source.day(DateTime.utc(2026, 9, 26));
      await Future<void>.delayed(Duration.zero);
      expect(requests, 2);
      pending.complete(http.Response(fixture('listing_20260923.json'), 200));
      await Future.wait([first, second]);
      expect(requests, 2);
    },
  );

  test('liveNow returns live and paused events in listing order', () async {
    final listing =
        jsonDecode(fixture('listing_20260923.json')) as Map<String, dynamic>;
    final rows = (listing['Weeks'] as List).first['ContentEntityDatas'] as List;
    rows[0]['EntityStatus'] = 1;
    rows[1]['EntityStatus'] = 2;
    final body = jsonEncode(listing);
    final source = ParlVuEventSource(
      parlvu: ParlVuClient(
        httpClient: MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('GetUpcomingEvents')
                ? '{"ContentEntityDatas":[]}'
                : body,
            200,
          ),
        ),
      ),
      openParliament: OpenParliamentClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      now: () => t0,
    );
    final live = await source.liveNow();
    expect(
      live.every(
        (e) => e.status == EventStatus.live || e.status == EventStatus.paused,
      ),
      isTrue,
    );
    expect(live.map((event) => event.id), [45728, 45801]);
  });

  test('liveNow loads live ids from the upcoming endpoint', () async {
    final requests = <String>{};
    final source = ParlVuEventSource(
      parlvu: ParlVuClient(
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response.bytes(
            utf8.encode(
              fixture(
                request.url.path.endsWith('GetUpcomingEvents')
                    ? 'upcoming_20260924.json'
                    : 'listing_20260924.json',
              ),
            ),
            200,
          );
        }),
      ),
      openParliament: OpenParliamentClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      now: () => DateTime.utc(2026, 9, 24, 16),
    );
    final live = await source.liveNow();
    expect(live.map((event) => event.id).toSet(), {45729, 45772});
    expect(
      requests,
      containsAll([
        '/Harmony/en/api/Data/GetListViewData',
        '/Harmony/en/api/Data/GetUpcomingEvents',
      ]),
    );
  });

  test('past day does not request upcoming events', () async {
    final paths = <String>[];
    final source = ParlVuEventSource(
      parlvu: ParlVuClient(
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response.bytes(
            utf8.encode(fixture('listing_20260923.json')),
            200,
          );
        }),
      ),
      openParliament: OpenParliamentClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      now: () => DateTime.utc(2026, 9, 24, 16),
    );
    await source.day(DateTime.utc(2026, 9, 23));
    expect(paths, ['/Harmony/en/api/Data/GetListViewData']);
  });

  test('detail is cached and live streams expire after 30 seconds', () async {
    var now = t0, requests = 0;
    final html = fixture('event_null_fk_45806.html');
    final source = ParlVuEventSource(
      parlvu: ParlVuClient(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response.bytes(
            utf8.encode(html.replaceFirst('"IsLive":false', '"IsLive":true')),
            200,
          );
        }),
      ),
      openParliament: OpenParliamentClient(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      now: () => now,
    );
    await source.detail(45806);
    expect(requests, 1);
    await source.detail(45806);
    expect(requests, 1);
    now = now.add(const Duration(seconds: 31));
    await source.detail(45806);
    expect(requests, 2);
  });

  test('ETHI Hansard speakers align and cache marks forever', () async {
    final counts = <String, int>{};
    final source = ParlVuEventSource(
      parlvu: ParlVuClient(
        httpClient: MockClient((_) async => http.Response('', 200)),
      ),
      openParliament: OpenParliamentClient(
        httpClient: MockClient((r) async {
          counts.update(r.url.path, (n) => n + 1, ifAbsent: () => 1);
          final file = r.url.path.contains('meetings')
              ? 'op_meetings_20260707.json'
              : r.url.path.contains('committees')
              ? 'op_committee_ethics.json'
              : r.url.queryParameters['offset'] == '100'
              ? 'op_speeches_ethi49_p2.json'
              : 'op_speeches_ethi49_p1.json';
          return http.Response.bytes(utf8.encode(fixture(file)), 200);
        }),
      ),
      now: () => t0,
    );
    final event = ListingEvent(
      id: 45680,
      foreignKey: null,
      title: 'ETHI Meeting No. 49',
      description: '',
      location: '',
      scheduledStart: parliamentTime('2026-07-07T11:01:00'),
      scheduledEnd: null,
      actualStart: parliamentTime('2026-07-07T11:01:00'),
      actualEnd: null,
      status: EventStatus.ended,
      statusCode: -1,
      statusText: '',
    );
    final detail = EventDetail(
      id: 45680,
      recordingStart: DateTime(2026),
      streams: [],
      captions: {},
    );
    // Fixture's caption timestamps carry the matches; event detail is parsed from its fixture.
    final parsed = ParlVuClient(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(fixture('event_ethi49_45680.html')),
          200,
        ),
      ),
    );
    final actual = await parsed.eventDetail(45680);
    final marks = await source.speakers(event, actual);
    expect(marks, hasLength(108));
    expect(
      marks.where((m) => m.source == MarkSource.captionMatch),
      hasLength(25),
    );
    final before = Map.of(counts);
    await source.speakers(event, actual);
    expect(counts, before);
    expect(detail.id, 45680);
  });

  test(
    'empty Hansard retries after 30 minutes and Question Period clips marks',
    () async {
      var now = t0, hits = 0;
      final source = ParlVuEventSource(
        parlvu: ParlVuClient(
          httpClient: MockClient((_) async => http.Response('', 200)),
        ),
        openParliament: OpenParliamentClient(
          httpClient: MockClient((r) async {
            hits++;
            return http.Response('{"objects":[]}', 200);
          }),
        ),
        now: () => now,
      );
      final committee = ListingEvent(
        id: 1,
        foreignKey: null,
        title: 'ETHI Meeting No. 49',
        description: '',
        location: '',
        scheduledStart: t0,
        scheduledEnd: null,
        actualStart: t0,
        actualEnd: null,
        status: EventStatus.ended,
        statusCode: -1,
        statusText: '',
      );
      final detail = EventDetail(
        id: 1,
        recordingStart: DateTime(2026),
        streams: [],
        captions: {},
      );
      expect(await source.speakers(committee, detail), isEmpty);
      expect(hits, 1);
      await source.speakers(committee, detail);
      expect(hits, 1);
      now = now.add(const Duration(minutes: 31));
      await source.speakers(committee, detail);
      expect(hits, 2);
      final qSource = ParlVuEventSource(
        parlvu: ParlVuClient(
          httpClient: MockClient((_) async => http.Response('', 200)),
        ),
        openParliament: OpenParliamentClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'objects': [
                  for (final time in ['14:00:00', '14:30:00', '15:30:00'])
                    {
                      'time': '2026-09-23T$time',
                      'attribution': {'en': 'Speaker'},
                      'content': {'en': 'Some words of speech at this time'},
                      'url': '/speech/',
                    },
                ],
              }),
              200,
            ),
          ),
        ),
        now: () => t0,
      );
      final qp = ListingEvent(
        id: 2,
        foreignKey: null,
        title: 'Question Period for HoC Sitting No. 142',
        description: '',
        location: '',
        scheduledStart: t0,
        scheduledEnd: null,
        actualStart: parliamentTime('2026-09-23T14:01:37'),
        actualEnd: parliamentTime('2026-09-23T15:13:03'),
        status: EventStatus.ended,
        statusCode: -1,
        statusText: '',
      );
      final marks = await qSource.speakers(qp, detail);
      expect(marks, hasLength(1));
      expect(
        marks.single.speech.bucketTime,
        parliamentTime('2026-09-23T14:30:00'),
      );
    },
  );
}
