import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

tz.Location? _ottawa;

tz.Location _location() {
  if (_ottawa == null) {
    tzdata.initializeTimeZones();
    _ottawa = tz.getLocation('America/Toronto');
  }
  return _ottawa!;
}

/// Converts a naive Ottawa wall-clock timestamp to UTC.
///
/// Accepts the shapes ParlVU and openparliament.ca send:
/// `2026-09-23T14:00:00`, `2026-09-23T14:01:29.0000000`,
/// `2026-09-23T16:30:43.712` and `2026-07-07 11:00:00`. Fractional seconds
/// beyond milliseconds are dropped. Throws [FormatException] on anything else.
DateTime parliamentTime(String naive) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?$',
  ).firstMatch(naive.trim());
  if (match == null) {
    throw FormatException('Not a parliament timestamp', naive);
  }
  int part(int i) => int.parse(match.group(i)!);
  final fraction = match.group(7);
  final millis = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0').substring(0, 3));
  return tz.TZDateTime(
    _location(),
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
    millis,
  ).toUtc();
}

/// The Ottawa calendar date (year, month, day at midnight UTC) containing
/// [instant]; used to build ParlVU's `YYYYMMDD` query dates.
DateTime parliamentDate(DateTime instant) {
  final local = tz.TZDateTime.from(instant, _location());
  return DateTime.utc(local.year, local.month, local.day);
}
