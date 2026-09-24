import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import 'fake_engine.dart';

import 'package:partake/player/player_screen.dart';

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
}
