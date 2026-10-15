import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/calendar/sitting_calendar.dart';
import 'package:partake/services/parlvu_event_source.dart';
import 'package:partake/ui/browse_screen.dart';
import 'package:partake/ui/event_tile.dart';
import 'package:partake/ui/home_screen.dart';

import '../fakes.dart';

final _today = DateTime.utc(2026, 10, 14, 16);
String _fixture() =>
    File('test/calendar/sitting_calendar_2026.html').readAsStringSync();
SittingCalendarClient _calendar({int status = 200}) => SittingCalendarClient(
  now: () => _today,
  client: MockClient((_) async => http.Response(_fixture(), status)),
);
ListingEvent _event() => ListingEvent(
  id: 1,
  foreignKey: null,
  title: 'FEWO Meeting No. 1',
  description: '',
  location: '',
  scheduledStart: DateTime.utc(2026, 10, 20, 16),
  scheduledEnd: null,
  actualStart: null,
  actualEnd: null,
  status: EventStatus.ended,
  statusCode: -1,
  statusText: '',
);
Widget _browse(
  FakeEventSource source, {
  FakeLibrary? library,
  SittingCalendarClient? calendar,
  DateTime? now,
}) => MaterialApp(
  home: Scaffold(
    body: BrowseScreen(
      source: source,
      library: library ?? FakeLibrary(),
      onOpen: (_) {},
      now: () => now ?? _today,
      calendar: calendar ?? _calendar(),
    ),
  ),
);
Finder _cell(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

class _RangeClient extends ParlVuClient {
  final calls = <(DateTime, DateTime, bool)>[];
  @override
  Future<List<ListingEvent>> eventsBetween(
    DateTime fromDay,
    DateTime toDay, {
    bool includeUpcoming = false,
  }) async {
    calls.add((fromDay, toDay, includeUpcoming));
    return [];
  }
}

void main() {
  test('1 fixture sitting days', () {
    final days = parseSittingDays(_fixture());
    expect(days, hasLength(112));
    expect(days, contains(DateTime.utc(2026, 10, 19)));
    expect(days, isNot(contains(DateTime.utc(2026, 10, 14))));
    final sorted = days.toList()..sort();
    expect(sorted.first, DateTime.utc(2026, 1, 26));
    expect(sorted.last, DateTime.utc(2026, 12, 11));
    expect(
      parseSittingDays(
        '<td data-x="a" class="extra 2026-10-19 chamber-meeting extra">',
      ),
      {DateTime.utc(2026, 10, 19)},
    );
  });
  test('2 break weeks and next sitting day', () {
    final days = parseSittingDays(_fixture());
    expect(isBreakWeek(DateTime.utc(2026, 10, 12), days), isTrue);
    expect(isBreakWeek(DateTime.utc(2026, 10, 19), days), isFalse);
    expect(
      nextSittingDay(DateTime.utc(2026, 10, 14), days),
      DateTime.utc(2026, 10, 19),
    );
    expect(nextSittingDay(DateTime.utc(2026, 12, 12), days), isNull);
  });
  test('3 client URL cache expiry concurrency and errors', () async {
    var now = _today;
    final urls = <Uri>[];
    final pending = Completer<http.Response>();
    final calendar = SittingCalendarClient(
      baseUri: Uri.parse('https://example.org/base/'),
      now: () => now,
      client: MockClient((r) async {
        urls.add(r.url);
        return urls.length == 1
            ? pending.future
            : http.Response(_fixture(), 200);
      }),
    );
    final a = calendar.year(2026), b = calendar.year(2026);
    await Future<void>.delayed(Duration.zero);
    expect(
      urls.single.toString(),
      'https://example.org/base/sitting-calendar/2026',
    );
    pending.complete(http.Response(_fixture(), 200));
    await Future.wait([a, b]);
    await calendar.year(2026);
    expect(urls, hasLength(1));
    await calendar.year(2025);
    now = now.add(const Duration(hours: 13));
    await calendar.year(2025);
    expect(urls, hasLength(2));
    await calendar.year(2026);
    expect(urls, hasLength(3));
    await expectLater(
      _calendar(status: 500).year(2026),
      throwsA(
        isA<SittingCalendarException>().having(
          (e) => e.statusCode,
          'status',
          500,
        ),
      ),
    );
  });
  testWidgets('4 Browse sitting semantics break caption and status', (
    tester,
  ) async {
    await tester.pumpWidget(_browse(FakeEventSource()));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(_cell('Monday 19 October, sitting day'), findsOneWidget);
    expect(find.byKey(const ValueKey('break-caption')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-status')),
        matching: find.text('House not sitting'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
  });
  testWidgets('5 Browse selection month navigation and upper bound', (
    tester,
  ) async {
    final source = FakeEventSource();
    await tester.pumpWidget(_browse(source));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Monday 19 October, sitting day'));
    await tester.pumpAndSettle();
    expect(source.calls, contains('day 2026-10-19'));
    expect(find.text('Sitting day'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    for (var i = 0; i < 13; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    expect(find.text('December 2027'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Next month',
            ),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('6 Browse followed markers and no-follow range suppression', (
    tester,
  ) async {
    final library = FakeLibrary();
    await library.setFollowed('FEWO', true);
    final source = FakeEventSource(
      days: {
        DateTime.utc(2026, 10, 20): [_event()],
      },
    );
    await tester.pumpWidget(_browse(source, library: library));
    await tester.pumpAndSettle();
    expect(source.calls.where((s) => s.startsWith('range')), [
      'range 2026-09-28 2026-11-08',
    ]);
    expect(_cell('Tuesday 20 October, sitting day, followed'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(source.calls.where((s) => s.startsWith('range')), hasLength(1));
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(source.calls.where((s) => s.startsWith('range')), hasLength(1));
    expect(_cell('Tuesday 20 October, sitting day, followed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final empty = FakeEventSource();
    await tester.pumpWidget(_browse(empty));
    await tester.pumpAndSettle();
    expect(empty.calls.where((s) => s.startsWith('range')), isEmpty);
  });
  testWidgets('7 Browse calendar failure preserves events', (tester) async {
    final source = FakeEventSource(
      days: {
        DateTime.utc(2026, 10, 14): [_event()],
      },
    );
    var fail = true;
    final calendar = SittingCalendarClient(
      now: () => _today,
      client: MockClient(
        (_) async => http.Response(_fixture(), fail ? 500 : 200),
      ),
    );
    await tester.pumpWidget(_browse(source, calendar: calendar));
    await tester.pumpAndSettle();
    expect(find.text('Sitting calendar unavailable'), findsOneWidget);
    expect(find.text('FEWO Meeting No. 1'), findsOneWidget);
    expect(find.text('House not sitting'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Sitting calendar unavailable'), findsNothing);
    expect(_cell('Monday 19 October, sitting day'), findsOneWidget);
    final unknown = SittingCalendarClient(
      client: MockClient((_) async => http.Response('', 200)),
    );
    await tester.pumpWidget(_browse(source, calendar: unknown));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-status')), findsNothing);
    expect(find.byKey(const ValueKey('break-caption')), findsNothing);
    expect(_cell('Monday 19 October'), findsOneWidget);
  });
  testWidgets('8 Browse narrow and wide layout', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    final source = FakeEventSource(
      days: {
        DateTime.utc(2026, 10, 14): [_event()],
      },
    );
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpWidget(_browse(source));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(EventTile)).left,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('month-grid'))).right,
      ),
    );
  });
  testWidgets('9 Home break notice and sitting week', (tester) async {
    Widget home(DateTime now) => MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          source: FakeEventSource(),
          library: FakeLibrary(),
          onOpen: (_) {},
          now: () => now,
          calendar: _calendar(),
        ),
      ),
    );
    await tester.pumpWidget(home(_today));
    await tester.pumpAndSettle();
    expect(find.text('House not sitting · returns Mon 19 Oct'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(home(DateTime.utc(2026, 10, 20, 16)));
    await tester.pumpAndSettle();
    expect(find.textContaining('House not sitting'), findsNothing);
  });
  test('10 range requests inclusive days upcoming and cache', () async {
    final client = _RangeClient();
    var now = _today;
    final source = ParlVuEventSource(
      parlvu: client,
      openParliament: OpenParliamentClient(),
      now: () => now,
    );
    final from = DateTime.utc(2026, 9, 28), to = DateTime.utc(2026, 11, 8);
    await source.range(from, to);
    await source.range(from, to);
    await source.range(from, to);
    expect(client.calls, [(from, to, true)]);
    now = now.add(const Duration(minutes: 11));
    await source.range(from, to);
    expect(client.calls, hasLength(2));
    final today = DateTime.utc(2026, 10, 14);
    await source.range(from, today);
    expect(client.calls.last, (from, today, true));
    await source.range(from, DateTime.utc(2026, 10, 13));
    expect(client.calls.last.$3, isFalse);
  });
}
