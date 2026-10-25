import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/calc/weight_moving_average.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S15 smoothed-trend: the smoothed trend in place of the 7-day average (D13)
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
// [/fork]
// [fork] S96 chart-touch
import 'package:opennutritracker/fork/report/chart_touch.dart';
// [/fork]

/// Smoothed weight trend line shared by the weight-history screen and the
/// Trends view, so both render the same chart — dated axis, a dashed
/// target-weight reference, dots on each reading, and a curved line.
///
/// [windowDays] sets how far back the chart looks; entries older than that
/// are dropped. The y-range is computed from the recorded weights so a
/// far-away target weight never squashes the trend.
class WeightTrendChart extends StatelessWidget {
  final List<WeightLogEntity> entries;
  final BodyWeightUnit bodyWeightUnit;
  final double? targetWeightKg;
  final int windowDays;
  final double chartHeight;

  /// Trailing-window length for the moving-average overlay. Null hides the
  /// overlay entirely; the default of 7 days is a common weight-tracking
  /// smoothing that hides day-to-day water swings without lagging the real
  /// trend too far (#1119).
  final int? movingAverageWindowDays;

  /// The clock "today" is read from. The window's DST behaviour depends on
  /// which dates it spans, so a test that reads the real clock only proves
  /// something for a few weeks a year; tests pin this and restore it.
  /// Production never assigns it.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  const WeightTrendChart({
    super.key,
    required this.entries,
    required this.bodyWeightUnit,
    required this.targetWeightKg,
    this.windowDays = 30,
    this.chartHeight = 220,
    this.movingAverageWindowDays = 7,
  });

  /// Converts a stored kg value to the chart's y-axis unit.
  double _toChartY(double kg) {
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        return kg;
      case BodyWeightUnit.lb:
        return UnitCalc.kgToLbs(kg);
      case BodyWeightUnit.st:
        // Decimal stones: total lbs / 14. One decimal is enough for the axis.
        return kg * 2.20462 / 14;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.primary;

    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    // windowDays calendar days ending today (today sits at the right edge),
    // matching how the calorie/water charts window their range. Built with
    // the y/m/d constructor, not `subtract(Duration)`: a Duration is fixed
    // 24-hour spans, so with an autumn fall-back inside the window it lands
    // an hour past local midnight and drops that day's entry (#1207).
    final windowStart = DateTime(
      today.year,
      today.month,
      today.day - (windowDays - 1),
    );
    // x = whole calendar days since the window start, so today sits at
    // x = windowDays - 1 and a day is one unit even when a DST transition
    // makes it 23 or 25 hours long. Every consumer of the x axis (dots,
    // date labels) goes through this pair so they cannot drift apart.
    int dayIndex(DateTime date) =>
        CalendarDayCalc.daysBetween(windowStart, date);
    DateTime dayAt(int x) => DateUtils.addDaysToDate(windowStart, x);

    final inWindow =
        entries
            .where(
              (e) => !e.date.isBefore(windowStart) && !e.date.isAfter(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (inWindow.length < 2) {
      return Padding(
        key: const Key('weightHistoryChartEmptyState'),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SizedBox(
          height: chartHeight,
          child: Center(
            child: Text(
              S.of(context).weightHistoryChartEmptyState,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (final entry in inWindow)
        FlSpot(dayIndex(entry.date).toDouble(), _toChartY(entry.weightKg)),
    ];

    // Compute the moving average against the *full* log and clip to the
    // visible window, so the leftmost MA point is anchored on entries
    // predating the window rather than lagging one window-length behind.
    // [fork] S15 smoothed-trend
    final smoothed = smoothedTrendPoints(entries);
    // [/fork]
    final maSpots = <FlSpot>[
      if (movingAverageWindowDays != null)
        for (final point
            // [fork] S15 smoothed-trend
            in (smoothed ??
                    WeightMovingAverage(windowDays: movingAverageWindowDays!)
                        .compute(entries))
                // [/fork]
                .where((p) =>
                    !p.date.isBefore(windowStart) &&
                    !p.date.isAfter(today)))
          FlSpot(dayIndex(point.date).toDouble(), _toChartY(point.weightKg)),
    ];

    // The MA is the one series whose leftmost points fold in readings
    // that predate the visible window, so its y can land above or below
    // the raw envelope; include both series in the range so the dashed
    // line never paints outside the plot (LineChartData defaults to
    // FlClipData.none()).
    final rangeSpots = [...spots, ...maSpots];
    final minY = rangeSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = rangeSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Pad so points don't sit on the edges. When all weights are identical we
    // still need a non-zero range or fl_chart throws.
    final yPadding = ((maxY - minY) * 0.15).clamp(0.5, 5.0);

    final targetY = targetWeightKg == null ? null : _toChartY(targetWeightKg!);
    // Only draw the dashed reference when the target sits within (or just
    // adjacent to) the auto y-range, so a far-off target doesn't autoscale
    // the chart away from the recorded weights.
    final showTargetLine =
        targetY != null &&
        targetY >= (minY - yPadding) &&
        targetY <= (maxY + yPadding);

    final localeTag = Localizations.localeOf(context).toLanguageTag();
    // [fork] S96 chart-touch: read here, as the tooltip is built outside
    // the build
    final unitLabel = switch (bodyWeightUnit) {
      BodyWeightUnit.kg => S.of(context).kgLabel,
      BodyWeightUnit.lb => S.of(context).lbsLabel,
      BodyWeightUnit.st => S.of(context).stLabel,
    };
    // [/fork]
    final dateFormat = DateFormat.MMMd(localeTag);
    // ~5 evenly spaced date labels regardless of window length.
    final labelInterval = (windowDays / 5)
        .ceilToDouble()
        .clamp(1.0, double.infinity)
        .toDouble();

    return Padding(
      key: const Key('weightHistoryChart'),
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
      // [fork] S96 chart-touch: a legend under the chart, as the dashed line
      // means the trend here and a plan on the Trend weight card
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
      // [/fork]
      SizedBox(
        height: chartHeight,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (windowDays - 1).toDouble(),
            minY: minY - yPadding,
            maxY: maxY + yPadding,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            // [fork] S96 chart-touch: each number says which it is, at one
            // decimal ("Trend 95.1 kg"; upstream's default showed
            // "95.13333333333337" over "94.6"), with no line to the axis
            lineTouchData: labelledTouch(
              context,
              (s) =>
                  '${s.barIndex == 0 ? 'Weighed' : 'Trend'} '
                  '${s.y.toStringAsFixed(1)} $unitLabel',
            ),
            // [/fork]
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  // [fork] S83 axis-labels: the padded edges are not ticks,
                  // and a half-step shows its decimal, so no two labels
                  // read the same ("88, 88, 87").
                  getTitlesWidget: (value, meta) =>
                      value == meta.min || value == meta.max
                      ? const SizedBox.shrink()
                      : Text(
                    value.toStringAsFixed(
                      bodyWeightUnit == BodyWeightUnit.st ||
                              value != value.roundToDouble()
                          ? 1
                          : 0,
                    ),
                    style: theme.textTheme.labelSmall,
                  ),
                  // [/fork]
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: labelInterval,
                  getTitlesWidget: (value, meta) {
                    final day = dayAt(value.toInt());
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        dateFormat.format(day),
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (showTargetLine)
                  HorizontalLine(
                    y: targetY,
                    color: theme.colorScheme.outline,
                    strokeWidth: 1.2,
                    dashArray: const [6, 4],
                  ),
              ],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: lineColor,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 3,
                        color: lineColor,
                        strokeWidth: 0,
                      ),
                ),
              ),
              // Moving-average overlay (#1119): dashed, no dots, thinner
              // than the primary line so the raw readings still read as
              // the leading signal. Rendered second so it sits on top of
              // the raw line where they overlap.
              if (maSpots.length >= 2)
                LineChartBarData(
                  spots: maSpots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: lineColor.withValues(alpha: 0.55),
                  barWidth: 1.5,
                  dashArray: const [6, 4],
                  dotData: const FlDotData(show: false),
                ),
            ],
          ),
        ),
      ),
      // [fork] S96 chart-touch
      if (maSpots.length >= 2)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            smoothed != null
                ? 'Dots: weigh-ins. Dashed: trend.'
                : 'Dots: weigh-ins. Dashed: 7-day average.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        ],
      ),
      // [/fork]
    );
  }
}
