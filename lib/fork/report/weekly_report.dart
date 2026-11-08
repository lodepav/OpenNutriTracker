import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

/// Eaten against the goal, each a mean over a week's logged days.
typedef Versus = ({double eaten, double goal});

/// How one day of a week stands in the report.
enum WeekDayMark {
  /// Food logged.
  logged,

  /// In the range, nothing logged.
  missed,

  /// Before the range or after today.
  outside,
}

/// How a week's mean energy stands against its goal: within
/// [onTargetShare] of it, or under, or over.
enum EnergyStanding { under, onTarget, over }

EnergyStanding energyStanding(Versus kcal) {
  if (kcal.goal <= 0) return EnergyStanding.onTarget;
  final share = (kcal.eaten - kcal.goal) / kcal.goal;
  return share > onTargetShare
      ? EnergyStanding.over
      : share < -onTargetShare
      ? EnergyStanding.under
      : EnergyStanding.onTarget;
}

/// One Monday-to-Sunday week, as MacroFactor's weekly nutrition report.
class WeekReport {
  final DateTime monday;

  /// Days with anything logged; the means are over these only, so a day
  /// left empty does not read as a day of fasting.
  final int daysLogged;

  /// The week's days within the range up to today: fewer than 7 for this
  /// week and for one the range cuts.
  final int daysShown;

  /// Monday to Sunday, each day's mark.
  final List<WeekDayMark> marks;
  final Versus kcal;
  final Versus? protein;
  final Versus? carbs;
  final Versus? fat;

  const WeekReport({
    required this.monday,
    required this.daysLogged,
    required this.daysShown,
    required this.kcal,
    this.marks = const [],
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
  bool inRange(int d) => d >= day(first) && d <= day(last);
  int shown(DateTime monday) => [
    for (var i = 0; i < 7; i++)
      if (inRange(day(monday) + i)) i,
  ].length;

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

  List<WeekDayMark> marks(DateTime monday, List<TrackedDayEntity> logged) {
    final weekdays = {for (final d in logged) d.day.weekday};
    return [
      for (var i = 0; i < 7; i++)
        weekdays.contains(i + 1)
            ? WeekDayMark.logged
            : inRange(day(monday) + i)
            ? WeekDayMark.missed
            : WeekDayMark.outside,
    ];
  }

  WeekReport report(DateTime monday, List<TrackedDayEntity> logged) =>
      WeekReport(
        monday: monday,
        daysLogged: logged.length,
        daysShown: shown(monday),
        marks: marks(monday, logged),
        kcal: mean(logged, (d) => d.caloriesTracked, (d) => d.calorieGoal)!,
        protein: mean(logged, (d) => d.proteinTracked, (d) => d.proteinGoal),
        carbs: mean(logged, (d) => d.carbsTracked, (d) => d.carbsGoal),
        fat: mean(logged, (d) => d.fatTracked, (d) => d.fatGoal),
      );

  final mondays = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final monday in mondays) report(monday, byWeek[monday]!)];
}

/// Seam S40: on Trends, each week of the range: which days were logged,
/// the mean energy of those days against its goal with a bar and how far
/// off, and each macro's mean against its goal with a bar in its colour.
class WeeklyReportCard extends StatelessWidget {
  final List<TrackedDayEntity> days;
  final int rangeDays;
  final AppPalette palette;

  /// The clock; the app's when null.
  final DateTime Function()? clock;

  /// Where the day starts, for the logical today the range ends on.
  final int dayStartMinutes;

  /// The explorer's intakes; the intake box in the app.
  final IntakeLoader? load;

  const WeeklyReportCard({
    super.key,
    required this.days,
    required this.rangeDays,
    required this.palette,
    this.clock,
    this.dayStartMinutes = 0,
    this.load,
  });

