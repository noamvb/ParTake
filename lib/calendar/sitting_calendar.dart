import 'package:http/http.dart' as http;
import 'package:parlvu/parlvu.dart';

/// Ottawa calendar dates, represented as UTC midnights.
Set<DateTime> parseSittingDays(String html) {
  final days = <DateTime>{};
  for (final cell in RegExp(
    r'<td\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html)) {
    final classes = RegExp(
      r'''\bclass\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(cell.group(0)!)?.group(1)?.split(RegExp(r'\s+'));
    if (classes == null || !classes.contains('chamber-meeting')) continue;
    for (final token in classes) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(token)) continue;
      final date = DateTime.tryParse('${token}T00:00:00Z');
      if (date != null && date.toIso8601String().startsWith(token)) {
        days.add(date);
      }
    }
  }
  return days;
}

class SittingCalendarException implements Exception {
  SittingCalendarException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'SittingCalendarException: HTTP $statusCode';
}

class SittingCalendarClient {
  SittingCalendarClient({
    Uri? baseUri,
    http.Client? client,
    DateTime Function()? now,
  }) : _base = baseUri ?? Uri.parse('https://www.ourcommons.ca/en/'),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final Uri _base;
  final http.Client _client;
  final DateTime Function() _now;
  final _cache = <int, ({DateTime fetchedAt, Set<DateTime> days})>{};
  final _pending = <int, Future<Set<DateTime>>>{};

  Future<Set<DateTime>> year(int year) {
    final pending = _pending[year];
    if (pending != null) return pending;
    final cached = _cache[year];
    if (cached != null &&
        (year < parliamentDate(_now()).year ||
            _now().difference(cached.fetchedAt) < const Duration(hours: 12))) {
      return Future.value(cached.days);
    }
    final future = _fetch(year);
    _pending[year] = future;
    return future;
  }

  Future<Set<DateTime>> _fetch(int year) async {
    try {
      final response = await _client.get(
        _base.resolve('sitting-calendar/$year'),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SittingCalendarException(response.statusCode);
      }
      final days = Set<DateTime>.unmodifiable(parseSittingDays(response.body));
      _cache[year] = (fetchedAt: _now(), days: days);
      return days;
    } finally {
      _pending.remove(year);
    }
  }
}

bool isBreakWeek(DateTime monday, Set<DateTime> sittingDays) {
  final start = DateTime.utc(monday.year, monday.month, monday.day);
  return !List.generate(
    5,
    (i) => start.add(Duration(days: i)),
  ).any(sittingDays.contains);
}

DateTime? nextSittingDay(DateTime from, Set<DateTime> sittingDays) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final later = sittingDays.where((day) => !day.isBefore(start)).toList()
    ..sort();
  return later.isEmpty ? null : later.first;
}

const calendarMonths = [
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
const calendarWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
