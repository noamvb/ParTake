import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/ui/event_tile.dart';

ListingEvent _event({
  int id = 1,
  String title = 'FEWO Meeting No. 47',
  String location = 'Room 415',
  EventStatus status = EventStatus.live,
  String statusText = '',
  DateTime? scheduledStart,
  DateTime? scheduledEnd,
  DateTime? actualStart,
  DateTime? actualEnd,
}) => ListingEvent(
  id: id,
  foreignKey: null,
  title: title,
  description: '',
  location: location,
  scheduledStart: scheduledStart ?? DateTime.utc(2026, 9, 23, 18, 0),
  scheduledEnd: scheduledEnd,
  actualStart: actualStart,
  actualEnd: actualEnd,
  status: status,
  statusCode: status.code ?? 999,
  statusText: statusText,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _tileFor(EventStatus status) => _wrap(
  EventTile(
    event: _event(status: status),
    followed: false,
    onTap: () {},
    onToggleFollow: () {},
  ),
);

void main() {
  testWidgets('status chips: exact text per status, none for ended', (
    tester,
  ) async {
    await tester.pumpWidget(_tileFor(EventStatus.live));
    expect(find.text('LIVE'), findsOneWidget);

    await tester.pumpWidget(_tileFor(EventStatus.paused));
    expect(find.text('Paused'), findsOneWidget);

    await tester.pumpWidget(_tileFor(EventStatus.notStarted));
    expect(find.text('Upcoming'), findsOneWidget);

    await tester.pumpWidget(_tileFor(EventStatus.cancelled));
    expect(find.text('Cancelled'), findsOneWidget);

    await tester.pumpWidget(_tileFor(EventStatus.inCamera));
    expect(find.text('In camera'), findsOneWidget);

    await tester.pumpWidget(_tileFor(EventStatus.ended));
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('Paused'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
    expect(find.text('In camera'), findsNothing);
  });

  testWidgets(
    'tapping a cancelled tile does not call onTap; a live tile does',
    (tester) async {
      var cancelledTaps = 0;
      var liveTaps = 0;

      await tester.pumpWidget(
        _wrap(
          EventTile(
            event: _event(status: EventStatus.cancelled),
            followed: false,
            onTap: () => cancelledTaps++,
            onToggleFollow: () {},
          ),
        ),
      );
      await tester.tap(find.byType(EventTile));
      await tester.pump();
      expect(cancelledTaps, 0);

      await tester.pumpWidget(
        _wrap(
          EventTile(
            event: _event(status: EventStatus.live),
            followed: false,
            onTap: () => liveTaps++,
            onToggleFollow: () {},
          ),
        ),
      );
      await tester.tap(find.byType(EventTile));
      await tester.pump();
      expect(liveTaps, 1);
    },
  );

  testWidgets('follow star tooltip toggles and calls onToggleFollow', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      _wrap(
        EventTile(
          event: _event(),
          followed: false,
          onTap: () {},
          onToggleFollow: () => toggles++,
        ),
      ),
    );
    expect(find.byTooltip('Follow'), findsOneWidget);
    expect(find.byTooltip('Unfollow'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        EventTile(
          event: _event(),
          followed: true,
          onTap: () {},
          onToggleFollow: () => toggles++,
        ),
      ),
    );
    expect(find.byTooltip('Unfollow'), findsOneWidget);
    expect(find.byTooltip('Follow'), findsNothing);

    await tester.tap(find.byTooltip('Unfollow'));
    await tester.pump();
    expect(toggles, 1);
  });
}
