import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_calendar_page.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/goal/goal_status.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _start = DateTime(2026, 10, 5);

PhasePlan _cut({DateTime? start}) => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 87.1,
  targetKg: 80,
  start: start ?? _start,
  paceKg: 0.5,
  breaks: false,
).toPlan();

class _MemoryPhases extends PhaseStore {
  final PhasePlan? saved;
  final List<GoalRecord> goals;

  _MemoryPhases(this.saved, {this.goals = const []});

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<List<GoalRecord>> history() async => goals;

  @override
  Future<List<PhasePlan>> upcoming() async => const [];
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

double _tileWidth(WidgetTester tester, String label) => tester
    .getSize(
      find.ancestor(of: find.text(label), matching: find.byType(FigureTile)),
    )
    .width;

void main() {
  group('the goal calendar', () {
    final today = DateTime(2026, 10, 29);
    final longAgo = GoalRecord(
      kind: PhaseKind.bulk,
      start: DateTime(2025, 1, 6),
      end: DateTime(2025, 4, 6),
      startKg: 80,
      endKg: 84,
      targetKg: 84,
    );

    test('names the kinds its goals have', () {
      expect(CalendarGoals(plan: _cut()).kinds, {PhaseKind.cut});
      expect(CalendarGoals(plan: _cut(), history: [longAgo]).kinds, {
        PhaseKind.cut,
        PhaseKind.bulk,
      });
    });

    testWidgets('the legend has only the kinds shown, Up next only with a '
        'goal queued', (tester) async {
      await _pump(
        tester,
        GoalCalendarPage(
          unit: BodyWeightUnit.kg,
          nowKg: null,
          today: today,
          store: _MemoryPhases(_cut()),
        ),
      );
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Maintenance'), findsNothing);
      expect(find.text('Bulk'), findsNothing);
      expect(find.text('Up next'), findsNothing);
    });

    testWidgets('the legend and the hint stay on screen when it opens at '
        'today', (tester) async {
      await _pump(
        tester,
        GoalCalendarPage(
          unit: BodyWeightUnit.kg,
          nowKg: null,
          today: today,
          store: _MemoryPhases(_cut(), goals: [longAgo]),
        ),
      );
      expect(find.text('October 2026').hitTestable(), findsOneWidget);
      expect(
        find.textContaining('Tap a day to edit or remove').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Bulk').hitTestable(), findsOneWidget);
    });
  });

  test('a range of one day prints the day once', () {
    final format = intl.DateFormat.yMMMd('en');
    expect(
      dateRangeText(format, DateTime(2026, 11, 21), DateTime(2026, 11, 21, 18)),
      'Nov 21, 2026',
    );
    expect(
      dateRangeText(format, DateTime(2026, 11, 21), DateTime(2026, 11, 23)),
      'Nov 21, 2026 – Nov 23, 2026',
    );
  });

  testWidgets('completed goals on the running goal\'s first day: started '
      'today, no change', (tester) async {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    await _pump(
      tester,
      CompletedGoalsPage(
        unit: BodyWeightUnit.kg,
        load: () async => (
          history: const <GoalRecord>[],
          running: _cut(start: today),
          trend: const [87.1, 87.1],
          today: today,
        ),
      ),
    );
    expect(find.text('Started today'), findsOneWidget);
    expect(find.textContaining('so far'), findsNothing);
    expect(find.textContaining('87.1 kg → 87.1 kg'), findsNothing);
  });

  testWidgets('Goal reached on its first day: one date, the odd tile wide', (
    tester,
  ) async {
    await _pump(
      tester,
      GoalReachedPage(
        plan: _cut(),
        nowKg: 79.9,
        unit: BodyWeightUnit.kg,
        today: _start,
        load: (_) async =>
            GoalRun(trend: const [], first: _start, expenditureKcal: 2500),
        upcoming: () async => const [],
      ),
    );
    expect(find.text('Oct 5, 2026 · 1 day'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('You burn now'), 200);
    expect(
      _tileWidth(tester, 'You burn now'),
      greaterThan(1.5 * _tileWidth(tester, 'Change')),
    );
  });

  testWidgets('Goal progress on day one: the lone tile spans the row', (
    tester,
  ) async {
    final t = DateTime.now();
    final now = DateTime(t.year, t.month, t.day);
    await _pump(
      tester,
      GoalProgressPage(
        unit: BodyWeightUnit.kg,
        loadGoal: () async => (
          inputs: GoalPlanInputs(
            pastTrendKg: const [87.1],
            trendKgPerDay: null,
            expenditureKcal: 2500,
            bodyFatPercent: 20,
            targetWeightKg: 80,
            paceKgPerWeek: -0.5,
          ),
          progress: GoalProgress(
            start: GoalStart(date: now, kg: 87.1, targetKg: 80),
            nowKg: 87.1,
            paceKgPerWeek: -0.5,
            trend: const [87.1],
            today: now,
          ),
        ),
        loadCalories: () async => (goalKcal: 2400.0, meanKcal: null),
        loadPlans: () async => (
          plan: null,
          upcoming: const <PhasePlan>[],
          history: const <GoalRecord>[],
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Calorie goal now'), 200);
    // 800 wide less the gutters: a whole row, not half of one.
    expect(_tileWidth(tester, 'Calorie goal now'), greaterThan(600));
  });
}
