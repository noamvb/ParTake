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
}
