import 'package:auto_size_text/auto_size_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S97 chart-touch
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/fork/report/chart_touch.dart';
// [/fork]
// [fork] S93 weight-outlook
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
// [/fork]
// [fork] S40 expenditure-card
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';
import 'package:opennutritracker/fork/body/body_card.dart';
import 'package:opennutritracker/fork/health/steps_card.dart';
import 'package:opennutritracker/fork/phases/phases_ui.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';
// [/fork]
// [fork] S120 trends-tiles
import 'package:opennutritracker/fork/trends/trends_overview.dart';
// [/fork]
// [fork] S111 typed-weigh-in
import 'package:opennutritracker/fork/weight/weigh_in_log.dart';
// [/fork]

class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key});

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  // The bloc is a GetIt singleton, so provide it by value rather than letting
  // BlocProvider close it on dispose. Settings holds the same instance and
  // pokes it with LoadTrendsEvent when the body-weight unit changes.
  final TrendsBloc _trendsBloc = locator<TrendsBloc>();

  @override
  void initState() {
    super.initState();
    _trendsBloc.add(const LoadTrendsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TrendsBloc>.value(
      value: _trendsBloc,
      child: const _TrendsView(),
    );
  }
}

class _TrendsView extends StatelessWidget {
  const _TrendsView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return BlocBuilder<TrendsBloc, TrendsState>(
      builder: (context, state) {
        if (state is! TrendsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        // [fork] S120 trends-tiles: MacroFactor's tile grid in place of
        // upstream's streak card, range picker and cards; the weight and
        // water cards open from their tiles, the calorie and macro cards
        // gave way to the Calories page (S40's cards follow the grid).
        return TrendsOverview(
          state: state,
          weightCard: (state) => _WeightCard(
            entries: state.weight,
            bodyWeightUnit: state.bodyWeightUnit,
            targetWeightKg: state.targetWeightKg,
            rangeDays: state.windowDays,
            palette: palette,
          ),
          waterCard: (state) => _WaterTrendCard(
            waterByDay: state.waterByDay,
            goalMl: state.waterGoalMl,
            rangeDays: state.windowDays,
            palette: palette,
          ),
          cards: {
            'weekly': WeeklyReportCard(
              days: state.days,
              rangeDays: state.windowDays,
              palette: palette,
            ),
            'goalPlan': GoalPlanCard(palette: palette, unit: state.bodyWeightUnit),
            'phases': DietPhasesCard(unit: state.bodyWeightUnit),
            'body': BodyMeasurementsCard(
              rangeDays: state.windowDays,
              palette: palette,
              imperial: state.bodyWeightUnit != BodyWeightUnit.kg,
            ),
            'steps': StepsCard(rangeDays: state.windowDays, palette: palette),
            'photos': const ProgressPhotosCard(),
          },
        );
        // [/fork]
      },
    );
  }
}

// [fork] S97 chart-touch: the day a chart's x stands for, as "Oct 3";
// made in the build, as the tooltip is built outside it
String Function(double x) _dayLabels(
  BuildContext context,
  DateTime today,
  int rangeDays,
) {
  final format =
      intl.DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag());
  return (x) => format.format(
        DateTime(today.year, today.month,
            today.day - (rangeDays - 1 - x.round())),
      );
}

