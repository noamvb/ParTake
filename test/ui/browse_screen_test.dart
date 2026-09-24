import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/ui/browse_screen.dart';
import 'package:partake/ui/event_tile.dart';

import '../fakes.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 18, 30);

ListingEvent _event({
  required int id,
  required String title,
  EventStatus status = EventStatus.ended,
}) => ListingEvent(
  id: id,
  foreignKey: null,
  title: title,
  description: '',
  location: 'Room 415',
  scheduledStart: DateTime.utc(2026, 9, 23, 17, 0),
  scheduledEnd: null,
  actualStart: null,
  actualEnd: null,
  status: status,
  statusCode: status.code ?? 999,
  statusText: '',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'starts at today; Next day and Previous day change the fetched date',
    (tester) async {
      final source = FakeEventSource();
      final library = FakeLibrary();

      await tester.pumpWidget(
        _wrap(
          BrowseScreen(
            source: source,
            library: library,
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.calls, contains('day 2026-09-23'));

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(source.calls, contains('day 2026-09-24'));

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(source.calls, contains('day 2026-09-22'));
    },
  );

  testWidgets('filter chips narrow the list by chamber/committee/following', (
    tester,
  ) async {
    final chamber = _event(id: 1, title: 'HoC Sitting No. 1');
    final committee1 = _event(id: 2, title: 'FEWO Meeting No. 1');
    final committee2 = _event(id: 3, title: 'ETHI Meeting No. 1');
    final source = FakeEventSource(
      days: {
        DateTime.utc(2026, 9, 23): [chamber, committee1, committee2],
      },
    );
    final library = FakeLibrary();

    await tester.pumpWidget(
      _wrap(
        BrowseScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chamber'));
    await tester.pumpAndSettle();
    expect(find.byType(EventTile), findsOneWidget);
    expect(find.text(chamber.title), findsOneWidget);

    await tester.tap(find.text('Committees'));
    await tester.pumpAndSettle();
    expect(find.byType(EventTile), findsNWidgets(2));

    final followingLibrary = FakeLibrary();
    await followingLibrary.setFollowed('FEWO', true);
    await tester.pumpWidget(
      _wrap(
        BrowseScreen(
          source: source,
          library: followingLibrary,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.byType(EventTile), findsOneWidget);
    expect(find.text(committee1.title), findsOneWidget);
  });

  testWidgets('empty day shows the no-proceedings message', (tester) async {
    final source = FakeEventSource();
    final library = FakeLibrary();

    await tester.pumpWidget(
      _wrap(
        BrowseScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No proceedings on this day.'), findsOneWidget);
  });
}
