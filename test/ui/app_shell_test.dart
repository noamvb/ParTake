import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/polls/polls_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/ui/app_shell.dart';
import 'package:partake/watch/watch_follows.dart';
import 'package:partake/watch/watch_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';
import '../polls/polls_seams.dart';
import '../watch/fake_watch_server.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 18, 30);

void main() {
  testWidgets('Following receives injected polls before Polls is opened', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'watch.imported': true});
    final library = FakeLibrary();
    final server = FakeWatchServer([
      const WatchFollow(
        id: 'mp',
        kind: 'mp',
        label: 'Daniel Gobeil',
        mp: WatchMpRef(
          personId: '123447',
          name: 'Daniel Gobeil',
          party: 'LPC',
          riding: 'Chicoutimi—Le Fjord',
        ),
      ),
    ]);
    final watch = WatchFollows(
      prefs: await SharedPreferences.getInstance(),
      library: library,
      defaultAddress: 'http://deck.test',
      clientFactory: server.client,
    );
    addTearDown(watch.dispose);
    await watch.sync();
    final requests = <Uri>[];
    final polls = PollsClient(
      address: Uri.parse('http://injected.test'),
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response.bytes(
          utf8.encode(jsonEncode(pollsSeam('ridings'))),
          200,
        );
      }),
    );
    addTearDown(polls.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          source: FakeEventSource(),
          library: library,
          watch: watch,
          polls: polls,
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('At risk'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.host, 'injected.test');
    expect(tester.takeException(), isNull);
  });
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

  testWidgets('12. Five tabs in order; Watch loads only when opened', (
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
    expect(
      find.descendant(of: bar, matching: find.text('Polls')),
      findsOneWidget,
    );
    final destinations = tester
        .widget<NavigationBar>(bar)
        .destinations
        .cast<NavigationDestination>();
    expect(destinations.map((d) => d.label), [
      'Home',
      'Watch',
      'Polls',
      'Browse',
      'Following',
    ]);
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
    '12. Digests appears only on Watch, including after visiting Polls',
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
      await tester.tap(find.descendant(of: bar, matching: find.text('Browse')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Digests'), findsNothing);
      await tester.tap(
        find.descendant(of: bar, matching: find.text('Following')),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Digests'), findsNothing);
      await tester.tap(find.descendant(of: bar, matching: find.text('Watch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Digests'));
      await tester.pumpAndSettle();
      expect(find.text('Evening digest, Mon 19 Oct'), findsOneWidget);
      expect(find.text('Morning digest, Tue 20 Oct'), findsOneWidget);
    },
  );
  for (final (size, ratio) in [
    (const Size(1080, 2400), 3.0),
    (const Size(1800, 2000), 2.25),
  ]) {
    testWidgets('12. Polls is lazy and shell fits $size at $ratio', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final polls = PollsClient(
        address: Uri.parse('http://deck.test'),
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response(
            jsonEncode(pollsSeam(r.url.path.split('/').last)),
            200,
          );
        }),
      );
      addTearDown(polls.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            source: FakeEventSource(),
            library: FakeLibrary(),
            polls: polls,
            onOpen: (_) {},
            now: _clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.text('Polls'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(find.text('201'), findsOneWidget);
      expect(find.byTooltip('Digests'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Digests'), findsOneWidget);
      await tester.tap(find.text('Polls'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(find.byTooltip('Digests'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Polls without a Deck explains setup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          source: FakeEventSource(),
          library: FakeLibrary(),
          onOpen: (_) {},
          now: _clock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polls'));
    await tester.pumpAndSettle();
    expect(
      find.text('Set the Deck address in the Watch tab first.'),
      findsOneWidget,
    );
  });
}
