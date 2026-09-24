import 'package:flutter/foundation.dart';
import 'package:parlvu/parlvu.dart';

/// Follow key for an event: `HOC` for the chamber (sittings and Question
/// Period), otherwise the committee acronym (`FEWO`). Events with neither
/// (rare, e.g. special joint sessions) fall back to their title.
String followKeyOf(ListingEvent event) =>
    event.isChamber ? 'HOC' : (event.committeeCode ?? event.title);

/// Where the viewer left off in one event. Stored per device only.
@immutable
class WatchRecord {
  const WatchRecord({
    required this.eventId,
    required this.title,
    required this.eventDate,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final int eventId;
  final String title;

  /// The event's Ottawa calendar date (UTC midnight, as from
  /// `parliamentDate`), so the player can find its listing row with
  /// `EventSource.day(eventDate)`.
  final DateTime eventDate;
  final Duration position;

  /// Null for live events.
  final Duration? duration;
  final DateTime updatedAt;

  /// True once within the last 2 minutes or past 95% of [duration].
  bool get finished {
    final total = duration;
    if (total == null || total == Duration.zero) return false;
    return position >= total * 0.95 ||
        total - position <= const Duration(minutes: 2);
  }

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'title': title,
    'eventDate': eventDate.toUtc().toIso8601String().substring(0, 10),
    'positionMs': position.inMilliseconds,
    'durationMs': duration?.inMilliseconds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static WatchRecord fromJson(Map<String, Object?> json) => WatchRecord(
    eventId: json['eventId']! as int,
    title: json['title']! as String,
    eventDate: DateTime.parse('${json['eventDate']! as String}T00:00:00Z'),
    position: Duration(milliseconds: json['positionMs']! as int),
    duration: json['durationMs'] == null
        ? null
        : Duration(milliseconds: json['durationMs']! as int),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );
}

/// Viewer preferences. Defaults are the decisions in docs/design.md.
@immutable
class AppSettings {
  const AppSettings({
    this.language = AudioLanguage.floor,
    this.captions = true,
  });

  /// Audio played by default when an event opens.
  final AudioLanguage language;

  /// Captions shown by default.
  final bool captions;

  AppSettings copyWith({AudioLanguage? language, bool? captions}) =>
      AppSettings(
        language: language ?? this.language,
        captions: captions ?? this.captions,
      );
}

/// Everything the app remembers on this device: follows, watch history and
/// settings. Listeners are notified after every change.
abstract class Library implements Listenable {
  Set<String> get follows;
  Future<void> setFollowed(String key, bool followed);

  /// Unfinished records, most recently updated first, at most 20.
  List<WatchRecord> get continueWatching;
  WatchRecord? record(int eventId);
  Future<void> saveProgress(WatchRecord record);

  AppSettings get settings;
  Future<void> updateSettings(AppSettings settings);
}

/// Read access to ParlVU and openparliament.ca for the UI. Implementations
/// cache; `refresh: true` bypasses the cache. Errors from the parlvu package
/// (`ParlVuFormatException`, HTTP exceptions) propagate unchanged so the UI
/// can show them.
abstract class EventSource {
  /// Events on one Ottawa calendar day (a UTC-midnight DateTime as produced
  /// by `parliamentDate`), in ParlVU's order.
  Future<List<ListingEvent>> day(DateTime ottawaDate, {bool refresh = false});

  /// Today's events whose status is live or paused.
  Future<List<ListingEvent>> liveNow({bool refresh = false});

  Future<EventDetail> detail(int id, {bool refresh = false});

  /// Speaker marks for an event: Hansard speeches aligned to the English
  /// captions (all interpolated when there are none). Empty when Hansard is
  /// not yet published. For a Question Period clip, only the marks inside the
  /// clip's actual start and end.
  Future<List<SpeakerMark>> speakers(ListingEvent event, EventDetail detail);
}
