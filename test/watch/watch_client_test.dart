import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/watch/watch_client.dart';

import 'watch_models_test.dart' show seam, seamList;

void main() {
  WatchClient client(Future<http.Response> Function(http.Request) handler) =>
      WatchClient(
        address: Uri.parse('http://deck.test:8797/other'),
        token: 't0k',
        client: MockClient(handler),
      );
  test('4 GET follows uses watch route and decodes seam', () async {
    final watch = client((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'http://deck.test:8797/watch/api/follows');
      return http.Response.bytes(utf8.encode(seam), 200);
    });
    final result = await watch.getFollows();
    expect(result.version, 1);
    expect(result.follows, hasLength(7));
  });
  test('5 PUT authenticates and exposes conflict list', () async {
    final watch = client((request) async {
      expect(request.method, 'PUT');
      expect(request.url.toString(), 'http://deck.test:8797/watch/api/follows');
      expect(request.headers['Authorization'], 'Bearer t0k');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body)['version'], 1);
      expect(jsonDecode(request.body)['follows'], hasLength(7));
      return http.Response.bytes(utf8.encode(seam), 409);
    });
    await expectLater(
      watch.putFollows(1, seamList().follows),
      throwsA(
        isA<WatchConflict>().having((e) => e.current.version, 'version', 1),
      ),
    );
  });
  test('6 unauthorized HTTP and transport errors are typed', () async {
    await expectLater(
      client((_) async => http.Response('{}', 401)).getFollows(),
      throwsA(isA<WatchUnauthorized>()),
    );
    await expectLater(
      client((_) async => http.Response('{"error":"boom"}', 500)).getFollows(),
      throwsA(
        isA<WatchHttpException>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.message, 'message', 'boom'),
      ),
    );
    await expectLater(
      client((_) async => throw http.ClientException('offline')).getFollows(),
      throwsA(isA<WatchHttpException>().having((e) => e.status, 'status', 0)),
    );
  });
  test('7 lookups send query and parse nullable fields', () async {
    final requests = <String>[];
    final watch = client((request) async {
      requests.add(request.url.toString());
      return http.Response(
        request.url.path.endsWith('members')
            ? '[{"person_id":"123447","name":"Billy Morin","party":"Conservative","riding":"Edmonton Northwest","province":"Alberta","role":null}]'
            : '[{"id":"45-1/C-37","number":"C-37","title":"Water","stage":"First reading","stage_at":null}]',
        200,
      );
    });
    final members = await watch.members('morin');
    final bills = await watch.bills('C-37');
    expect(requests, [
      'http://deck.test:8797/watch/api/members?q=morin',
      'http://deck.test:8797/watch/api/bills?q=C-37',
    ]);
    expect(members.single.personId, '123447');
    expect(members.single.role, isNull);
    expect(bills.single.id, '45-1/C-37');
    expect(bills.single.stageAt, isNull);
  });
}
