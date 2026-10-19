import 'dart:async';

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import 'fake_engine.dart';
import 'audio_variants.dart';

import 'package:partake/player/player_session.dart';

import 'package:partake/player/player_screen.dart';

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
  Widget app(FakeEngine engine, {List<SpeakerMark> marks = const []}) {
    final date = DateTime.utc(2026, 9, 23);
    final src = FakeEventSource(
      details: {45750: detail},
      days: {
        date: [row],
      },
      speakerMarks: {45750: marks},
    );
    return MaterialApp(
      home: PlayerScreen(
        key: ValueKey(marks.isEmpty ? 'empty-speakers' : 'speaker-marks'),
        request: OpenRequest(
          eventId: 45750,
          title: row.title,
          eventDate: date,
          event: row,
        ),
        source: src,
        library: FakeLibrary(),
        engineFactory: () => engine,
        videoBuilder: (_) => const ColoredBox(color: Colors.black),
      ),
    );
  }

  test(
    'no live caption factory by default, so natively segments are decoded',
    () {
      final screen = PlayerScreen(
        request: OpenRequest(
          eventId: 45750,
          title: row.title,
          eventDate: DateTime.utc(2026, 9, 23),
        ),
        source: FakeEventSource(),
        library: FakeLibrary(),
      );
      expect(screen.liveCaptionsFactory, isNull);
    },
  );
  testWidgets('hold fast long press shows pill and release restores rate', (
    tester,
  ) async {
    final e = FakeEngine();
    await tester.pumpWidget(app(e));
    await tester.pumpAndSettle();
    final video = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == Colors.black,
    );
    final gesture = await tester.startGesture(tester.getCenter(video));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('hold-fast-pill')), findsOneWidget);
    expect(e.rates.last, 2.0);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('hold-fast-pill')), findsNothing);
    expect(e.rates.last, 1.0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('hold fast short tap leaves rate and pill unchanged', (
    tester,
  ) async {
    final e = FakeEngine();
    await tester.pumpWidget(app(e));
    await tester.pumpAndSettle();
    final video = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == Colors.black,
    );
    final rates = List<double>.of(e.rates);
    await tester.tap(video);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('hold-fast-pill')), findsNothing);
    expect(e.rates, rates);
    // Positive control: this video actually responds to a held gesture.
    final gesture = await tester.startGesture(tester.getCenter(video));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('hold-fast-pill')), findsOneWidget);
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('responsive layout places panel below and beside video', (
    tester,
  ) async {
    final e = FakeEngine();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(e));
    await tester.pumpAndSettle();
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    final video = tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == Colors.black,
          ),
        )
        .dx;
    final speakers = tester.getTopLeft(find.text('Speakers')).dx;
    expect(speakers, lessThan(80));
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expect(tester.getTopLeft(find.text('Speakers')).dx, greaterThan(video));
    tester.view.resetPhysicalSize();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('language menu offers present languages and switches stream', (
    tester,
  ) async {
    final e = FakeEngine();
    await tester.pumpWidget(app(e));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Audio language'));
    await tester.pumpAndSettle();
    expect(find.text('Floor'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(
      e.opened.last.url,
      detail.preferredStream(AudioLanguage.english)!.url,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'speaker rows show names and approximate marker; empty state explains Hansard',
    (tester) async {
      final marks = [
        for (var i = 0; i < 2; i++)
          SpeakerMark(
            speech: Speech(
              bucketTime: DateTime.utc(2026),
              speaker: 'Speaker $i (Role)',
              politicianUrl: null,
              textEn: '',
              procedural: false,
              url: '',
            ),
            wallClock: DateTime.utc(2026, 9, 23, 17, i),
            source: i == 0 ? MarkSource.captionMatch : MarkSource.interpolated,
          ),
      ];
      await tester.pumpWidget(app(FakeEngine()));
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.textContaining('Speaker list appears once Hansard is published'),
        findsOneWidget,
      );
      final e = FakeEngine();
      await tester.pumpWidget(app(e, marks: marks));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Speaker 0'), findsOneWidget);
      expect(find.text('Speaker 1'), findsOneWidget);
      expect(find.textContaining('~'), findsOneWidget);
      await tester.tap(find.text('Speaker 0'));
      await tester.pump();
      expect(e.seeks, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('caption shortcut toggles and search hit seeks', (tester) async {
    final e = FakeEngine();
    await tester.pumpWidget(app(e));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Captions on'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(find.byTooltip('Captions off'), findsOneWidget);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search captions',
      ),
      'welcome',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome'), findsWidgets);
    await tester.tap(find.textContaining('Welcome').last);
    await tester.pump();
    expect(e.seeks, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('live controls stay put when Go live appears', (tester) async {
    final live = parseEventPage(
      File('packages/parlvu/test/fixtures/event_live_hoc143_45729.html')
          .readAsStringSync(),
      id: 45729,
    );
    final date = DateTime.utc(2026, 9, 24);
    final liveRow = ListingEvent(
      id: 45729,
      foreignKey: null,
      title: 'HoC Sitting No. 143',
      description: '',
      location: '',
      scheduledStart: date,
      scheduledEnd: null,
      actualStart: null,
      actualEnd: null,
      status: EventStatus.live,
      statusCode: 1,
      statusText: '',
    );
    final e = FakeEngine();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          request: OpenRequest(
            eventId: 45729,
            title: liveRow.title,
            eventDate: date,
            event: liveRow,
          ),
          source: FakeEventSource(
            details: {45729: live},
            days: {
              date: [liveRow],
            },
          ),
          library: FakeLibrary(),
          engineFactory: () => e,
          videoBuilder: (_) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    e.emitDuration(const Duration(seconds: 600));
    e.emitPosition(const Duration(seconds: 595));
    await tester.pump();
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Go live').hitTestable(), findsNothing);
    final back = tester.getTopLeft(find.byTooltip('Back 30 seconds'));
    e.emitPosition(const Duration(seconds: 500));
    await tester.pump();
    await tester.pump();
    expect(find.text('Go live').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.byTooltip('Back 30 seconds')), back);
    await tester.tap(find.text('Go live'));
    await tester.pump();
    expect(e.seeks.last, const Duration(seconds: 564));
    tester.view.resetPhysicalSize();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'live captions display and live caption search explains availability',
    (tester) async {
      final live = parseEventPage(
        File('packages/parlvu/test/fixtures/event_live_hoc143_45729.html')
            .readAsStringSync(),
        id: 45729,
      );
      final date = DateTime.utc(2026, 9, 24);
      final liveRow = ListingEvent(
        id: 45729,
        foreignKey: null,
        title: 'HoC Sitting No. 143',
        description: '',
        location: '',
        scheduledStart: date,
        scheduledEnd: null,
        actualStart: null,
        actualEnd: null,
        status: EventStatus.live,
        statusCode: 1,
        statusText: '',
      );
      final feed = FakeLiveCaptions();
      final e = FakeEngine();
      final library = FakeLibrary();
      await library.updateSettings(
        const AppSettings(language: AudioLanguage.english),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            request: OpenRequest(
              eventId: 45729,
              title: liveRow.title,
              eventDate: date,
              event: liveRow,
            ),
            source: FakeEventSource(
              details: {45729: live},
              days: {
                date: [liveRow],
              },
            ),
            library: library,
            engineFactory: () => e,
            liveCaptionsFactory: () => feed,
            videoBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(feed.followed, isNotEmpty);
      expect(feed.followed.last?.toString(), contains('/VL/EN/Playlist.m3u8'));
      await tester.tap(find.byTooltip('Audio language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floor').last);
      await tester.pumpAndSettle();
      expect(feed.followed.last, isNull);
      feed.emit('Honourable Member.');
      await tester.pump();
      await tester.pump();
      expect(find.text('Honourable Member.'), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(
        find.text('Caption search is available once the sitting is archived.'),
        findsOneWidget,
      );
      expect(
        find.text('Live captions come with English or French audio.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      feed.dispose();
    },
  );
  Future<void> closeSession(WidgetTester tester, PlayerSession session) async {
    final closing = session.close();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await closing;
  }

  Future<PlayerSession> audioSession({bool audio = true}) async =>
      PlayerSession(
        request: OpenRequest(
          eventId: 45750,
          title: row.title,
          eventDate: row.scheduledStart,
          event: row,
        ),
        source: FakeEventSource(
          details: {45750: audioVideoDetail(audio: audio)},
        ),
        library: FakeLibrary(),
        engineFactory: FakeEngine.new,
        liveCaptionsFactory: FakeLiveCaptions.new,
        videoBuilder: (_) => const ColoredBox(color: Colors.black),
      );

  testWidgets(
    'case 5 background audio button shows placeholder and show video',
    (tester) async {
      final session = await audioSession();
      addTearDown(() {
        unawaited(session.close());
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            request: session.request,
            source: session.controller.source,
            library: session.controller.library,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Background audio'), findsOneWidget);
      await tester.tap(find.byTooltip('Background audio'));
      await tester.pumpAndSettle();
      expect(
        find.text('Audio only - keeps playing in the background'),
        findsOneWidget,
      );
      expect(find.byTooltip('Show video'), findsOneWidget);
      expect(session.controller.audioOnly, isTrue);
      await tester.tap(find.byTooltip('Show video'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Background audio'), findsOneWidget);
      expect(session.controller.audioOnly, isFalse);
      await tester.pumpWidget(const SizedBox());
      await closeSession(tester, session);
    },
  );

  testWidgets('case 6 background audio button absent without audio variant', (
    tester,
  ) async {
    final session = await audioSession(audio: false);
    addTearDown(() {
      unawaited(session.close());
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          request: session.request,
          source: session.controller.source,
          library: session.controller.library,
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Positive control: the ready player controls are mounted.
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Background audio'), findsNothing);
    expect(find.byTooltip('Show video'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await closeSession(tester, session);
  });

  testWidgets('an event that has not started says so, not a format error', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 10, 19, 18, 0);
    final upcoming = ListingEvent(
      id: 45900,
      foreignKey: null,
      title: 'HoC Sitting No. 150',
      description: '',
      location: '',
      scheduledStart: start,
      scheduledEnd: null,
      actualStart: null,
      actualEnd: null,
      status: EventStatus.notStarted,
      statusCode: 0,
      statusText: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          request: OpenRequest(
            eventId: upcoming.id,
            title: upcoming.title,
            eventDate: DateTime.utc(2026, 10, 19),
            event: upcoming,
          ),
          source: _NotStartedSource(),
          library: FakeLibrary(),
          engineFactory: FakeEngine.new,
          videoBuilder: (_) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final local = start.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(
      find.text(
        "This hasn't started yet. "
        'Scheduled for ${two(local.hour)}:${two(local.minute)}.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ParlVuFormatException'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}

class _NotStartedSource extends FakeEventSource {
  @override
  Future<EventDetail> detail(int id, {bool refresh = false}) async =>
      throw const EventNotStartedException();
}
