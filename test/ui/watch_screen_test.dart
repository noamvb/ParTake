import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:partake/ui/open_request.dart';
import 'package:partake/ui/watch_screen.dart';
import 'package:partake/watch/watch_follows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';
import '../watch/fake_watch_server.dart';

const _listKey = ValueKey('watch-feed-list');
const _liveStripKey = ValueKey('watch-live-strip');
final _scrollable = find.descendant(
  of: find.byKey(_listKey),
  matching: find.byType(Scrollable),
);
DateTime _clock() => DateTime.utc(2026, 10, 9, 18);
Future<bool> _noLinks(Uri uri) async => true;
void _noOpen(OpenRequest request) {}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The seam's captioned speech (from the digest literal) as a one-item feed.
String _captionFeed() => jsonEncode({
  'items': [jsonDecode(digestSeam)['sections'][0]['items'][0]],
  'next': null,
});

Future<WatchFollows> _deck(FakeWatchServer server) async {
  SharedPreferences.setMockInitialValues({'watch.imported': true});
  final prefs = await SharedPreferences.getInstance();
  final watch = WatchFollows(
    prefs: prefs,
    library: FakeLibrary(),
    defaultAddress: 'http://deck.test',
    clientFactory: server.client,
  );
  await watch.sync();
  return watch;
}

