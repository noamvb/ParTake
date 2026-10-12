import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/polls/polls_client.dart';
import 'package:partake/ui/polls_screen.dart';
import 'package:partake/ui/riding_screen.dart';

import '../polls/polls_seams.dart';

PollsClient _client({
  Map<String, dynamic>? summary,
  Map<String, dynamic>? ridings,
  int summaryStatus = 200,
  int leadersStatus = 200,
  List<Uri>? requests,
}) => PollsClient(
  address: Uri.parse('http://deck.test'),
  client: MockClient((r) async {
    requests?.add(r.url);
    final path = r.url.path.split('/').last;
    final status = path == 'summary'
        ? summaryStatus
        : path == 'leaders'
        ? leadersStatus
        : 200;
    if (status != 200) return http.Response('{"error":"Unavailable"}', status);
    final data = switch (path) {
      'summary' => summary ?? pollsSeam('summary'),
      'leaders' => pollsSeam('leaders'),
      'list' => pollsSeam('list'),
      'ridings' => ridings ?? pollsSeam('ridings'),
      _ => pollsSeam('riding'),
    };
    if (path == 'list' && r.url.queryParameters['before'] != null) {
      data['next'] = null;
      data['polls'][0]['firm'] = 'Second page firm';
      data['polls'][0]['id'] = 'second-page';
    }
    return http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void _size(WidgetTester tester, Size size, double ratio) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (number, label, size, ratio) in [
    (3, 'cover', const Size(1080, 2400), 3.0),
    (4, 'inner', const Size(1800, 2000), 2.25),
  ]) {
    testWidgets('$number. Seats and charts fit the $label screen', (
      tester,
    ) async {
      _size(tester, size, ratio);
      final client = _client();
      addTearDown(client.close);
      await _show(tester, PollsScreen(polls: client));
      expect(find.text('Projection, Mon 12 Oct'), findsOneWidget);
      expect(find.text('LPC'), findsOneWidget);
      expect(find.text('201'), findsOneWidget);
      expect(find.text('188-214'), findsNothing);
      expect(find.text('191-211'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.text('Ridings'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('5. Majority line and odds exist only with majority data', (
    tester,
  ) async {
    _size(tester, const Size(1080, 2400), 3);
    final client = _client();
    addTearDown(client.close);
    await _show(tester, PollsScreen(polls: client));
    expect(find.byKey(const ValueKey('majority-line')), findsOneWidget);
    expect(find.text('Majority: LPC 91%'), findsOneWidget);
    final p2 = _client(summary: p2SummarySeam());
    addTearDown(p2.close);
    await _show(tester, PollsScreen(key: const ValueKey('p2'), polls: p2));
    expect(find.byKey(const ValueKey('majority-line')), findsNothing);
    expect(find.textContaining('Majority:'), findsNothing);
    expect(find.textContaining('Minority:'), findsNothing);
    expect(find.text('201'), findsOneWidget);
  });

  testWidgets('6. Summary 404 keeps latest polls visible', (tester) async {
    final client = _client(summaryStatus: 404);
    addTearDown(client.close);
    await _show(tester, PollsScreen(polls: client));
    expect(find.text('No projection yet.'), findsOneWidget);
    await _scrollTo(tester, find.text('Nanos Research, 2026-10-02'));
    expect(find.text('Nanos Research, 2026-10-02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7. Failed leaders call does not hide seats', (tester) async {
    final client = _client(leadersStatus: 500);
    addTearDown(client.close);
    await _show(tester, PollsScreen(polls: client));
    expect(find.text('201'), findsOneWidget);
    await _scrollTo(tester, find.text('Unavailable'));
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('8. More requests the next cursor and appends polls', (
    tester,
  ) async {
    final requests = <Uri>[];
    final client = _client(requests: requests);
    addTearDown(client.close);
    await _show(tester, PollsScreen(polls: client));
    await _scrollTo(tester, find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final listRequests = requests
        .where((u) => u.path.endsWith('/list'))
        .toList();
    expect(listRequests, hasLength(2));
    expect(
      listRequests.last.queryParameters['before'],
      pollsSeam('list')['next'],
    );
    await _scrollTo(tester, find.text('Second page firm, 2026-10-02'));
    expect(find.text('More'), findsNothing);
    expect(find.text('Nanos Research, 2026-10-02'), findsOneWidget);
  });

  testWidgets('9. Riding search ignores case and accents', (tester) async {
    final client = _client();
    addTearDown(client.close);
    await _show(tester, RidingsScreen(polls: client));
    await tester.enterText(find.byType(TextField), 'CHICOUTIMI');
    await tester.pumpAndSettle();
    expect(find.text('Chicoutimi—Le Fjord (QC)'), findsOneWidget);
    expect(find.text('Montréal (QC)'), findsNothing);
    await tester.enterText(find.byType(TextField), 'montreal');
    await tester.pumpAndSettle();
    expect(find.text('Montréal (QC)'), findsOneWidget);
    expect(find.text('Chicoutimi—Le Fjord (QC)'), findsNothing);
  });

  testWidgets('10. All four status labels and nullable holder fields display', (
    tester,
  ) async {
    _size(tester, const Size(1080, 2400), 3);
    final client = _client();
    addTearDown(client.close);
    await _show(tester, RidingsScreen(polls: client));
    for (final label in ['Safe', 'Likely', 'At risk', 'Vacant']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Projected: LPC · 64%'), findsOneWidget);
    final loss = _client(ridings: projectedLossSeam());
    addTearDown(loss.close);
    await _show(
      tester,
      RidingsScreen(key: const ValueKey('loss'), polls: loss),
    );
    expect(find.text('Projected loss'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('11. Riding shows 2025, Now and share history without overflow', (
    tester,
  ) async {
    _size(tester, const Size(1080, 2400), 3);
    final client = _client();
    addTearDown(client.close);
    await _show(tester, RidingScreen(polls: client, id: '24038'));
    expect(find.text('2025'), findsWidgets);
    expect(find.text('Now'), findsWidgets);
    expect(find.text('38.2%'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const ValueKey('OTH-Now')));
    expect(find.byKey(const ValueKey('OTH-2025')), findsOneWidget);
    expect(find.byKey(const ValueKey('OTH-Now')), findsOneWidget);
    await _scrollTo(tester, find.byKey(const ValueKey('polls-history-chart')));
    expect(find.byKey(const ValueKey('polls-history-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sections render before an outstanding leaders response', (
    tester,
  ) async {
    final leaders = Completer<http.Response>();
    final client = PollsClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((r) async {
        if (r.url.path.endsWith('leaders')) return leaders.future;
        return http.Response(
          jsonEncode(
            pollsSeam(r.url.path.endsWith('summary') ? 'summary' : 'list'),
          ),
          200,
        );
      }),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PollsScreen(polls: client)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('201'), findsOneWidget);
    leaders.complete(http.Response(jsonEncode(pollsSeam('leaders')), 200));
    await tester.pumpAndSettle();
  });

  testWidgets('Source attribution opens the API source URL', (tester) async {
    final client = _client();
    addTearDown(client.close);
    Uri? opened;
    await _show(
      tester,
      PollsScreen(
        polls: client,
        openLink: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );
    await _scrollTo(tester, find.text('Source: Wikipedia, CC BY-SA 4.0'));
    await tester.tap(find.text('Source: Wikipedia, CC BY-SA 4.0'));
    expect(opened.toString(), pollsSeam('leaders')['source']['url']);
  });
}
