import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_calendar_page.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Monday 5 October 2026; the cut runs 13 weeks, to Jan 3.
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
  kind: PhaseKind.bulk,
  start: DateTime(2026, 6, 1),
  end: DateTime(2026, 8, 30),
  startKg: 81.2,
  endKg: 85.9,
  targetKg: 86,
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

Finder _day(int year, int month, int day) =>
    find.bySemanticsIdentifier('goal-calendar-day-$year-$month-$day');

void main() {
  final today = DateTime(2026, 10, 29);
  final goals = CalendarGoals(
    plan: _cut,
    upcoming: [_hold, _bulk],
    history: [_done],
  );

  test('a day is in the running goal, a queued one or a completed one', () {
    expect(goals.on(DateTime(2026, 10, 29))?.current, isTrue);
    expect(goals.on(DateTime(2027, 1, 4))?.queued, 0);
    expect(goals.on(DateTime(2027, 2, 1))?.kind, PhaseKind.bulk);
    expect(goals.on(DateTime(2026, 8, 30))?.record, same(_done));
    expect(goals.on(DateTime(2026, 9, 1)), isNull);
    final span = goals.span(today)!;
    expect(span.first, DateTime(2026, 6, 1));
    expect(span.last, _bulk.end.subtract(const Duration(hours: 12)).date);
  });

  test("a month's lines name each goal and when it runs in it", () async {
    await initializeDateFormatting('en');
    String? linesIn(DateTime month) => [
      for (final b in goals.bands(BodyWeightUnit.kg))
        ?b.lineIn(month, DateTime(month.year, month.month + 1), 'en'),
    ].join(' / ');
    expect(linesIn(DateTime(2026, 10)), 'Cut to 80.0 kg · from Oct 5');
    expect(
      linesIn(DateTime(2027, 1)),
      'Cut to 80.0 kg · until Jan 3 / '
      'Maintenance, 4 weeks · Jan 4 – 31 · up next',
    );
    expect(linesIn(DateTime(2026, 7)), 'Bulk to 86.0 kg · done');
  });

  testWidgets('a queued goal is moved or removed from its day', (tester) async {
    final store = _MemoryPhases(_cut, [_hold, _bulk]);
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
    expect(find.text('October 2026'), findsOneWidget);

    await tester.scrollUntilVisible(_day(2027, 2, 3), 300);
    await tester.tap(_day(2027, 2, 3));
    await tester.pumpAndSettle();
    expect(find.text('Bulk · up next, 2nd'), findsOneWidget);
    expect(find.text('Move before Maintenance, 4 weeks'), findsOneWidget);
    expect(find.textContaining('Move after'), findsNothing);
    await tester.tap(find.text('Move before Maintenance, 4 weeks'));
    await tester.pumpAndSettle();
    expect(
      [for (final p in store.queue) p.kind],
      [PhaseKind.bulk, PhaseKind.maintain],
    );
    expect(store.queue.first.start, _cut.end);

    await tester.scrollUntilVisible(_day(2027, 1, 5), -300);
    await tester.tap(_day(2027, 1, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove this goal'));
    await tester.pumpAndSettle();
    // Asked first.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.queue, hasLength(2));
    await tester.tap(find.text('Remove this goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect([for (final p in store.queue) p.kind], [PhaseKind.maintain]);
  });

  testWidgets('the running goal is completed now from today', (tester) async {
    final store = _MemoryPhases(_cut, [_hold]);
    final saved = <(double?, double?)>[];
    await _pump(
      tester,
      GoalCalendarPage(
        unit: BodyWeightUnit.kg,
        nowKg: 85.1,
        today: today,
        store: store,
        actions: GoalActions(
          store: store,
          save: (pace, target) async {
            saved.add((pace, target));
            return true;
          },
          clock: () => today,
        ),
      ),
    );
    await tester.tap(_day(2026, 10, 29));
    await tester.pumpAndSettle();
    expect(find.text('Cut · now'), findsOneWidget);
    expect(find.textContaining('week 4 of 13'), findsOneWidget);
    expect(
      find.text(
        'Keeps it in completed goals; Maintenance, 4 weeks starts today',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Complete it now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(store.goals.single.kind, PhaseKind.cut);
    expect(store.saved!.kind, PhaseKind.maintain);
    expect(store.saved!.start, today);
    expect(saved, [(0.0, null)]);
    // A completed day opens nothing.
    expect(find.text('Cut · now'), findsNothing);
  });

  testWidgets('the Today button and the edit row', (tester) async {
    final store = _MemoryPhases(_cut, [_hold]);
    final edited = <int?>[];
    await _pump(
      tester,
      GoalCalendarPage(
        unit: BodyWeightUnit.kg,
        nowKg: null,
        today: today,
        store: store,
        edit: (_, i) async {
          edited.add(i);
          return true;
        },
      ),
    );
    await tester.scrollUntilVisible(_day(2027, 1, 20), 300);
    await tester.tap(_day(2027, 1, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit this goal'));
    await tester.pumpAndSettle();
    expect(edited, [0]);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    await tester.tap(_day(2026, 10, 29));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit the plan'));
    await tester.pumpAndSettle();
    expect(edited, [0, null]);
  });

  testWidgets('Goal reached names the goal that starts next', (tester) async {
    await _pump(
      tester,
      GoalReachedPage(
        plan: _cut,
        nowKg: 79.9,
        unit: BodyWeightUnit.kg,
        today: DateTime(2027, 1, 4),
        load: (_) async => GoalRun(trend: const [], first: _cut.start),
        upcoming: () async => [_hold],
      ),
    );
    await tester.scrollUntilVisible(find.text('Continue'), 200);
    expect(find.text('Mark completed and start the next'), findsOneWidget);
    expect(find.text('Maintenance, 4 weeks starts today.'), findsOneWidget);
    expect(find.text('Mark completed and plan the next'), findsNothing);
  });

  testWidgets('a new weight picked is changed by tapping its row again', (
    tester,
  ) async {
    await _pump(
      tester,
      Scaffold(
        body: ExtendSheet(
          plan: _cut,
          nowKg: 80.8,
          unit: BodyWeightUnit.kg,
          ended: true,
          today: _cut.end,
          actions: GoalActions(
            store: _MemoryPhases(_cut, const []),
            save: (_, _) async => true,
            clock: () => _cut.end,
          ),
        ),
      ),
    );
    await tester.tap(find.text('To a new weight'));
    await tester.pumpAndSettle();
    expect(find.byType(SetTargetWeightDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to change'), findsOneWidget);

    await tester.tap(find.text('Tap to change'));
    await tester.pumpAndSettle();
    expect(find.byType(SetTargetWeightDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('goal-extend-weight-edit'),
      findsOneWidget,
    );
  });

  testWidgets('completed goals: lost while cutting, no bulk tile', (
    tester,
  ) async {
    await _pump(
      tester,
      CompletedGoalsPage(
        unit: BodyWeightUnit.kg,
        load: () async => (
          history: [
            GoalRecord(
              kind: PhaseKind.cut,
              start: DateTime(2026, 1, 5),
              end: DateTime(2026, 4, 6),
              startKg: 88,
              endKg: 81.2,
              targetKg: 81,
            ),
          ],
          running: null,
          trend: const <double>[],
          today: today,
        ),
      ),
    );
    expect(find.text('Lost while cutting'), findsOneWidget);
    expect(find.text('6.8 kg'), findsOneWidget);
    expect(find.textContaining('bulking'), findsNothing);
  });
}

extension on DateTime {
  DateTime get date => DateTime(year, month, day);
}
