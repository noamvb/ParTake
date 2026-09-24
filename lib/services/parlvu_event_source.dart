import 'package:parlvu/parlvu.dart';

import '../core/library.dart';

class ParlVuEventSource implements EventSource {
  ParlVuEventSource({
    required this.parlvu,
    required this.openParliament,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ParlVuClient parlvu;
  final OpenParliamentClient openParliament;
  final DateTime Function() _now;
  final Map<
    DateTime,
    ({
      DateTime fetchedAt,
      Future<List<ListingEvent>> future,
      List<ListingEvent>? value,
    })
  >
  _days = {};
  final Map<
    int,
    ({DateTime fetchedAt, Future<EventDetail> future, EventDetail? value})
  >
  _details = {};
  final Map<
    int,
    ({
      DateTime fetchedAt,
      Future<List<SpeakerMark>> future,
      List<SpeakerMark>? value,
    })
  >
  _speakers = {};

  @override
  Future<List<ListingEvent>> day(
    DateTime ottawaDate, {
    bool refresh = false,
  }) async {
    final date = DateTime.utc(
      ottawaDate.year,
      ottawaDate.month,
      ottawaDate.day,
    );
    final existing = _days[date];
    final today = parliamentDate(_now());
    final ttl = date.isBefore(today)
        ? null
        : date == today
        ? const Duration(seconds: 60)
        : const Duration(minutes: 10);
    if (!refresh &&
        existing != null &&
        (existing.value == null ||
            ttl == null ||
            _now().difference(existing.fetchedAt) < ttl)) {
      return existing.value ?? await existing.future;
    }
    final future = parlvu.eventsBetween(date, date);
    final entry = (
      fetchedAt: _now(),
      future: future,
      value: null as List<ListingEvent>?,
    );
    _days[date] = entry;
    try {
      final value = await future;
      _days[date] = (fetchedAt: entry.fetchedAt, future: future, value: value);
      return value;
    } catch (_) {
      if (identical(_days[date], entry)) _days.remove(date);
      rethrow;
    }
  }

  @override
  Future<List<ListingEvent>> liveNow({bool refresh = false}) async =>
      (await day(parliamentDate(_now()), refresh: refresh))
          .where(
            (e) =>
                e.status == EventStatus.live || e.status == EventStatus.paused,
          )
          .toList();

  @override
  Future<EventDetail> detail(int id, {bool refresh = false}) async {
    final old = _details[id];
    if (!refresh &&
        old != null &&
        (old.value == null ||
            !old.value!.streams.any((s) => s.isLive) ||
            _now().difference(old.fetchedAt) < const Duration(seconds: 30))) {
      return old.value ?? await old.future;
    }
    final future = parlvu.eventDetail(id);
    final entry = (
      fetchedAt: _now(),
      future: future,
      value: null as EventDetail?,
    );
    _details[id] = entry;
    try {
      final value = await future;
      _details[id] = (fetchedAt: entry.fetchedAt, future: future, value: value);
      return value;
    } catch (_) {
      if (identical(_details[id], entry)) _details.remove(id);
      rethrow;
    }
  }

  @override
  Future<List<SpeakerMark>> speakers(
    ListingEvent event,
    EventDetail detail,
  ) async {
    final old = _speakers[event.id];
    if (old != null &&
        (_now().difference(old.fetchedAt) < const Duration(minutes: 30) ||
            old.value?.isNotEmpty == true)) {
      return old.value ?? await old.future;
    }
    final future = _loadSpeakers(event, detail);
    final entry = (
      fetchedAt: _now(),
      future: future,
      value: null as List<SpeakerMark>?,
    );
    _speakers[event.id] = entry;
    try {
      final value = await future;
      _speakers[event.id] = (
        fetchedAt: entry.fetchedAt,
        future: future,
        value: value,
      );
      return value;
    } catch (_) {
      if (identical(_speakers[event.id], entry)) _speakers.remove(event.id);
      rethrow;
    }
  }

  Future<List<SpeakerMark>> _loadSpeakers(
    ListingEvent event,
    EventDetail detail,
  ) async {
    final date = parliamentDate(event.actualStart ?? event.scheduledStart);
    List<Speech> speeches;
    if (event.isChamber) {
      speeches = await openParliament.houseDebate(date);
    } else if (event.committeeCode != null && event.number != null) {
      speeches = await openParliament.committeeMeeting(
        acronym: event.committeeCode!,
        ottawaDate: date,
        number: event.number!,
      );
    } else {
      return [];
    }
    if (speeches.isEmpty) return [];
    var marks = alignSpeeches(
      speeches,
      detail.captions[AudioLanguage.english] ?? const [],
    );
    if (event.isQuestionPeriod) {
      marks = marks
          .where(
            (m) =>
                (event.actualStart == null ||
                    !m.wallClock.isBefore(event.actualStart!)) &&
                (event.actualEnd == null ||
                    !m.wallClock.isAfter(event.actualEnd!)),
          )
          .toList();
    }
    return marks;
  }
}
