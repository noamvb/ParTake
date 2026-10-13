import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/watch/watch_client.dart';
import 'package:partake/watch/watch_models.dart';

/// The feed literal the service returns (`test/watch/feed_seam.json`).
final feedSeam = File('test/watch/feed_seam.json').readAsStringSync();

/// Phase 2 literals: digest list, one digest and the live strip.
final digestsSeam = File('test/watch/digests_seam.json').readAsStringSync();
final digestSeam = File('test/watch/digest_seam.json').readAsStringSync();
final liveSeam = File('test/watch/live_seam.json').readAsStringSync();

/// The four follows that the seam feed refers to by id.
List<WatchFollow> feedFollows() => [
  WatchFollow(
    id: 'f_ghi234',
    kind: 'topic',
    label: 'Housing affordability',
    topic: WatchTopic(
      en: 'housing affordability',
      fr: 'abordabilité du logement',
      keywords: const ['CMHC'],
      threshold: 0.55,
    ),
  ),
  const WatchFollow(
    id: 'f_jkl567',
    kind: 'bill',
    label: 'C-37',
    bill: WatchBillRef(
      id: '45-1/C-37',
      number: 'C-37',
      title: 'First Nations Clean Water Act',
    ),
  ),
  const WatchFollow(
    id: 'f_mno234',
    kind: 'mp',
    label: 'Billy Morin',
    mp: WatchMpRef(
      personId: '123447',
      name: 'Billy Morin',
      party: 'Conservative',
      riding: 'Edmonton Northwest',
    ),
  ),
  const WatchFollow(
    id: 'f_pqr567',
    kind: 'votes',
    label: 'Party splits',
    votesFilter: 'party_split',
  ),
];

/// Answers `GET /watch/api/feed` with [total] synthetic speeches, [size] per
/// page; the cursor is `c_<offset of the next page>`.
http.Response pagedFeed(Uri url, {int total = 60, int size = 25}) {
  final start = url.queryParameters['before'] == null
      ? 0
      : int.parse(url.queryParameters['before']!.substring(2));
  final end = start + size < total ? start + size : total;
  return http.Response(
    jsonEncode({
      'items': [
        for (var i = start; i < end; i++)
          {
            'id': 'm_s_$i',
            'kind': 'speech',
            'at': '2026-10-09T14:00:00Z',
            'follows': [
              {'id': 'f_ghi234', 'score': 0.5},
            ],
            'source': 'hansard',
            'superseded': false,
            'title': 'Item $i',
            'text': 'Text $i',
            'lang': 'en',
            'speaker': null,
            'video': null,
            'links': {'hansard': null, 'legisinfo': null, 'division': null},
            'division': null,
            'bill_stage': null,
          },
      ],
      'next': end < total ? 'c_$end' : null,
    }),
    200,
  );
}

class FakeWatchServer {
  FakeWatchServer([List<WatchFollow> initial = const []])
    : follows = initial.toList();
  List<WatchFollow> follows;
  int version = 1;
  bool offline = false;
  List<WatchFollow>? conflict;
  final requests = <http.Request>[];
  final puts = <List<WatchFollow>>[];
  final imports = <List<String>>[];
  final feedRequests = <Uri>[];

  /// Answers `GET /watch/api/feed`; defaults to the seam page.
  Future<http.Response> Function(Uri url)? feedAnswer;

  /// Answers `GET /watch/api/live`; defaults to nothing being recorded.
  Future<http.Response> Function(Uri url)? liveAnswer;
  final liveRequests = <Uri>[];

  /// Answers `GET /watch/api/alerts`; defaults to no alerts.
  Future<http.Response> Function(Uri url)? alertsAnswer;
  final alertsRequests = <Uri>[];

  /// Answers `GET /watch/api/digests`; defaults to the seam list.
  Future<http.Response> Function(Uri url)? digestsAnswer;

  /// Answers `GET /watch/api/digests/<id>`; defaults to the seam digest.
  Future<http.Response> Function(Uri url)? digestAnswer;

  WatchClient client(Uri address, String token) => WatchClient(
    address: address,
    token: token,
    client: MockClient((request) async {
      requests.add(request);
      if (offline) throw http.ClientException('offline');
      if (request.url.path == '/watch/api/feed') {
        feedRequests.add(request.url);
        final answer = feedAnswer;
        return answer == null
            ? http.Response.bytes(utf8.encode(feedSeam), 200)
            : answer(request.url);
      }
      if (request.url.path == '/watch/api/live') {
        liveRequests.add(request.url);
        final answer = liveAnswer;
        return answer == null
            ? http.Response.bytes(utf8.encode('[]'), 200)
            : answer(request.url);
      }
      if (request.url.path == '/watch/api/alerts') {
        alertsRequests.add(request.url);
        final answer = alertsAnswer;
        return answer == null
            ? http.Response.bytes(utf8.encode('[]'), 200)
            : answer(request.url);
      }
      if (request.url.path == '/watch/api/digests') {
        final answer = digestsAnswer;
        return answer == null
            ? http.Response.bytes(utf8.encode(digestsSeam), 200)
            : answer(request.url);
      }
      if (request.url.path.startsWith('/watch/api/digests/')) {
        final answer = digestAnswer;
        return answer == null
            ? http.Response.bytes(utf8.encode(digestSeam), 200)
            : answer(request.url);
      }
      if (request.method == 'POST') {
        final keys = List<String>.from(jsonDecode(request.body)['keys']);
        imports.add(keys);
        for (final key in keys) {
          if (!follows.any((f) => legacyKeyOf(f) == key)) {
            follows.add(legacyFollow(key));
          }
        }
      } else if (request.method == 'PUT') {
        final body = jsonDecode(request.body);
        final next = WatchFollowList.fromJson(body).follows;
        puts.add(next);
        if (conflict != null) {
          follows = conflict!;
          conflict = null;
          version++;
          return response(409);
        }
        follows = next;
        version++;
      }
      return response(200);
    }),
  );

  http.Response response(int status) => http.Response.bytes(
    utf8.encode(
      jsonEncode(WatchFollowList(version: version, follows: follows).toJson()),
    ),
    status,
  );
}
