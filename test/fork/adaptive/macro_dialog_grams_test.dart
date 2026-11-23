import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/macro_program_ui.dart';

void main() {
  const basis = (
    kcal: 2500.0,
    weightKg: 80.0,
    bodyFatPercent: 20.0,
    goalKcal: 0.0,
  );

  Future<void> open(WidgetTester tester, MacroProgram? program) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  MacroProgramDialog(program, basis: Future.value(basis)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String line(MacroProgram program) =>
      'Today: ${macroGramsText(program.macrosFor(kcal: basis.kcal, weightKg: basis.weightKg, bodyFatPercent: basis.bodyFatPercent, goalKcal: basis.goalKcal)).replaceAll(' g', '\u00A0g')}';

  testWidgets('the dialog says the grams a day the choices give, live', (
    tester,
  ) async {
    await open(tester, const MacroProgram());
    // under the chips, above the fat footnote
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('macro-program-grams'))).dy,
      lessThan(
        tester
            .getTopLeft(find.textContaining('under which it is not advised'))
            .dy,
      ),
    );
    // G4-12: "a weekday's shift" was jargon; the switch says what it does.
    expect(find.textContaining("weekday's shift"), findsNothing);
    expect(
      find.textContaining('In grams for your body weight'),
      findsOneWidget,
    );
    // 80 kg at 1.6 and 0.8 g/kg: 128 g protein, 64 g fat, carbs the rest.
    expect(
      // A number and its "g" kept together (G4-12).
      find.text('Today: Carbs 353\u00A0g · Fat 64\u00A0g · Protein 128\u00A0g'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('macro-protein-2')));
    await tester.tap(find.byKey(const ValueKey('macro-protein-2')));
    await tester.pumpAndSettle();
    expect(
      find.text(line(const MacroProgram().copyWith(proteinGPerKg: 2.2))),
      findsOneWidget,
    );
  });

  testWidgets('off, or with no basis read, there is no grams line', (
    tester,
  ) async {
    await open(tester, null);
    expect(find.byKey(const ValueKey('macro-program-grams')), findsNothing);
  });

  testWidgets("the footnote's last line clears the scroll's edge", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, const MacroProgram());
    final scroll = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    await tester.drag(scroll, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final footnote = find.textContaining('under which it is not advised');
    expect(
      tester.getBottomLeft(footnote).dy,
      lessThanOrEqualTo(tester.getBottomLeft(scroll).dy - 16),
    );
  });
}
