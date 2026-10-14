import 'dart:convert';

import 'package:http/http.dart' as http;

import '../watch/watch_client.dart';
import 'polls_models.dart';

class PollsClient {
  PollsClient({required this.address, http.Client? client})
    : _snapshot = false,
      _client = client ?? http.Client();
  PollsClient.snapshot({required Uri base, http.Client? client})
    : address = base,
      _snapshot = true,
      _client = client ?? http.Client();
  final bool _snapshot;
  final Uri address;
  final http.Client _client;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = _snapshot
        ? address.resolve('$path.json')
        : address
              .resolve('/watch/api/polls/$path')
              .replace(queryParameters: query);
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw WatchHttpException(0, error.toString());
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WatchHttpException(
        response.statusCode,
        decoded is Map && decoded['error'] is String
            ? decoded['error'] as String
            : response.reasonPhrase ?? 'Request failed',
      );
    }
    return decoded as Map<String, dynamic>;
  }

  Future<PollsSummary> summary({bool history = true}) async =>
      PollsSummary.fromJson(
        await _get('summary', {'history': history ? '1' : '0'}),
      );
  Future<PollsPage> list({
    String region = 'CAN',
    int limit = 50,
    String? before,
  }) async {
    if (_snapshot) {
      if (region != 'CAN') {
        throw const WatchHttpException(404, 'Not in snapshot');
      }
      if (before != null) {
        return PollsPage.fromJson({
          'polls': <dynamic>[],
          'next': null,
          'source': {'name': '', 'url': address.toString(), 'fetched_at': ''},
        });
      }
    }
    return PollsPage.fromJson(
      await _get('list', {
        'region': region,
        'limit': '$limit',
        'before': ?before,
      }),
    );
  }

  Future<LeaderPolls> leaders() async =>
      LeaderPolls.fromJson(await _get('leaders'));
  Future<List<RidingSummary>> ridings({String? mp}) async => List.unmodifiable(
    ((await _get('ridings', {'mp': ?mp}))['ridings'] as List)
        .map((r) => RidingSummary.fromJson(r))
        .where((r) => !_snapshot || mp == null || r.mp?.personId == mp),
  );
  Future<RidingDetail> riding(String id) async =>
      RidingDetail.fromJson(await _get('ridings/${Uri.encodeComponent(id)}'));
  void close() => _client.close();
}
