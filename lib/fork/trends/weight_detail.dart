import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/goal_progress_page.dart';
import 'package:opennutritracker/fork/goal/goal_you_tile.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_overview.dart'
    show TrendsGoal, TrendsOverview;
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

/// The spans the weight page's change chips compare, in days, as
/// MacroFactor's insights do.
const weightChangeSpans = [3, 7, 14, 30, 90];

/// The trend's change over each of [spans] up to [today], kg; null where
/// the trend does not reach back that far.
Map<int, double?> trendChangesOver(
  Map<DateTime, double> trendByDay,
  DateTime today,
  List<int> spans,
) {
  final now = trendByDay[today];
  return {
    for (final d in spans)
      d: switch ((
        now,
        trendByDay[DateTime(today.year, today.month, today.day - d)],
      )) {
        (final double a, final double b) => a - b,
        _ => null,
      },
  };
}

/// Variant B of the weight trend page (round 3): the trend's three
/// numbers, the range, the chart, its change over set spans, four tiles
/// (highest, lowest, weigh-ins, to the goal), the explainer and the
/// weigh-ins.
List<Widget> weightDetailBody(
  BuildContext context,
  TrendsLoaded state,
  List<DateTime> dates,
  TrendsDeps deps,
  Widget pills,
) {
  const gap = SizedBox(height: Dimens.spacing16);
  final stats = WeightTrendStats.of(state.weight, dates);
  final wu = state.bodyWeightUnit;
  final label = weightUnitLabel(context, wu);
  String? w(double? kg, {bool signed = false}) => kg == null
      ? null
      : signed
      ? signedText(weightIn(wu, kg), 1)
      : weightIn(wu, kg).toStringAsFixed(1);
  final today = dates.isEmpty ? null : dates.last;
  final dayFormat = intl.DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  String day(DateTime d) => d == today ? 'today' : dayFormat.format(d);

  // The whole log's trend, so a 90-day change reads past a week's range.
  final trendByDay = {
    for (final p in trendPoints(state.weight, until: today))
      DateTime(p.date.year, p.date.month, p.date.day): p.weightKg,
  };
  final changes = today == null
      ? const <int, double?>{}
      : trendChangesOver(trendByDay, today, weightChangeSpans);
  // The goal tile's pace: the last 30 days, as Goal progress and the
  // planner name it, whatever the range.
  final pace30 = changes[30] == null ? null : changes[30]! / 30;

  // Highest and lowest trend in the range, the first day each was.
  ({double kg, DateTime on})? high, low;
  for (final (i, kg) in stats.trend.indexed) {
    if (kg == null) continue;
    if (high == null || kg > high.kg) high = (kg: kg, on: dates[i]);
    if (low == null || kg < low.kg) low = (kg: kg, on: dates[i]);
  }
  final weighInDays = {
    for (final e in state.weight)
      if (dates.isNotEmpty &&
          !e.date.isBefore(dates.first) &&
          !DateTime(e.date.year, e.date.month, e.date.day).isAfter(today!))
        DateTime(e.date.year, e.date.month, e.date.day),
  }.length;

  return [
    StatHeader(
      stats: [
        (label: 'Trend weight', value: w(stats.nowKg) ?? '–', unit: label),
        (
          label: 'Change',
          value: w(stats.changeKg, signed: true) ?? '–',
          unit: label,
        ),
        (
          label: 'Per week',
          value: stats.perWeekKg == null
              ? '–'
              : signedRate(weightIn(wu, stats.perWeekKg!)),
          unit: label,
        ),
      ],
    ),
    gap,
    pills,
    gap,
    deps.weightCard(state),
    trendSection(context, 'Trend change over'),
    ChangeChips(
      changes: [
        for (final d in weightChangeSpans)
          (
            span: '$d d',
            value: w(changes[d], signed: true) ?? '–',
            spoken: changes[d] == null
                ? 'Over $d days: not enough weigh-ins'
                : 'Over $d days: ${w(changes[d], signed: true)} $label',
          ),
      ],
    ),
    const SizedBox(height: Dimens.spacing12),
    FigureGrid(
      tiles: [
        FigureTile(
          label: 'Highest trend',
          value: w(high?.kg) ?? '–',
          unit: high == null ? null : label,
          note: high == null ? null : day(high.on),
        ),
        FigureTile(
          label: 'Lowest trend',
          value: w(low?.kg) ?? '–',
          unit: low == null ? null : label,
          note: low == null ? null : day(low.on),
        ),
        FigureTile(
          label: 'Days weighed in',
          value: '$weighInDays',
          unit: 'of ${dates.length} days',
          note: weighInDays * 2 < dates.length
              ? 'Daily weigh-ins steady the trend'
              : null,
        ),
        _GoalFigure(
          key: ValueKey(state.targetWeightKg),
          state: state,
          now: stats.nowKg,
          kgPerDay: pace30,
        ),
      ],
    ),
    const SizedBox(height: Dimens.spacing12),
    const ExplainerLink(
      title: 'What is the trend weight?',
      body:
          'The scale moves with water, salt and the food in you, often by '
          'a kilo (2 lb) or more from one day to the next. The trend smooths '
          'those swings out, so it shows what your weight is really doing. '
          'Each weigh-in nudges it a little, so it follows your weight '
          'closely when you weigh in often.',
    ),
    if (scaleNoise(state.weight, dates) case final noise?) ...[
      trendSection(context, 'Scale swings'),
      FigureGrid(
        tiles: [
          FigureTile(
            label: 'Average swing',
            value: w(noise.meanKg)!,
            unit: label,
            note: 'a weigh-in, off the trend',
          ),
          FigureTile(
            label: 'Largest',
            value: w(noise.largest.kg, signed: true)!,
            unit: label,
            note: day(noise.largest.on),
          ),
        ],
      ),
      _SwingNotes(
        key: ValueKey(dates.first),
        state: state,
        dates: dates,
        byDay: noise.byDay,
        load: deps.loadIntakes,
      ),
    ],
    ...weighInRows(context, state, dates, stats),
  ];
}

