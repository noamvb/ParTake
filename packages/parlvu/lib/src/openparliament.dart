import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'time.dart';

class SpeechPage {
  const SpeechPage(this.speeches, this.nextUrl);
  final List<Speech> speeches;
  final String? nextUrl;
}

class OpenParliamentHttpException implements Exception {
  const OpenParliamentHttpException(this.uri, this.statusCode);
  final Uri uri;
  final int statusCode;
  @override
  String toString() =>
      'OpenParliamentHttpException: $uri returned HTTP $statusCode';
}

SpeechPage parseSpeechPage(String body) {
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ParlVuFormatException(
      'Response is not JSON',
      snippet: body.substring(0, body.length.clamp(0, 200)),
    );
  }
  if (decoded is! Map || decoded['objects'] is! List) {
    throw ParlVuFormatException('Response objects is not a list');
  }
  final speeches = <Speech>[];
  for (final item in decoded['objects'] as List) {
    if (item is! Map ||
        item['time'] is! String ||
        item['attribution'] is! Map ||
        item['attribution']['en'] is! String ||
        item['content'] is! Map ||
        item['content']['en'] is! String ||
        item['url'] is! String) {
      throw ParlVuFormatException('Speech is missing a required field');
    }
    try {
      speeches.add(
        Speech(
          bucketTime: parliamentTime(item['time'] as String),
          speaker: item['attribution']['en'] as String,
          politicianUrl: item['politician_url'] as String?,
          textEn: _plainText(item['content']['en'] as String),
          paragraphs: _speechParagraphs(
            item['content']['en'] as String,
            item['content']['fr'] is String
                ? item['content']['fr'] as String
                : '',
          ),
          procedural: item['procedural'] == true,
          url: item['url'] as String,
        ),
      );
    } on FormatException catch (e) {
      throw ParlVuFormatException('Invalid speech time', snippet: e.toString());
    }
  }
  final pagination = decoded['pagination'];
  final next = pagination is Map ? pagination['next_url'] : null;
  return SpeechPage(speeches, next is String ? next : null);
}

class _HtmlParagraph {
  const _HtmlParagraph(this.id, this.language, this.text);
  final String? id;
  final AudioLanguage? language;
  final String text;
}

List<SpeechParagraph> _speechParagraphs(String htmlEn, String htmlFr) {
  List<_HtmlParagraph> parse(String html) =>
      RegExp(
        r'<p\b([^>]*)>(.*?)</p\s*>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html).map((match) {
        final attrs = match.group(1)!;
        final id = RegExp(
          r'''\bdata-hocid\s*=\s*["'](\d+)["']''',
          caseSensitive: false,
        ).firstMatch(attrs)?.group(1);
        final lang = RegExp(
          r'''\bdata-originallang\s*=\s*["'](en|fr)["']''',
          caseSensitive: false,
        ).firstMatch(attrs)?.group(1)?.toLowerCase();
        return _HtmlParagraph(
          id,
          lang == null ? null : AudioLanguage.fromCode(lang),
          _plainText(match.group(2)!),
        );
      }).toList();

  final en = parse(htmlEn);
  final fr = parse(htmlFr);
  final frById = <String, int>{};
  for (var i = 0; i < fr.length; i++) {
    final id = fr[i].id;
    if (id != null) frById[id] = i;
  }
  final usedFr = <int>{};
  final result = <SpeechParagraph>[];
  for (var i = 0; i < en.length; i++) {
    final e = en[i];
    int? j;
    if (e.id == null || (i < fr.length && fr[i].id == null)) {
      if (i < fr.length && !usedFr.contains(i)) j = i;
    } else {
      j = frById[e.id];
    }
    if (j != null) usedFr.add(j);
    final f = j == null ? null : fr[j];
    result.add(
      SpeechParagraph(
        language: e.language ?? f?.language,
        textEn: e.text,
        textFr: f?.text ?? '',
      ),
    );
  }
  for (var i = 0; i < fr.length; i++) {
    if (usedFr.contains(i)) continue;
    final f = fr[i];
    result.add(
      SpeechParagraph(language: f.language, textEn: '', textFr: f.text),
    );
  }
  return result;
}

