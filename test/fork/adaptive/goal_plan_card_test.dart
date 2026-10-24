import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

class _Plan extends Fake implements AdaptiveService {
  @override
  Future<GoalPlanInputs?> goalPlan({int pastDays = 60}) async =>
      const GoalPlanInputs(
        pastTrendKg: [91, 90.4],
        trendKgPerDay: -0.05,
        expenditureKcal: 2500,
        bodyFatPercent: 25,
        targetWeightKg: 80,
        paceKgPerWeek: -0.5,
      );
}

class _Phases extends Fake implements PhaseStore {
  int step = 0;

  @override
  Future<int> milestoneStep() async => step;

  @override
  Future<void> saveMilestoneStep(int step) async => this.step = step;
}

void main() {
  testWidgets('milestones are off until chosen, then dated and kept', (
    tester,
  ) async {
    final phases = _Phases();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalPlanCard(
              palette: AppPalette.light,
              unit: BodyWeightUnit.kg,
              service: _Plan(),
              phases: phases,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('88.0 kg'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('plan-milestones-2')));
    await tester.tap(find.byKey(const ValueKey('plan-milestones-2')));
    await tester.pumpAndSettle();
    // Every 2 kg from 90.4 at 0.5 kg a week: 90 in 6 days, 88 in 34.
    for (final kg in ['90.0 kg', '88.0 kg', '86.0 kg', '84.0 kg', '82.0 kg']) {
      expect(find.text(kg), findsOneWidget);
    }
    expect(find.textContaining('(1 week)'), findsOneWidget);
    expect(find.textContaining('(5 weeks)'), findsOneWidget);
    expect(phases.step, 2);
  });
}
