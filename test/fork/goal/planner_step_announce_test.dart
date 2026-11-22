import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// The step line is a live region, so TalkBack says the new step on Next
/// and Back.
void main() {
  testWidgets('the step line is a live region on every step', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: GoalPlannerScreen(
            setup: const PlannerSetup(
              nowKg: 84,
              unit: BodyWeightUnit.kg,
              expenditureKcal: 2600,
              bodyFatPercent: 22,
            ),
            draft: GoalDraft.fresh(84, DateTime(2026, 10, 5), targetKg: 80),
            onStart: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.textContaining('Step 1 of')),
      isSemantics(isLiveRegion: true),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.textContaining('Step 2 of')),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });
}
