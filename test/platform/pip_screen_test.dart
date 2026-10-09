import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/platform/pip.dart';
import 'package:partake/player/player_screen.dart';
import 'package:partake/player/player_session.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import '../player/audio_variants.dart';
import '../player/fake_engine.dart';
import 'fake_pip.dart';

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

  final audioOnly = EventDetail(
    id: detail.id,
    recordingStart: detail.recordingStart,
    streams: [
      for (final s in detail.streams)
        StreamVariant(
          language: s.language,
          url: s.url,
          tag: s.tag,
          audioOnly: true,
          isLive: s.isLive,
          isSd: s.isSd,
          preRoll: s.preRoll,
          duration: s.duration,
          enableCc: s.enableCc,
        ),
    ],
    captions: detail.captions,
  );

  Widget app(FakePip pip, FakeEngine engine, {EventDetail? event}) =>
      MaterialApp(
        home: PlayerScreen(
          request: OpenRequest(
            eventId: 45750,
            title: row.title,
            eventDate: DateTime.utc(2026, 9, 23),
            event: row,
          ),
          source: FakeEventSource(
            details: {45750: event ?? detail},
            days: {
              DateTime.utc(2026, 9, 23): [row],
            },
          ),
          library: FakeLibrary(),
          engineFactory: () => engine,
          videoBuilder: (_) => const SizedBox(key: Key('player-video')),
          pip: pip,
        ),
      );

  testWidgets('PiP button visibility and enter action follow availability', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    await tester.pumpWidget(app(pip, FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Picture in picture'), findsOneWidget);
    await tester.tap(find.byTooltip('Picture in picture'));
    expect(pip.enterCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await tester.pumpWidget(app(FakePip(available: false), FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Picture in picture'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PiP mode hides controls and panel while preserving video', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    await tester.pumpWidget(app(pip, FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    pip.states.add(true);
    await tester.pump();
    expect(find.byKey(const Key('player-video')), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Speakers'), findsNothing);
    expect(find.byTooltip('Back 10 seconds'), findsNothing);
    pip.states.add(false);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto enter follows playing and is cancelled on dispose', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    await tester.pumpWidget(app(pip, FakeEngine()));
    await tester.pumpAndSettle();
    expect(pip.autoEnterCalls, contains(true));
    await tester.pumpWidget(const SizedBox());
    expect(pip.autoEnterCalls.last, false);
  });

  testWidgets('auto enter stays off while an audio-only stream plays', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioOnly));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    expect(pip.autoEnterCalls, isNot(contains(true)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'PiP headphones keeps the current stream and only hides the picture',
    (tester) async {
      final pip = FakePip(available: true);
      final engine = FakeEngine();
      await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
      await tester.pumpAndSettle();
      final session =
          (tester.state(find.byType(PlayerScreen)) as dynamic).session
              as PlayerSession;
      expect(engine.playing, isTrue);
      final opened = engine.opened.length;
      pip.states.add(true);
      pip.actionsController.add(PipAction.audioOnly);
      await tester.pumpAndSettle();
      expect(pip.closeWindowCalls, 1);
      expect(session.controller.audioOnly, isTrue);
      expect(engine.opened.length, opened);
      expect(engine.opened.last.url.path, endsWith('/video.m3u8'));
      expect(engine.playing, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Show video after PiP headphones uncovers without reopening', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
    await tester.pumpAndSettle();
    final session =
        (tester.state(find.byType(PlayerScreen)) as dynamic).session
            as PlayerSession;
    final opened = engine.opened.length;
    pip.actionsController.add(PipAction.audioOnly);
    await tester.pumpAndSettle();
    expect(session.controller.audioOnly, isTrue);
    await session.controller.setAudioOnly(false);
    expect(session.controller.audioOnly, isFalse);
    expect(engine.opened.length, opened);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PiP play/pause action toggles playback', (tester) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    pip.actionsController.add(PipAction.playPause);
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);
    pip.actionsController.add(PipAction.playPause);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dismissing the PiP window pauses playback', (tester) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    pip.actionsController.add(PipAction.dismissed);
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);
    expect(pip.closeWindowCalls, 0);
    pip.actionsController.add(PipAction.dismissed);
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PiP window is told when playback pauses and resumes', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
    await tester.pumpAndSettle();
    expect(pip.setPlayingCalls.last, isTrue);
    pip.actionsController.add(PipAction.playPause);
    await tester.pumpAndSettle();
    expect(pip.setPlayingCalls.last, isFalse);
    pip.actionsController.add(PipAction.playPause);
    await tester.pumpAndSettle();
    expect(pip.setPlayingCalls.last, isTrue);
    for (var i = 1; i < pip.setPlayingCalls.length; i++) {
      expect(pip.setPlayingCalls[i], isNot(pip.setPlayingCalls[i - 1]));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PiP actions are ignored after the player closes', (
    tester,
  ) async {
    final pip = FakePip(available: true);
    final engine = FakeEngine();
    await tester.pumpWidget(app(pip, engine, event: audioVideoDetail()));
    await tester.pumpAndSettle();
    expect(pip.actionsController.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    for (final action in PipAction.values) {
      pip.actionsController.add(action);
    }
    await tester.pumpAndSettle();
    expect(pip.closeWindowCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
