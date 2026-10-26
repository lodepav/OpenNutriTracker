import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

/// Water's colour on Trends, a blue the palette lacks.
Color waterColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF7DB8E8)
    : const Color(0xFF2F7DBF);

/// [v] at [digits] decimals with its sign, "+12" or "-12"; one that rounds
/// to nothing is unsigned, never "-0".
String signedText(double v, [int digits = 0]) {
  final text = v.toStringAsFixed(digits);
  if (double.parse(text) == 0) return 0.toStringAsFixed(digits);
  return v > 0 ? '+$text' : text;
}

/// MacroFactor's 1W–All pills; picking one reloads Trends at that range.
class RangePills extends StatelessWidget {
  final int rangeDays;
  final ValueChanged<int> onChanged;

  const RangePills({
    super.key,
    required this.rangeDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'trends-range',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final r in trendRanges)
              Expanded(
                child: Semantics(
                  identifier: 'trends-range-${r.label.toLowerCase()}',
                  selected: r.days == rangeDays,
                  inMutuallyExclusiveGroup: true,
                  child: Material(
                    color: r.days == rangeDays
                        ? palette.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: ValueKey('trends-range-${r.days}'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: r.days == rangeDays
                          ? null
                          : () => onChanged(r.days),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: Text(
                            r.label,
                            style: text.labelLarge?.copyWith(
                              color: r.days == rangeDays
                                  ? palette.textStrong
                                  : palette.textMuted,
                              fontWeight: r.days == rangeDays
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tile's small chart: bars a day, or a line through the days present.
/// More days than fit are averaged into at most [maxBars] bars.
class Sparkline extends StatelessWidget {
  final DaySeries values;
  final bool bars;
  final Color color;
  final int maxBars;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.bars = true,
    this.maxBars = 14,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 26,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          bars ? bucketed(values, maxBars) : values,
          bars,
          color,
          paletteOf(context).surfaceMuted,
        ),
      ),
    ),
  );

  /// [values] in at most [count] groups, each the mean of its days
  /// present.
  static DaySeries bucketed(DaySeries values, int count) {
    if (values.length <= count) return values;
    return [
      for (var b = 0; b < count; b++)
        meanOf(
          values.sublist(
            b * values.length ~/ count,
            (b + 1) * values.length ~/ count,
          ),
        ),
    ];
  }
}

class _SparkPainter extends CustomPainter {
  final DaySeries values;
  final bool bars;
  final Color color;
  final Color track;

  _SparkPainter(this.values, this.bars, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().map((v) => v.abs()).toList();
    if (values.isEmpty || present.isEmpty) return;
    if (bars) {
      // From the period's lowest to its highest, as the pages' charts.
      final range = fittedRange(present);
      final span = range.max - range.min;
      final slot = size.width / values.length;
      final w = math.min(slot * 0.72, 16.0);
      for (final (i, v) in values.indexed) {
        final x = i * slot + (slot - w) / 2;
        final h = v == null || span == 0
            ? 2.0
            : math.max(2.0, (v.abs() - range.min) / span * size.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, w, h),
            const Radius.circular(2),
          ),
          Paint()..color = v == null ? track : color,
        );
      }
      return;
    }
    final points = [
      for (final (i, v) in values.indexed)
        if (v != null) (i, v),
    ];
    final lo = points.map((p) => p.$2).reduce(math.min);
    final hi = points.map((p) => p.$2).reduce(math.max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    final dx = values.length < 2 ? 0.0 : size.width / (values.length - 1);
    Offset at((int, double) p) =>
        Offset(p.$1 * dx, 3 + (1 - (p.$2 - lo) / span) * (size.height - 6));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (points.length == 1) {
      canvas.drawCircle(
        at(points.single),
        2.5,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color || old.bars != bars;
}

/// One tile of the grid: what it is, its number, its small chart.
class TrendTile extends StatelessWidget {
  final String id;
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;
  final Widget chart;
  final VoidCallback onTap;

  const TrendTile({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
    required this.chart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: id,
      child: AppCard(
        key: ValueKey(id),
        borderRadius: Dimens.radiusS,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: palette.textMuted),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 2),
            AutoSizeText.rich(
              TextSpan(
                text: value,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? palette.textStrong,
                ),
                children: [
                  if (suffix != null)
                    TextSpan(
                      text: ' $suffix',
                      style: text.labelMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              minFontSize: 11,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            chart,
          ],
        ),
      ),
    );
  }
}

/// A detail page's three numbers over its chart, as MacroFactor's.
class StatHeader extends StatelessWidget {
  final List<({String label, String value, String? unit})> stats;

  const StatHeader({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    TextSpan value(({String label, String value, String? unit}) s) => TextSpan(
      text: s.value,
      style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      children: [
        if (s.unit != null)
          TextSpan(
            text: ' ${s.unit}',
            style: text.labelMedium?.copyWith(color: palette.textMuted),
          ),
      ],
    );
    // Large text leaves a third of the width too narrow for a label or a
    // number and its unit: a row each, the label beside its figure.
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Column(
        children: [
          for (final s in stats)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Dimens.spacing4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        style: text.labelMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    Text.rich(value(s)),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Dimens.spacing8,
      children: [
        for (final s in stats)
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: palette.textMuted),
                  ),
                  AutoSizeText.rich(value(s), maxLines: 1, minFontSize: 12),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The day an x of a daily chart stands for, as "Oct 3".
String Function(int i) dayLabels(BuildContext context, List<DateTime> dates) {
  final format = intl.DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  return (i) => format.format(dates[i]);
}

/// The x axis of a daily chart: the weekday under each bar for a week,
/// else none.
FlTitlesData weekdayTitles(BuildContext context, List<DateTime> dates) {
  if (dates.length > 7) return const FlTitlesData(show: false);
  final format = intl.DateFormat.E(
    Localizations.localeOf(context).toLanguageTag(),
  );
  final style = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: paletteOf(context).textMuted);
  return FlTitlesData(
    leftTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    topTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        // Grown with the text, so a large font is not cut off.
        reservedSize: MediaQuery.textScalerOf(context).scale(22),
        getTitlesWidget: (x, meta) => SideTitleWidget(
          meta: meta,
          child: Text(format.format(dates[x.toInt()]), style: style),
        ),
      ),
    ),
  );
}

/// The y range a chart of [values] spans: a little under the lowest to a
/// little over the highest, so a period's changes fill the chart rather
/// than sit on a bar from zero. All positive, it stays at or over zero;
/// [minSpan] keeps a flat period from filling it with noise.
({double min, double max}) fittedRange(
  Iterable<double> values, {
  double minSpan = 1,
}) {
  if (values.isEmpty) return (min: 0, max: minSpan);
  final lo = values.reduce(math.min), hi = values.reduce(math.max);
  final pad = math.max(hi - lo, minSpan) * 0.15;
  return (min: lo >= 0 && lo - pad < 0 ? 0 : lo - pad, max: hi + pad);
}

/// A dashed goal line across a chart.
ExtraLinesData goalLine(BuildContext context, double? goal) =>
    goal == null || goal <= 0
    ? const ExtraLinesData()
    : ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: goal,
            color: paletteOf(context).textMuted,
            strokeWidth: 1.2,
            dashArray: const [6, 4],
          ),
        ],
      );

/// Bars a day of [values] (already in the unit shown), with the [goal]
/// dashed across; negative bars hang below zero.
class DailyBarChart extends StatelessWidget {
  final DaySeries values;
  final List<DateTime> dates;
  final Color color;
  final Color? negativeColor;
  final double? goal;
  final String unit;
  final String label;

  /// A tap on a day's bar; [selected] is the day picked, the others dimmed.
  final void Function(int index)? onTap;
  final int? selected;

  const DailyBarChart({
    super.key,
    required this.values,
    required this.dates,
    required this.color,
    this.negativeColor,
    this.goal,
    required this.unit,
    required this.label,
    this.onTap,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>();
    if (present.isEmpty) {
      return noData(context, 'Nothing logged in this range.');
    }
    // Over the period's own lowest and highest (and the goal), so its
    // changes show; bars that cross zero keep it.
    final range = fittedRange([
      ...present,
      if (goal != null && goal! > 0) goal!,
      if (present.any((v) => v < 0)) 0,
    ]);
    final base = range.min > 0 ? range.min : 0.0;
    final dayLabel = dayLabels(context, dates);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(
          builder: (context, box) => BarChart(
            BarChartData(
              minY: range.min,
              maxY: range.max,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: weekdayTitles(context, dates),
              extraLinesData: goalLine(context, goal),
              barTouchData: BarTouchData(
                touchCallback: onTap == null
                    ? null
                    : (event, response) {
                        final spot = response?.spot;
                        if (event is FlTapUpEvent && spot != null) {
                          onTap!(spot.touchedBarGroupIndex);
                        }
                      },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${rod.toY.round()} $unit\n${dayLabel(group.x)}',
                    TextStyle(color: scheme.onInverseSurface),
                  ),
                ),
              ),
              barGroups: [
                for (final (i, v) in values.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        fromY: base,
                        toY: v ?? base,
                        width: barWidth(box.maxWidth, values.length),
                        color: ((v ?? 0) < 0 ? negativeColor ?? color : color)
                            .withValues(
                              alpha: selected == null || selected == i
                                  ? 1
                                  : 0.35,
                            ),
                        borderRadius: BorderRadius.circular(
                          values.length <= 31 ? 3 : 0,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bar's width for [count] bars across [width].
double barWidth(double width, int count) =>
    (width / count * 0.66).clamp(1.0, 30.0);

/// In place of a chart with nothing to draw, at its height.
Widget noData(BuildContext context, String message) => SizedBox(
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