/// The gap to the trend that counts as a jump after a high day, kg.
const swingNoteKg = 0.2;

/// Whether the weigh-ins after high-carb or high-sodium days ran further
/// above the trend than the rest, and what that says.
class _SwingNotes extends StatefulWidget {
  final TrendsLoaded state;
  final List<DateTime> dates;
  final Map<DateTime, double> byDay;
  final IntakeLoader load;

  const _SwingNotes({
    super.key,
    required this.state,
    required this.dates,
    required this.byDay,
    required this.load,
  });

  @override
  State<_SwingNotes> createState() => _SwingNotesState();
}

class _SwingNotesState extends State<_SwingNotes> {
  late final Future<List<double?>?> _sodium = _loadSodium();

  Future<List<double?>?> _loadSodium() async {
    try {
      return nutrientByDay(
        await widget.load(widget.dates.first, widget.dates.last),
        widget.dates,
        explorerNutrients.firstWhere((n) => n.label == 'Salt'),
        dayStartMinutes: await dayStartMinutes(),
      );
    } catch (_) {
      // No database, in widget tests.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wu = widget.state.bodyWeightUnit;
    final label = weightUnitLabel(context, wu);
    String kg(double v) => '${signedText(weightIn(wu, v), 1)} $label';
    String? note(List<double?> values, String high, String why) {
      final s = swingAfterHigh(widget.byDay, widget.dates, values);
      if (s == null || s.after - s.other < swingNoteKg) return null;
      return 'After your $high days you weighed in ${kg(s.after)} off the '
          'trend on average, against ${kg(s.other)} after the rest: $why, '
          'not fat.';
    }

    return FutureBuilder(
      future: _sodium,
      builder: (context, snapshot) {
        final notes = [
          ?note(
            nutritionSeries(
              widget.state.days,
              widget.dates,
              (d) => d.carbsTracked,
            ),
            'higher-carb',
            'water stored with the carbs',
          ),
          if (snapshot.data case final sodium?)
            ?note(sodium, 'saltier', 'water held with the salt'),
        ];
        final style = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: paletteOf(context).textMuted);
        return Padding(
          padding: const EdgeInsets.only(top: Dimens.spacing8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                  child: Text(n, style: style),
                ),
              if (notes.isEmpty)
                Text(
                  'How far each weigh-in sits from the trend: water, salt and '
                  'food in you, not fat.',
                  style: style,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// [_goalTile] with the goal's kept start, which says when the target is
/// passed, read as the Trends tile reads it.
class _GoalFigure extends StatefulWidget {
  final TrendsLoaded state;
  final double? now;
  final double? kgPerDay;

  const _GoalFigure({
    super.key,
    required this.state,
    required this.now,
    required this.kgPerDay,
  });

  @override
  State<_GoalFigure> createState() => _GoalFigureState();
}

class _GoalFigureState extends State<_GoalFigure> {
  late final _goal = TrendsOverview.goal();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _goal,
    builder: (context, goal) => _goalTile(
      context,
      widget.state,
      widget.now,
      widget.kgPerDay,
      goal.data,
    ),
  );
}

/// "To your goal": the way left and the day at this pace; it opens Goal
/// progress.
Widget _goalTile(
  BuildContext context,
  TrendsLoaded state,
  double? now,
  double? kgPerDay,
  TrendsGoal? goal,
) {
  final wu = state.bodyWeightUnit;
  void open() => openGoalProgress(context, wu);
  final target = state.targetWeightKg;
  if (target == null || now == null) {
    final untargeted = untargetedGoal(context, goal?.plan, goal?.since);
    return FigureTile(
      label: 'To your goal',
      value: untargeted.value,
      note: untargeted.note ?? 'Plan one to see your progress',
      onTap: open,
    );
  }
  final left = goalLeftKg(target, now, goal?.progress);
  final days = kgPerDay == null || left < 0.1
      ? null
      : daysToTarget(now, target, kgPerDay);
  final t = DateTime.now();
  final locale = Localizations.localeOf(context).toLanguageTag();
  final on = days == null ? null : DateTime(t.year, t.month, t.day + days);
  final format = on?.year == t.year
      ? intl.DateFormat.MMMd(locale)
      : intl.DateFormat.yMMMd(locale);
  return FigureTile(
    label: 'To your goal',
    value: left < 0.1 ? 'There' : weightIn(wu, left).toStringAsFixed(1),
    unit: left < 0.1 ? null : weightUnitLabel(context, wu),
    note: left < 0.1
        ? null
        : kgPerDay == null
        ? 'under 30 days of trend'
        : on == null
        ? 'not at your last 30 days’ pace'
        : '${format.format(on)} at your last 30 days’ pace',
    onTap: open,
  );
}

/// The range's weigh-ins, newest first, each with the trend that day.
List<Widget> weighInRows(
  BuildContext context,
  TrendsLoaded state,
  List<DateTime> dates,
  WeightTrendStats stats,
) {
  if (dates.isEmpty) return const [];
  final palette = paletteOf(context);
  final text = Theme.of(context).textTheme;
  final wu = state.bodyWeightUnit;
  final label = weightUnitLabel(context, wu);
  final today = dates.last;
  final format = intl.DateFormat.MMMEd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  final entries = [
    for (final e in state.weight)
      if (!e.date.isBefore(dates.first) &&
          !DateTime(e.date.year, e.date.month, e.date.day).isAfter(today))
        e,
  ]..sort((a, b) => b.date.compareTo(a.date));
  if (entries.isEmpty) return const [];
  return [
    trendSection(context, 'Weigh-ins'),
    for (final e in entries)
      Builder(
        builder: (context) {
          final day = DateTime(e.date.year, e.date.month, e.date.day);
          final i = dates.indexOf(day);
          final trend = i < 0 ? null : stats.trend[i];
          return MergeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day == today ? 'Today' : format.format(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trend != null)
                    Text(
                      'trend ${weightIn(wu, trend).toStringAsFixed(1)}',
                      style: text.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  const SizedBox(width: Dimens.spacing16),
                  Text(
                    '${weightIn(wu, e.weightKg).toStringAsFixed(1)} $label',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        },
      ),
  ];
}
