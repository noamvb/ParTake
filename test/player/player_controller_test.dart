import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';
import 'package:partake/player/caption_index.dart';
import 'package:partake/player/player_controller.dart';
import 'package:partake/platform/live_captions.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import 'fake_engine.dart';
import 'fake_live_captions.dart';

void main() {
  final detail = parseEventPage(
    File('packages/parlvu/test/fixtures/event_fewo_13596766.html')
        .readAsStringSync(),
    id: 45750,
  );
  final row = ListingEvent(
    id: 45750,
    foreignKey: null,
    title: 'FEWO Meeting',
    description: '',
    location: '',
    scheduledStart: DateTime.utc(2026, 9, 23),
    scheduledEnd: null,
    actualStart: null,
    actualEnd: null,
    status: EventStatus.ended,
    statusCode: -1,
    statusText: '',
  );
  final date = DateTime.utc(2026, 9, 23);
  FakeEventSource source({EventDetail? d, bool includeRow = true}) =>
      FakeEventSource(
        details: {45750: d ?? detail},
        days: {
          date: includeRow ? [row] : [],
        },
      );
  OpenRequest request({ListingEvent? event, Duration? resume}) => OpenRequest(
    eventId: 45750,
    title: row.title,
    eventDate: date,
    event: event,
    resumeAt: resume,
  );
  Future<(PlayerController, FakeLiveCaptions)> openedLive({
    bool captions = true,
  }) async {
    final liveDetail = parseEventPage(
      File('packages/parlvu/test/fixtures/event_live_hoc143_45729.html')
          .readAsStringSync(),
      id: 45729,
    );
    final liveDate = DateTime.utc(2026, 9, 24);
    final liveRow = ListingEvent(
      id: 45729,
      foreignKey: null,
      title: 'HoC Sitting No. 143',
      description: '',
      location: '',
      scheduledStart: liveDate,
      scheduledEnd: null,
      actualStart: null,
      actualEnd: null,
      status: EventStatus.live,
      statusCode: 1,
      statusText: '',
    );
    final feed = FakeLiveCaptions();
    final c = PlayerController(
      source: FakeEventSource(details: {45729: liveDetail}),
      library: FakeLibrary(),
      engine: FakeEngine(),
      liveCaptions: feed,
    );
    await c.open(
      OpenRequest(
        eventId: 45729,
        title: liveRow.title,
        eventDate: liveDate,
        event: liveRow,
      ),
    );
    c.setCaptions(captions);
    return (c, feed);
  }

  Future<(PlayerController, FakeEngine, FakeLibrary, FakeEventSource)> opened({
    AudioLanguage lang = AudioLanguage.floor,
    Duration? resume,
    ListingEvent? event,
    LiveCaptionFeed? liveCaptions,
  }) async {
    final lib = FakeLibrary();
    if (lang != AudioLanguage.floor) {
      await lib.updateSettings(AppSettings(language: lang));
    }
    final eng = FakeEngine();
    final src = source();
    final c = PlayerController(
      source: src,
      library: lib,
      engine: eng,
      liveCaptions: liveCaptions,
    );
    await c.open(request(event: event, resume: resume));
    await Future<void>.delayed(Duration.zero);
    return (c, eng, lib, src);
  }

  test('opens floor with resume and captions enabled', () async {
    final (c, e, _, _) = await opened(resume: const Duration(seconds: 100));
    expect(c.phase, PlayerPhase.ready);
    expect(
      e.opened.single.url,
      c.detail!.preferredStream(AudioLanguage.floor)!.url,
    );
    expect(e.opened.single.start, const Duration(seconds: 100));
    expect(c.captionsOn, true);
    await c.close();
  });
  test('live caption feed drives overlay text and clears it', () async {
    final (c, feed) = await openedLive();
    feed.emit('Honourable Member.');
    await Future<void>.delayed(Duration.zero);
    expect(c.captionText, 'Honourable Member.');
    feed.emit(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.captionText, isNull);
    await c.close();
    feed.dispose();
  });
  test('live caption feed is hidden when captions are off', () async {
    final (c, feed) = await openedLive(captions: false);
    feed.emit('Honourable Member.');
    await Future<void>.delayed(Duration.zero);
    expect(c.captionText, isNull);
    await c.close();
    feed.dispose();
  });
  test(
    'archived caption text comes from page captions instead of feed',
    () async {
      final feed = FakeLiveCaptions();
      final (c, _, _, _) = await opened(liveCaptions: feed);
      final at = c.detail!.offsetOf(
        parliamentTime('2026-09-23T16:30:44'),
        c.stream!,
      );
      await c.seek(at);
      feed.emit('Live feed text');
      await Future<void>.delayed(Duration.zero);
      expect(c.captionText, c.currentCaption?.text);
      await c.close();
      feed.dispose();
    },
  );
  test(
    'Floor captions follow paragraph language at the current wall clock',
    () async {
      final w1 = detail.recordingStart.add(const Duration(seconds: 100));
      final w2 = detail.recordingStart.add(const Duration(seconds: 140));
      Caption cap(DateTime at, String text) => Caption(
        begin: at,
        end: at.add(const Duration(seconds: 5)),
        text: text,
      );
      final customDetail = EventDetail(
        id: detail.id,
        recordingStart: detail.recordingStart,
        streams: detail.streams,
        captions: {
          AudioLanguage.english: [cap(w1, 'English floor line')],
          AudioLanguage.french: [cap(w2, 'Ligne française')],
        },
      );
      Speech speech(AudioLanguage lang, String en, String fr) => Speech(
        bucketTime: w1,
        speaker: 'A',
        politicianUrl: null,
        textEn: en,
        procedural: false,
        url: '/a/',
        paragraphs: [SpeechParagraph(language: lang, textEn: en, textFr: fr)],
      );
      final marks = [
        SpeakerMark(
          speech: speech(AudioLanguage.english, 'english opening', ''),
          wallClock: w1.subtract(const Duration(seconds: 10)),
          source: MarkSource.interpolated,
        ),
        SpeakerMark(
          speech: speech(AudioLanguage.french, '', 'ouverture française'),
          wallClock: w1.add(const Duration(seconds: 10)),
          source: MarkSource.interpolated,
        ),
      ];
      final src = FakeEventSource(
        details: {45750: customDetail},
        speakerMarks: {45750: marks},
      );
      final eng = FakeEngine();
      final c = PlayerController(
        source: src,
        library: FakeLibrary(),
        engine: eng,
      );
      await c.open(request(event: row));
      await Future<void>.delayed(Duration.zero);
      expect(c.floorSwitches.last.language, AudioLanguage.french);
      final stream = c.stream!;
      eng.emitPosition(customDetail.offsetOf(w1, stream));
      await Future<void>.delayed(Duration.zero);
      expect(c.currentCaption!.text, 'English floor line');
      eng.emitPosition(customDetail.offsetOf(w2, stream));
      await Future<void>.delayed(Duration.zero);
      expect(c.currentCaption!.text, 'Ligne française');
      await c.setLanguage(AudioLanguage.english);
      eng.emitPosition(customDetail.offsetOf(w2, c.stream!));
      await Future<void>.delayed(Duration.zero);
      expect(c.currentCaption, isNull);
      await c.close();
    },
  );
  test('opens preferred English video', () async {
    final (c, e, _, _) = await opened(lang: AudioLanguage.english);
    expect(
      e.opened.single.url,
      c.detail!.preferredStream(AudioLanguage.english)!.url,
    );
    await c.close();
  });
  test('looks up listing row then speakers when no row supplied', () async {
    final (c, _, _, s) = await opened();
    expect(s.calls, containsAllInOrder(['day 2026-09-23', 'speakers 45750']));
    expect(c.event!.id, 45750);
    await c.close();
  });
  test(
    'language switch retains position and follows French captions',
    () async {
      final (c, e, _, _) = await opened();
      e.emitPosition(const Duration(seconds: 500));
      await Future<void>.delayed(Duration.zero);
      await c.setLanguage(AudioLanguage.french);
      expect(
        e.opened.last.url,
        c.detail!.preferredStream(AudioLanguage.french)!.url,
      );
      expect(e.opened.last.start, const Duration(seconds: 500));
      final wall = c.detail!.wallClockAt(
        const Duration(seconds: 500),
        c.stream!,
      );
      expect(
        c.currentCaption,
        CaptionIndex(c.detail!.captions[AudioLanguage.french]!).at(wall),
      );
      await c.close();
    },
  );
  test(
    'position updates current caption and caption toggle clears it',
    () async {
      final (c, e, _, _) = await opened();
      final at = c.detail!.offsetOf(
        parliamentTime('2026-09-23T16:30:44'),
        c.stream!,
      );
      e.emitPosition(at);
      await Future<void>.delayed(Duration.zero);
      expect(c.currentCaption!.text, '>> Voice of Interpreter: Welcome');
      c.setCaptions(false);
      expect(c.currentCaption, isNull);
      await c.close();
    },
  );
  test('seekToMark maps wall clock through offsetOf', () async {
    final (c, e, _, _) = await opened();
    final mark = SpeakerMark(
      speech: Speech(
        bucketTime: DateTime.utc(2026),
        speaker: 'A',
        politicianUrl: null,
        textEn: '',
        procedural: false,
        url: '',
      ),
      wallClock: parliamentTime('2026-09-23T17:00:00'),
      source: MarkSource.captionMatch,
    );
    await c.seekToMark(mark);
    expect(e.seeks.single, c.detail!.offsetOf(mark.wallClock, c.stream!));
    await c.close();
  });
  test('search uses current caption language', () async {
    final (c, _, _, _) = await opened();
    expect(c.search('welcome'), isNotEmpty);
    await c.close();
  });
  test(
    'throttles progress and saves again on close with requested date',
    () async {
      var clock = DateTime.utc(2026);
      final lib = _RecordingLibrary();
      final eng = FakeEngine();
      final c = PlayerController(
        source: source(),
        library: lib,
        engine: eng,
        now: () => clock,
      );
      await c.open(request());
      eng.emitPosition(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);
      expect(lib.writes, 0);
      clock = clock.add(const Duration(seconds: 16));
      eng.emitPosition(const Duration(seconds: 26));
      await Future<void>.delayed(Duration.zero);
      expect(lib.writes, 1);
      expect(lib.record(45750)!.position, const Duration(seconds: 26));
      expect(lib.record(45750)!.eventDate, date);
      await c.close();
      expect(lib.writes, 2);
    },
  );
  test(
    'live stream does not save and goLive seeks just short of the edge',
    () async {
      final live = EventDetail(
        id: 1,
        recordingStart: detail.recordingStart,
        streams: [
          for (final s in detail.streams)
            if (s.language == AudioLanguage.floor)
              StreamVariant(
                language: s.language,
                url: s.url,
                tag: s.tag,
                audioOnly: s.audioOnly,
                isLive: true,
                isSd: s.isSd,
                preRoll: s.preRoll,
                duration: null,
                enableCc: s.enableCc,
              ),
        ],
        captions: detail.captions,
      );
      final lib = FakeLibrary();
      final e = FakeEngine();
      final c = PlayerController(
        source: source(d: live),
        library: lib,
        engine: e,
      );
      await c.open(request());
      e.emitDuration(const Duration(seconds: 600));
      e.emitPosition(const Duration(seconds: 550));
      await Future<void>.delayed(Duration.zero);
      expect(c.behindLive, false);
      e.emitPosition(const Duration(seconds: 500));
      await Future<void>.delayed(Duration.zero);
      expect(c.behindLive, true);
      await c.goLive();
      expect(e.seeks.last, const Duration(seconds: 564));
      expect(c.behindLive, false);
      await c.close();
      expect(lib.record(45750), isNull);
    },
  );
  test('detail failure enters error without opening engine', () async {
    final e = FakeEngine();
    final c = PlayerController(
      source: FakeEventSource(),
      library: FakeLibrary(),
      engine: e,
    );
    await c.open(request());
    expect(c.phase, PlayerPhase.error);
    expect(e.opened, isEmpty);
    await c.close();
  });
  test(
    'language switch keeps playing when the new stream opens paused',
    () async {
      final (c, e, _, _) = await opened();
      expect(c.playing, true);
      e.playOnOpen = false;
      final plays = e.plays;
      await c.setLanguage(AudioLanguage.english);
      expect(e.plays, plays + 1);
      expect(e.playing, true);
      await c.close();
    },
  );
  test('language switch while paused stays paused', () async {
    final (c, e, _, _) = await opened();
    await c.togglePlay();
    expect(e.playing, false);
    final pauses = e.pauses;
    await c.setLanguage(AudioLanguage.english);
    expect(e.pauses, pauses + 1);
    expect(e.playing, false);
    await c.close();
  });
  test('rate validation and language reopen preserve selected rate', () async {
    final (c, e, _, _) = await opened();
    await c.setRate(1.5);
    expect(e.rates.last, 1.5);
    expect(() => c.setRate(3), throwsArgumentError);
    await c.setLanguage(AudioLanguage.english);
    expect(e.rates.last, 1.5);
    await c.close();
  });
  test('unavailable requested language adopts floor stream language', () async {
    final only = EventDetail(
      id: 1,
      recordingStart: detail.recordingStart,
      streams: [detail.preferredStream(AudioLanguage.floor)!],
      captions: {},
    );
    final lib = FakeLibrary();
    await lib.updateSettings(const AppSettings(language: AudioLanguage.french));
    final e = FakeEngine();
    final c = PlayerController(
      source: source(d: only),
      library: lib,
      engine: e,
    );
    await c.open(request());
    expect(c.language, AudioLanguage.floor);
    expect(e.opened.single.url, only.streams.single.url);
    await c.close();
  });
}

class _RecordingLibrary extends FakeLibrary {
  int writes = 0;
  @override
  Future<void> saveProgress(WatchRecord record) async {
    writes++;
    await super.saveProgress(record);
  }
}
