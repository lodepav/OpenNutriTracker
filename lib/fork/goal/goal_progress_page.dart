import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Opens Goal progress.
void openGoalProgress(BuildContext context, BodyWeightUnit unit) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GoalProgressPage(unit: unit)),
    );

/// The calorie goal now and the mean of the logged days of the last 30.
typedef GoalCalories = ({double? goalKcal, double? meanKcal});

/// The goal's plan and the goals completed before it.
typedef GoalPlans = ({
  PhasePlan? plan,
  List<PhasePlan> upcoming,
  List<GoalRecord> history,
});

Future<GoalPlans> _loadPlans() async {
  final store = PhaseStore();
  return (
    plan: await store.plan(),
    upcoming: await store.upcoming(),
    history: await store.history(),
  );
}

Future<GoalCalories> _loadCalories() async {
  if (!locator.isRegistered<GetTrackedDayUsecase>()) {
    return (goalKcal: null, meanKcal: null);
  }
  final t = DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final days = await locator<GetTrackedDayUsecase>().getTrackedDaysByRange(
    DateTime(today.year, today.month, today.day - 29),
    today,
  );
  days.sort((a, b) => a.day.compareTo(b.day));
  final logged = [
    for (final d in days)
      if (isLogged(d)) d.caloriesTracked,
  ];
  return (
    goalKcal: days.isEmpty ? null : days.last.calorieGoal,
    meanKcal: meanOf(logged),
  );
}

/// Goal progress (round 3, variant B with A's pace and arrival cards): the
/// start, now and target; how far along against the plan; the trend since
/// the start with the plan and the projection; pace; when you get there;
/// milestones.
class GoalProgressPage extends StatefulWidget {
  final BodyWeightUnit unit;

  /// The goal and the calories; the profile's by default.
  final Future<GoalState> Function()? loadGoal;
  final Future<GoalCalories> Function()? loadCalories;
  final Future<GoalPlans> Function()? loadPlans;

  const GoalProgressPage({
    super.key,
    required this.unit,
    this.loadGoal,
    this.loadCalories,
    this.loadPlans,
  });

  @override
  State<GoalProgressPage> createState() => _GoalProgressPageState();
}

class _GoalProgressPageState extends State<GoalProgressPage> {
  late Future<(GoalState, GoalCalories, int, GoalPlans)> _data = _load();

