import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'parlvu_parser.dart';
import 'time.dart';

class ParlVuHttpException implements Exception {
  ParlVuHttpException(this.uri, this.statusCode);
  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'ParlVuHttpException: $uri returned HTTP $statusCode';
}

class ParlVuClient {
  ParlVuClient({http.Client? httpClient, Uri? baseUri})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null,
      _baseUri = baseUri ?? Uri.parse('https://parlvu.parl.gc.ca');

  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  static const _headers = {
    'User-Agent': 'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
    'Accept': 'application/json, text/html',
  };

  Future<http.Response> _get(Uri uri) async {
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw ParlVuHttpException(uri, response.statusCode);
    }
    return response;
  }

  Future<List<ListingEvent>> eventsBetween(
    DateTime fromDay,
    DateTime toDay, {
    bool includeUpcoming = false,
  }) async {
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=${date(fromDay)}&endDate=${date(toDay)}&searchTime=&searchForward=true&order=asc',
    );
    if (includeUpcoming) {
      final upcomingUri = Uri.parse(
        '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/Harmony/en/api/Data/GetUpcomingEvents?lastModified=',
      );
      final responses = await Future.wait([_get(uri), _get(upcomingUri)]);
      final listing = parseListing(utf8.decode(responses[0].bodyBytes));
      final upcoming = parseUpcoming(utf8.decode(responses[1].bodyBytes))
          .where((event) {
            final day = parliamentDate(event.scheduledStart);
            return !day.isBefore(fromDay) && !day.isAfter(toDay);
          });
      final merged = {for (final event in listing) event.id: event};
      for (final event in upcoming) {
        merged[event.id] = event;
      }
      final result = merged.values.toList()
        ..sort((a, b) {
          final byStart = a.scheduledStart.compareTo(b.scheduledStart);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
      return result;
    }
    final response = await _get(uri);
    return parseListing(utf8.decode(response.bodyBytes));
  }

  Future<EventDetail> eventDetail(int id) async {
    final uri = Uri.parse(
      '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/$id',
    );
    final response = await _get(uri);
    return parseEventPage(utf8.decode(response.bodyBytes), id: id);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
