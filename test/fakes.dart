import 'package:flutter/foundation.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';

/// In-memory [Library] for widget and unit tests.
class FakeLibrary extends ChangeNotifier implements Library {
  final Set<String> _follows = {};
  final Map<int, WatchRecord> _records = {};
  AppSettings _settings = const AppSettings();

  @override
  Set<String> get follows => Set.unmodifiable(_follows);

  @override
  Future<void> setFollowed(String key, bool followed) async {
    followed ? _follows.add(key) : _follows.remove(key);
    notifyListeners();
  }

  @override
  List<WatchRecord> get continueWatching {
    final open = _records.values.where((r) => !r.finished).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return open.take(20).toList();
  }

  @override
  WatchRecord? record(int eventId) => _records[eventId];

  @override
  Future<void> saveProgress(WatchRecord record) async {
    _records[record.eventId] = record;
    notifyListeners();
  }

  @override
  AppSettings get settings => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
  }
}

/// [EventSource] serving fixed data. Unknown ids throw [StateError].
class FakeEventSource implements EventSource {
  FakeEventSource({
    Map<DateTime, List<ListingEvent>>? days,
    Map<int, EventDetail>? details,
    Map<int, List<SpeakerMark>>? speakerMarks,
  }) : days = days ?? {},
       details = details ?? {},
       speakerMarks = speakerMarks ?? {};

  final Map<DateTime, List<ListingEvent>> days;
  final Map<int, EventDetail> details;
  final Map<int, List<SpeakerMark>> speakerMarks;

  /// Every call, in order, e.g. `day 2026-09-23`, `detail 45728`.
  final List<String> calls = [];

  @override
  Future<List<ListingEvent>> day(
    DateTime ottawaDate, {
    bool refresh = false,
  }) async {
    calls.add('day ${ottawaDate.toIso8601String().substring(0, 10)}');
    return days[ottawaDate] ?? const [];
  }

  @override
  Future<List<ListingEvent>> liveNow({bool refresh = false}) async {
    calls.add('liveNow');
    return [
      for (final list in days.values)
        for (final e in list)
          if (e.status == EventStatus.live || e.status == EventStatus.paused) e,
    ];
  }

  @override
  Future<EventDetail> detail(int id, {bool refresh = false}) async {
    calls.add('detail $id');
    return details[id] ?? (throw StateError('no detail $id'));
  }

  @override
  Future<List<SpeakerMark>> speakers(
    ListingEvent event,
    EventDetail detail,
  ) async {
    calls.add('speakers ${event.id}');
    return speakerMarks[event.id] ?? const [];
  }
}
