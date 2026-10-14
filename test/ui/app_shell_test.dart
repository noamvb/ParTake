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

import 'package:parlvu/parlvu.dart';
import 'package:partake/platform/app_features.dart';
import 'package:partake/update/update_check.dart';

import '../fakes.dart';
import '../polls/polls_seams.dart';
import '../watch/fake_watch_server.dart';

DateTime _clock() => DateTime.utc(2026, 9, 23, 18, 30);

void main() {
  testWidgets('viewer 9: narrow and wide navigation has Home and Browse', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    Widget shell(AppFeatures features) => MaterialApp(
      home: AppShell(
        features: features,
        source: FakeEventSource(),
        library: FakeLibrary(),
        onOpen: (_) {},
        now: _clock,
      ),
    );
    await tester.pumpWidget(shell(const AppFeatures()));
    await tester.pumpAndSettle();
    for (final label in ['Watch', 'Polls', 'Following']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.pumpWidget(shell(AppFeatures.viewerOnly));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.cast<NavigationDestination>().map((d) => d.label), [
      'Home',
      'Polls',
      'Browse',
    ]);
    for (final label in ['Watch', 'Following']) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Digests'), findsNothing);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.map((d) => (d.label as Text).data), [
      'Home',
      'Polls',
      'Browse',
    ]);
  });

  testWidgets('viewer 10: Home hides follow stars with a positive control', (
    tester,
  ) async {
    final event = ListingEvent(
      id: 1,
      foreignKey: null,
      title: 'Viewer event',
      description: '',
      location: 'Room 415',
      scheduledStart: _clock(),
      scheduledEnd: null,
      actualStart: null,
      actualEnd: null,
      status: EventStatus.ended,
      statusCode: EventStatus.ended.code!,
      statusText: '',
    );
    final source = FakeEventSource(
      days: {
        parliamentDate(_clock()): [event],
      },
    );
    Widget shell(AppFeatures features) => MaterialApp(
      home: AppShell(
        features: features,
        source: source,
        library: FakeLibrary(),
        onOpen: (_) {},
        now: _clock,
      ),
    );
    await tester.pumpWidget(shell(const AppFeatures()));
    await tester.pumpAndSettle();
    expect(find.text('Viewer event'), findsOneWidget);
    expect(find.byTooltip('Follow'), findsWidgets);
    await tester.pumpWidget(shell(AppFeatures.viewerOnly));
    await tester.pumpAndSettle();
    expect(find.text('Viewer event'), findsOneWidget);
    expect(find.byTooltip('Follow'), findsNothing);
  });

  testWidgets('viewer 11: update banner downloads and dismisses', (
    tester,
  ) async {
    final urls = <Uri>[];
    final url = Uri.parse('https://example.com/r');
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          source: FakeEventSource(),
          library: FakeLibrary(),
          onOpen: (_) {},
          now: _clock,
          checkForUpdate: () async {
            checks++;
            return UpdateInfo(version: '0.8.0', url: url);
          },
          openUrl: urls.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ParTake 0.8.0 is available.'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(urls, [url]);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('ParTake 0.8.0 is available.'), findsNothing);
    expect(checks, 1);
  });

  testWidgets('viewer 12: null and omitted checks show no banner', (
    tester,
  ) async {
    Widget shell(Future<UpdateInfo?> Function()? check) => MaterialApp(
      home: AppShell(
        key: UniqueKey(),
        source: FakeEventSource(),
        library: FakeLibrary(),
        onOpen: (_) {},
        now: _clock,
        checkForUpdate: check,
      ),
    );
    await tester.pumpWidget(
      shell(
        () async => UpdateInfo(
          version: '0.8.0',
          url: Uri.parse('https://example.com/r'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('is available.'), findsOneWidget);
    await tester.pumpWidget(shell(() async => null));
    await tester.pumpAndSettle();
    expect(find.textContaining('is available.'), findsNothing);
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
    expect(find.textContaining('is available.'), findsNothing);
  });

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
  testWidgets('Viewer snapshot Polls shows the summary without Deck setup', (
    tester,
  ) async {
    final base = Uri.parse('https://example.test/snap/');
    final polls = PollsClient.snapshot(
      base: base,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(
            pollsSeam(r.url.path.split('/').last.replaceAll('.json', '')),
          ),
          200,
        ),
      ),
    );
    addTearDown(polls.close);
    Widget shell(AppFeatures features, {PollsClient? client}) => MaterialApp(
      home: AppShell(
        features: features,
        polls: client,
        source: FakeEventSource(),
        library: FakeLibrary(),
        onOpen: (_) {},
        now: _clock,
      ),
    );
    final setup = find.text('Set the Deck address in the Watch tab first.');
    await tester.pumpWidget(shell(const AppFeatures()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polls'));
    await tester.pumpAndSettle();
    expect(setup, findsOneWidget);
    await tester.pumpWidget(
      shell(
        AppFeatures(deck: false, following: false, pollsSnapshot: base),
        client: polls,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polls'));
    await tester.pumpAndSettle();
    expect(
      find.text('${pollsSeam('summary')['polls_used']} polls'),
      findsOneWidget,
    );
    expect(setup, findsNothing);
    expect(
      AppFeatures.viewerOnly.pollsSnapshot.toString(),
      'https://raw.githubusercontent.com/noamvb/ParTake/polls-data/',
    );
  });
}
