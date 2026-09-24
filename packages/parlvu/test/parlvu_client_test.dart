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
