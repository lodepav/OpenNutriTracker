import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/fork/phases/phase_report.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/phases/phases_ui.dart';

DateTime day(int month, int d) => DateTime(2026, month, d);

// A four-week cut from Monday 7 September, two weeks of maintenance, then
// a four-week bulk running on 26 October, its second week.
final plan = PhasePlan(
  start: day(9, 7),
  phases: const [
    DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 4),
    DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 2),
    DietPhase(kind: PhaseKind.bulk, kgPerWeek: 0.25, weeks: 4),
  ],
);
final today = day(10, 26);

// The trend falls 0.06 kg a day through the cut, then holds; it stops
// before the bulk.
final trend = {
  for (var i = 0; i <= 41; i++)
    DateTime(2026, 9, 7 + i): 90 - 0.06 * (i < 27 ? i : 27),
};

TrackedDayEntity tracked(DateTime d, double kcal) =>
    TrackedDayEntity(day: d, calorieGoal: 2000, caloriesTracked: kcal);

// In the cut: on target, on target, over, and one day not logged.
final days = [
  tracked(day(9, 8), 2000),
  tracked(day(9, 9), 2100),
  tracked(day(9, 10), 2500),
  tracked(day(9, 11), 0),
];
final burn = {day(9, 7): 2600.0, day(10, 4): 2500.0};

List<PhaseReport> reports(PhasePlan p) => phaseReports(
  p,
  today: today,
  trendByDay: trend,
  trackedDays: days,
  burnByDay: burn,
);

void main() {
  test('the phases begun, latest first, the running one to today', () {
    final r = reports(plan);
    expect(
      [for (final x in r) x.phase.kind],
      [PhaseKind.bulk, PhaseKind.maintain, PhaseKind.cut],
    );
    expect((r[0].first, r[0].last, r[0].running), (day(10, 19), today, true));
    expect(
      (r[1].first, r[1].last, r[1].running),
      (day(10, 5), day(10, 18), false),
    );
    expect((r[2].first, r[2].last, r[2].length), (day(9, 7), day(10, 4), 28));
  });

  test('a cut: the change and pace against the plan, eaten, burnt', () {
    final cut = reports(plan).last;
    expect(cut.startKg, 90);
    expect(cut.changeKg, closeTo(-1.62, 1e-9));
    expect(cut.plannedKg, closeTo(-0.5 * 27 / 7, 1e-9));
    expect(cut.kgPerWeek, closeTo(-0.42, 1e-9));
    expect(cut.eatenKcal, closeTo(2200, 1e-9));
    expect((cut.days.onTarget, cut.days.over, cut.days.logged), (2, 1, 3));
    expect((cut.startBurnKcal, cut.endBurnKcal), (2600, 2500));
  });

  test('no trend at its start, or under a week in: no change, no pace', () {
    final bulk = reports(plan).first;
    expect(bulk.startKg, isNull);
    expect(bulk.changeKg, isNull);
    expect(bulk.kgPerWeek, isNull);
    expect(bulk.plannedKg, closeTo(0.25, 1e-9));
    expect(bulk.eatenKcal, isNull);
    expect(bulk.days.logged, 0);
  });

  test('a phase to a weight plans no further than it', () {
    final toWeight = PhasePlan(
      start: day(9, 7),
      phases: const [
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 4, untilKg: 89),
        DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 10),
      ],
    );
    expect(reports(toWeight).last.plannedKg, closeTo(-1, 1e-9));
  });

  test('a plan not begun: none', () {
    final later = PhasePlan(start: day(11, 2), phases: plan.phases);
    expect(reports(later), isEmpty);
  });

  testWidgets('the page: each phase\'s card, latest first', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhaseReportsPage(
          plan: plan,
          unit: BodyWeightUnit.kg,
          today: today,
          load: () async =>
              (trendByDay: trend, trackedDays: days, burnByDay: burn),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bulk (now)'), findsOneWidget);
    expect(find.text('Since Oct 19 · week 2 of 4'), findsOneWidget);
    expect(find.text('– · plan +0.3 kg'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bulk (now)')).dy,
      lessThan(tester.getTopLeft(find.text('Maintenance')).dy),
    );

    await tester.scrollUntilVisible(find.text('Cut'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Sep 7 – Oct 4 · 4 weeks'), findsOneWidget);
    expect(find.text('90.0 kg → 88.4 kg'), findsOneWidget);
    expect(find.text('-1.6 kg · plan -1.9 kg'), findsOneWidget);
    expect(find.text('-0.4 kg a week · plan -0.5 kg a week'), findsOneWidget);
    expect(find.text('2200 kcal'), findsOneWidget);
    expect(find.text('2 of 3 days logged'), findsOneWidget);
    expect(find.text('2600 kcal → 2500 kcal'), findsOneWidget);
  });

  group('the card\'s way to them', () {
    Future<void> pump(WidgetTester tester, PhasePlan p) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DietPhasesCard(
                store: _Memory(p),
                clock: () => DateTime(2026, 10, 26, 10),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('once a phase has begun', (tester) async {
      await pump(tester, plan);
      await tester.tap(find.byKey(const ValueKey('phases-reports')));
      await tester.pumpAndSettle();
      expect(find.text('Phase reports'), findsOneWidget);
      // Nothing to read here, no locator: said, not a spinner.
      expect(find.text('Your history could not be read.'), findsOneWidget);
    });

    testWidgets('none before', (tester) async {
      await pump(tester, PhasePlan(start: day(11, 2), phases: plan.phases));
      expect(find.byKey(const ValueKey('phases-reports')), findsNothing);
    });
  });
}

class _Memory extends PhaseStore {
  final PhasePlan saved;

  _Memory(this.saved);

  @override
  Future<PhasePlan?> plan() async => saved;
}
