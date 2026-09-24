import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'parlvu_parser.dart';

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
    DateTime toDay,
  ) async {
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '${_baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=${date(fromDay)}&endDate=${date(toDay)}&searchTime=&searchForward=true&order=asc',
    );
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
