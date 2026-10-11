import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'watch_models.dart';

class WatchConflict implements Exception {
  const WatchConflict(this.current);
  final WatchFollowList current;
}

class WatchUnauthorized implements Exception {
  const WatchUnauthorized();
}

class WatchHttpException implements Exception {
  const WatchHttpException(this.status, this.message);
  final int status;
  final String message;
}

class WatchClient {
  WatchClient({required this.address, this.token = '', http.Client? client})
    : _client = client ?? http.Client();
  final Uri address;
  final String token;
  final http.Client _client;

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    String? query,
  }) async {
    var uri = address.resolve('/watch/api/$path');
    if (query != null) uri = uri.replace(queryParameters: {'q': query});
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw WatchHttpException(0, error.toString());
    }
    if (response.statusCode == 401) throw const WatchUnauthorized();
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
    }
    if (response.statusCode == 409 && method == 'PUT' && path == 'follows') {
      throw WatchConflict(WatchFollowList.fromJson(decoded));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WatchHttpException(
        response.statusCode,
        decoded is Map && decoded['error'] is String
            ? decoded['error'] as String
            : response.reasonPhrase ?? 'Request failed',
      );
    }
    return decoded;
  }

  Future<WatchFollowList> getFollows() async =>
      WatchFollowList.fromJson(await _request('GET', 'follows'));
  Future<WatchFollowList> putFollows(
    int version,
    List<WatchFollow> follows,
  ) async => WatchFollowList.fromJson(
    await _request(
      'PUT',
      'follows',
      body: WatchFollowList(version: version, follows: follows).toJson(),
    ),
  );
  Future<WatchFollowList> importKeys(List<String> keys) async =>
      WatchFollowList.fromJson(
        await _request('POST', 'follows/import', body: {'keys': keys}),
      );
  Future<List<WatchMember>> members(String q) async =>
      (await _request('GET', 'members', query: q) as List)
          .map((m) => WatchMember.fromJson(m))
          .toList();
  Future<List<WatchBill>> bills(String q) async =>
      (await _request('GET', 'bills', query: q) as List)
          .map((b) => WatchBill.fromJson(b))
          .toList();

  void close() => _client.close();
}
