import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_summary.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

// The goal summary every place shows (design A), one case a state; kg,
// the trend at 87.1 kg, a target of 80.0 kg from 89.4 kg on Oct 5.

final _today = DateTime(2026, 11, 19);
final _start = DateTime(2026, 10, 5);

typedef _Pace = ({UserWeightGoalEntity goal, double? kgPerWeek});

const _Pace _losing = (goal: UserWeightGoalEntity.loseWeight, kgPerWeek: -0.4);

GoalSummary _summary({
  PhasePlan? plan,
  List<GoalRecord> history = const [],
  _Pace? pace,
  double? targetKg,
  double? nowKg,
  GoalProgress? progress,
  double? kgPerDay,
}) => goalSummary(
  locale: 'en',
  unit: BodyWeightUnit.kg,
  unitLabel: 'kg',
  today: _today,
  plan: plan,
  history: history,
  pace: pace,
  targetKg: targetKg,
  nowKg: nowKg,
  progress: progress,
  kgPerDay: kgPerDay,
);

/// What a tile shows: value, suffix, note, bar, the phase bar, action, tap.
List<Object?> _shown(GoalSummary s) => [
  s.value,
  s.suffix,
  s.note,
  s.bar == null ? null : double.parse(s.bar!.toStringAsFixed(3)),
  s.phases,
  s.action?.label,
  s.tap,
];

GoalProgress _progress(List<double> trend, {double nowKg = 87.1}) =>
    GoalProgress(
      start: GoalStart(date: _start, kg: 89.4, targetKg: 80),
      nowKg: nowKg,
      paceKgPerWeek: -0.5,
      trend: trend,
      today: _today,
    );

GoalRecord _record({double? targetKg}) => GoalRecord(
  kind: PhaseKind.cut,
  start: DateTime(2026, 6, 1),
  end: DateTime(2026, 10, 29),
  startKg: 90,
  endKg: 82,
  targetKg: targetKg,
);

