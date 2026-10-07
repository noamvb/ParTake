import 'package:http/http.dart' as http;

import 'models.dart';
import 'time.dart';

/// One itinerary day on which the Prime Minister attends Question Period.
class PmQuestionPeriod {
  const PmQuestionPeriod({
    required this.day,
    required this.startsAt,
    required this.timeLabel,
    required this.link,
  });

  /// Ottawa calendar date as midnight UTC, as returned by [parliamentDate].
  final DateTime day;

  /// Start instant in UTC.
  final DateTime startsAt;

  /// Published time, normalised to single spaces with no nbsp and trimmed.
  final String timeLabel;
  final Uri link;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _unescape(String text) => text.replaceAllMapped(
  RegExp(r'&(lt|gt|amp|quot|apos|#\d+|#x[0-9a-fA-F]+);'),
  (match) {
    final entity = match[1]!;
    if (entity.startsWith('#')) {
      final hex = entity.startsWith('#x');
      return String.fromCharCode(
        int.parse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10),
      );
    }
    return const {
      'lt': '<',
      'gt': '>',
      'amp': '&',
      'quot': '"',
      'apos': "'",
    }[entity]!;
  },
);

String _text(String html) =>
    _unescape(html)
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

String? _tag(String item, String tag) => RegExp(
  '<$tag\\b[^>]*>(.*?)</$tag\\s*>',
  caseSensitive: false,
  dotAll: true,
).firstMatch(item)?[1];

/// Parses the PMO news RSS; returns QP attendances in feed order.
/// Throws [ParlVuFormatException] for a response without an RSS channel.
List<PmQuestionPeriod> parsePmQuestionPeriods(String rssXml) {
  if (!RegExp(
    r'<rss\b[^>]*>.*<channel\b[^>]*>.*</channel\s*>.*</rss\s*>',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(rssXml)) {
    throw ParlVuFormatException('Response is not a PMO RSS feed');
  }
  final attendances = <PmQuestionPeriod>[];
  final titlePattern = RegExp(
    '^(${_weekdays.join('|')}), (${_months.join('|')}) ([1-9]|[12][0-9]|3[01]), ([0-9]{4})\$',
  );
  for (final item in RegExp(
    r'<item\b[^>]*>(.*?)</item\s*>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(rssXml)) {
    final title = titlePattern.firstMatch(
      _unescape(_tag(item[1]!, 'title') ?? ''),
    );
    if (title == null) continue;
    final day = DateTime.utc(
      int.parse(title[4]!),
      _months.indexOf(title[2]!) + 1,
      int.parse(title[3]!),
    );
    if (day.day != int.parse(title[3]!) ||
        _weekdays[day.weekday - 1] != title[1]) {
      continue;
    }
    final description = _unescape(_tag(item[1]!, 'description') ?? '');
    for (final paragraph in RegExp(
      r'<p\b[^>]*>(.*?)</p\s*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(description)) {
      if (!RegExp(
        'will attend Question Period',
        caseSensitive: false,
      ).hasMatch(_text(paragraph[1]!))) {
        continue;
      }
      final published = _text(_tag(paragraph[1]!, 'strong') ?? '');
      final time = RegExp(
        r'^(\d{1,2}):(\d{2}) (a\.m\.|p\.m\.)$',
        caseSensitive: false,
      ).firstMatch(published);
      var hour = day.weekday == DateTime.friday ? 11 : 14;
      var minute = 15;
      var label = day.weekday == DateTime.friday ? '11:15 a.m.' : '2:15 p.m.';
      if (time != null) {
        final clockHour = int.parse(time[1]!);
        minute = int.parse(time[2]!);
        if (clockHour < 1 || clockHour > 12 || minute > 59) {
          throw ParlVuFormatException('Invalid PM Question Period time');
        }
        final suffix = time[3]!.toLowerCase();
        hour = clockHour % 12 + (suffix == 'p.m.' ? 12 : 0);
        label = '$clockHour:${time[2]} $suffix';
      }
      final date = day.toIso8601String().substring(0, 10);
      attendances.add(
        PmQuestionPeriod(
          day: day,
          startsAt: parliamentTime(
            '$date'
            'T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
          ),
          timeLabel: label,
          link: Uri.parse(_unescape(_tag(item[1]!, 'link') ?? '').trim()),
        ),
      );
      break;
    }
  }
  return attendances;
}

class PmItineraryClient {
  PmItineraryClient({http.Client? httpClient, Uri? feedUri})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null,
      _feedUri = feedUri ?? defaultFeed;

  static final Uri defaultFeed = Uri.parse('https://www.pm.gc.ca/en/news.rss');
  static const _agent =
      'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)';
  final http.Client _client;
  final bool _ownsClient;
  final Uri _feedUri;

  /// Fetches the feed; non-200 responses throw [ParlVuFormatException].
  Future<List<PmQuestionPeriod>> questionPeriods() async {
    final response = await _client.get(
      _feedUri,
      headers: {'User-Agent': _agent},
    );
    if (response.statusCode != 200) {
      throw ParlVuFormatException(
        'PMO feed returned HTTP ${response.statusCode}',
      );
    }
    return parsePmQuestionPeriods(response.body);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
