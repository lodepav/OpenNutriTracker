import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_calendar_page.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Monday 5 October 2026; the cut runs to Jan 3, the queue after it.
final _cut = GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: DateTime(2026, 10, 5),
).toPlan();

final _hold = GoalDraft(
  kind: PhaseKind.maintain,
  startKg: 80,
  start: DateTime(2027, 1, 4),
  maintainWeeks: 4,
).toPlan();

final _bulk = GoalDraft(
  kind: PhaseKind.bulk,
  startKg: 80,
  targetKg: 84,
  start: DateTime(2027, 2, 1),
  paceKg: 0.25,
).toPlan();

final _done = GoalRecord(
  kind: PhaseKind.cut,
  start: DateTime(2026, 1, 5),
  end: DateTime(2026, 4, 6),
  startKg: 88,
  endKg: 81.2,
  targetKg: 81,
);

class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;
  final queue = <PhasePlan>[];
  final goals = <GoalRecord>[];

  _MemoryPhases(this.saved, List<PhasePlan> queue) {
    this.queue.addAll(queue);
  }

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<void> save(PhasePlan? plan) async => saved = plan;

  @override
  Future<List<PhasePlan>> upcoming() async => [...queue];

  @override
  Future<void> saveUpcoming(List<PhasePlan> plans) async => queue
    ..clear()
    ..addAll(plans);

  @override
  Future<List<GoalRecord>> history() async => goals;

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      goals.addAll(records);
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

Finder _id(String id) => find.bySemanticsIdentifier(id);

