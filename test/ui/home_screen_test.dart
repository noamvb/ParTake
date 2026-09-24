import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/core/library.dart';
import 'package:partake/ui/event_tile.dart';
import 'package:partake/ui/home_screen.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 18, 30);
final DateTime _today = parliamentDate(_clock());

ListingEvent _event({
  required int id,
  required String title,
  String location = 'Room 415',
  EventStatus status = EventStatus.ended,
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
  scheduledStart: scheduledStart ?? DateTime.utc(2026, 9, 23, 17, 0),
  scheduledEnd: scheduledEnd,
  actualStart: actualStart,
  actualEnd: actualEnd,
  status: status,
  statusCode: status.code ?? 999,
  statusText: '',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// [EventSource] whose [day] always throws.
class _ThrowingDaySource implements EventSource {
  _ThrowingDaySource(this.inner);
  final FakeEventSource inner;
  int dayCalls = 0;

  @override
  Future<List<ListingEvent>> day(
    DateTime ottawaDate, {
    bool refresh = false,
  }) async {
    dayCalls++;
    throw ParlVuFormatException('Weeks must be a list');
  }

  @override
  Future<List<ListingEvent>> liveNow({bool refresh = false}) =>
      inner.liveNow(refresh: refresh);

  @override
  Future<EventDetail> detail(int id, {bool refresh = false}) =>
      inner.detail(id, refresh: refresh);

  @override
  Future<List<SpeakerMark>> speakers(ListingEvent event, EventDetail detail) =>
      inner.speakers(event, detail);
}

void main() {
  testWidgets('Live now appears before Today when a live event exists today', (
    tester,
  ) async {
    final live = _event(
      id: 1,
      title: 'HoC Sitting No. 142',
      status: EventStatus.live,
      actualStart: DateTime.utc(2026, 9, 23, 17, 0),
    );
    final ended1 = _event(id: 2, title: 'FEWO Meeting No. 1');
    final ended2 = _event(id: 3, title: 'ETHI Meeting No. 1');
    final source = FakeEventSource(
      days: {
        _today: [live, ended1, ended2],
      },
    );
    final library = FakeLibrary();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live now'), findsOneWidget);
    expect(find.text(live.title), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Live now')).dy,
      lessThan(tester.getTopLeft(find.text('Today')).dy),
    );
  });

  testWidgets('Live now header is absent with no live events', (tester) async {
    final ended1 = _event(id: 2, title: 'FEWO Meeting No. 1');
    final ended2 = _event(id: 3, title: 'ETHI Meeting No. 1');
    final source = FakeEventSource(
      days: {
        _today: [ended1, ended2],
      },
    );
    final library = FakeLibrary();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live now'), findsNothing);
  });

  testWidgets(
    'Continue watching shows only the unfinished record with formatted resume time',
    (tester) async {
      final source = FakeEventSource();
      final library = FakeLibrary();
      final finished = WatchRecord(
        eventId: 10,
        title: 'Finished Meeting',
        eventDate: _today,
        position: const Duration(hours: 2),
        duration: const Duration(hours: 2),
        updatedAt: _clock(),
      );
      final open = WatchRecord(
        eventId: 20,
        title: 'Open Meeting',
        eventDate: _today,
        position: const Duration(hours: 1, minutes: 2, seconds: 3),
        duration: const Duration(hours: 3),
        updatedAt: _clock(),
      );
      await library.saveProgress(finished);
      await library.saveProgress(open);

      OpenRequest? opened;
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            source: source,
            library: library,
            onOpen: (r) => opened = r,
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.text('Resume at 1:02:03'), findsOneWidget);
      expect(find.text(finished.title), findsNothing);

      await tester.tap(find.text('Resume at 1:02:03'));
      await tester.pump();

      expect(opened, isNotNull);
      expect(opened!.eventId, 20);
      expect(
        opened!.resumeAt,
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    },
  );

  testWidgets('followed events sort first, preserving order within groups', (
    tester,
  ) async {
    final a = _event(id: 1, title: 'FEWO Meeting No. 1');
    final b = _event(id: 2, title: 'HoC Sitting No. 1');
    final c = _event(id: 3, title: 'ETHI Meeting No. 1');
    final source = FakeEventSource(
      days: {
        _today: [a, b, c],
      },
    );
    final library = FakeLibrary();
    await library.setFollowed('ETHI', true);

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cY = tester.getTopLeft(find.text(c.title)).dy;
    final aY = tester.getTopLeft(find.text(a.title)).dy;
    final bY = tester.getTopLeft(find.text(b.title)).dy;
    expect(cY, lessThan(aY));
    expect(aY, lessThan(bY));
  });

  testWidgets(
    'tapping a Today event calls onOpen with event and resumeAt set',
    (tester) async {
      final e = _event(
        id: 42,
        title: 'FEWO Meeting No. 1',
        status: EventStatus.notStarted,
      );
      final source = FakeEventSource(
        days: {
          _today: [e],
        },
      );
      final library = FakeLibrary();
      await library.saveProgress(
        WatchRecord(
          eventId: 42,
          title: e.title,
          eventDate: _today,
          position: const Duration(minutes: 5),
          duration: null,
          updatedAt: _clock(),
        ),
      );

      OpenRequest? opened;
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            source: source,
            library: library,
            onOpen: (r) => opened = r,
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EventTile));
      await tester.pump();

      expect(opened, isNotNull);
      expect(opened!.eventId, 42);
      expect(opened!.event, same(e));
      expect(opened!.resumeAt, const Duration(minutes: 5));
    },
  );

  testWidgets('starring an event calls library.setFollowed', (tester) async {
    final e = _event(id: 1, title: 'FEWO Meeting No. 1');
    final source = FakeEventSource(
      days: {
        _today: [e],
      },
    );
    final library = FakeLibrary();

    await tester.pumpWidget(
      _wrap(
        HomeScreen(
          source: source,
          library: library,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Follow'));
    await tester.pump();

    expect(library.follows, contains('FEWO'));
  });

  testWidgets(
    'ParlVuFormatException shows the format-change message and retry refetches',
    (tester) async {
      final source = _ThrowingDaySource(FakeEventSource());
      final library = FakeLibrary();

      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            source: source,
            library: library,
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('ParlVU changed its page format. ParTake needs an update.'),
        findsOneWidget,
      );
      expect(find.text('Weeks must be a list'), findsOneWidget);
      expect(source.dayCalls, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(source.dayCalls, 2);
    },
  );

  testWidgets(
    'periodic refresh polls liveNow only while something is live or upcoming',
    (tester) async {
      final live = _event(
        id: 1,
        title: 'HoC Sitting No. 142',
        status: EventStatus.live,
        actualStart: DateTime.utc(2026, 9, 23, 17, 0),
      );
      final liveSource = FakeEventSource(
        days: {
          _today: [live],
        },
      );
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            key: const ValueKey('live-scenario'),
            source: liveSource,
            library: FakeLibrary(),
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final liveCallsBefore = liveSource.calls
          .where((c) => c == 'liveNow')
          .length;

      await tester.pump(const Duration(seconds: 61));
      await tester.pump();

      final liveCallsAfter = liveSource.calls
          .where((c) => c == 'liveNow')
          .length;
      expect(liveCallsAfter, greaterThan(liveCallsBefore));

      final ended = _event(id: 2, title: 'FEWO Meeting No. 1');
      final endedSource = FakeEventSource(
        days: {
          _today: [ended],
        },
      );
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            key: const ValueKey('ended-scenario'),
            source: endedSource,
            library: FakeLibrary(),
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final endedCallsBefore = endedSource.calls
          .where((c) => c == 'liveNow')
          .length;

      await tester.pump(const Duration(seconds: 61));
      await tester.pump();

      final endedCallsAfter = endedSource.calls
          .where((c) => c == 'liveNow')
          .length;
      expect(endedCallsAfter, endedCallsBefore);
    },
  );
}
