/// Shared value types for ParlVU and openparliament.ca data.
///
/// Every [DateTime] in this package is UTC. ParlVU and openparliament.ca both
/// publish naive Ottawa wall-clock times; convert them with [parliamentTime]
/// (see time.dart) and never with [DateTime.parse] alone.
library;

/// Status of a ParlVU event, from the listing's `EntityStatus` integer.
///
/// Codes come from ParlVU's own `getEventStatusClass` script (research run
/// 20260923-213446-agy-64907).
enum EventStatus {
  notStarted(0),
  live(1),
  paused(2),
  ended(-1),
  cancelled(-3),
  opened(-4),
  inCamera(101),
  unknown(null);

  const EventStatus(this.code);

  /// The `EntityStatus` value ParlVU sends, or null for [unknown].
  final int? code;

  static EventStatus fromCode(int code) => EventStatus.values.firstWhere(
    (s) => s.code == code,
    orElse: () => EventStatus.unknown,
  );
}

/// One row of ParlVU's day listing (`GetListViewData`).
class ListingEvent {
  const ListingEvent({
    required this.id,
    required this.foreignKey,
    required this.title,
    required this.description,
    required this.location,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.actualStart,
    required this.actualEnd,
    required this.status,
    required this.statusCode,
    required this.statusText,
  });

  /// ParlVU content-entity id (`Id`). Always present; opens the event page
  /// through `/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/{id}`.
  final int id;

  /// Legacy event page id (`ForeignKey`, the `fk=` parameter). Often null.
  final String? foreignKey;

  /// e.g. `HoC Sitting No. 142`, `FEWO Meeting No. 47`, `HESA Meeting No. 35-2`.
  final String title;
  final String description;
  final String location;
  final DateTime scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final EventStatus status;

  /// Raw `EntityStatus`, kept so an unrecognised code is still visible.
  final int statusCode;

  /// Raw `EntityStatusDesc`, e.g. `Adjourned`.
  final String statusText;

  /// True for House of Commons chamber sittings (`HoC Sitting No. N`).
  bool get isChamber => title.startsWith('HoC ');

  /// Committee acronym from the title (`FEWO`), or null for the chamber.
  String? get committeeCode {
    if (isChamber) return null;
    final match = RegExp(r'^([A-Z]{3,5}) ').firstMatch(title);
    return match?.group(1);
  }

  /// Meeting or sitting number from the title (`47` in `FEWO Meeting No. 47`,
  /// `35` in `HESA Meeting No. 35-2`), or null when the title has none.
  int? get number {
    final match = RegExp(r'No\. (\d+)').firstMatch(title);
    return match == null ? null : int.parse(match.group(1)!);
  }
}

/// Which audio a stream carries.
enum AudioLanguage {
  floor('fl'),
  english('en'),
  french('fr');

  const AudioLanguage(this.code);

  /// ParlVU's `Lang` value.
  final String code;

