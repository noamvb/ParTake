import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
const agent =
    'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)';

void main() {
  test(
    'eventsBetween sends exact URL and headers and parses listing',
    () async {
      http.Request? request;
      final client = ParlVuClient(
        httpClient: MockClient((r) async {
          request = r;
          return http.Response.bytes(
            utf8.encode(fixture('listing_20260923.json')),
            200,
          );
        }),
      );
      final events = await client.eventsBetween(
        DateTime.utc(2026, 9, 23),
        DateTime.utc(2026, 9, 24),
      );
      expect(
        request!.url.toString(),
        'https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=20260923&endDate=20260924&searchTime=&searchForward=true&order=asc',
      );
      expect(request!.headers['user-agent'], agent);
      expect(request!.headers['accept'], 'application/json, text/html');
      expect(events, hasLength(10));
    },
  );
  test('includes and merges upcoming events for requested dates', () async {
    final requests = <String>{};
    final client = ParlVuClient(
      httpClient: MockClient((request) async {
        requests.add(request.url.toString());
        final file = request.url.path.endsWith('GetUpcomingEvents')
            ? 'upcoming_20260924.json'
            : 'listing_20260924.json';
        return http.Response.bytes(utf8.encode(fixture(file)), 200);
      }),
    );
    final events = await client.eventsBetween(
      DateTime.utc(2026, 9, 24),
      DateTime.utc(2026, 9, 24),
      includeUpcoming: true,
    );
    expect(requests, {
      'https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=20260924&endDate=20260924&searchTime=&searchForward=true&order=asc',
      'https://parlvu.parl.gc.ca/Harmony/en/api/Data/GetUpcomingEvents?lastModified=',
    });
    expect(events, hasLength(16));
    expect(
      events.singleWhere((event) => event.id == 45729).status,
      EventStatus.live,
    );
    expect(
      events.any((event) => event.id == 45730 || event.id == 44792),
      isFalse,
    );
    final sorted = [...events]
      ..sort((a, b) {
        final byStart = a.scheduledStart.compareTo(b.scheduledStart);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    expect(events, sorted);
  });
  test('merges listing-only rows across adjacent dates', () async {
    final client = ParlVuClient(
      httpClient: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            fixture(
              request.url.path.endsWith('GetUpcomingEvents')
                  ? 'upcoming_20260924.json'
                  : 'listing_20260923.json',
            ),
          ),
          200,
        ),
      ),
    );
    expect(
      await client.eventsBetween(
        DateTime.utc(2026, 9, 23),
        DateTime.utc(2026, 9, 24),
        includeUpcoming: true,
      ),
      hasLength(26),
    );
  });
  test('upcoming row replaces listing row with matching id', () async {
    const row0 =
        '{"Id":7,"Title":"old","ScheduledStart":"2026-09-24T10:00:00","EntityStatus":0}';
    const row1 =
        '{"Id":7,"Title":"new","ScheduledStart":"2026-09-24T10:00:00","EntityStatus":1}';
    final client = ParlVuClient(
      httpClient: MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('GetUpcomingEvents')
              ? '{"ContentEntityDatas":[[$row1]]}'
              : '{"Weeks":[{"ContentEntityDatas":[$row0]}]}',
          200,
        ),
      ),
    );
    final events = await client.eventsBetween(
      DateTime.utc(2026, 9, 24),
      DateTime.utc(2026, 9, 24),
      includeUpcoming: true,
    );
    expect(events, hasLength(1));
    expect(events.single.id, 7);
    expect(events.single.status, EventStatus.live);
  });
  test('upcoming HTTP failure throws without partial results', () async {
    final client = ParlVuClient(
      httpClient: MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('GetUpcomingEvents')
              ? 'failure'
              : '{"Weeks":[]}',
          request.url.path.endsWith('GetUpcomingEvents') ? 500 : 200,
        ),
      ),
    );
    await expectLater(
      client.eventsBetween(
        DateTime.utc(2026, 9, 24),
        DateTime.utc(2026, 9, 24),
        includeUpcoming: true,
      ),
      throwsA(isA<ParlVuHttpException>()),
    );
  });
  test('omitting includeUpcoming sends one request', () async {
    var requests = 0;
    final client = ParlVuClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{"Weeks":[]}', 200);
      }),
    );
    await client.eventsBetween(
      DateTime.utc(2026, 9, 24),
      DateTime.utc(2026, 9, 24),
    );
    expect(requests, 1);
  });
  test('eventDetail sends exact route and parses event page', () async {
    http.Request? request;
    final client = ParlVuClient(
      httpClient: MockClient((r) async {
        request = r;
        return http.Response.bytes(
          utf8.encode(fixture('event_null_fk_45806.html')),
          200,
        );
      }),
    );
    final detail = await client.eventDetail(45806);
    expect(
      request!.url.toString(),
      'https://parlvu.parl.gc.ca/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45806',
    );
    expect(detail.streams, hasLength(9));
  });
  test('non-200 response throws HTTP exception before parsing', () async {
    final client = ParlVuClient(
      httpClient: MockClient(
        (r) async => http.Response.bytes(
          utf8.encode(fixture('event_fewo_13596766.html')),
          502,
        ),
      ),
    );
    await expectLater(
      client.eventDetail(1),
      throwsA(
        isA<ParlVuHttpException>().having(
          (e) => e.statusCode,
          'statusCode',
          502,
        ),
      ),
    );
  });
}