void main() {
  final today = DateTime(2026, 10, 29);
  final saved = <(double?, double?)>[];
  GoalActions actionsOn(PhaseStore store) => GoalActions(
    store: store,
    save: (pace, target) async {
      saved.add((pace, target));
      return true;
    },
    clock: () => today,
  );

  setUp(saved.clear);

  Widget section(_MemoryPhases store, {VoidCallback? onChanged}) => Scaffold(
    body: SingleChildScrollView(
      child: GoalPlanSection(
        plan: store.saved,
        upcoming: store.queue,
        history: store.goals,
        nowKg: 85,
        unit: BodyWeightUnit.kg,
        today: today,
        onChanged: onChanged ?? () {},
        actions: () => actionsOn(store),
      ),
    ),
  );

  testWidgets('Up next moves a goal later, and Undo puts it back', (
    tester,
  ) async {
    final store = _MemoryPhases(_cut, [_hold, _bulk]);
    await _pump(tester, section(store));
    await tester.scrollUntilVisible(_id('goal-upcoming-0-menu'), 200);
    await tester.tap(_id('goal-upcoming-0-menu'));
    await tester.pumpAndSettle();
    expect(find.text('Move earlier'), findsNothing);
    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    expect(
      [for (final p in store.queue) p.kind],
      [PhaseKind.bulk, PhaseKind.maintain],
    );
    expect(find.text('Moved'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      [for (final p in store.queue) p.kind],
      [PhaseKind.maintain, PhaseKind.bulk],
    );
    expect(store.saved, same(_cut));
  });

  testWidgets('the running goal opens on a tap: complete it now', (
    tester,
  ) async {
    final store = _MemoryPhases(_cut, [_hold]);
    var changed = 0;
    await _pump(tester, section(store, onChanged: () => changed++));
    await tester.scrollUntilVisible(_id('goal-phase-0'), 200);
    await tester.tap(_id('goal-phase-0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete it now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(store.goals.single.kind, PhaseKind.cut);
    expect(store.saved!.kind, PhaseKind.maintain);
    expect(changed, greaterThan(0));
  });

  testWidgets('an Undo goes once the goals change again', (tester) async {
    final store = _MemoryPhases(_cut, [_hold, _bulk]);
    await _pump(tester, section(store));
    await tester.scrollUntilVisible(_id('goal-upcoming-0-menu'), 200);
    await tester.tap(_id('goal-upcoming-0-menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    // Completed elsewhere, as from the calendar.
    PhaseStore.changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Up next removes a goal with an Undo; one alone has no moves', (
    tester,
  ) async {
    final store = _MemoryPhases(_cut, [_hold]);
    await _pump(tester, section(store));
    await tester.scrollUntilVisible(_id('goal-upcoming-0-menu'), 200);
    await tester.tap(_id('goal-upcoming-0-menu'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Move'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(store.queue, isEmpty);
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect([for (final p in store.queue) p.kind], [PhaseKind.maintain]);
  });

  testWidgets('Up next flags a goal left behind its target', (tester) async {
    // A bulk to 84 that now starts at 85: nothing to gain.
    final stale = PhasePlan(
      start: DateTime(2027, 1, 4),
      startKg: 85,
      targetKg: 84,
      phases: const [
        DietPhase(kind: PhaseKind.bulk, kgPerWeek: 0.25, weeks: 1),
      ],
    );
    await _pump(tester, section(_MemoryPhases(_cut, [_hold, stale])));
    await tester.scrollUntilVisible(_id('goal-upcoming-1'), 200);
    expect(find.textContaining('behind where it now starts'), findsOneWidget);
  });

  testWidgets('a goal with no target: until its end, then since it', (
    tester,
  ) async {
    late ({String value, String? note}) before, after;
    await _pump(
      tester,
      Builder(
        builder: (context) {
          before = untargetedGoal(context, _hold, null, today: today);
          after = untargetedGoal(
            context,
            _hold,
            null,
            today: DateTime(2027, 2, 1),
          );
          return const SizedBox();
        },
      ),
    );
    // The hold runs Jan 4 to Jan 31; on Feb 1 it has ended.
    expect(before, (value: 'Maintain', note: 'until Jan 31'));
    expect(after, (value: 'Maintain', note: 'since Feb 1'));
  });

  testWidgets('the two plan buttons stack full width', (tester) async {
    await _pump(tester, section(_MemoryPhases(_cut, [_hold])));
    final edit = tester.getRect(_id('goal-plan-edit'));
    final next = tester.getRect(_id('goal-plan-new'));
    expect(next.top, greaterThan(edit.bottom));
    expect(next.width, edit.width);
  });

  testWidgets('removing the running goal from the calendar is undone', (
    tester,
  ) async {
    final store = _MemoryPhases(_cut, [_hold]);
    await _pump(
      tester,
      GoalCalendarPage(
        unit: BodyWeightUnit.kg,
        nowKg: 85.1,
        today: today,
        store: store,
        actions: actionsOn(store),
      ),
    );
    await tester.tap(_id('goal-calendar-day-2026-10-29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove this goal'));
    await tester.pumpAndSettle();
    expect(find.text('It is not saved in your completed goals.'), findsOne);
    await tester.tap(_id('goal-calendar-confirm'));
    await tester.pumpAndSettle();
    expect(store.saved!.kind, PhaseKind.maintain);
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.saved, same(_cut));
    expect(store.queue.single.start, _cut.end);
    // The cut's pace and target are the profile's again.
    expect(saved.last, (_cut.paceOn(today), 80.0));
  });

  testWidgets('no goal: "No goal", or maintaining since the last one', (
    tester,
  ) async {
    Widget tile(List<GoalRecord> history, {bool profileGoal = false}) =>
        Scaffold(
          body: GoalYouTile(
            key: UniqueKey(),
            title: 'Goal',
            value: 'Keep',
            note: null,
            below: 'Not set',
            profileGoal: profileGoal,
            onTap: () {},
            load: () async => (plan: null, history: history),
          ),
        );
    await _pump(tester, tile(const []));
    expect(find.text(noGoalText), findsOneWidget);
    expect(find.text('Plan a goal'), findsOneWidget);
    expect(find.text('Keep'), findsNothing);

    await _pump(tester, tile([_done]));
    expect(
      find.text('Maintain since Apr 6', findRichText: true),
      findsOneWidget,
    );

    await _pump(tester, tile([_done], profileGoal: true));
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);

    // A maintenance goal running is named, not "Keep · Not set".
    await _pump(
      tester,
      Scaffold(
        body: GoalYouTile(
          key: UniqueKey(),
          title: 'Goal',
          value: 'Keep',
          note: null,
          below: 'Not set',
          profileGoal: true,
          onTap: () {},
          load: () async => (plan: _hold, history: const <GoalRecord>[]),
        ),
      ),
    );
    expect(
      find.text('Maintain until Jan 31', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Not set'), findsNothing);

    final store = _MemoryPhases(null, const [])..goals.add(_done);
    await _pump(tester, section(store));
    expect(find.text('Maintaining since Apr 6'), findsOneWidget);
  });

  test('one rule for a goal\'s weeks: rounded, at least one', () {
    final d = DateTime(2026, 10, 29);
    expect(goalWeeks(d, d), 1);
    expect(goalWeeks(d, DateTime(2026, 11, 8)), 1);
    expect(goalWeeks(d, DateTime(2026, 11, 9)), 2);
    expect(_done.weeks, goalWeeks(_done.start, _done.end));
  });

  group('Goal progress', () {
    final t = DateTime.now();
    final now = DateTime(t.year, t.month, t.day);

    Future<void> pumpProgress(
      WidgetTester tester, {
      required int daysIn,
      PhasePlan? plan,
    }) {
      final trend = [for (var i = 0; i <= daysIn; i++) 86.4 - 0.05 * i];
      final start = now.subtract(Duration(days: daysIn));
      return _pump(
        tester,
        GoalProgressPage(
          unit: BodyWeightUnit.kg,
          loadGoal: () async => (
            inputs: GoalPlanInputs(
              pastTrendKg: trend,
              trendKgPerDay: null,
              expenditureKcal: 2500,
              bodyFatPercent: 20,
              targetWeightKg: 80,
              paceKgPerWeek: -0.5,
            ),
            progress: GoalProgress(
              start: GoalStart(date: start, kg: 86.4, targetKg: 80),
              nowKg: trend.last,
              paceKgPerWeek: -0.5,
              trend: trend,
              today: now,
            ),
          ),
          loadCalories: () async => (goalKcal: null, meanKcal: null),
          loadPlans: () async => (
            plan: plan,
            upcoming: const <PhasePlan>[],
            history: const <GoalRecord>[],
          ),
        ),
      );
    }

    testWidgets('on the first day: "Started today"', (tester) async {
      await pumpProgress(tester, daysIn: 0);
      await tester.scrollUntilVisible(find.text('Started today'), 200);
      expect(find.textContaining('in 0 days'), findsNothing);
    });

    testWidgets("the plan's line reaches the target on the plan's end", (
      tester,
    ) async {
      final start = now.subtract(const Duration(days: 14));
      // Diet breaks: the plan ends later than the pace alone would.
      final plan = GoalDraft(
        kind: PhaseKind.cut,
        startKg: 86.4,
        targetKg: 80,
        start: start,
        paceKg: 0.5,
        breaks: true,
      ).toPlan();
      await pumpProgress(tester, daysIn: 14, plan: plan);
      final chart = tester.widget<LineChart>(find.byType(LineChart).first);
      final last = CalendarDayCalc.daysBetween(
        start,
        plan.end.subtract(const Duration(hours: 12)),
      );
      expect(
        chart.data.lineBarsData.any(
          (b) => b.spots.length == 2 && b.spots.last.x == last,
        ),
        isTrue,
      );
      final exact = daysToTarget(86.4, 80, -0.5 / 7)!;
      expect(last, greaterThan(exact));
    });
  });
}
