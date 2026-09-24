import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/app.dart';
import 'package:partake/ui/open_request.dart';

import 'fakes.dart';

ListingEvent _event(int id, String title, EventStatus status) => ListingEvent(
  id: id,
  foreignKey: null,
  title: title,
  description: '',
  location: 'West Block',
  scheduledStart: DateTime.utc(2026, 9, 23, 18),
  scheduledEnd: DateTime.utc(2026, 9, 23, 23),
  actualStart: DateTime.utc(2026, 9, 23, 18, 1),
  actualEnd: null,
  status: status,
  statusCode: status.code ?? 0,
  statusText: '',
);

void main() {
  final now = DateTime.utc(2026, 9, 23, 18, 30);

  testWidgets('tapping a listed event opens the player route', (tester) async {
    final opened = <OpenRequest>[];
    final source = FakeEventSource(
      days: {
        DateTime.utc(2026, 9, 23): [
          _event(45728, 'HoC Sitting No. 142', EventStatus.live),
        ],
      },
    );
    await tester.pumpWidget(
      PartakeApp(
        source: source,
        library: FakeLibrary(),
        now: () => now,
        playerBuilder: (request) {
          opened.add(request);
          return Scaffold(body: Text('player ${request.eventId}'));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HoC Sitting No. 142').first);
    await tester.pumpAndSettle();

    expect(opened.single.eventId, 45728);
    expect(opened.single.event?.title, 'HoC Sitting No. 142');
    expect(find.text('player 45728'), findsOneWidget);
  });

  testWidgets('an external open request (alert tap) opens the player', (
    tester,
  ) async {
    final requests = StreamController<OpenRequest>();
    await tester.pumpWidget(
      PartakeApp(
        source: FakeEventSource(),
        library: FakeLibrary(),
        now: () => now,
        openRequests: requests.stream,
        playerBuilder: (request) =>
            Scaffold(body: Text('player ${request.eventId}')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('player 45806'), findsNothing);

    requests.add(
      OpenRequest(
        eventId: 45806,
        title: 'Live proceedings',
        eventDate: DateTime.utc(2026, 9, 23),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('player 45806'), findsOneWidget);
    await requests.close();
  });
}