  @override
  Widget build(BuildContext context) {
    final now = clock;
    final today = now == null
        ? DayBoundaryCalc.currentLogicalDayMinutes(dayStartMinutes)
        : DayBoundaryCalc.logicalDayOfMinutes(now(), dayStartMinutes);
    final first = DateTime(today.year, today.month, today.day - rangeDays + 1);
    final weeks = weeklyReports(days, first, today);
    if (weeks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final thisMonday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing12,
          Dimens.spacing16,
          Dimens.spacing16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly report',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Semantics(
                  identifier: 'weekly-report-nutrients',
                  child: TextButton.icon(
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
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Nutrients'),
                  ),
                ),
              ],
            ),
            Text(
              'Daily averages of the days with food logged',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            for (final (i, week) in weeks.indexed) ...[
              if (i > 0)
                Divider(height: Dimens.spacing24, color: palette.border)
              else
                const SizedBox(height: Dimens.spacing12),
              _Week(
                week: week,
                palette: palette,
                current: week.monday == thisMonday,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Week extends StatelessWidget {
  final WeekReport week;
  final AppPalette palette;
  final bool current;

  const _Week({
    required this.week,
    required this.palette,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    // The locale's short date, as the weight chart's axis writes it.
    final format = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final sunday = DateTime(
      week.monday.year,
      week.monday.month,
      week.monday.day + 6,
    );
    final dates = '${format.format(week.monday)} – ${format.format(sunday)}';
    final days =
        '${week.daysLogged} of ${week.daysShown} '
        '${week.daysShown == 1 ? 'day' : 'days'} logged';

    final kcal = week.kcal;
    final standing = energyStanding(kcal);
    final error = theme.colorScheme.error;
    final (standingColor, standingWord) = switch (standing) {
      EnergyStanding.onTarget => (palette.accent, 'On target'),
      EnergyStanding.over => (error, 'Over'),
      EnergyStanding.under => (palette.textMuted, 'Under'),
    };
    final off = kcal.eaten - kcal.goal;
    final offText = energyText(context, off, signed: true);
    final unit = energyUnit(context);

    final macros = inMacroOrder<(String, Versus?, Color)>(
      carbs: ('Carbs', week.carbs, palette.carbsColor),
      fat: ('Fat', week.fat, palette.fatColor),
      protein: ('Protein', week.protein, palette.proteinColor),
    ).where((m) => m.$2 != null).toList();

    final spoken = [
      dates,
      if (current) 'this week',
      days,
      '${energyText(context, kcal.eaten)} a day of '
          '${energyText(context, kcal.goal)}, $offText, '
          '${standingWord.toLowerCase()}',
      for (final (name, v, _) in macros)
        '$name ${v!.eaten.round()} of ${v.goal.round()} g',
    ].join(', ');

    return Semantics(
      key: ValueKey('week-${DateFormat('yyyy-MM-dd').format(week.monday)}'),
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dates,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (current) ...[
                _Badge(
                  label: 'This week',
                  color: palette.accent,
                  palette: palette,
                ),
                const SizedBox(width: Dimens.spacing8),
              ],
              _DayDots(marks: week.marks, palette: palette),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text.rich(
                    maxLines: 1,
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${energyValue(context, kcal.eaten)}',
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.textStrong,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${energyValue(context, kcal.goal)} $unit',
                          style: text.bodyMedium?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              _Badge(
                label: '$offText · $standingWord',
                color: standingColor,
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          _Bar(
            share: kcal.goal <= 0 ? 0 : kcal.eaten / kcal.goal,
            color: standingColor,
            palette: palette,
            height: 8,
          ),
          const SizedBox(height: Dimens.spacing4),
          Text(days, style: text.bodySmall?.copyWith(color: palette.textMuted)),
          if (macros.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, (name, v, color)) in macros.indexed) ...[
                  if (i > 0) const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: _Macro(
                      name: name,
                      versus: v!,
                      color: color,
                      palette: palette,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A macro's name in its colour, its grams against the goal, and a bar.
class _Macro extends StatelessWidget {
  final String name;
  final Versus versus;
  final Color color;
  final AppPalette palette;

  const _Macro({
    required this.name,
    required this.versus,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final eaten = versus.eaten.round();
    final goal = versus.goal.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            maxLines: 1,
            TextSpan(
              children: [
                TextSpan(
                  text: '$eaten',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.textStrong,
                  ),
                ),
                TextSpan(text: ' / $goal g'),
              ],
            ),
            style: text.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ),
        const SizedBox(height: Dimens.spacing4),
        _Bar(
          share: goal <= 0 ? 0 : versus.eaten / versus.goal,
          color: color,
          palette: palette,
          height: 5,
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double share;
  final Color color;
  final AppPalette palette;
  final double height;

  const _Bar({
    required this.share,
    required this.color,
    required this.palette,
    required this.height,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: LinearProgressIndicator(
      value: share.clamp(0.0, 1.0),
      minHeight: height,
      color: color,
      backgroundColor: palette.surfaceMuted,
    ),
  );
}

/// A small rounded label tinted with [color].
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final AppPalette palette;

  const _Badge({
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Dimens.spacing8,
      vertical: 2,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Monday to Sunday: a filled dot for a logged day, a ring for a day in
/// the range with nothing logged, a faint dot for one outside it.
class _DayDots extends StatelessWidget {
  final List<WeekDayMark> marks;
  final AppPalette palette;

  const _DayDots({required this.marks, required this.palette});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, mark) in marks.indexed) ...[
        if (i > 0) const SizedBox(width: 3),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (mark) {
              WeekDayMark.logged => palette.accent,
              WeekDayMark.missed => Colors.transparent,
              WeekDayMark.outside => palette.surfaceMuted,
            },
            border: mark == WeekDayMark.missed
                ? Border.all(color: palette.textMuted, width: 1.2)
                : null,
          ),
        ),
      ],
    ],
  );
}