Future<void> _pumpFeed(
  WidgetTester tester,
  WatchFollows? watch, {
  Future<bool> Function(Uri uri) openLink = _noLinks,
  OpenEvent onOpen = _noOpen,
}) async {
  await tester.pumpWidget(
    _wrap(
      WatchScreen(
        watch: watch,
        now: _clock,
        openLink: openLink,
        onOpen: onOpen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDigests(
  WidgetTester tester,
  WatchFollows? watch, {
  OpenEvent onOpen = _noOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DigestsScreen(
        watch: watch,
        now: _clock,
        onOpen: onOpen,
        openLink: _noLinks,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls back to the top, then down until [finder] is on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.drag(find.byKey(_listKey), const Offset(0, 10000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 200, scrollable: _scrollable);
}

void _useSize(WidgetTester tester, Size size) {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
}

Future<void> _expectSeamCards(WidgetTester tester) async {
  for (final title in [
    'C-37: Second reading (House of Commons)',
    'Government Orders - First Nations Clean Water Act',
    'Vote 7: Negatived',
    'INDU, meeting 50',
    'Mandy Gull-Masty · Liberal',
    'Negatived · 1 yea, 2 nay, 0 paired',
    'Conservative split: 1 yea, 1 nay',
    'Billy Morin: Nay',
    'Housing affordability 71%',
    'Sheehan Carter',
  ]) {
    await _reveal(tester, find.text(title));
    expect(find.text(title), findsOneWidget, reason: title);
  }
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('feed cards show the seam content on the narrow cover screen', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    final watch = await _deck(FakeWatchServer(feedFollows()));
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    await _expectSeamCards(tester);
  });

  testWidgets('feed cards show the seam content on the wide inner screen', (
    tester,
  ) async {
    _useSize(tester, const Size(840, 760));
    final watch = await _deck(FakeWatchServer(feedFollows()));
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    await _expectSeamCards(tester);
  });

  testWidgets('link buttons open the matching URL', (tester) async {
    _useSize(tester, const Size(360, 740));
    final opened = <Uri>[];
    final watch = await _deck(FakeWatchServer(feedFollows()));
    addTearDown(watch.dispose);
    await _pumpFeed(
      tester,
      watch,
      openLink: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await _reveal(tester, find.widgetWithText(TextButton, 'Hansard'));
    await tester.tap(find.widgetWithText(TextButton, 'Hansard'));
    await tester.pump();
    expect(
      opened.last,
      Uri.parse(
        'https://www.ourcommons.ca/DocumentViewer/en/45-1/house/sitting-149/hansard#Para9484631',
      ),
    );

    await _reveal(tester, find.widgetWithText(TextButton, 'Evidence'));
    expect(find.widgetWithText(TextButton, 'Evidence'), findsOneWidget);

    await _reveal(tester, find.widgetWithText(TextButton, 'Vote details'));
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Vote details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Vote details'));
    await tester.pump();
    expect(
      opened.last,
      Uri.parse('https://www.ourcommons.ca/Members/en/votes/45/1/7'),
    );
  });

  testWidgets(
    'filter chips reload with the follow and All reloads without it',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpFeed(tester, watch);
      expect(
        server.feedRequests.single.queryParametersAll.containsKey("follow"),
        isFalse,
      );

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'C-37'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'C-37'));
      await tester.pumpAndSettle();
      expect(server.feedRequests.last.queryParametersAll['follow'], [
        'f_jkl567',
      ]);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(server.feedRequests, hasLength(3));
      expect(
        server.feedRequests.last.queryParametersAll.containsKey("follow"),
        isFalse,
      );
    },
  );

  testWidgets(
    'scrolling to the end pages in 60 items and never overlaps loads',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      final gate = Completer<void>();
      server.feedAnswer = (url) async {
        if (url.queryParameters['before'] != null) await gate.future;
        return pagedFeed(url);
      };
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpFeed(tester, watch);

      Future<void> toEnd() =>
          tester.drag(find.byKey(_listKey), const Offset(0, -10000));
      await toEnd();
      await tester.pump();
      expect(server.feedRequests, hasLength(2));
      await toEnd();
      await tester.pump();
      expect(server.feedRequests, hasLength(2));

      gate.complete();
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_listKey), const Offset(0, 10000));
      await tester.pumpAndSettle();
      final titles = <String>{};
      void collect() => titles.addAll(
        tester
            .widgetList<Text>(find.textContaining('Item '))
            .map((t) => t.data!),
      );
      collect();
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byKey(_listKey), const Offset(0, -400));
        await tester.pumpAndSettle();
        collect();
      }
      expect(server.feedRequests, hasLength(3));
      expect(titles, hasLength(60));
    },
  );

  testWidgets('no Deck shows the setup message and makes no request', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    await _pumpFeed(tester, null);
    expect(
      find.text(
        'Parliament watch runs on the Deck. Set up the Deck connection in Following.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an empty page says nothing matched', (tester) async {
    _useSize(tester, const Size(360, 740));
    final server = FakeWatchServer(feedFollows());
    server.feedAnswer = (_) async =>
        http.Response('{"items": [], "next": null}', 200);
    final watch = await _deck(server);
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    expect(find.text('Nothing has matched your follows yet.'), findsOneWidget);
  });

  testWidgets('a failing feed shows the error and Retry loads the items', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    final server = FakeWatchServer(feedFollows());
    var failing = true;
    server.feedAnswer = (url) async => failing
        ? http.Response('{"error": "boom"}', 500)
        : http.Response.bytes(utf8.encode(feedSeam), 200);
    final watch = await _deck(server);
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    expect(find.text('boom'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    failing = false;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsNothing);
    expect(find.text('Vote 7: Negatived'), findsOneWidget);
  });

  Future<void> expectCaptionCard(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('From live captions'), findsOneWidget);
    expect(find.textContaining('Probably Mandy Gull-Masty'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Watch'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'caption card shows the live label, the guessed speaker and Watch at 360x740',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      server.feedAnswer = (_) async =>
          http.Response.bytes(utf8.encode(_captionFeed()), 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpFeed(tester, watch);
      await expectCaptionCard(tester);
    },
  );

  testWidgets(
    'caption card shows the live label, the guessed speaker and Watch at 840x760',
    (tester) async {
      _useSize(tester, const Size(840, 760));
      final server = FakeWatchServer(feedFollows());
      server.feedAnswer = (_) async =>
          http.Response.bytes(utf8.encode(_captionFeed()), 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpFeed(tester, watch);
      await expectCaptionCard(tester);
    },
  );

  testWidgets(
    'Watch calls onOpen once with the event and the moment to seek to',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      server.feedAnswer = (_) async =>
          http.Response.bytes(utf8.encode(_captionFeed()), 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      final opened = <OpenRequest>[];
      await _pumpFeed(tester, watch, onOpen: opened.add);

      await tester.tap(find.widgetWithText(TextButton, 'Watch'));
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.eventId, 45873);
      expect(opened.single.title, 'House of Commons, sitting 150');
      expect(opened.single.eventDate, DateTime.utc(2026, 10, 19));
      expect(opened.single.seekTo, DateTime.utc(2026, 10, 19, 15, 31, 12, 400));
    },
  );

  Future<void> expectDigestRows(WidgetTester tester) async {
    expect(find.text('Morning digest, Tue 20 Oct'), findsOneWidget);
    expect(find.text('Evening digest, Mon 19 Oct'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('1 items'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Morning digest, Tue 20 Oct'),
        matching: find.text('Updated with the official record'),
      ),
      findsOneWidget,
    );
    expect(find.text('Updated with the official record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'digests list shows the rows and the morning update line at 360x740',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final watch = await _deck(FakeWatchServer(feedFollows()));
      addTearDown(watch.dispose);
      await _pumpDigests(tester, watch);
      await expectDigestRows(tester);
    },
  );

  testWidgets(
    'digests list shows the rows and the morning update line at 840x760',
    (tester) async {
      _useSize(tester, const Size(840, 760));
      final watch = await _deck(FakeWatchServer(feedFollows()));
      addTearDown(watch.dispose);
      await _pumpDigests(tester, watch);
      await expectDigestRows(tester);
    },
  );

  testWidgets('tapping the evening digest opens it with its section and item', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    final server = FakeWatchServer(feedFollows());
    final watch = await _deck(server);
    addTearDown(watch.dispose);
    await _pumpDigests(tester, watch);

    await tester.tap(find.text('Evening digest, Mon 19 Oct'));
    await tester.pumpAndSettle();
    expect(find.text('Bill C-37'), findsOneWidget);
    expect(find.text('House of Commons, sitting 150'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Watch'), findsOneWidget);
    expect(find.text('From live captions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> expectEmptyDigests(WidgetTester tester) async {
    expect(
      find.text(
        'No digests yet. The first one arrives the evening after a sitting.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'an empty digests list says the first one is still to come at 360x740',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      server.digestsAnswer = (_) async => http.Response('[]', 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpDigests(tester, watch);
      await expectEmptyDigests(tester);
    },
  );

  testWidgets(
    'an empty digests list says the first one is still to come at 840x760',
    (tester) async {
      _useSize(tester, const Size(840, 760));
      final server = FakeWatchServer(feedFollows());
      server.digestsAnswer = (_) async => http.Response('[]', 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpDigests(tester, watch);
      await expectEmptyDigests(tester);
    },
  );

  testWidgets(
    'the live strip shows LIVE, the title and the guessed speaker, and opens the event',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      server.liveAnswer = (_) async =>
          http.Response.bytes(utf8.encode(liveSeam), 200);
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      final opened = <OpenRequest>[];
      await _pumpFeed(tester, watch, onOpen: opened.add);

      final strip = find.byKey(_liveStripKey);
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.text('LIVE')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.text('House of Commons, sitting 150'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.text('Now: Probably Mandy Gull-Masty'),
        ),
        findsOneWidget,
      );

      await tester.tap(strip);
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.eventId, 45873);
      expect(opened.single.title, 'House of Commons, sitting 150');
      expect(opened.single.eventDate, DateTime.utc(2026, 10, 9));
      expect(opened.single.seekTo, isNull);
    },
  );

  testWidgets('no live rows means no live strip', (tester) async {
    _useSize(tester, const Size(360, 740));
    final watch = await _deck(FakeWatchServer(feedFollows()));
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    expect(find.byKey(_liveStripKey), findsNothing);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('a failing live request hides the strip without an error', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    final server = FakeWatchServer(feedFollows());
    server.liveAnswer = (_) async => http.Response('{"error": "boom"}', 500);
    final watch = await _deck(server);
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    expect(find.byKey(_liveStripKey), findsNothing);
    expect(find.text('boom'), findsNothing);
    expect(find.text('Vote 7: Negatived'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the live strip asks again 60 seconds later while the tab is shown',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      await _pumpFeed(tester, watch);
      expect(server.liveRequests, hasLength(1));

      await tester.pump(const Duration(seconds: 60));
      expect(server.liveRequests, hasLength(2));
    },
  );

  testWidgets(
    'the live strip stops asking while the tab is hidden and resumes when shown',
    (tester) async {
      _useSize(tester, const Size(360, 740));
      final server = FakeWatchServer(feedFollows());
      final watch = await _deck(server);
      addTearDown(watch.dispose);
      Widget tab({required bool shown}) => _wrap(
        TickerMode(
          enabled: shown,
          child: WatchScreen(
            watch: watch,
            now: _clock,
            openLink: _noLinks,
            onOpen: _noOpen,
          ),
        ),
      );
      await tester.pumpWidget(tab(shown: true));
      await tester.pumpAndSettle();
      expect(server.liveRequests, hasLength(1));

      await tester.pumpWidget(tab(shown: false));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 120));
      expect(server.liveRequests, hasLength(1));

      await tester.pumpWidget(tab(shown: true));
      await tester.pumpAndSettle();
      expect(server.liveRequests, hasLength(2));
    },
  );

  testWidgets('a failing refresh hides the strip that was showing', (
    tester,
  ) async {
    _useSize(tester, const Size(360, 740));
    final server = FakeWatchServer(feedFollows());
    var failing = false;
    server.liveAnswer = (_) async => failing
        ? http.Response('{"error": "boom"}', 500)
        : http.Response.bytes(utf8.encode(liveSeam), 200);
    final watch = await _deck(server);
    addTearDown(watch.dispose);
    await _pumpFeed(tester, watch);
    expect(find.byKey(_liveStripKey), findsOneWidget);

    failing = true;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.byKey(_liveStripKey), findsNothing);
    expect(find.text('boom'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
