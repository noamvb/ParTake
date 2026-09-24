import 'dart:convert';

import 'models.dart';
import 'time.dart';

String _snippet(String input) =>
    input.length <= 200 ? input : input.substring(0, 200);

Never _bad(String message, String input) =>
    throw ParlVuFormatException(message, snippet: _snippet(input));

DateTime _time(Object? value, String input, String field) {
  if (value is! String) _bad('$field must be a timestamp string', input);
  try {
    return parliamentTime(value);
  } on FormatException {
    _bad('$field is not a valid timestamp', input);
  }
}

DateTime? _optionalTime(Object? value, String input, String field) =>
    value == null ? null : _time(value, input, field);

List<ListingEvent> parseListing(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    _bad('listing is not valid JSON', body);
  }
  if (decoded is! Map<String, dynamic>) _bad('listing must be an object', body);
  final weeks = decoded['Weeks'];
  if (weeks is! List) _bad('Weeks must be a list', body);
  final result = <ListingEvent>[];
  for (final week in weeks) {
    if (week is! Map<String, dynamic> || week['ContentEntityDatas'] is! List) {
      _bad('ContentEntityDatas must be a list', body);
    }
    for (final row in week['ContentEntityDatas'] as List) {
      if (row is! Map<String, dynamic>) {
        _bad('listing row must be an object', body);
      }
      for (final field in ['Id', 'Title', 'ScheduledStart', 'EntityStatus']) {
        if (!row.containsKey(field)) {
          _bad('listing row is missing $field', jsonEncode(row));
        }
      }
      if (row['Id'] is! int ||
          row['Title'] is! String ||
          row['EntityStatus'] is! int) {
        _bad('listing row has a field with the wrong type', jsonEncode(row));
      }
      for (final field in ['Description', 'Location', 'EntityStatusDesc']) {
        final v = row[field];
        if (v != null && v is! String) {
          _bad('$field must be a string', jsonEncode(row));
        }
      }
      final code = row['EntityStatus'] as int;
      final fk = row['ForeignKey'];
      if (fk != null && fk is! String) {
        _bad('ForeignKey must be a string', jsonEncode(row));
      }
      result.add(
        ListingEvent(
          id: row['Id'] as int,
          foreignKey: fk as String?,
          title: row['Title'] as String,
          description: (row['Description'] as String?) ?? '',
          location: (row['Location'] as String?) ?? '',
          scheduledStart: _time(
            row['ScheduledStart'],
            jsonEncode(row),
            'ScheduledStart',
          ),
          scheduledEnd: _optionalTime(
            row['ScheduledEnd'],
            jsonEncode(row),
            'ScheduledEnd',
          ),
          actualStart: _optionalTime(
            row['ActualStart'],
            jsonEncode(row),
            'ActualStart',
          ),
          actualEnd: _optionalTime(
            row['ActualEnd'],
            jsonEncode(row),
            'ActualEnd',
          ),
          status: EventStatus.fromCode(code),
          statusCode: code,
          statusText: (row['EntityStatusDesc'] as String?) ?? '',
        ),
      );
    }
  }
  return result;
}

String _jsonAt(String input, int start, String piece) {
  while (start < input.length && input[start].trim().isEmpty) {
    start++;
  }
  if (start >= input.length || (input[start] != '{' && input[start] != '[')) {
    _bad('$piece value is missing', input);
  }
  final opener = input[start];
  final closer = opener == '{' ? '}' : ']';
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = start; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        quoted = false;
      }
      continue;
    }
    if (c == '"') {
      quoted = true;
      continue;
    }
    if (c == opener) depth++;
    if (c == closer && --depth == 0) return input.substring(start, i + 1);
  }
  _bad('$piece value is incomplete', input);
}

Object? _embedded(String html, String marker, String piece, String nextMarker) {
  final at = html.indexOf(marker);
  if (at < 0 || html.indexOf(marker, at + marker.length) >= 0) {
    _bad('$piece marker is missing or ambiguous', html);
  }
  final start = at + marker.length;
  String raw;
  try {
    raw = _jsonAt(html, start, piece);
    return jsonDecode(raw);
  } on ParlVuFormatException {
    rethrow;
  } on FormatException {
    _bad('$piece value does not decode', html);
  }
}

EventDetail parseEventPage(String html, {required int id}) {
  final streamsValue = _embedded(
    html,
    'var availableStreams = ',
    'availableStreams',
    '',
  );
  if (streamsValue is! List) _bad('availableStreams must be a list', html);
  final infoValue = _embedded(html, '\tEventInfo:', 'EventInfo', '\tccItems:');
  if (infoValue is! Map<String, dynamic>) {
    _bad('EventInfo must be an object', html);
  }
  final tags = infoValue['timeTags'];
  final start = tags is Map ? tags['STARTTIME'] : null;
  final timestamp = start is Map ? start['timestamp'] : null;
  if (timestamp == null) _bad('STARTTIME is missing', html);
  final recordingStart = _time(timestamp, html, 'STARTTIME');
  final ccValue = _embedded(html, '\tccItems:', 'ccItems', '');
  if (ccValue is! Map<String, dynamic>) _bad('ccItems must be an object', html);
  final streams = <StreamVariant>[];
  for (final value in streamsValue) {
    if (value is! Map<String, dynamic>) {
      _bad('availableStreams contains a non-object', html);
    }
    final language = AudioLanguage.fromCode(
      value['Lang'] is String ? value['Lang'] as String : '',
    );
    if (language == null) continue;
    if (value['Url'] is! String ||
        value['Tag'] is! String ||
        value['AudioOnly'] is! bool ||
        value['IsLive'] is! bool ||
        value['EnableCC'] is! bool ||
        value['PreRoll'] is! num) {
      _bad('availableStreams entry has invalid fields', html);
    }
    final duration = value['Duration'];
    if (duration != null && duration is! int) {
      _bad('availableStreams Duration must be an integer', html);
    }
    final tag = value['Tag'] as String;
    streams.add(
      StreamVariant(
        language: language,
        url: Uri.parse(value['Url'] as String),
        tag: tag,
        audioOnly: value['AudioOnly'] as bool,
        isLive: value['IsLive'] as bool,
        isSd: tag.endsWith(' SD'),
        preRoll: Duration(
          milliseconds: ((value['PreRoll'] as num) * 1000).round(),
        ),
        duration: duration == null ? null : Duration(seconds: duration as int),
        enableCc: value['EnableCC'] as bool,
      ),
    );
  }
  final captions = <AudioLanguage, List<Caption>>{};
  for (final entry in [
    (AudioLanguage.english, 'en'),
    (AudioLanguage.french, 'fr'),
  ]) {
    final value = ccValue[entry.$2];
    if (value == null) continue;
    if (value is! List) _bad('ccItems ${entry.$2} must be a list', html);
    if (value.isEmpty) continue;
    captions[entry.$1] = value.map((item) {
      if (item is! Map<String, dynamic>) {
        _bad('ccItems caption must be an object', html);
      }
      return Caption(
        begin: _time(item['Begin'], html, 'ccItems Begin'),
        end: _time(item['End'], html, 'ccItems End'),
        text: item['Content'] is String
            ? (item['Content'] as String).trim()
            : _bad('ccItems Content must be a string', html),
      );
    }).toList();
  }
  return EventDetail(
    id: id,
    recordingStart: recordingStart,
    streams: streams,
    captions: captions,
  );
}
