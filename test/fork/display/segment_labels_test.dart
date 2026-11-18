import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../../helpers/ux_checks.dart';

/// Each label of [T]'s segments on one line: a one-word label on two is
/// broken inside the word.
void _expectOneLine<T>(WidgetTester tester, List<String> labels) {
  for (final label in labels) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(
          of: find.byType(SegmentedButton<T>),
          matching: find.text(label),
        ),
        matching: find.byType(RichText),
      ),
    );
    final lines = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        )
        .map((box) => box.top.round())
        .toSet();
    expect(lines, hasLength(1), reason: '$label: $lines');
  }
}

/// On a 360 dp phone, in the app's fonts.
Future<void> _narrow(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('at 2x on a 360 dp phone, Home\'s Left and Eaten each stay '
      'on one line', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: SingleChildScrollView(
          child: DashboardWidget(
            totalKcalSupplied: 1800,
            totalKcalBurned: 0,
            totalKcalDaily: 2500,
            totalKcalLeft: 700,
            totalCarbsIntake: 100,
            totalFatsIntake: 30,
            totalProteinsIntake: 60,
            totalCarbsGoal: 375,
            totalFatsGoal: 69,
            totalProteinsGoal: 93,
            loadCredit: () async => ActivityCredit.added,
            homeLoads: const Stream.empty(),
          ),
        ),
      ),
    );
    await _narrow(tester);
    _expectOneLine<bool>(tester, ['Left', 'Eaten']);
  });

  testWidgets('at 2x on a 360 dp phone, the foods page\'s switch keeps each '
      'word whole', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MacroFoodsPage(
          initial: FoodsMetric.protein,
          intakes: [intakeOf('Oats', 80, protein100: 13, carbs100: 60)],
          totals: const {},
          day: DateTime(2026, 10, 25),
        ),
      ),
    );
    await _narrow(tester);
    _expectOneLine<FoodsMetric>(tester, ['Kcal', 'Carbs', 'Fat', 'Protein']);
  });
}
