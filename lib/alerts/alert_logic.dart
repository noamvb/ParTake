import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';

class AlarmPlan {
  const AlarmPlan({
    required this.eventId,
    required this.title,
    required this.at,
  });

  final int eventId;
  final String title;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is AlarmPlan &&
      eventId == other.eventId &&
      title == other.title &&
      at == other.at;

  @override
  int get hashCode => Object.hash(eventId, title, at);
}

List<AlarmPlan> planAlarms(
  List<ListingEvent> events,
  Set<String> follows,
  DateTime now,
) {
  final horizon = now.add(const Duration(hours: 36));
  return [
    for (final event in events)
      if (follows.contains(followKeyOf(event)) &&
          event.status == EventStatus.notStarted &&
          event.scheduledStart.isAfter(now) &&
          !event.scheduledStart.isAfter(horizon))
        AlarmPlan(
          eventId: event.id,
          title: event.title,
          at: event.scheduledStart.toUtc(),
        ),
  ];
}

List<ListingEvent> liveToNotify(
  List<ListingEvent> events,
  Set<String> follows,
  Set<int> notified,
) => [
  for (final event in events)
    if (follows.contains(followKeyOf(event)) &&
        (event.status == EventStatus.live ||
            event.status == EventStatus.paused) &&
        !notified.contains(event.id))
      event,
];

sealed class CheckOutcome {}

class NotifyLive extends CheckOutcome {
  NotifyLive(this.event);
  final ListingEvent event;
}

class CheckAgain extends CheckOutcome {
  CheckAgain(this.at);
  final DateTime at;
}

class StopChecking extends CheckOutcome {
  StopChecking(this.reason);
  final String reason;
}

CheckOutcome decideCheck({
  required ListingEvent? row,
  required DateTime scheduledStart,
  required DateTime now,
  required bool alreadyNotified,
}) {
  if (alreadyNotified) return StopChecking('already notified');
  if (row == null) return StopChecking('not in listing');
  if (row.status == EventStatus.live || row.status == EventStatus.paused) {
    return NotifyLive(row);
  }
  if (row.status == EventStatus.cancelled ||
      row.status == EventStatus.inCamera ||
      row.status == EventStatus.ended) {
    return StopChecking(row.status.name);
  }
  if (!now.isBefore(scheduledStart.add(const Duration(minutes: 60)))) {
    return StopChecking('gave up after 60 minutes');
  }
  return CheckAgain(now.add(const Duration(minutes: 2)));
}
