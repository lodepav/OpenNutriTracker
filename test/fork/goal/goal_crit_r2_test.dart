import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phase_report.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// The critique's cut: Nov 21 from 87.1 kg to 82 at 0.5 kg a week.
final _day0 = DateTime(2026, 11, 21);
PhasePlan _planFrom(DateTime start) => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 87.1,
  targetKg: 82,
  start: start,
  paceKg: 0.5,
).toPlan();

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

/// Saves to the settings in use; [checkIn] is the last one accepted.
class _Store extends Fake implements AdaptiveStore {
  final CheckInRecord? checkIn;

  _Store([this.checkIn]);

  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<CheckInRecord?> lastCheckIn() async => checkIn;
}

Finder _id(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  group('one arrival date', () {
    test('a begun goal opened unchanged keeps its plan, not one from the '
        'trend now', () {
      final plan = _planFrom(_day0);
      // After a weigh-in the trend is 86.6: planned again it ended Jan 29.
      final draft = GoalDraft.of(plan, 86.6).copyWith(startKg: 86.6);
      final edited = editedPlan(
        plan,
        draft,
        today: DateTime(2026, 11, 22),
        nowKg: 86.6,
      );
      expect(identical(edited, plan), isTrue);
      expect(edited.lastDay, DateTime(2027, 2, 5));
      // A change still plans what is to go from the trend now.
      final faster = editedPlan(
        plan,
        draft.copyWith(paceKg: 0.75),
        today: DateTime(2026, 11, 22),
        nowKg: 86.6,
      );
      expect(identical(faster, plan), isFalse);
      // Past its end, saved as it was, it is still planned on from now.
      final over = editedPlan(
        plan,
        draft,
        today: DateTime(2027, 3, 1),
        nowKg: 84,
      );
      expect(identical(over, plan), isFalse);
      expect(over.end.isAfter(plan.end), isTrue);
    });

    test("the plan's last day, its whole weeks counted, while it reaches "
        'the target; else from today at its pace', () {
      final plan = _planFrom(_day0);
      final progress = GoalProgress(
        start: GoalStart(
          date: _day0,
          kg: 87.1,
          targetKg: 82,
          paceKgPerWeek: -0.5,
        ),
        nowKg: 87.1,
        paceKgPerWeek: -0.5,
        trend: const [87.1],
        today: _day0,
      );
      final a = goalArrivals(progress, plan);
      // The check-in said Feb 1 (72 days at the pace), the plan Feb 5.
      expect(a.byPlan, DateTime(2027, 2, 5));
      expect(a.planEnds, isTrue);
      expect(a.recent, isNull);
      expect(a.atRecent, isNull);
      final none = goalArrivals(progress, null);
      expect(none.planEnds, isFalse);
      expect(none.byPlan, DateTime(2027, 2, 1));
    });
  });

  group('Edit plan', () {
    final today = DateTime(2026, 11, 22);
    final running = _planFrom(_day0);
    Widget opener() => Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => GoalPlannerScreen(
                setup: PlannerSetup(
                  nowKg: 86.6,
                  unit: BodyWeightUnit.kg,
                  expenditureKcal: 3045,
                  formulaKcal: 2738,
                  bodyFatPercent: 22,
                  running: running,
                ),
                draft: GoalDraft.of(running, 86.6).copyWith(startKg: 86.6),
                editing: running,
                today: today,
                store: _Store(),
                onStart: (_) async => true,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    testWidgets('opens on the saved plan and closes without asking when '
        'nothing changed', (tester) async {
      await _pump(tester, opener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Feb 5, 2027'), findsWidgets);
      expect(find.textContaining('Jan 29, 2027'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('asks once the pace changed', (tester) async {
      await _pump(tester, opener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final change = find.descendant(
        of: _id('goal-plan-change-pace'),
        matching: find.text('Change'),
      );
      await tester.scrollUntilVisible(
        change,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Fast ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
    });

    testWidgets('asks once a setting changed', (tester) async {
      await _pump(tester, opener());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      AdaptiveStore.settings.value = AdaptiveStore.settings.value.copyWith(
        adaptiveTarget: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
    });
  });

  group('the planner on Adaptive', () {
    GoalPlannerScreen planner({CheckInRecord? checkIn}) => GoalPlannerScreen(
      setup: const PlannerSetup(
        nowKg: 87.1,
        unit: BodyWeightUnit.kg,
        expenditureKcal: 3036,
        formulaKcal: 2738,
        bodyFatPercent: 22,
      ),
      draft: GoalDraft.fresh(87.1, _day0, targetKg: 82),
      today: _day0,
      store: _Store(checkIn),
      onStart: (_) async => true,
    );

    Future<void> toStep(WidgetTester tester, String name) async {
      while (find
          .byKey(ValueKey('goal-planner-step-$name'))
          .evaluate()
          .isEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('before the first check-in the plan says when its target '
        'starts', (tester) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await _pump(tester, planner());
      await toStep(tester, 'plan');
      expect(
        find.byKey(const ValueKey('goal-plan-adaptive-starts')),
        findsOneWidget,
      );
    });

    testWidgets('after a check-in, or on Formula, nothing is said', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await _pump(
        tester,
        planner(
          checkIn: CheckInRecord(
            date: _day0,
            expenditureKcal: 3036,
            proposedKcal: 2545,
            acceptedKcal: 2545,
          ),
        ),
      );
      await toStep(tester, 'plan');
      expect(
        find.byKey(const ValueKey('goal-plan-adaptive-starts')),
        findsNothing,
      );
      AdaptiveStore.settings.value = const AdaptiveSettings();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('goal-plan-adaptive-starts')),
        findsNothing,
      );
    });

    testWidgets("the pace's deficit says why it is not the Formula's", (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await _pump(tester, planner());
      await toStep(tester, 'pace');
      await tester.scrollUntilVisible(
        find.textContaining('On Adaptive a kg counts as about'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await toStep(tester, 'target');
      await tester.scrollUntilVisible(
        find.textContaining('On Adaptive a kg counts as about'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      // Counted flat, the two agree: nothing to explain.
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        flatEnergy: true,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('On Adaptive a kg counts as about'),
        findsNothing,
      );
    });

    testWidgets('the target step prints the pace as the pace step does', (
      tester,
    ) async {
      await _pump(tester, planner());
      await toStep(tester, 'target');
      expect(find.text('Pace, 0.5 kg a week'), findsOneWidget);
    });
  });

  testWidgets('the explainer says a change applies from the end of the '
      'week', (tester) async {
    final t = DateTime.now();
    final now = DateTime(t.year, t.month, t.day);
    await _pump(
      tester,
      GoalProgressPage(
        unit: BodyWeightUnit.kg,
        loadGoal: () async => (
          inputs: const GoalPlanInputs(
            pastTrendKg: [87.1],
            trendKgPerDay: null,
            expenditureKcal: 3036,
            bodyFatPercent: 22,
            targetWeightKg: 82,
            paceKgPerWeek: -0.5,
          ),
          progress: GoalProgress(
            start: GoalStart(date: now, kg: 87.1, targetKg: 82),
            nowKg: 87.1,
            paceKgPerWeek: -0.5,
            trend: const [87.1],
            today: now,
          ),
        ),
        loadCalories: () async => (goalKcal: null, meanKcal: null),
        loadPlans: () async => (
          plan: _planFrom(now),
          upcoming: const <PhasePlan>[],
          history: const <GoalRecord>[],
        ),
      ),
    );
    // Goal progress's date is the shared one, the plan's last day.
    final last = _planFrom(now).lastDay;
    final shown =
        (last.year == now.year
                ? intl.DateFormat.MMMd('en')
                : intl.DateFormat.yMMMd('en'))
            .format(last);
    await tester.scrollUntilVisible(find.text('By your plan'), 200);
    expect(find.text(shown), findsOneWidget);
    final link = find.text('How is the plan worked out?');
    await tester.scrollUntilVisible(link, 200);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A pace change applies from the end of the current'),
      findsOneWidget,
    );
    expect(find.textContaining('starts again from that day'), findsNothing);
  });

  testWidgets("a phase's first day shows its figures once, no arrow", (
    tester,
  ) async {
    final plan = _planFrom(_day0);
    await tester.pumpWidget(
      MaterialApp(
        home: PhaseReportsPage(
          plan: plan,
          unit: BodyWeightUnit.kg,
          today: _day0,
          load: () async => (
            trendByDay: {_day0: 87.1},
            trackedDays: const <TrackedDayEntity>[],
            burnByDay: {_day0: 3036.0},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('87.1 kg'), findsOneWidget);
    expect(find.textContaining('→'), findsNothing);
    expect(find.text('3036 kcal'), findsOneWidget);
  });
}
