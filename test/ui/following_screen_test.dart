import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/ui/following_screen.dart';

import '../fakes.dart';

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
}