  Future<(GoalState, GoalCalories, int, GoalPlans)> _load() async {
    final goal = await (widget.loadGoal ?? () => GoalStartStore().load())();
    final calories = await (widget.loadCalories ?? _loadCalories)();
    var step = 0;
    try {
      step = await PhaseStore().milestoneStep();
    } catch (_) {
      // No store in a test: the default step.
    }
    GoalPlans plans = (plan: null, upcoming: const [], history: const []);
    try {
      plans = await (widget.loadPlans ?? _loadPlans)();
    } catch (_) {
      // No store in a test: no plan.
    }
    return (goal, calories, step, plans);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  @override
  void initState() {
    super.initState();
    paceChanges.addListener(_reload);
    PhaseStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    paceChanges.removeListener(_reload);
    PhaseStore.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Goal progress')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: noData(context, 'Your goal could not be read.'));
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (goal, calories, step, plans) = data;
        final nowKg = goal.inputs?.nowKg;
        final section = GoalPlanSection(
          plan: plans.plan,
          upcoming: plans.upcoming,
          history: plans.history,
          nowKg: nowKg,
          unit: widget.unit,
          today: DateTime.now(),
          onChanged: _reload,
          showStatus: false,
        );
        final plan = plans.plan;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // Reached or over, what to do next comes first.
            if (plan != null && nowKg != null)
              GoalStatusBanner(
                plan,
                nowKg,
                widget.unit,
                DateTime.now(),
                _reload,
              ),
            if (goal.inputs == null)
              noData(context, 'Weigh in to see your progress.')
            else if (goal.progress == null)
              ..._noTarget(context, goal.inputs!.nowKg, plans.plan)
            else
              ..._body(context, goal.progress!, calories, step, plans.plan),
            const SizedBox(height: Dimens.spacing16),
            section,
          ],
        );
      },
    ),
  );

  List<Widget> _noTarget(BuildContext context, double nowKg, PhasePlan? plan) =>
      [
        if (plan != null && plan.kind != PhaseKind.maintain) ...[
          noData(context, 'Set a target weight to see how far along you are.'),
          const SizedBox(height: Dimens.spacing16),
          Center(
            child: OutlinedButton(
              onPressed: () async {
                if (await setTargetWeight(context, widget.unit, nowKg, null)) {
                  _reload();
                }
              },
              child: const Text('Set target weight'),
            ),
          ),
        ],
      ];

  String _kg(double kg) => weightIn(widget.unit, kg).toStringAsFixed(1);

  String _rate(double kgPerWeek) =>
      '${signedRate(weightIn(widget.unit, kgPerWeek))} '
      '${weightUnitLabel(context, widget.unit)} a week';

  List<Widget> _body(
    BuildContext context,
    GoalProgress p,
    GoalCalories calories,
    int step,
    PhasePlan? plan,
  ) {
    final label = weightUnitLabel(context, widget.unit);
    final format = intl.DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final yearFormat = intl.DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    String date(DateTime? d) => d == null
        ? '–'
        : d.year == p.today.year
        ? format.format(d)
        : yearFormat.format(d);
    final recent = p.recentPace();
    final atPace = p.arrivalAt(recent?.kgPerWeek);
    final atPlan = p.arrivalAt(p.paceKgPerWeek);
    const gap = SizedBox(height: Dimens.spacing16);

    return [
      StatHeader(
        stats: [
          (
            label: 'Start · ${date(p.start.date)}',
            value: _kg(p.start.kg),
            unit: label,
          ),
          (label: 'Trend now', value: _kg(p.nowKg), unit: label),
          (label: 'Target', value: _kg(p.targetKg), unit: label),
        ],
      ),
      gap,
      _ProgressCard(progress: p, kg: _kg, unit: label),
      gap,
      AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: _GoalChart(
          progress: p,
          unit: widget.unit,
          atPace: recent?.kgPerWeek,
        ),
      ),
      trendSection(context, 'Pace'),
      TrendRows(
        rows: [
          (label: 'Your plan', value: _rate(p.paceKgPerWeek)),
          if (recent != null)
            (label: 'Last ${recent.days} days', value: _rate(recent.kgPerWeek)),
          if (p.sinceStartKgPerWeek != null)
            (label: 'Since the start', value: _rate(p.sinceStartKgPerWeek!)),
        ],
      ),
      if (!p.reached) ...[
        trendSection(context, 'When you get there'),
        TrendRows(
          rows: [
            // The plan's own end counts its diet breaks.
            if (plan?.targetKg != null)
              (
                label: 'By your plan',
                value: date(plan!.end.subtract(const Duration(hours: 12))),
              )
            else
              (
                label: 'From today at your plan’s pace',
                value: atPlan == null ? 'Not at this pace' : date(atPlan),
              ),
            if (recent != null)
              (
                label: 'At your last ${recent.days} days’ pace',
                value: atPace == null ? 'Not at this pace' : date(atPace),
              ),
          ],
        ),
      ],
      const SizedBox(height: Dimens.spacing12),
      FigureGrid(
        tiles: [
          FigureTile(
            label: 'Since the start',
            value: signedText(weightIn(widget.unit, p.nowKg - p.start.kg), 1),
            unit: label,
            note: switch ((p.daysIn / 7).floor()) {
              0 => 'in ${p.daysIn} days',
              1 => 'in 1 week',
              final w => 'in $w weeks',
            },
          ),
          FigureTile(
            label: 'Calorie goal now',
            value: calories.goalKcal == null
                ? '–'
                : '${energyValue(context, calories.goalKcal!)}',
            unit: calories.goalKcal == null ? null : energyUnit(context),
            note: calories.meanKcal == null
                ? null
                : 'you averaged ${energyText(context, calories.meanKcal!)} '
                      'over 30 days',
          ),
        ],
      ),
      ..._milestones(context, p, step, recent, date),
      gap,
      const ExplainerLink(
        title: 'How is the plan worked out?',
        body:
            'The plan runs from where your trend weight was when you set '
            'the target, at the pace in your goal planner, until it reaches '
            'the target. When you change the pace, the plan starts again '
            'from that day. The dates ahead assume your trend keeps the pace '
            'they name.',
      ),
    ];
  }

  /// The milestones every step of the planner's choice, or the smallest
  /// step that makes no more than eight.
  List<Widget> _milestones(
    BuildContext context,
    GoalProgress p,
    int chosen,
    ({double kgPerWeek, int days})? recent,
    String Function(DateTime?) date,
  ) {
    final kgPerWeek = recent?.kgPerWeek;
    final kg = widget.unit == BodyWeightUnit.kg;
    final steps = kg ? milestoneStepsKg : milestoneStepsLb;
    final perKg = kg ? 1.0 : 2.20462;
    var step = chosen > 0 ? steps[chosen - 1] : steps[kg ? 1 : 1];
    for (final s in steps) {
      if (s < step) continue;
      step = s;
      if (p.milestones(s, perKg: perKg).length <= 8) break;
    }
    final rows = p.milestones(step, perKg: perKg, kgPerWeek: kgPerWeek);
    final palette = paletteOf(context);
    final label = weightUnitLabel(context, widget.unit);
    return [
      trendSection(
        context,
        recent == null
            ? 'Milestones'
            : 'Milestones, at your last ${recent.days} days’ pace',
      ),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
        child: Column(
          children: [
            for (final (i, m) in rows.indexed)
              MergeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: palette.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        m.reached
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: m.reached ? palette.accent : palette.textMuted,
                      ),
                      const SizedBox(width: Dimens.spacing12),
                      Expanded(
                        child: Text(
                          '${_kg(m.kg)} $label'
                          '${i == rows.length - 1 ? ' · target' : ''}',
                        ),
                      ),
                      const SizedBox(width: Dimens.spacing12),
                      Text(
                        m.reached
                            ? (m.on == null
                                  ? 'Reached'
                                  : 'Reached ${date(m.on)}')
                            : (m.on == null ? '–' : 'About ${date(m.on)}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

/// How far along, against where the plan has you today.
class _ProgressCard extends StatelessWidget {
  final GoalProgress progress;
  final String Function(double kg) kg;
  final String unit;

  const _ProgressCard({
    required this.progress,
    required this.kg,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final percent = (p.fraction * 100).round();
    final planPercent = (p.planFraction * 100).round();
    final status = p.reached
        ? 'Target reached'
        : p.behindKg.abs() < 0.2
        ? 'On plan'
        : p.behindKg > 0
        ? '${kg(p.behindKg)} $unit behind the plan'
        : '${kg(-p.behindKg)} $unit ahead of the plan';
    final good = p.reached || p.behindKg < 0.2;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Semantics(
        label:
            '$percent percent there, ${kg(p.toGoKg.abs())} $unit to go. '
            'The plan has you $planPercent percent there by today. $status.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: '$percent% there',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                children: [
                  if (!p.reached)
                    TextSpan(
                      text: ' · ${kg(p.toGoKg.abs())} $unit to go',
                      style: text.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            LayoutBuilder(
              builder: (context, box) => SizedBox(
                height: 18,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 4,
                      child: ClipRRect(
                        borderRadius: Dimens.borderRadiusS,
                        child: LinearProgressIndicator(
                          value: p.fraction,
                          minHeight: 10,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor: palette.surfaceMuted,
                        ),
                      ),
                    ),
                    // The plan's mark for today.
                    Positioned(
                      left: (box.maxWidth * p.planFraction - 1).clamp(
                        0,
                        box.maxWidth - 2,
                      ),
                      top: 0,
                      child: Container(
                        width: 2,
                        height: 18,
                        color: palette.textStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing4,
              children: [
                Text(
                  p.replanned
                      ? 'Plan since ${intl.DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag()).format(p.start.planDate)}: '
                            '$planPercent% by today'
                      : 'Plan: $planPercent% by today',
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: good
                        ? palette.accent.withValues(alpha: 0.14)
                        : palette.surfaceMuted,
                    borderRadius: Dimens.borderRadiusM,
                  ),
                  child: Text(
                    status,
                    style: text.labelMedium?.copyWith(
                      color: palette.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chart's x for [day]: calendar days from [origin], a whole day
/// across a daylight saving change, when local midnights are 23 or 25
/// hours apart.
@visibleForTesting
double chartDay(DateTime origin, DateTime day) =>
    CalendarDayCalc.daysBetween(origin, day).toDouble();

/// The trend since the start, the plan from the start, the projection
/// from today at [atPace] and the target.
class _GoalChart extends StatelessWidget {
  final GoalProgress progress;
  final BodyWeightUnit unit;
  final double? atPace;

  const _GoalChart({required this.progress, required this.unit, this.atPace});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final line = theme.colorScheme.primary;
    double y(double kg) => weightIn(unit, kg);
    // Day 0 is the start, or the first day of the trend kept after it.
    final trendFirst = DateTime(
      p.today.year,
      p.today.month,
      p.today.day - (p.trend.length - 1),
    );
    final origin = p.start.date.isAfter(trendFirst) ? p.start.date : trendFirst;
    final todayX = chartDay(origin, p.today);

    final trend = [
      for (final (i, kg) in p.trend.indexed)
        if (!DateTime(
          trendFirst.year,
          trendFirst.month,
          trendFirst.day + i,
        ).isBefore(origin))
          FlSpot(
            chartDay(
              origin,
              DateTime(trendFirst.year, trendFirst.month, trendFirst.day + i),
            ),
            y(kg),
          ),
    ];
    // The plan from its own start: the goal's, or the last pace change.
    final planX = chartDay(origin, p.start.planDate);
    final planDays = p.paceKgPerWeek == 0
        ? null
        : daysToTarget(p.start.planKg, p.targetKg, p.paceKgPerWeek / 7);
    final arrival = p.arrivalAt(atPace);
    final paceDays = arrival == null
        ? null
        : CalendarDayCalc.daysBetween(p.today, arrival);
    final endX = math.min(
      todayX + 365,
      [
        todayX + 14,
        if (planDays != null) planX + planDays + 7,
        if (paceDays != null) todayX + paceDays + 7,
      ].reduce(math.max),
    );
    final plan = [
      FlSpot(planX, y(p.start.planKg)),
      if (planDays != null)
        FlSpot(
          math.min(planX + planDays, endX),
          y(p.planKgAfter(math.min(planDays, (endX - planX).round()))),
        ),
    ];
    final projection = paceDays == null || p.reached
        ? const <FlSpot>[]
        : [
            FlSpot(todayX, y(p.nowKg)),
            FlSpot(
              math.min(todayX + paceDays, endX),
              y(p.nowKg + atPace! / 7 * math.min(paceDays, endX - todayX)),
            ),
          ];
    final ys = [
      ...trend.map((s) => s.y),
      ...plan.map((s) => s.y),
      ...projection.map((s) => s.y),
      y(p.targetKg),
    ];
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = ((maxY - minY) * 0.12).clamp(0.5, 5.0);
    final format = intl.DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final label = weightUnitLabel(context, unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: Semantics(
            label:
                'Trend weight since ${format.format(p.start.date)}, the plan '
                'and the projection to the target of '
                '${y(p.targetKg).toStringAsFixed(1)} $label',
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: endX,
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: labelledTouch(
                  context,
                  (s) =>
                      '${switch (s.barIndex) {
                        0 => 'Plan',
                        1 => 'Your pace',
                        _ => 'Trend',
                      }} ${s.y.toStringAsFixed(1)} $label',
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36 * textScale,
                      getTitlesWidget: (value, meta) =>
                          value == meta.min || value == meta.max
                          ? const SizedBox.shrink()
                          : Text(
                              value.toStringAsFixed(
                                value == value.roundToDouble() ? 0 : 1,
                              ),
                              style: theme.textTheme.labelSmall,
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24 * textScale,
                      interval: math.max(1, endX / 3),
                      // The last date would run past the edge.
                      getTitlesWidget: (value, meta) => value == meta.max
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                format.format(
                                  DateUtils.addDaysToDate(
                                    origin,
                                    value.round(),
                                  ),
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: y(p.targetKg),
                      color: palette.accent,
                      strokeWidth: 1.4,
                      dashArray: const [6, 4],
                    ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: plan,
                    color: palette.textMuted,
                    barWidth: 1.5,
                    dashArray: const [3, 4],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: projection,
                    color: line,
                    barWidth: 2,
                    dashArray: const [6, 5],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: trend,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: line,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      checkToShowDot: (spot, bar) => spot == bar.spots.last,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 5,
                            color: line,
                            strokeWidth: 0,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Text(
          'Solid line: your trend. Fine dots: the plan'
          '${p.replanned ? ' since you changed the pace' : ''}. Dashes from '
          'today: at your recent pace. Level dashes: the target.',
          style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}
