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
