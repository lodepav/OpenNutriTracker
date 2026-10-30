import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/diary_timeline.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width, double scale) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: TimelineGap(
                    from: DateTime(2026, 10, 30, 9),
                    to: DateTime(2026, 10, 30, 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  final text = find.textContaining('nothing logged');

  testWidgets('a text with room stays on a line beside the rule', (
    tester,
  ) async {
    await pump(tester, 500, 1);
    final oneLine = tester.getSize(text).height;
    expect(oneLine, lessThan(24));
    expect(tester.getSize(find.byType(Divider)).width, greaterThan(0));
  });

  testWidgets('a text too wide for the row wraps rather than overflows', (
    tester,
  ) async {
    await pump(tester, 500, 1);
    final oneLine = tester.getSize(text).height;
    await pump(tester, 320, 2);
    // A RenderFlex overflow would fail the test by itself.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(text).height, greaterThan(oneLine * 2));
    // 240 of margin either side of the box, then the row's 16 of padding.
    expect(tester.getTopRight(text).dx, lessThanOrEqualTo(800 - 240 - 16));
  });

  testWidgets('the range ends when the empty hours end', (tester) async {
    await pump(tester, 500, 1);
    // 9:00 to 12:00 are the empty hours' starts: empty until 1 PM.
    expect(find.text('9:00 AM – 1:00 PM · nothing logged'), findsOneWidget);
  });
}
