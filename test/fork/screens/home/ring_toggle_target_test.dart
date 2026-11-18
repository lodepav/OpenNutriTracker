import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:provider/provider.dart';

import '../../../helpers/ux_checks.dart';

void main() {
  testWidgets('the ring\'s Left and Eaten are each a 48 dp tap target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
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
      textScale: 1,
    );
    await tester.pumpAndSettle();
    for (final label in ['Left', 'Eaten']) {
      final rect = tester
          .getSemantics(
            find.descendant(
              of: find.byKey(const ValueKey('home-ring-mode')),
              matching: find.text(label),
            ),
          )
          .rect;
      expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      expect(rect.width, greaterThanOrEqualTo(48), reason: label);
    }
    semantics.dispose();
  });
}
