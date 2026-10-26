import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/trends/weight_detail.dart';

final today = DateTime(2026, 10, 26);

DateTime ago(int days) => DateTime(today.year, today.month, today.day - days);

/// A trend falling [perDay] a day from [from] over [days] days to today.
List<double> falling(double from, double perDay, int days) => [
  for (var i = 0; i <= days; i++) from - perDay * i,
];

void main() {
  group('resolveGoalStart', () {
    final trend = falling(90, 0.05, 40);

    test('none stored: the first day of the trend', () {
      final s = resolveGoalStart(
        stored: null,
        targetKg: 82,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      );
      expect(s.date, ago(40));
      expect(s.kg, 90);
      expect(s.targetKg, 82);
    });

    test('the same target keeps the stored start', () {
      final stored = GoalStart(
        date: ago(10),
        kg: 89,
        targetKg: 82,
        paceKgPerWeek: -0.5,
      );
      expect(
        resolveGoalStart(
          stored: stored,
          targetKg: 82.02,
          paceKgPerWeek: -0.5,
          trend: trend,
          today: today,
        ),
        same(stored),
      );
    });

    test('a changed target starts today at the trend now', () {
      final s = resolveGoalStart(
        stored: GoalStart(date: ago(10), kg: 89, targetKg: 82),
        targetKg: 80,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      );
      expect(s.date, today);
      expect(s.kg, trend.last);
      expect(s.targetKg, 80);
    });

    test('a changed pace starts the plan today, the goal where it was', () {
      final stored = GoalStart(
        date: ago(10),
        kg: 89,
        targetKg: 82,
        paceKgPerWeek: -0.5,
      );
      final s = resolveGoalStart(
        stored: stored,
        targetKg: 82,
        paceKgPerWeek: -0.25,
        trend: trend,
        today: today,
      );
      expect((s.date, s.kg), (ago(10), 89));
      expect(
        (s.planDate, s.planKg, s.paceKgPerWeek),
        (today, trend.last, -0.25),
      );
    });

    test('a start kept before the pace takes the pace, the plan unmoved', () {
      final s = resolveGoalStart(
        stored: GoalStart(date: ago(10), kg: 89, targetKg: 82),
        targetKg: 82,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      );
      expect((s.planDate, s.planKg, s.paceKgPerWeek), (ago(10), 89, -0.5));
    });

    test('kept as JSON, with and without a replan', () {
      final s = GoalStart(date: ago(3), kg: 88.4, targetKg: 82);
      final back = GoalStart.fromJson(s.toJson());
      expect((back.date, back.kg, back.targetKg), (s.date, s.kg, s.targetKg));
      expect(back.paceKgPerWeek, isNull);
      final r = GoalStart.fromJson(s.replanned(today, 88, -0.3).toJson());
      expect((r.planDate, r.planKg, r.paceKgPerWeek), (today, 88, -0.3));
      expect((r.date, r.kg), (ago(3), 88.4));
    });
  });

  group('GoalProgress, losing 90 → 80 at 0.5 kg a week', () {
    // 70 days in, 2 kg lost: the plan had 5.
    final trend = falling(90, 2 / 70, 70);
    final p = GoalProgress(
      start: GoalStart(date: ago(70), kg: 90, targetKg: 80),
      nowKg: trend.last,
      paceKgPerWeek: -0.5,
      trend: trend,
      today: today,
    );

    test('how far along, and against the plan', () {
      expect(p.totalKg, -10);
      expect(p.toGoKg, closeTo(-8, 1e-9));
      expect(p.fraction, closeTo(0.2, 1e-9));
      expect(p.planKgAfter(70), closeTo(85, 1e-9));
      expect(p.planFraction, closeTo(0.5, 1e-9));
      expect(p.behindKg, closeTo(3, 1e-9));
      expect(p.reached, isFalse);
    });

    test('the plan stops at the target', () {
      expect(p.planKgAfter(1000), 80);
    });

    test('replanned 14 days ago at 88: behind counts from there', () {
      final r = GoalProgress(
        start: p.start.replanned(ago(14), 88.5, -0.5),
        nowKg: trend.last,
        paceKgPerWeek: -0.5,
        trend: trend,
        today: today,
      );
      expect(r.replanned, isTrue);
      expect(r.planKgToday, closeTo(87.5, 1e-9));
      expect(r.behindKg, closeTo(0.5, 1e-9));
      // Still the way from the goal's own start.
      expect(r.fraction, closeTo(0.2, 1e-9));
    });

    test('paces: recent over 30 days, since the start', () {
      final recent = p.recentPace()!;
      expect(recent.days, 30);
      expect(recent.kgPerWeek, closeTo(-0.2, 1e-9));
      expect(p.sinceStartKgPerWeek, closeTo(-0.2, 1e-9));
    });

    test('arrival at a pace, none moving away', () {
      // 8 kg at 0.5 a week: 112 days.
      expect(p.arrivalAt(-0.5), DateTime(2027, 2, 15));
      expect(p.arrivalAt(0.3), isNull);
      expect(p.arrivalAt(null), isNull);
    });

    test('milestones: reached ones dated off the trend, the rest ahead', () {
      final m = p.milestones(2, kgPerWeek: -0.5);
      expect([for (final x in m) x.kg], [88, 86, 84, 82, 80]);
      expect(m.first.reached, isTrue);
      // 2 kg at 2/70 a day: day 70, today.
      expect(m.first.on, today);
      expect(m[1].reached, isFalse);
      // 88 − 86 = 2 kg from 88 now at 0.5 a week: 28 days.
      expect(m[1].on, today.add(const Duration(days: 28)));
      expect(m.last.kg, 80);
    });
  });

  test('gaining: behind is still the way short of the plan', () {
    final p = GoalProgress(
      start: GoalStart(date: ago(14), kg: 60, targetKg: 64),
      nowKg: 60.5,
      paceKgPerWeek: 0.5,
      trend: falling(60, -0.5 / 14, 14),
      today: today,
    );
    expect(p.fraction, closeTo(0.125, 1e-9));
    expect(p.behindKg, closeTo(0.5, 1e-9));
  });

  test('past the target: reached, all the way', () {
    final p = GoalProgress(
      start: GoalStart(date: ago(14), kg: 82, targetKg: 80),
      nowKg: 79.8,
      paceKgPerWeek: -0.5,
      trend: falling(82, 2.2 / 14, 14),
      today: today,
    );
    expect(p.reached, isTrue);
    expect(p.toGoKg, 0);
    expect(p.fraction, 1);
  });

  test('a week of history gives no recent pace', () {
    final p = GoalProgress(
      start: GoalStart(date: ago(5), kg: 82, targetKg: 80),
      nowKg: 81.9,
      paceKgPerWeek: -0.5,
      trend: falling(82, 0.02, 5),
      today: today,
    );
    expect(p.recentPace(), isNull);
    expect(p.sinceStartKgPerWeek, isNull);
  });

  test('trendChangesOver: each span, none past the trend', () {
    final byDay = {for (var i = 0; i <= 10; i++) ago(i): 80.0 + i * 0.1};
    final c = trendChangesOver(byDay, today, const [3, 7, 14]);
    expect(c[3], closeTo(-0.3, 1e-9));
    expect(c[7], closeTo(-0.7, 1e-9));
    expect(c[14], isNull);
  });
}
