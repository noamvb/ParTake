import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/player/player_screen.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
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
}
