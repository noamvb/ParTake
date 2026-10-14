import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/polls/polls_client.dart';
import 'package:partake/watch/watch_client.dart';

import 'polls_seams.dart';

void main() {
  test('2. Client paths, query parameters and parsed responses', () async {
    final requests = <Uri>[];
    final client = PollsClient(
      address: Uri.parse('http://deck.test/ignored'),
      client: MockClient((r) async {
        requests.add(r.url);
        final seam = switch (r.url.path.split('/').last) {
          'summary' => 'summary',
          'list' => 'list',
          'leaders' => 'leaders',
          'ridings' => 'ridings',
          _ => 'riding',
        };
        return http.Response(
          jsonEncode(pollsSeam(seam)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    await client.summary(history: false);
    await client.list(region: 'QC', limit: 20, before: 'X');
    await client.ridings(mp: '123');
    await client.riding('24038');
    await client.leaders();
    expect(requests.map((u) => u.toString()), [
      'http://deck.test/watch/api/polls/summary?history=0',
      'http://deck.test/watch/api/polls/list?region=QC&limit=20&before=X',
      'http://deck.test/watch/api/polls/ridings?mp=123',
      'http://deck.test/watch/api/polls/ridings/24038',
      'http://deck.test/watch/api/polls/leaders',
    ]);
  });

  for (final status in [401, 404, 500]) {
    test('2. HTTP $status preserves API error text', () async {
      final client = PollsClient(
        address: Uri.parse('http://deck.test'),
        client: MockClient(
          (r) async => http.Response('{"error":"Not ready"}', status),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.summary(),
        throwsA(
          isA<WatchHttpException>()
              .having((e) => e.status, 'status', status)
              .having((e) => e.message, 'message', 'Not ready'),
        ),
      );
    });
  }
  test('2. Network errors use WatchHttpException status zero', () async {
    final client = PollsClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((r) async => throw http.ClientException('offline')),
    );
    addTearDown(client.close);
    await expectLater(
      client.list(),
      throwsA(isA<WatchHttpException>().having((e) => e.status, 'status', 0)),
    );
  });
  test('B1. Snapshot requests the five public JSON paths', () async {
    final base = Uri.parse('https://example.test/snap/');
    final requests = <Uri>[];
    final client = PollsClient.snapshot(
      base: base,
      client: MockClient((r) async {
        requests.add(r.url);
        final name = r.url.path.split('/').last.replaceAll('.json', '');
        final seam = name == '24038' ? 'riding' : name;
        return http.Response.bytes(
          utf8.encode(jsonEncode(pollsSeam(seam))),
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(client.address, base);
    expect((await client.summary(history: false)).pollsUsed, 14);
    await client.leaders();
    await client.list();
    await client.ridings();
    expect((await client.riding('24038')).id, '24038');
    expect(requests.map((u) => u.toString()), [
      '${base}summary.json',
      '${base}leaders.json',
      '${base}list.json',
      '${base}ridings.json',
      '${base}ridings/24038.json',
    ]);
  });

  test(
    'B2. Snapshot paging and unavailable regions make no requests',
    () async {
      var requests = 0;
      final client = PollsClient.snapshot(
        base: Uri.parse('https://example.test/snap/'),
        client: MockClient((r) async {
          requests++;
          return http.Response(jsonEncode(pollsSeam('list')), 200);
        }),
      );
      addTearDown(client.close);
      await client.list();
      expect(requests, 1);
      requests = 0;
      final page = await client.list(before: 'x');
      expect(page.polls, isEmpty);
      expect(page.next, isNull);
      await expectLater(
        client.list(region: 'QC'),
        throwsA(
          isA<WatchHttpException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', 'Not in snapshot'),
        ),
      );
      expect(requests, 0);
    },
  );

  test('B3. Snapshot filters riding MPs locally without a query', () async {
    final seam = pollsSeam('ridings');
    final riding = (seam['ridings'] as List).firstWhere((r) => r['mp'] != null);
    final requests = <Uri>[];
    final client = PollsClient.snapshot(
      base: Uri.parse('https://example.test/snap/'),
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response.bytes(utf8.encode(jsonEncode(seam)), 200);
      }),
    );
    addTearDown(client.close);
    final ridings = await client.ridings(mp: riding['mp']['person_id']);
    expect(ridings.map((r) => r.id), [riding['id']]);
    expect(
      requests.single.toString(),
      'https://example.test/snap/ridings.json',
    );
    expect(requests.single.query, isEmpty);
  });

  test('B4. Snapshot HTTP 404 preserves the status', () async {
    final client = PollsClient.snapshot(
      base: Uri.parse('https://example.test/snap/'),
      client: MockClient(
        (r) async => http.Response('{"error":"Missing"}', 404),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.summary(),
      throwsA(isA<WatchHttpException>().having((e) => e.status, 'status', 404)),
    );
  });
}
