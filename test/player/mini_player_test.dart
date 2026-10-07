import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/app.dart';
import 'package:partake/player/mini_player.dart';
import 'package:partake/player/player_screen.dart';
import 'package:partake/player/player_session.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import '../platform/fake_pip.dart';
import 'audio_variants.dart';
import 'fake_engine.dart';
import 'fake_live_captions.dart';

void main() {
  final date = DateTime.utc(2026, 9, 23);
  ListingEvent row(int id) => ListingEvent(
    id: id,
    foreignKey: null,
    title: 'Session $id',
    description: '',
    location: '',
    scheduledStart: date,
    scheduledEnd: null,
    actualStart: null,
    actualEnd: null,
    status: EventStatus.ended,
    statusCode: -1,
    statusText: '',
  );
  OpenRequest request(int id) => OpenRequest(
    eventId: id,
    title: row(id).title,
    eventDate: date,
    event: row(id),
  );

  late List<FakeEngine> engines;
  late List<PlayerSession> sessions;
  late List<FakePip> pips;
  late StreamController<OpenRequest> requests;

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // Dart's cached cancellation futures use the real zone, while subsequent
    // awaits return to the test clock. Drain both through session teardown.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<void> app(WidgetTester tester) async {
    engines = [];
    sessions = [];
    pips = [];
    requests = StreamController<OpenRequest>();
    final source = FakeEventSource(
      details: {1: audioVideoDetail(id: 1), 2: audioVideoDetail(id: 2)},
      days: {
        date: [row(1), row(2)],
      },
    );
    final library = FakeLibrary();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      for (final session in sessions) {
        unawaited(session.close());
      }
      for (final pip in pips) {
        unawaited(pip.states.close());
      }
      unawaited(requests.close());
      await tester.pump();
    });
    await tester.pumpWidget(
      PartakeApp(
        source: source,
        library: library,
        now: () => date.add(const Duration(hours: 18)),
        openRequests: requests.stream,
        sessionFactory: (request) {
          final engine = FakeEngine();
          engines.add(engine);
          final pip = FakePip(available: true);
          pips.add(pip);
          final session = PlayerSession(
            request: request,
            source: source,
            library: library,
            engineFactory: () => engine,
            liveCaptionsFactory: FakeLiveCaptions.new,
            pip: pip,
            videoBuilder: (_) => const ColoredBox(
              key: Key('session-video'),
              color: Colors.black,
            ),
          );
          sessions.add(session);
          return session;
        },
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Session 1').first);
    await settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byKey(const Key('session-video')), findsOneWidget);
  }

  Future<void> minimize(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Minimize'));
    // During the pop animation the retained route must not mount another video.
    await tester.pump();
    expect(
      find.byKey(const Key('session-video'), skipOffstage: false),
      findsOneWidget,
    );
    await settle(tester);
  }

  testWidgets('case 7 minimize keeps one playing engine on Home', (
    tester,
  ) async {
    await app(tester);
    await minimize(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(engines.single.opened, hasLength(1));
    expect(engines.single.playing, isTrue);
    expect(engines.single.disposed, isFalse);
    final size = tester.getSize(find.byType(MiniPlayer));
    expect(size.width, closeTo(220, .001));
    expect(size.width / size.height, closeTo(16 / 9, .001));
    await tester.tap(find.byTooltip('Pause'));
    await settle(tester);
    expect(engines.single.playing, isFalse);
    await tester.tap(find.byTooltip('Play'));
    await settle(tester);
    expect(engines.single.playing, isTrue);
    // System PiP replaces the shell with exactly one full-window surface.
    pips.single.states.add(true);
    await tester.pump();
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('session-video')), findsOneWidget);
    pips.single.states.add(false);
    await tester.pump();
    expect(find.byType(MiniPlayer), findsOneWidget);
    await sessions.single.controller.setAudioOnly(true);
    await settle(tester);
    expect(pips.single.autoEnterCalls.last, isFalse);
    tester.view.physicalSize = const Size(320, 800);
    await settle(tester);
    final placeholder = find.text(
      'Audio only - keeps playing in the background',
    );
    expect(placeholder, findsOneWidget);
    final textBounds = tester.getRect(placeholder);
    final miniBounds = tester.getRect(find.byType(MiniPlayer));
    expect(textBounds.width, lessThanOrEqualTo(miniBounds.width));
    expect(textBounds.height, lessThanOrEqualTo(miniBounds.height));
  });

  testWidgets('case 8 mini player expands without reopening', (tester) async {
    await app(tester);
    await minimize(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(MiniPlayer),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    expect(find.byType(MiniPlayer), findsNothing);
    expect(
      find.byKey(const Key('session-video'), skipOffstage: false),
      findsOneWidget,
    );
    await settle(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(engines.single.opened, hasLength(1));
    expect(engines.single.playing, isTrue);
  });

  testWidgets('case 9 closing mini player disposes the engine', (tester) async {
    await app(tester);
    await minimize(tester);
    expect(engines.single.disposed, isFalse);
    await tester.tap(find.byTooltip('Close player'));
    await settle(tester);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(engines.single.disposed, isTrue);
    expect(pips.single.autoEnterCalls.last, isFalse);
  });

  testWidgets('case 10 different event replaces and closes session', (
    tester,
  ) async {
    await app(tester);
    await minimize(tester);
    await tester.tap(find.text('Session 2').first);
    await settle(tester);
    expect(engines, hasLength(2));
    expect(engines.first.disposed, isTrue);
    expect(engines.last.opened, hasLength(1));
    expect(
      engines.last.opened.single.url.toString(),
      'https://example.test/2/floor/video.m3u8',
    );
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(MiniPlayer), findsNothing);
  });

  testWidgets('case 11 same event reuses the minimized session', (
    tester,
  ) async {
    await app(tester);
    await minimize(tester);
    requests.add(request(1));
    await settle(tester);
    expect(engines, hasLength(1));
    expect(engines.single.opened, hasLength(1));
    expect(engines.single.disposed, isFalse);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(MiniPlayer), findsNothing);
    // Full-screen close also tears down an injected session.
    await tester.tap(find.byTooltip('Close player'));
    await settle(tester);
    expect(engines.single.disposed, isTrue);
    expect(find.byType(PlayerScreen), findsNothing);
  });

  testWidgets('case 12 system back minimizes rather than closes', (
    tester,
  ) async {
    await app(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(engines.single.disposed, isFalse);
    expect(engines.single.opened, hasLength(1));
    expect(engines.single.playing, isTrue);
  });
}