  static AudioLanguage? fromCode(String code) {
    for (final l in AudioLanguage.values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// One entry of an event page's `availableStreams`.
class StreamVariant {
  const StreamVariant({
    required this.language,
    required this.url,
    required this.tag,
    required this.audioOnly,
    required this.isLive,
    required this.isSd,
    required this.preRoll,
    required this.duration,
    required this.enableCc,
  });

  final AudioLanguage language;

  /// HLS master playlist URL.
  final Uri url;

  /// ParlVU's label, e.g. `Floor Video`, `English Video SD`, `French Audio`.
  final String tag;
  final bool audioOnly;
  final bool isLive;

  /// True when [tag] ends in ` SD`.
  final bool isSd;

  /// `PreRoll`: how long the media file runs before the recorded start.
  final Duration preRoll;

  /// `Duration` in whole seconds, or null when ParlVU sends none (live).
  final Duration? duration;
  final bool enableCc;
}

/// One closed-caption line (`ccItems`). Times are UTC.
class Caption {
  const Caption({required this.begin, required this.end, required this.text});

  final DateTime begin;
  final DateTime end;

  /// Caption text with surrounding whitespace trimmed.
  final String text;
}

/// Everything the player needs from one ParlVU event page.
class EventDetail {
  const EventDetail({
    required this.id,
    required this.recordingStart,
    required this.streams,
    required this.captions,
  });

  final int id;

  /// `EventInfo.timeTags.STARTTIME.timestamp`, in UTC.
  final DateTime recordingStart;
  final List<StreamVariant> streams;

  /// Captions keyed by language; only [AudioLanguage.english] and
  /// [AudioLanguage.french] ever appear. Empty map when ParlVU has none.
  final Map<AudioLanguage, List<Caption>> captions;

  /// Position in [stream]'s media for a wall-clock instant.
  ///
  /// The media file starts `PreRoll` before the recorded start, so
  /// offset = wallClock - recordingStart + preRoll. Verified on 2026-09-23:
  /// file names carry the file start (`..._16-30-09_VL.mp4`) and STARTTIME
  /// was 16:30:39 with PreRoll 30.
  Duration offsetOf(DateTime wallClock, StreamVariant stream) =>
      wallClock.difference(recordingStart) + stream.preRoll;

  /// The inverse of [offsetOf].
  DateTime wallClockAt(Duration offset, StreamVariant stream) =>
      recordingStart.add(offset - stream.preRoll);

  /// The best stream for [language]: video before audio-only, HD before SD.
  /// Falls back to the floor language, then to any stream. Null only when
  /// [streams] is empty.
  StreamVariant? preferredStream(AudioLanguage language) {
    int rank(StreamVariant s) => (s.audioOnly ? 2 : 0) + (s.isSd ? 1 : 0);
    for (final lang in [language, AudioLanguage.floor]) {
      final candidates = streams.where((s) => s.language == lang).toList()
        ..sort((a, b) => rank(a).compareTo(rank(b)));
      if (candidates.isNotEmpty) return candidates.first;
    }
    return streams.isEmpty ? null : streams.first;
  }
}

/// One speech from openparliament.ca.
class Speech {
  const Speech({
    required this.bucketTime,
    required this.speaker,
    required this.politicianUrl,
    required this.textEn,
    required this.procedural,
    required this.url,
  });

  /// The speech's `time`, UTC. openparliament.ca publishes Hansard's
  /// 5-minute markers here, so this is the start of a 5-minute bucket, not
  /// the moment the speech began.
  final DateTime bucketTime;

  /// `attribution.en`, e.g. `The Chair (John Brassard (Barrie South—Innisfil, CPC))`.
  final String speaker;

  /// e.g. `/politicians/john-brassard/`, or null for unattributed speeches.
  final String? politicianUrl;

  /// `content.en` with HTML tags removed and entities decoded.
  final String textEn;
  final bool procedural;

  /// openparliament.ca path of the speech, e.g. `/committees/ethics/45-1/49/the-chair-1/`.
  final String url;
}

/// How a [SpeakerMark]'s time was found.
enum MarkSource {
  /// The speech's opening words were found in the captions.
  captionMatch,

  /// No caption match; the time was spread through the 5-minute bucket.
  interpolated,
}

/// A speech placed on the event's wall clock, ready to become a seek target.
class SpeakerMark {
  const SpeakerMark({
    required this.speech,
    required this.wallClock,
    required this.source,
  });

  final Speech speech;

  /// UTC instant the speech starts; feed to [EventDetail.offsetOf].
  final DateTime wallClock;
  final MarkSource source;
}

/// Thrown when a ParlVU or openparliament.ca response no longer has the shape
/// this package expects. The app must surface it, never swallow it: it is the
/// signal that the site changed and the scraper needs updating.
class ParlVuFormatException implements Exception {
  ParlVuFormatException(this.message, {this.snippet});

  final String message;

  /// Up to 200 characters of the offending input, for diagnosis.
  final String? snippet;

  @override
  String toString() => snippet == null
      ? 'ParlVuFormatException: $message'
      : 'ParlVuFormatException: $message (near: $snippet)';
}
