import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/highlight_button.dart';

/// Onboarding's Start while it saves (seam S466): off, with a spinner.
void main() {
  testWidgets('a busy button cannot be tapped and shows progress', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightButton(
            buttonLabel: 'Start',
            onButtonPressed: () => taps++,
            buttonActive: true,
            busy: true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'), warnIfMissed: false);
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
