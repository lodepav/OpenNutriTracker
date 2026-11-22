import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/fasting/presentation/widgets/fasting_warning_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

// G2 sweep: the decline says what it does, and the help links are 48 dp
// targets.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        home: const Scaffold(body: FastingWarningDialog()),
      ),
    );
    await tester.pump();
  }

  testWidgets('the decline is "Not now": the page asks again next time', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Not for me'), findsNothing);
  });

  testWidgets('each help link is a 48 dp link target', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (final label in ['BEAT (UK)', 'NEDA (US)']) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(target, findsOneWidget, reason: label);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.text(label)),
        isSemantics(isLink: true, hasTapAction: true, label: label),
      );
    }
    handle.dispose();
  });
}