PhasePlan _cutTo80({DateTime? start, int weeks = 25}) => PhasePlan(
  start: start ?? _start,
  startKg: 89.4,
  targetKg: 80,
  phases: [DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: weeks)],
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  test('no goal: no target, no plan, no rate', () {
    const none = [
      'No goal',
      null,
      'Plan a pace, dates and calories',
      null,
      false,
      'Plan a goal',
      GoalTap.planner,
    ];
    // Only when the profile could not be read.
    expect(_shown(_summary()), none);
  });

  test('a direction with no weekly rate: its verb, no end date', () {
    const _Pace direction = (
      goal: UserWeightGoalEntity.loseWeight,
      kgPerWeek: null,
    );
    expect(_shown(_summary(pace: direction)), [
      'Losing',
      null,
      'No end date',
      null,
      false,
      'Plan a goal',
      GoalTap.planner,
    ]);
    final keeping = _summary(
      pace: (goal: UserWeightGoalEntity.maintainWeight, kgPerWeek: null),
    );
    expect((keeping.value, keeping.note), ('Maintain', 'No end date'));
    // A direction wins over "since", as a rate does.
    expect(_summary(history: [_record()], pace: direction).value, 'Losing');
  });

  test('a pace only: the verb, the rate, no end date', () {
    expect(_shown(_summary(pace: _losing)), [
      'Losing',
      '0.4 kg a week',
      'No end date',
      null,
      false,
      'Plan a goal',
      GoalTap.planner,
    ]);
    expect(
      _summary(
        pace: (goal: UserWeightGoalEntity.gainWeight, kgPerWeek: 0.25),
      ).value,
      'Gaining',
    );
  });

  test('keeping: Maintain, no end date', () {
    expect(
      _shown(
        _summary(
          pace: (goal: UserWeightGoalEntity.maintainWeight, kgPerWeek: 0),
        ),
      ),
      [
        'Maintain',
        null,
        'No end date',
        null,
        false,
        'Plan a goal',
        GoalTap.planner,
      ],
    );
  });

  test('maintaining since a completed goal, the last one named', () {
    final s = _summary(history: [_record(targetKg: 82)]);
    expect(_shown(s), [
      'Maintain',
      'since Oct 29',
      'Last goal: cut to 82.0 kg',
      null,
      false,
      'Plan a goal',
      GoalTap.planner,
    ]);
    expect(s.sinceGoal, isTrue);
    // A goal with no target names none.
    expect(_summary(history: [_record()]).note, isNull);
    // A rate of 0 set after keeps "since".
    expect(
      _summary(
        history: [_record()],
        pace: (goal: UserWeightGoalEntity.maintainWeight, kgPerWeek: 0),
      ).suffix,
      'since Oct 29',
    );
  });

  test('a rate set on You after a completed goal wins over "since"', () {
    final s = _summary(history: [_record(targetKg: 82)], pace: _losing);
    expect(
      (s.value, s.suffix, s.note),
      ('Losing', '0.4 kg a week', 'No end date'),
    );
    expect(s.sinceGoal, isFalse);
  });

  test('a plan with dates and no target: its kind until its last day', () {
    // Four weeks' cut from Oct 22, then a diet break from Nov 19.
    PhasePlan plan(DateTime start) => PhasePlan(
      start: start,
      phases: const [
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 4),
        DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 1),
        DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 4),
      ],
    );
    final s = _summary(plan: plan(DateTime(2026, 10, 22)), nowKg: 87.1);
    expect(_shown(s), [
      'Cut',
      'until Dec 23',
      'Now: diet break',
      null,
      true,
      null,
      GoalTap.progress,
    ]);
    // Not begun: no phase now.
    expect(_summary(plan: plan(DateTime(2026, 12, 1))).note, isNull);
  });

  test('a plan with a target: the way to go, its kind and last day', () {
    expect(_shown(_summary(plan: _cutTo80(), targetKg: 80, nowKg: 87.1)), [
      '7.1',
      'kg to go',
      'Cut · about Mar 28, 2027',
      0.245,
      false,
      null,
      GoalTap.progress,
    ]);
  });

  test('a target and no plan: the day at the 30-day pace, or why none', () {
    final trend = [for (var i = 0; i <= 45; i++) 89.4 - 2.3 / 45 * i];
    GoalSummary at(double? kgPerDay) => _summary(
      targetKg: 80,
      nowKg: 87.1,
      progress: _progress(trend),
      kgPerDay: kgPerDay,
      pace: _losing,
    );
    expect(_shown(at(-0.06)), [
      '7.1',
      'kg to go',
      'About Mar 18, 2027 at your 30-day pace',
      0.245,
      false,
      'Plan a goal',
      GoalTap.progress,
    ]);
    // The tap opens Goal progress, so the tile offers no planner it doesn't open.
    expect(at(-0.06).tileAction, isNull);
    expect(at(null).note, 'Under 30 days of trend');
    expect(at(0.05).note, 'Not at your 30-day pace');
    // The start and target under the card's bar.
    expect(at(null).start, (kg: 89.4, day: _start));
    expect(at(null).targetKg, 80);
  });

  test('the 30-day pace needs 30 days of trend', () {
    expect(kgPerDay30(_progress([for (var i = 0; i < 30; i++) 88.0])), isNull);
    expect(
      kgPerDay30(_progress([for (var i = 0; i <= 30; i++) 88 - 0.1 * i])),
      closeTo(-0.1, 1e-9),
    );
    expect(kgPerDay30(null), isNull);
  });

  test('reached: there, on the day the trend got there', () {
    // 85 kg until Nov 14, at the target since.
    final trend = [for (var i = 0; i <= 45; i++) i < 40 ? 85.0 : 80.0];
    final progress = _progress(trend, nowKg: 80);
    expect(_shown(_summary(targetKg: 80, nowKg: 80, progress: progress)), [
      'There',
      null,
      '80.0 kg on Nov 14 · keep it or go on',
      1.0,
      false,
      'Plan a goal',
      GoalTap.progress,
    ]);
    // With a plan: complete it or extend it, as Goal reached does.
    expect(
      _shown(
        _summary(plan: _cutTo80(), targetKg: 80, nowKg: 80, progress: progress),
      ),
      [
        'There',
        null,
        '80.0 kg on Nov 14 · keep it or go on',
        1.0,
        false,
        'Complete or extend',
        GoalTap.reached,
      ],
    );
    expect(
      _summary(targetKg: 80, nowKg: 80, progress: progress).tileAction,
      isNull,
    );
    expect(
      _summary(
        plan: _cutTo80(),
        targetKg: 80,
        nowKg: 80,
        progress: progress,
      ).tileAction,
      GoalAction.completeOrExtend,
    );
    expect(_summary(pace: _losing).tileAction, GoalAction.plan);
    // The day not known: the weight alone.
    expect(
      _summary(targetKg: 80, nowKg: 79.95).note,
      '80.0 kg · keep it or go on',
    );
  });

  test('a plan past its end, short of the target: ended, extend it', () {
    final s = _summary(
      plan: _cutTo80(start: DateTime(2026, 9, 7), weeks: 8),
      targetKg: 80,
      nowKg: 85,
    );
    expect(_shown(s), [
      'Ended',
      null,
      'Nov 1 · keep it or go on',
      null,
      false,
      'Complete or extend',
      GoalTap.extend,
    ]);
  });

  test('spoken once: label, value and suffix, note', () {
    expect(
      _summary(pace: _losing).spoken(),
      'Goal, Losing 0.4 kg a week, No end date',
    );
    expect(
      _summary().spoken('To your goal'),
      startsWith('To your goal, No goal'),
    );
    // The dot between a note's parts is a pause.
    expect(
      _summary(plan: _cutTo80(), targetKg: 80, nowKg: 87.1).spoken(),
      'Goal, 7.1 kg to go, Cut, about Mar 28, 2027',
    );
  });
}
