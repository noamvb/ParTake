import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/ui/app_shell.dart';

import '../fakes.dart';

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
}