/// In place of a chart with nothing to draw, at its height.
Widget _noData(BuildContext context, String message) => SizedBox(
      height: 140,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
// [/fork]

class _WaterTrendCard extends StatelessWidget {
  final Map<DateTime, int> waterByDay;
  final int goalMl;
  final int rangeDays;
  final AppPalette palette;
  const _WaterTrendCard({
    required this.waterByDay,
    required this.goalMl,
    required this.rangeDays,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = palette.proteinColor;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final spots = <FlSpot>[];
    var sum = 0;
    var loggedDays = 0;
    for (int i = 0; i < rangeDays; i++) {
      final day = today.subtract(Duration(days: rangeDays - 1 - i));
      final ml = waterByDay[DateTime(day.year, day.month, day.day)] ?? 0;
      spots.add(FlSpot(i.toDouble(), ml.toDouble()));
      if (ml > 0) {
        sum += ml;
        loggedDays++;
      }
    }
    final avg = loggedDays == 0 ? 0 : (sum / rangeDays).round();
    final maxWater = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    // [fork] S97 chart-touch
    final dayLabel = _dayLabels(context, today, rangeDays);
    // [/fork]
    final maxY =
        [maxWater, goalMl.toDouble()].reduce((a, b) => a > b ? a : b) * 1.15 + 1;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AutoSizeText(S.of(context).trendsWaterLabel,
                    style: text.titleMedium,
                    maxLines: 1,
                    minFontSize: 12,
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                S.of(context).waterChipLabel(avg, goalMl),
                style: text.bodySmall?.copyWith(
                    color: palette.textMuted, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing20),
          // [fork] S97 chart-touch
          if (loggedDays == 0)
            _noData(context, 'No water logged in this range.')
          else
          // [/fork]
          Semantics(
            label: S.of(context).trendsWaterLabel,
            child: SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (rangeDays - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  // [fork] S97 chart-touch
                  lineTouchData: labelledTouch(
                    context,
                    (s) => '${s.y.round()}',
                    after: (s) => ' ml\n${dayLabel(s.x)}',
                  ),
                  // [/fork]
                  extraLinesData: goalMl <= 0
                      ? const ExtraLinesData()
                      : ExtraLinesData(horizontalLines: [
                          HorizontalLine(
                            y: goalMl.toDouble(),
                            color: palette.textMuted,
                            strokeWidth: 1.2,
                            dashArray: const [6, 4],
                          ),
                        ]),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(show: rangeDays <= 7),
                      belowBarData: BarAreaData(
                          show: true, color: color.withValues(alpha: 0.12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  final List<WeightLogEntity> entries;
  final BodyWeightUnit bodyWeightUnit;
  final double? targetWeightKg;
  final int rangeDays;
  final AppPalette palette;
  const _WeightCard({
    required this.entries,
    required this.bodyWeightUnit,
    required this.targetWeightKg,
    required this.rangeDays,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // [fork] S93 weight-outlook: the weigh-ins the chart draws, so the
    // outlook shows only when the chart has a trend, and from the same
    // points; all of them read a rate under "Log at least two days".
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(today.year, today.month, today.day - (rangeDays - 1));
    bool inRange(DateTime d) => !d.isBefore(start) && !d.isAfter(today);
    final readings = [
      for (final e in [...entries]..sort((a, b) => a.date.compareTo(b.date)))
        if (inRange(e.date)) (date: e.date, kg: e.weightKg),
    ];
    // The rate from the smoothed trend, as the Goal planner's "Last 7
    // days" is: carried on to today, over the range's days back from it;
    // a fit of the raw readings read -0.0 where the planner said -0.18.
    final from = DateTime(today.year, today.month, today.day - rangeDays);
    final trend = trendPoints(entries, until: today)
        .where((p) => !p.date.isBefore(from) && !p.date.isAfter(today))
        .toList();
    final projection = readings.length < 2
        ? null
        : weightProjection(
            trend.length < 2
                ? readings
                : [
                    for (final p in [trend.first, trend.last])
                      (date: p.date, kg: p.weightKg),
                  ],
            targetWeightKg,
          );
    // [/fork]
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AutoSizeText(S.of(context).weightHistoryWeightLabel,
                    style: text.titleMedium,
                    maxLines: 1,
                    minFontSize: 12,
                    overflow: TextOverflow.ellipsis),
              ),
              Semantics(
                identifier: 'trends-log-weight',
                // Tight bounds: without this the node inherits the whole
                // card's box (the container gotcha) and coordinate taps miss.
                container: true,
                child: IconButton(
                  tooltip: S.of(context).weightHistoryAddEntry,
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _logWeight(context),
                ),
              ),
            ],
          ),
          if (projection != null)
            Text(
              _projectionLabel(context, projection),
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          const SizedBox(height: Dimens.spacing12),
          WeightTrendChart(
            entries: entries,
            bodyWeightUnit: bodyWeightUnit,
            targetWeightKg: targetWeightKg,
            windowDays: rangeDays,
          ),
        ],
      ),
    );
  }

  /// One-line weight outlook: the weekly rate of change (in the user's unit),
  /// plus a rough number of weeks to the target when one is set and the trend
  /// is heading toward it.
  String _projectionLabel(
    BuildContext context,
    ({double ratePerWeek, int? weeksToTarget}) projection,
  ) {
    // [fork] S93 weight-outlook: measured, not the plan's pace, at two
    // decimals as the Trend weight card's, and never "-0.00"
    final (rate, unit) = switch (bodyWeightUnit) {
      BodyWeightUnit.kg => (projection.ratePerWeek, S.of(context).kgLabel),
      BodyWeightUnit.lb => (
        projection.ratePerWeek * 2.20462,
        S.of(context).lbsLabel,
      ),
      // Decimal stones for rate display.
      BodyWeightUnit.st => (
        projection.ratePerWeek * 2.20462 / 14,
        S.of(context).stLabel,
      ),
    };
    var label = 'Trend: ${signedRate(rate)} $unit a week';
    // [/fork]
    if (projection.weeksToTarget != null) {
      label += ' · ~${projection.weeksToTarget} '
          '${S.of(context).trendsWeeksToGoalLabel}';
    }
    return label;
  }

  /// Logs a weight entry from the trends view, reusing the same dialog and
  /// persistence path as the home weight chip, then reloads the trend so the
  /// chart reflects the new point. Keeping weight editable here means it no
  /// longer lives only behind the home widget.
  Future<void> _logWeight(BuildContext context) async {
    final trendsBloc = context.read<TrendsBloc>();
    final rangeDays = trendsBloc.state is TrendsLoaded
        ? (trendsBloc.state as TrendsLoaded).rangeDays
        : 7;
    final user = await locator<GetUserUsecase>().getUserData();
    final logged = await weighInsByDay(); // [fork] S111
    if (!context.mounted) return;
    final entered = await showDialog<({double weight, DateTime date})>(
      context: context,
      builder: (_) => SetWeightDialog(
        initialKg: user.weightKG,
        unit: bodyWeightUnit,
        allowDateSelection: true,
        logged: logged, // [fork] S111
      ),
    );
    if (entered == null || !context.mounted) return; // [fork] S111
    // The dialog now always returns kg in the weight slot.
    final kg = entered.weight;
    final d = entered.date;
    // [fork] S111 typed-weigh-in: says what it filed, with an Undo that
    // brings back the weigh-in it replaced
    final day = DateTime(d.year, d.month, d.day);
    await logWeighIn(
      context,
      kg: kg,
      day: day,
      unit: bodyWeightUnit,
      replaced: logged[day],
      refresh: () async {
        final updated = await locator<GetUserUsecase>().getUserData();
        await locator<ProfileBloc>().updateUser(updated);
        if (context.mounted) {
          trendsBloc.add(LoadTrendsEvent(rangeDays: rangeDays));
        }
      },
    );
    // [/fork]
  }
}
