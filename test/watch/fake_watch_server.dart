import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/watch/watch_client.dart';
import 'package:partake/watch/watch_models.dart';

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

  WatchClient client(Uri address, String token) => WatchClient(
    address: address,
    token: token,
    client: MockClient((request) async {
      requests.add(request);
      if (offline) throw http.ClientException('offline');
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
