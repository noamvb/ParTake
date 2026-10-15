import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/pm/pm_client.dart';
import 'package:partake/ui/pm_screen.dart';

Map<String, dynamic> _seam(String name) =>
    jsonDecode(File('test/pm/${name}_seam.json').readAsStringSync());
DateTime _clock() => DateTime.utc(2026, 7, 15, 11);
PmClient _client(List<Uri> urls, {bool empty = false}) => PmClient(
  address: Uri.parse('http://deck.test'),
  client: MockClient((r) async {
    urls.add(r.url);
    final name = r.url.path.contains('/items/')
        ? 'item'
        : r.url.path.split('/').last;
    final data = _seam(name);
    if (empty && name == 'today') data['days'] = [];
    if (name == 'feed') {
      if (r.url.queryParameters['type'] != null) {
        data['items'] = (data['items'] as List)
            .where((e) => e['type'] == r.url.queryParameters['type'])
            .toList();
      }
      if (r.url.queryParameters['before'] != null) {
        data['next'] = null;
        data['items'] = [
          {...data['items'][0], 'title': 'Second page'},
        ];
      }
    }
    return http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
  }),
);
Future<void> _show(WidgetTester tester, PmClient client) async {
  addTearDown(client.close);
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PmScreen(pm: client, now: _clock, showTiles: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('9 Today renders now next and both days', (tester) async {
    await _show(tester, _client([]));
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('No public event right now'), findsOneWidget);
    expect(find.text('08:00 Ottawa'), findsWidgets);
    expect(find.text('Today · 2026-07-15'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tomorrow · 2026-07-16'), 300);
    expect(find.text('Tomorrow · 2026-07-16'), findsOneWidget);
  });
  testWidgets('10 Today empty itinerary message', (tester) async {
    await _show(tester, _client([], empty: true));
    expect(
      find.text(
        'No itinerary published yet. The PMO posts tomorrow\'s around 5 p.m.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('11 Feed filters paginates and opens Deck item', (tester) async {
    final urls = <Uri>[];
    await _show(tester, _client(urls));
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Readouts'));
    await tester.pumpAndSettle();
    expect(urls.any((u) => u.queryParameters['type'] == 'readout'), isTrue);
    await tester.drag(
      find.byKey(const ValueKey('pm-feed-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(
      urls.any(
        (u) =>
            u.queryParameters['before'] == 'c1' &&
            u.queryParameters['type'] == 'readout',
      ),
      isTrue,
    );
    expect(find.text('Second page'), findsOneWidget);
    await tester.tap(
      find.text('Prime Minister speaks with President of Guyana'),
    );
    await tester.pumpAndSettle();
    expect(urls.last.path, '/watch/api/pm/items/readouts/2026/10/14/x');
    expect(find.text('Open on pm.gc.ca'), findsOneWidget);
    expect(find.text('First paragraph.'), findsOneWidget);
    expect(find.text('Second paragraph.'), findsOneWidget);
  });
  testWidgets('12 Visits maps geocoded places and opens counts', (
    tester,
  ) async {
    await _show(tester, _client([]));
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(1),
    );
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('Not on map: Unknown place'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pm-place-paris-france')));
    await tester.pumpAndSettle();
    expect(find.text('14 visits · 9 days'), findsOneWidget);
    expect(find.text('First: 2025-03-21 · Last: 2026-07-15'), findsOneWidget);
  });
  testWidgets('13 Week requests prior Monday through Sunday', (tester) async {
    final urls = <Uri>[];
    await _show(tester, _client(urls));
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );
    expect(urls.last.queryParameters, {
      'since': '2026-07-13',
      'until': '2026-07-19',
    });
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single
          .points,
      hasLength(2),
    );
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(urls.last.queryParameters, {
      'since': '2026-07-06',
      'until': '2026-07-12',
    });
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNotNull,
    );

    final snapshot = PmClient.snapshot(
      base: Uri.parse('https://test/snap/'),
      client: MockClient(
        (r) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(_seam(r.url.path.split('/').last.split('.').first)),
          ),
          200,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _show(tester, snapshot);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed,
      isNull,
    );
  });
}