String _plainText(String html) {
  var text = html
      .replaceAll(RegExp(r'</p\s*>|<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  text = text.replaceAllMapped(RegExp(r'&(?:amp|lt|gt|quot|#39|#\d+);'), (m) {
    switch (m[0]) {
      case '&amp;':
        return '&';
      case '&lt;':
        return '<';
      case '&gt;':
        return '>';
      case '&quot;':
        return '"';
      case '&#39;':
        return "'";
      default:
        return String.fromCharCode(
          int.parse(m[0]!.substring(2, m[0]!.length - 1)),
        );
    }
  });
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class OpenParliamentClient {
  OpenParliamentClient({http.Client? httpClient, Uri? baseUri})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null,
      baseUri = baseUri ?? Uri.https('api.openparliament.ca');

  final http.Client _client;
  final bool _ownsClient;
  final Uri baseUri;
  final Map<String, Future<dynamic>> _committeeCache = {};
  static const _agent =
      'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)';

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<Speech>> houseDebate(DateTime ottawaDate) {
    final path =
        '/debates/${ottawaDate.year}/${ottawaDate.month}/${ottawaDate.day}/';
    return _speechPages('/speeches/', {
      'document': path,
      'format': 'json',
      'limit': '100',
    });
  }

  Future<List<Speech>> committeeMeeting({
    required String acronym,
    required DateTime ottawaDate,
    required int number,
  }) async {
    final date =
        '${ottawaDate.year.toString().padLeft(4, '0')}-${ottawaDate.month.toString().padLeft(2, '0')}-${ottawaDate.day.toString().padLeft(2, '0')}';
    final meetings = await _getJson(
      _uri('/committees/meetings/', {'format': 'json', 'date': date}),
    );
    final objects = meetings is Map && meetings['objects'] is List
        ? meetings['objects'] as List
        : const [];
    for (final m in objects) {
      if (m is! Map || m['number'] != number || m['committee_url'] is! String) {
        continue;
      }
      if (m['has_evidence'] == false) {
        continue;
      }
      final committeePath = m['committee_url'] as String;
      final committee = await (_committeeCache[committeePath] ??= _getJson(
        _uri(committeePath, {'format': 'json'}),
      ));
      final sessions = committee is Map && committee['sessions'] is List
          ? committee['sessions'] as List
          : const [];
      if (sessions.any(
        (s) =>
            s is Map &&
            s['acronym'] is String &&
            (s['acronym'] as String).toLowerCase() == acronym.toLowerCase(),
      )) {
        final document = m['url'];
        if (document is String) {
          return _speechPages('/speeches/', {
            'document': document,
            'format': 'json',
            'limit': '100',
          });
        }
      }
    }
    return [];
  }

  Uri _uri(String path, Map<String, String> query) =>
      baseUri.replace(path: path, queryParameters: query);
  Future<dynamic> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: {'User-Agent': _agent});
    if (response.statusCode != 200) {
      throw OpenParliamentHttpException(uri, response.statusCode);
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw ParlVuFormatException(
        'Response is not JSON',
        snippet: response.body.substring(0, response.body.length.clamp(0, 200)),
      );
    }
  }

  Future<List<Speech>> _speechPages(
    String path,
    Map<String, String> query,
  ) async {
    var uri = _uri(path, query);
    final result = <Speech>[];
    while (true) {
      final response = await _client.get(uri, headers: {'User-Agent': _agent});
      if (response.statusCode != 200) {
        throw OpenParliamentHttpException(uri, response.statusCode);
      }
      final page = parseSpeechPage(response.body);
      result.addAll(page.speeches);
      if (page.nextUrl == null) return result;
      uri = baseUri.resolve(page.nextUrl!);
    }
  }
}
