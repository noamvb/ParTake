import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/polls/polls_client.dart';
import 'package:partake/ui/riding_screen.dart';
import 'package:partake/watch/watch_models.dart';

import '../polls/polls_seams.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/ui/following_screen.dart';

import '../fakes.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:partake/watch/watch_follows.dart';

import '../watch/fake_watch_server.dart';
import '../watch/watch_models_test.dart' show seam, seamList;

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const label =
      'Daniel Gobeil with a very long MP label that wraps across several lines';
  const mp = WatchFollow(
    id: 'mp-test',
    kind: 'mp',
    label: label,
    mp: WatchMpRef(
      personId: '123447',
      name: 'Daniel Gobeil',
      party: 'LPC',
      riding: 'Chicoutimi—Le Fjord',
    ),
  );
  Future<WatchFollows> deck() async {
    SharedPreferences.setMockInitialValues({'watch.imported': true});
    final watch = WatchFollows(
      prefs: await SharedPreferences.getInstance(),
      library: FakeLibrary(),
      defaultAddress: 'http://deck.test',
      clientFactory: FakeWatchServer([mp]).client,
    );
    await watch.sync();
    addTearDown(watch.dispose);
    return watch;
  }

  for (final (size, ratio) in [
    (const Size(1080, 2400), 3.0),
    (const Size(1800, 2000), 2.25),
  ]) {
    testWidgets('MP chip and navigation fit $size at $ratio', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final watch = await deck();
      final requests = <Uri>[];
      final polls = PollsClient(
        address: Uri.parse('http://deck.test'),
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(
                pollsSeam(
                  r.url.path.endsWith('/ridings') ? 'ridings' : 'riding',
                ),
              ),
            ),
            200,
          );
        }),
      );
      addTearDown(polls.close);
      await tester.pumpWidget(
        _wrap(
          FollowingScreen(library: FakeLibrary(), watch: watch, polls: polls),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('At risk'), findsOneWidget);
      expect(find.byTooltip('Remove $label'), findsOneWidget);
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters, isEmpty);
      expect(tester.takeException(), isNull);
      await watch.sync();
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(RidingScreen), findsOneWidget);
      expect(requests.last.path, '/watch/api/polls/ridings/24038');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('loading, failed, and unmatched ridings leave MP row usable', (
    tester,
  ) async {
    final watch = await deck();
    final gate = Completer<http.Response>();
    var requests = 0;
    final polls = PollsClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((r) {
        requests++;
        return gate.future;
      }),
    );
    addTearDown(polls.close);
    final library = FakeLibrary();
    await tester.pumpWidget(
      _wrap(FollowingScreen(library: library, watch: watch, polls: polls)),
    );
    await tester.pump();
    expect(find.byType(RidingStatusChip), findsNothing);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap,
      isNull,
    );
    gate.complete(http.Response('{"error":"polls failed"}', 500));
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    expect(find.textContaining('polls failed'), findsNothing);
    expect(find.byType(RidingStatusChip), findsNothing);
    await watch.sync();
    await tester.pumpAndSettle();
    expect(requests, 1);
    final unmatched = PollsClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((_) async => http.Response('{"ridings":[]}', 200)),
    );
    addTearDown(unmatched.close);
    await tester.pumpWidget(
      _wrap(FollowingScreen(library: library, watch: watch, polls: unmatched)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap,
      isNull,
    );
    expect(find.byType(RidingStatusChip), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changed MP ids reload once; non-MP changes do not', (
    tester,
  ) async {
    final watch = await deck();
    var requests = 0;
    final polls = PollsClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(
          utf8.encode(jsonEncode(pollsSeam('ridings'))),
          200,
        );
      }),
    );
    addTearDown(polls.close);
    await tester.pumpWidget(
      _wrap(
        FollowingScreen(library: FakeLibrary(), watch: watch, polls: polls),
      ),
    );
    await tester.pumpAndSettle();
    await watch.add(const WatchFollow(kind: 'votes', label: 'Votes'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    await watch.add(
      const WatchFollow(
        kind: 'mp',
        label: 'Jane',
        mp: WatchMpRef(
          personId: '123',
          name: 'Jane',
          party: 'LPC',
          riding: 'Montréal',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Safe'), findsOneWidget);
  });
  testWidgets(
    'lists followed keys, unfollow removes one, empty shows the hint',
    (tester) async {
      final library = FakeLibrary();
      await library.setFollowed('HOC', true);
      await library.setFollowed('FEWO', true);

      await tester.pumpWidget(_wrap(FollowingScreen(library: library)));
      await tester.pump();

      expect(find.text('House of Commons (chamber)'), findsOneWidget);
      expect(find.text('FEWO'), findsOneWidget);

      await tester.tap(find.byTooltip('Unfollow FEWO'));
      await tester.pump();

      expect(find.text('FEWO'), findsNothing);
      expect(find.text('House of Commons (chamber)'), findsOneWidget);

      await tester.tap(find.byTooltip('Unfollow HOC'));
      await tester.pump();

      expect(
        find.text(
          'Follow the chamber or a committee with the star on any event.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('PM switch follows and unfollows PM-QP', (tester) async {
    final library = FakeLibrary();
    await tester.pumpWidget(_wrap(FollowingScreen(library: library)));
    await tester.tap(find.text('Prime Minister at Question Period'));
    await tester.pump();
    expect(library.follows.contains('PM-QP'), isTrue);
    await tester.tap(find.text('Prime Minister at Question Period'));
    await tester.pump();
    expect(library.follows.contains('PM-QP'), isFalse);
  });

  testWidgets('PM only follow leaves committee list empty', (tester) async {
    final library = FakeLibrary();
    await library.setFollowed('PM-QP', true);
    await tester.pumpWidget(_wrap(FollowingScreen(library: library)));
    expect(find.widgetWithText(ListTile, 'PM-QP'), findsNothing);
    expect(
      find.text(
        'Follow the chamber or a committee with the star on any event.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('15 Deck list removes MP and retains legacy follows', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'watch.cache': seam,
      'watch.imported': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final library = FakeLibrary();
    await library.setFollowed('HOC', true);
    await library.setFollowed('ETHI', true);
    final server = FakeWatchServer(seamList().follows);
    final watch = WatchFollows(
      prefs: prefs,
      library: library,
      defaultAddress: 'http://deck.test',
      clientFactory: server.client,
    );
    addTearDown(watch.dispose);
    await tester.pumpWidget(
      _wrap(FollowingScreen(library: library, watch: watch)),
    );
    expect(find.text('On the Deck'), findsOneWidget);
    expect(find.text('Housing affordability'), findsOneWidget);
    expect(find.text('Billy Morin'), findsOneWidget);
    expect(find.text('MP · Conservative · Edmonton Northwest'), findsOneWidget);
    expect(find.text('Bill C-37'), findsOneWidget);
    expect(find.text('Votes that split a party'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Remove Billy Morin'));
    await tester.tap(find.byTooltip('Remove Billy Morin'));
    await tester.pumpAndSettle();
    expect(server.puts, hasLength(1));
    expect(server.puts.single.any((f) => f.kind == 'mp'), isFalse);
    expect(find.text('House of Commons (chamber)'), findsOneWidget);
    expect(find.text('ETHI'), findsOneWidget);
  });

  testWidgets('16 Deck layout and editor fit narrow and wide screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({
      'watch.cache': seam,
      'watch.imported': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final library = FakeLibrary();
    final server = FakeWatchServer(seamList().follows)..offline = true;
    final watch = WatchFollows(
      prefs: prefs,
      library: library,
      defaultAddress: 'http://deck.test',
      clientFactory: server.client,
    );
    addTearDown(watch.dispose);
    await watch.sync();
    expect(watch.lastError, 'Deck unreachable');
    for (final size in [const Size(320, 640), const Size(900, 700)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        _wrap(FollowingScreen(library: library, watch: watch)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add a follow'));
    await tester.tap(find.byTooltip('Add a follow'));
    await tester.pumpAndSettle();
    for (final text in ['Topic', 'Bill', 'MP', 'Votes']) {
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(text),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
