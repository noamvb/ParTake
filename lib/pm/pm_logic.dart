import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'pm_models.dart';

tz.Location? _ottawa;
tz.Location _location() {
  if (_ottawa == null) {
    tzdata.initializeTimeZones();
    _ottawa = tz.getLocation('America/Toronto');
  }
  return _ottawa!;
}

/// Ottawa's date, represented as midnight UTC for date-only comparisons.
DateTime ottawaDate(DateTime instant) {
  final local = tz.TZDateTime.from(instant, _location());
  return DateTime.utc(local.year, local.month, local.day);
}

class PmNowAndNext {
  const PmNowAndNext(this.now, this.next);
  final PmNow now;
  final PmEvent? next;
}

/// Recomputes the marker using the current clock, including stale snapshots.
PmNowAndNext nowAndNext(PmToday today, DateTime nowUtc) {
  final date = ottawaDate(nowUtc).toIso8601String().substring(0, 10);
  final events =
      today.days
          .expand((d) => d.events)
          .where((e) => e.startsAt != null)
          .toList()
        ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  PmEvent? current, next;
  for (final event in events) {
    if (event.startsAt!.isAfter(nowUtc)) {
      next ??= event;
    } else if (event.date == date) {
      current = event;
    }
  }
  Place? fallback;
  final days =
      today.days
          .where((d) => d.date.compareTo(date) <= 0 && d.events.isNotEmpty)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  // Before today's first event, retain the previous itinerary's last place.
  final previous = days.where((d) => d.date.compareTo(date) < 0).toList();
  if (previous.isNotEmpty) {
    fallback = previous.last.events.last.place;
  } else if (today.now.event != null &&
      today.now.event!.date.compareTo(date) < 0) {
    fallback = today.now.place;
  } else if (days.isNotEmpty) {
    fallback = days.last.events.last.place;
  } else {
    fallback = today.now.place;
  }
  return PmNowAndNext(
    PmNow(place: current?.place ?? fallback, event: current),
    next,
  );
}

String? ottawaLabel(PmEvent event) {
  if (event.startsAt == null || event.place.zone == 'America/Toronto') {
    return null;
  }
  final local = tz.TZDateTime.from(event.startsAt!, _location());
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} Ottawa';
}
