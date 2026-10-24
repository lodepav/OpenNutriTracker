import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

/// Eaten against the goal, each a mean over a week's logged days.
typedef Versus = ({double eaten, double goal});

/// One Monday-to-Sunday week, as MacroFactor's weekly nutrition report.
class WeekReport {
  final DateTime monday;

  /// Days with anything logged; the means are over these only, so a day
  /// left empty does not read as a day of fasting.
  final int daysLogged;

  /// The week's days within the range up to today: fewer than 7 for this
  /// week and for one the range cuts.
  final int daysShown;
  final Versus kcal;
  final Versus? protein;
  final Versus? carbs;
  final Versus? fat;

  const WeekReport({
    required this.monday,
    required this.daysLogged,
    required this.daysShown,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
  });
}

/// [days] grouped by week, newest first; weeks with nothing logged are
/// left out. A macro is left out of a week where a logged day lacks it.
/// [first] and [last] are the range's days.
List<WeekReport> weeklyReports(
  List<TrackedDayEntity> days,
  DateTime first,
  DateTime last,
) {
  int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  int shown(DateTime monday) {
    final from = day(monday) < day(first) ? day(first) : day(monday);
    final to = day(monday) + 6 > day(last) ? day(last) : day(monday) + 6;
    return to - from + 1;
  }

  final byWeek = <DateTime, List<TrackedDayEntity>>{};
  for (final d in days) {
    if (d.caloriesTracked <= 0) continue;
    final monday = DateTime(
      d.day.year,
      d.day.month,
      d.day.day - d.day.weekday + 1,
    );
    (byWeek[monday] ??= []).add(d);
  }

  Versus? mean(
    List<TrackedDayEntity> logged,
    double? Function(TrackedDayEntity) eaten,
    double? Function(TrackedDayEntity) goal,
  ) {
    var e = 0.0, g = 0.0;
    for (final d in logged) {
      final (de, dg) = (eaten(d), goal(d));
      if (de == null || dg == null) return null;
      e += de;
      g += dg;
    }
    return (eaten: e / logged.length, goal: g / logged.length);
  }

  WeekReport report(DateTime monday, List<TrackedDayEntity> logged) =>
      WeekReport(
        monday: monday,
        daysLogged: logged.length,
        daysShown: shown(monday),
        kcal: mean(logged, (d) => d.caloriesTracked, (d) => d.calorieGoal)!,
        protein: mean(logged, (d) => d.proteinTracked, (d) => d.proteinGoal),
        carbs: mean(logged, (d) => d.carbsTracked, (d) => d.carbsGoal),
        fat: mean(logged, (d) => d.fatTracked, (d) => d.fatGoal),
      );

  final mondays = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final monday in mondays) report(monday, byWeek[monday]!)];
}

/// Seam S40: on Trends, each week of the range: days logged, and the
/// mean energy and macros of those days against their goals.
class WeeklyReportCard extends StatelessWidget {
  final List<TrackedDayEntity> days;
  final int rangeDays;
  final AppPalette palette;
  final DateTime Function() clock;

  /// The explorer's intakes; the intake box in the app.
  final IntakeLoader? load;

  const WeeklyReportCard({
    super.key,
    required this.days,
    required this.rangeDays,
    required this.palette,
    this.clock = DateTime.now,
    this.load,
  });

  @override
  Widget build(BuildContext context) {
    final today = clock();
    final first = DateTime(today.year, today.month, today.day - rangeDays + 1);
    final weeks = weeklyReports(days, first, today);
    if (weeks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing16),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly report',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const ValueKey('nutrient-explorer'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NutrientExplorerScreen(
                        days: days,
                        first: first,
                        last: today,
                        load: load,
                      ),
                    ),
                  ),
                  child: const Text('Nutrients'),
                ),
              ],
            ),
            Text(
              'Means of the logged days, against their goals',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            for (final week in weeks) _week(context, week),
          ],
        ),
      ),
    );
  }

  Widget _week(BuildContext context, WeekReport week) {
    final theme = Theme.of(context);
    final format = DateFormat('d MMM');
    final sunday = DateTime(
      week.monday.year,
      week.monday.month,
      week.monday.day + 6,
    );
    String grams(String name, Versus? v) =>
        v == null ? '' : '$name ${v.eaten.round()}/${v.goal.round()} g';
    final macros = inMacroOrder(
      protein: grams('P', week.protein),
      carbs: grams('C', week.carbs),
      fat: grams('F', week.fat),
    ).where((m) => m.isNotEmpty).join(' · ');
    final off = week.kcal.eaten - week.kcal.goal;
    return Padding(
      key: ValueKey('week-${DateFormat('yyyy-MM-dd').format(week.monday)}'),
      padding: const EdgeInsets.only(top: Dimens.spacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${format.format(week.monday)} – ${format.format(sunday)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${week.daysLogged}/${week.daysShown} days',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          Text(
            '${energyText(context, week.kcal.eaten)} of '
            '${energyText(context, week.kcal.goal)} '
            '(${energyText(context, off, signed: true)})',
          ),
          if (macros.isNotEmpty)
            Text(
              macros,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
