// Leftover G4 items: G4-7 (calendar day sheet, month labels), G4-12
// (completed goals dates), G4-19 (one unit label and pace format, history
// named), G4-25 (a tiny remaining change ends this week).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_calendar_page.dart';
import 'package:opennutritracker/fork/goal/goal_explained.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_status.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _Phases extends PhaseStore {
  final PhasePlan? saved;

  _Phases(this.saved);

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<List<PhasePlan>> upcoming() async => [];

  @override
  Future<List<GoalRecord>> history() async => [];
}

Future<void> _pump(WidgetTester tester, Widget home) async {
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('G4-19: paces drop a trailing zero, weights say lb', () {
    expect(signedPaceText(-0.5, BodyWeightUnit.kg), '−0.5 kg a week');
    expect(signedPaceText(-0.25, BodyWeightUnit.kg), '−0.25 kg a week');
    expect(signedPaceText(-0.5, BodyWeightUnit.lb), '−1.1 lb a week');
    expect(signedPaceText(0.001, BodyWeightUnit.kg), '0.0 kg a week');
    expect(goalWeightLabel(BodyWeightUnit.lb), 'lb');
    expect(goalWeightLabel(BodyWeightUnit.kg), 'kg');
  });

  test('G4-7: the first column\'s part month gives way to the next', () {
    // Monday Oct 19: two weeks of October, then November from Nov 2.
    List<int> months(double width) => [
      for (final l in gridMonthLabels(
        from: DateTime(2026, 10, 19),
        weeks: 12,
        cell: 14,
        width: (_) => width,
      ))
        l.month.month,
    ];
    // "Oct" fits in its two weeks: November is named too (it was not).
    expect(months(20), [10, 11, 12, 1]);
    // Too wide for both: October gives way, never November.
    expect(months(30), [11, 12, 1]);
  });

  test('G4-25: a change reached this week ends the goal with this week', () {
    // Saturday Nov 21, day one of a cut from 87.1 kg.
    final start = DateTime(2026, 11, 16);
    final plan = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 87.1,
      targetKg: 82,
      start: start,
      paceKg: 0.5,
    ).toPlan();
    final today = DateTime(2026, 11, 21);
    final edited = editedPlan(
      plan,
      GoalDraft.of(plan, 87.1).copyWith(targetKg: () => 87.0),
      today: today,
      nowKg: 87.1,
    );
    expect(edited.phases, hasLength(1));
    expect(edited.phases.single.untilKg, 87.0);
    expect(edited.targetKg, 87.0);
    expect(edited.lastDay, DateTime(2026, 11, 22));
  });

  test('G4-25: a faster pace that only it reaches this week does not end '
      'the goal at the old pace', () {
    final start = DateTime(2026, 11, 16);
    final plan = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 82.4,
      targetKg: 82,
      start: start,
      paceKg: 0.25,
    ).toPlan();
    final edited = editedPlan(
      plan,
      GoalDraft.of(plan, 82.4).copyWith(paceKg: 0.5),
      today: start,
      nowKg: 82.4,
    );
    // At 0.25 kg a week this week ends near 82.15, short of 82.
    expect(edited.lastDay.isAfter(DateTime(2026, 11, 22)), isTrue);
  });

  testWidgets('G4-7: the day sheet names the day tapped', (tester) async {
    final cut = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 86.4,
      targetKg: 80,
      start: DateTime(2026, 10, 5),
    ).toPlan();
    final today = DateTime(2026, 10, 29);
    final store = _Phases(cut);
    await _pump(
      tester,
      GoalCalendarPage(
        unit: BodyWeightUnit.kg,
        nowKg: 85.1,
        today: today,
        store: store,
        actions: GoalActions(
          store: store,
          save: (_, _) async => true,
          clock: () => today,
        ),
      ),
    );
    final day = find.bySemanticsIdentifier('goal-calendar-day-2026-11-10');
    await tester.scrollUntilVisible(day, 300);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('Tue, Nov 10 is in this goal'), findsOneWidget);
  });

  testWidgets('G4-12: completed goals\' chart says when it starts', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 29);
    await _pump(
      tester,
      CompletedGoalsPage(
        unit: BodyWeightUnit.kg,
        load: () async => (
          history: [
            GoalRecord(
              kind: PhaseKind.cut,
              start: DateTime(2026, 10, 1),
              end: DateTime(2026, 10, 28),
              startKg: 87,
              endKg: 85.6,
            ),
          ],
          running: null,
          trend: const [86.0, 85.8, 85.6],
          today: today,
        ),
      ),
    );
    final dates = find.byKey(const ValueKey('completed-goals-chart-dates'));
    expect(dates, findsOneWidget);
    expect(
      find.descendant(of: dates, matching: find.text('Oct 27, 2026')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dates, matching: find.text('Today')),
      findsOneWidget,
    );
  });

  testWidgets('G4-19: the explainer names the check-in history', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
    );
    addTearDown(
      () => AdaptiveStore.settings.value = const AdaptiveSettings(),
    );
    await _pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (_) => GoalExplainedBody(
            breakdown: KcalGoalBreakdownEntity.compute(
              user: UserEntity(
                birthday: DateTime(1990, 1, 1),
                heightCM: 180,
                weightKG: 80,
                gender: UserGenderEntity.male,
                goal: UserWeightGoalEntity.maintainWeight,
                pal: UserPALEntity.sedentary,
              ),
              totalKcalActivities: 0,
            ),
            showTargetNote: true,
            onInputs: () {},
            onEquations: () {},
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('goal-explained-check-in-history'));
    expect(
      find.descendant(of: row, matching: find.text('Check-in history')),
      findsOneWidget,
    );
  });

  testWidgets('G4-19: the You tile says lb to go, not lbs', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: GoalYouTile(
          title: 'Goal',
          unit: BodyWeightUnit.lb,
          targetKg: 80,
          pace: (goal: UserWeightGoalEntity.loseWeight, kgPerWeek: -0.4),
          load: () async => (
            progress: null,
            nowKg: 87.1,
            plan: null,
            history: const <GoalRecord>[],
            pace: null,
          ),
        ),
      ),
    );
    expect(tester.widget<TrendTile>(find.byType(TrendTile)).suffix, 'lb to go');
  });
}
