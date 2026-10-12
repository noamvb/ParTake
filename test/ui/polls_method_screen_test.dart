import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partake/polls/polls_method.dart';
import 'package:partake/ui/polls_method_screen.dart';

void main() {
  for (final (label, size, ratio) in [
    ('cover', const Size(1080, 2400), 3.0),
    ('wide', const Size(1800, 2000), 2.25),
  ]) {
    testWidgets('All 11 sections render without overflow on $label', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: PollsMethodScreen()));
      expect(pollsMethod, hasLength(11));
      for (final section in pollsMethod) {
        await tester.ensureVisible(find.text(section.title));
        await tester.pumpAndSettle();
        expect(find.text(section.title).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final content = tester.widget<ConstrainedBox>(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 720,
        ),
      );
      expect(content.constraints.maxWidth, 720);
    });
  }

  testWidgets('Section 5 opens at the top without user scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PollsMethodScreen(section: '5.')),
    );
    await tester.pumpAndSettle();
    final title = find.text('5. Ranges and odds');
    expect(title.hitTestable(), findsOneWidget);
    final scrollTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(tester.getTopLeft(title).dy, closeTo(scrollTop, 1));
  });

  testWidgets('Status bullet labels render in bold', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PollsMethodScreen(section: '6.')),
    );
    await tester.pumpAndSettle();
    for (final label in ['Safe', 'Likely', 'At risk', 'Projected loss']) {
      final text = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan is TextSpan &&
              (widget.textSpan! as TextSpan).children!.first.toPlainText() ==
                  label,
        ),
      );
      final span = (text.textSpan! as TextSpan).children!.first as TextSpan;
      expect(span.style!.fontWeight, FontWeight.bold);
    }
  });
}
