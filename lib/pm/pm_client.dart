import 'dart:convert';

import 'package:http/http.dart' as http;

import '../watch/watch_client.dart';
import 'pm_models.dart';

class PmClient {
  PmClient({required this.address, http.Client? client})
    : isSnapshot = false,
      _client = client ?? http.Client();
  PmClient.snapshot({required Uri base, http.Client? client})
    : address = base,
      isSnapshot = true,
      _client = client ?? http.Client();
  final bool isSnapshot;
  final Uri address;
  final http.Client _client;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = isSnapshot
        ? address.resolve('pm/$path.json')
        : address
              .resolve('/watch/api/pm/$path')
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

  Future<PmToday> today() async => PmToday.fromJson(await _get('today'));

  Future<FeedPage> feed({String? type, int limit = 50, String? before}) async {
    final data = await _get('feed', {
      'type': ?type,
      'limit': '$limit',
      'before': ?before,
    });
    if (isSnapshot) {
      data['next'] = null;
      if (type != null) {
        data['items'] = (data['items'] as List)
            .where((i) => type.split(',').contains(i['type']))
            .toList();
      }
    }
    return FeedPage.fromJson(data);
  }

  Future<PmItem> item(String id) async {
    if (isSnapshot) {
      throw UnsupportedError('Item bodies are not in the snapshot');
    }
    return PmItem.fromJson(await _get('items/$id'));
  }

  Future<List<MapPlace>> places({DateTime? since, DateTime? until}) async {
    final data = await _get('places', {
      'since': ?_date(since),
      'until': ?_date(until),
    });
    return List.unmodifiable(
      (data['places'] as List)
          .map((p) => MapPlace.fromJson(p))
          .where(
            (p) =>
                !isSnapshot ||
                since == null ||
                p.last.compareTo(_date(since)!) >= 0,
          ),
    );
  }

  Future<List<PathStop>> path({
    required DateTime since,
    required DateTime until,
  }) async {
    final data = await _get('path', {
      'since': _date(since)!,
      'until': _date(until)!,
    });
    return List.unmodifiable(
      (data['stops'] as List)
          .map((s) => PathStop.fromJson(s))
          .where(
            (s) =>
                !isSnapshot ||
                (s.date.compareTo(_date(since)!) >= 0 &&
                    s.date.compareTo(_date(until)!) <= 0),
          ),
    );
  }

  void close() => _client.close();
}

String? _date(DateTime? value) => value?.toIso8601String().substring(0, 10);
