import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/ui/app_shell.dart';
import 'package:partake/watch/watch_follows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';
import '../watch/fake_watch_server.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 18, 30);

void main() {
  testWidgets(
    'switches nav layout at 720px, keeps screen state, shows the About dialog',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;

      final source = FakeEventSource();
      final library = FakeLibrary();

      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            source: source,
            library: library,
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      final liveCallsAfterFirstLoad = source.calls
          .where((c) => c == 'liveNow')
          .length;

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      final liveCallsAfterSwitch = source.calls
          .where((c) => c == 'liveNow')
          .length;
      expect(liveCallsAfterSwitch, liveCallsAfterFirstLoad);

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byTooltip('About'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Not affiliated with or endorsed by the House of Commons',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Watch tab sits second and loads its feed only when opened', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);

    SharedPreferences.setMockInitialValues({'watch.imported': true});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeWatchServer(feedFollows());
    final watch = WatchFollows(
      prefs: prefs,
      library: FakeLibrary(),
      defaultAddress: 'http://deck.test',
      clientFactory: server.client,
    );
    addTearDown(watch.dispose);
    await watch.sync();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          source: FakeEventSource(),
          library: FakeLibrary(),
          watch: watch,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(NavigationBar);
    expect(
      find.descendant(of: bar, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Watch')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Browse')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Following')),
      findsOneWidget,
    );
    expect(server.feedRequests, isEmpty);

    await tester.tap(find.descendant(of: bar, matching: find.text('Watch')));
    await tester.pumpAndSettle();
    expect(server.feedRequests, hasLength(1));
    expect(
      find.text('C-37: Second reading (House of Commons)'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the Digests action is on the Watch tab only and opens the list',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);

      SharedPreferences.setMockInitialValues({'watch.imported': true});
      final prefs = await SharedPreferences.getInstance();
      final server = FakeWatchServer(feedFollows());
      final watch = WatchFollows(
        prefs: prefs,
        library: FakeLibrary(),
        defaultAddress: 'http://deck.test',
        clientFactory: server.client,
      );
      addTearDown(watch.dispose);
      await watch.sync();

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            source: FakeEventSource(),
            library: FakeLibrary(),
            watch: watch,
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Digests'), findsNothing);

      final bar = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Watch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Digests'));
      await tester.pumpAndSettle();
      expect(find.text('Evening digest, Mon 19 Oct'), findsOneWidget);
      expect(find.text('Morning digest, Tue 20 Oct'), findsOneWidget);
    },
  );
}
