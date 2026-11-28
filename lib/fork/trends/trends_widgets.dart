import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/motion.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart'
    show ChartLegend;
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_range.dart';
import 'package:opennutritracker/fork/trends/value_axis.dart';

/// Water's colour on Trends.
Color waterColor(BuildContext context) => paletteOf(context).water;

/// A tile's short warning line, at 4.5:1 or more on the tile.
Color noteColor(BuildContext context) => paletteOf(context).warningText;

/// [text] with its units whole: no line break inside "-0.16/wk",
/// "kcal/day", "2925 kcal" or "fl oz"; " / " and " · " still break.
String keepUnits(String text) => text
    .replaceAll('fl oz', 'fl\u00A0oz')
    .replaceAllMapped(
      RegExp(r'(?<=\d) (?=\p{L})', unicode: true),
      (_) => '\u00A0',
    )
    .replaceAllMapped(RegExp(r'(?<=\S)/(?=\S)'), (_) => '/\u2060');

/// [v] at [digits] decimals with its sign, "+12" or "−12" (a true minus);
/// one that rounds to nothing is unsigned, never "−0".
String signedText(double v, [int digits = 0]) {
  final text = v.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) return 0.toStringAsFixed(digits);
  return v > 0 ? '+$text' : '\u2212$text';
}

/// MacroFactor's 1W–All pills; picking one reloads Trends at that range,
/// and Trends opens at it next time ([TrendsRange]). Given [ranges], the
/// pills are those and a pick is not kept as Trends' range.
class RangePills extends StatelessWidget {
  final int rangeDays;
  final ValueChanged<int> onChanged;

  /// The ranges shown, Trends' when null.
  final List<({int days, String label, String spoken})>? ranges;

  /// The Semantics identifier and the start of each pill's key.
  final String idPrefix;

  const RangePills({
    super.key,
    required this.rangeDays,
    required this.onChanged,
    this.ranges,
    this.idPrefix = 'trends-range',
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final options =
        ranges ??
        [
          for (final r in trendRanges)
            (
              days: r.days,
              label: r.label,
              spoken: switch (r.days) {
                7 => '1 week',
                30 => '1 month',
                365 => '1 year',
                0 => 'All',
                _ => '${r.days ~/ 30} months',
              },
            ),
        ];
    return Semantics(
      identifier: idPrefix,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final r in options)
              Expanded(
                child: Semantics(
                  identifier:
                      '$idPrefix-${r.label.toLowerCase().replaceAll(' ', '')}',
                  label: r.spoken,
                  button: true,
                  selected: r.days == rangeDays,
                  inMutuallyExclusiveGroup: true,
                  child: Material(
                    color: r.days == rangeDays
                        ? palette.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: ValueKey('$idPrefix-${r.days}'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: r.days == rangeDays
                          ? null
                          : () {
                              if (ranges == null) TrendsRange.save(r.days);
                              onChanged(r.days);
                            },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: ExcludeSemantics(
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
              ),
          ],
        ),
      ),
    );
  }
}

/// A tile's small chart: bars a day from zero, or a line through the days
/// present. More days than fit are averaged into at most [maxBars] bars.
class Sparkline extends StatelessWidget {
  final DaySeries values;
  final bool bars;
  final Color color;

  /// A bar below zero's colour, [color] when null.
  final Color? negativeColor;
  final int maxBars;

  /// The daily goal, drawn as a tick across the bars; none when null.
  final double? goal;

  /// A line's highest and lowest value as printed beside it, in the unit
  /// the tile shows; no scale when null.
  final String Function(double value)? scaleText;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.negativeColor,
    this.goal,
    this.scaleText,
    this.bars = true,
    this.maxBars = 14,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final spark = SizedBox(
      height: 26,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          bars ? bucketed(values, maxBars) : values,
          bars,
          color,
          negativeColor ?? color,
          palette.surfaceMuted,
          bars ? goal : null,
          chartSafe(palette.textMuted, palette.surface),
        ),
      ),
    );
    final present = values.nonNulls;
    if (bars || scaleText == null || present.isEmpty) {
      return ExcludeSemantics(child: spark);
    }
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.textMuted);
    return ExcludeSemantics(
      child: Row(
        children: [
          Expanded(child: spark),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(scaleText!(present.reduce(math.max)), style: style),
              Text(scaleText!(present.reduce(math.min)), style: style),
            ],
          ),
        ],
      ),
    );
  }

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
  final Color negativeColor;
  final Color track;
  final double? goal;

  /// The goal's and the zero line's colour, 3:1 on the card.
  final Color lineColor;

  _SparkPainter(
    this.values,
    this.bars,
    this.color,
    this.negativeColor,
    this.track,
    this.goal,
    this.lineColor,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (values.isEmpty || present.isEmpty) return;
    if (bars) {
      final target = goal != null && goal! > 0 ? goal : null;
      // From zero, so a low day is not drawn as the stub of an empty one.
      final hi = math.max(
        target ?? 0.0,
        math.max(0.0, present.reduce(math.max)),
      );
      final lo = math.min(0.0, present.reduce(math.min));
      final span = hi - lo;
      final zero = span == 0 ? size.height : hi / span * size.height;
      final slot = size.width / values.length;
      final w = math.min(slot * 0.72, 16.0);
      for (final (i, v) in values.indexed) {
        final x = i * slot + (slot - w) / 2;
        final h = v == null || span == 0
            ? 2.0
            : math.max(2.0, v.abs() / span * size.height);
        final top = v != null && v < 0
            ? math.min(zero, size.height - h)
            : (zero - h).clamp(0.0, size.height - h);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, w, h),
            const Radius.circular(2),
          ),
          Paint()
            ..color = v == null
                ? track
                : v < 0
                ? negativeColor
                : color,
        );
      }
      // The line deficits hang from, so a bar's side of it reads.
      if (lo < 0) {
        canvas.drawLine(
          Offset(0, zero),
          Offset(size.width, zero),
          Paint()
            ..color = lineColor
            ..strokeWidth = 1,
        );
      }
      if (target != null) {
        // Inside the box, so the line at the top is not cut in half.
        final y = (zero - target / span * size.height).clamp(0.75, size.height);
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = lineColor
            ..strokeWidth = 1.5,
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
      old.values != values ||
      old.color != color ||
      old.negativeColor != negativeColor ||
      old.bars != bars ||
      old.goal != goal ||
      old.lineColor != lineColor;
}

/// One tile of a grid, on Home, Trends and You alike: what it is, its
/// number, and a small chart or line under them.
class TrendTile extends StatelessWidget {
  final String id;
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;

  /// Under the value: a chart, a bar or a line of text; none when null.
  final Widget? chart;
  final VoidCallback? onTap;

  /// What a screen reader says for the whole tile, in words
  /// ("Calories, daily average 2573 of 2925 kcal"), as is: it includes
  /// the [note] if that should be heard. The label, value and note when
  /// null.
  final String? spokenLabel;

  /// What the tap does, for a screen reader ("Open the weight trend").
  final String? hint;

  /// A short line under the value, e.g. "over limit" for a passed limit.
  final String? note;

  /// [note] is a plain fact ("from Nov 9"), muted, not a warning in amber.
  final bool noteMuted;

  /// A + in the corner that logs (a weigh-in, water), [actionTooltip] its
  /// name; beside the card rather than in it, a button in a button being
  /// one target to a screen reader.
  final VoidCallback? onAction;
  final String? actionTooltip;

  const TrendTile({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
    this.chart,
    this.onTap,
    this.spokenLabel,
    this.hint,
    this.note,
    this.noteMuted = false,
    this.onAction,
    this.actionTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final card = Semantics(
      identifier: id,
      container: true,
      button: onTap != null,
      label:
          spokenLabel ??
          [label, suffix == null ? value : '$value $suffix', ?note].join(', '),
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
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
                    // A second line, not "Shoulders · left vs right" cut (A6).
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: palette.textMuted),
                  ),
                ),
                // The + takes the corner and says the tile acts.
                if (onAction != null)
                  const SizedBox(width: 32)
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textMuted,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            // Wraps rather than shrinks: Home's rows size by IntrinsicHeight.
            Text.rich(
              TextSpan(
                text: value,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? palette.textStrong,
                ),
                children: [
                  if (suffix != null)
                    TextSpan(
                      text: ' ${keepUnits(suffix!)}',
                      style: text.labelMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            if (note != null)
              Text(
                note!,
                style: noteMuted
                    ? text.bodySmall?.copyWith(color: palette.textMuted)
                    : text.labelMedium?.copyWith(
                        color: noteColor(context),
                        fontWeight: FontWeight.w600,
                      ),
              ),
            if (chart != null) ...[const SizedBox(height: 6), chart!],
          ],
        ),
      ),
    );
    if (onAction == null) return card;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        card,
        PositionedDirectional(
          top: 0,
          end: 0,
          child: IconButton(
            key: Key('$id-add'),
            tooltip: actionTooltip,
            icon: const Icon(Icons.add_rounded),
            onPressed: onAction,
          ),
        ),
      ],
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
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = text.labelMedium?.copyWith(color: palette.textMuted);
    // Whether every label, and every figure at its smallest (12 sp, scaled),
    // fits a third of [width] on one line.
    bool fits(double width) {
      final column =
          (width - Dimens.spacing8 * (stats.length - 1)) / stats.length;
      // AutoSizeText shrinks to 12 over the ambient size, before the scale
      final shrink = math.min(
        1.0,
        12 / (DefaultTextStyle.of(context).style.fontSize ?? 14),
      );
      double wide(InlineSpan span) {
        final painter = TextPainter(
          text: span,
          textScaler: scaler,
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final w = painter.width;
        painter.dispose();
        return w;
      }

      return stats.every(
        (s) =>
            wide(TextSpan(text: s.label, style: labelStyle)) <= column &&
            wide(value(s)) * shrink <= column,
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Large text, or a narrow screen, leaves a third of the width too
        // narrow for a label or a number and its unit: a row each, the label
        // beside its figure.
        if (scaler.scale(1) >= 1.5 || !fits(box.maxWidth)) {
          return _stacked(context, value);
        }
        return _columns(context, value);
      },
    );
  }

  Widget _stacked(
    BuildContext context,
    TextSpan Function(({String label, String value, String? unit})) value,
  ) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
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

  Widget _columns(
    BuildContext context,
    TextSpan Function(({String label, String value, String? unit})) value,
  ) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
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

/// The range [dates] spans, as a page's header says it: "Nov 2025 –
/// Nov 2026" over more than about six months, "Dec 30, 2025 – Jan 5, 2026"
/// across a new year, else "Oct 30 – Nov 28"; as the Expenditure chart's
/// dates.
String rangeDatesText(BuildContext context, List<DateTime> dates) {
  if (dates.isEmpty) return '';
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = dates.length > 183
      ? intl.DateFormat.yMMM(locale)
      : dates.first.year != dates.last.year
      ? intl.DateFormat.yMMMd(locale)
      : intl.DateFormat.MMMd(locale);
  if (dates.length == 1) return format.format(dates.single);
  return '${format.format(dates.first)} – ${format.format(dates.last)}';
}

/// The x axis of a bar chart whose bars start on [dates], [perBar] days a
/// bar ([daysPerBar]): the weekday under each of a week's daily bars, else
/// the first, middle and last bar's date ("Nov 2025" for months), the
/// middle left out where the three would not fit; [right], its value axis.
FlTitlesData weekdayTitles(
  BuildContext context,
  List<DateTime> dates, {
  AxisTitles right = const AxisTitles(),
  int perBar = 1,
}) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final weekdays = perBar == 1 && dates.length <= 7;
  final format = weekdays
      ? intl.DateFormat.E(locale)
      : perBar >= 28
      ? intl.DateFormat.yMMM(locale)
      // Across a new year, as the Expenditure chart's dates.
      : dates.first.year != dates.last.year
      ? intl.DateFormat.yMMMd(locale)
      : intl.DateFormat.MMMd(locale);
  final style = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: paletteOf(context).textMuted);
  final scaler = MediaQuery.textScalerOf(context);
  final last = dates.length - 1;
  double wide(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  Widget dated(double x, TitleMeta meta) {
    final i = x.toInt();
    if (i != 0 && i != last && i != last ~/ 2) return const SizedBox.shrink();
    final text = format.format(dates[i]);
    if (i == last ~/ 2 && i != 0) {
      // The ends' labels sit inside the edges, the middle's centred.
      final end = math.max(
        wide(format.format(dates.first)),
        wide(format.format(dates.last)),
      );
      if (2 * end + wide(text) + 24 > meta.parentAxisSize) {
        return const SizedBox.shrink();
      }
    }
    // The ends shifted inside by their own width: fl_chart's fitInside
    // measures a label once, so after a font change it cut the first.
    final half = wide(text) / 2;
    final shift = i == 0
        ? math.max(0.0, half - meta.axisPosition)
        : i == last
        ? math.min(0.0, meta.parentAxisSize - meta.axisPosition - half)
        : 0.0;
    return Transform.translate(
      offset: Offset(shift, 0),
      child: SideTitleWidget(
        meta: meta,
        child: Text(text, softWrap: false, style: style),
      ),
    );
  }

  return FlTitlesData(
    leftTitles: const AxisTitles(),
    rightTitles: right,
    topTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        // Grown with the text, so a large font is not cut off.
        reservedSize: scaler.scale(22),
        getTitlesWidget: (x, meta) => weekdays
            ? SideTitleWidget(
                meta: meta,
                // Shrunk to its day's slot, which the value axis narrows,
                // with a gap to the next.
                child: SizedBox(
                  width: math.max(0, meta.parentAxisSize / dates.length - 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(format.format(dates[x.toInt()]), style: style),
                  ),
                ),
              )
            : dated(x, meta),
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

/// The days a bar of a range of [days] stands for: one to a month, a week
/// to six months, past that a calendar month (30).
int daysPerBar(int days) => days <= 31
    ? 1
    : days <= 186
    ? 7
    : 30;

/// The bars of a range of [dates] ([daysPerBar]), each its days' indices
/// from start to end (exclusive): a day each; a week each, the last
/// ending on the last day, so the newest bar is the last seven days; or a
/// calendar month each.
List<({int start, int end})> barSpans(List<DateTime> dates) {
  final n = dates.length;
  return switch (daysPerBar(n)) {
    1 => [for (var i = 0; i < n; i++) (start: i, end: i + 1)],
    7 => [
      for (var end = n - (n - 1) ~/ 7 * 7; end <= n; end += 7)
        (start: math.max(0, end - 7), end: end),
    ],
    _ => _months(dates),
  };
}

List<({int start, int end})> _months(List<DateTime> dates) {
  final spans = <({int start, int end})>[];
  var start = 0;
  for (var i = 1; i <= dates.length; i++) {
    if (i == dates.length || dates[i].month != dates[start].month) {
      spans.add((start: start, end: i));
      start = i;
    }
  }
  return spans;
}

/// [values] averaged over each of [spans]: the mean of its days logged,
/// null without any.
DaySeries spanMeans(DaySeries values, List<({int start, int end})> spans) => [
  for (final s in spans) meanOf(values.sublist(s.start, s.end)),
];

/// What a bar of [span] of [dates] stands for, as its tooltip says it:
/// the day "Nov 3", the week "Nov 3 – Nov 9" or the month "Nov 2025".
String Function(({int start, int end}) span) spanLabels(
  BuildContext context,
  List<DateTime> dates,
) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final day = intl.DateFormat.MMMd(locale);
  final month = intl.DateFormat.yMMM(locale);
  final perBar = daysPerBar(dates.length);
  return (s) => perBar == 1 || s.end - s.start == 1
      ? day.format(dates[s.start])
      : perBar == 7
      ? '${day.format(dates[s.start])} – ${day.format(dates[s.end - 1])}'
      : month.format(dates[s.start]);
}

/// A bar's tooltip: its figure, or for a bar of several days their
/// average, and what the bar stands for.
String barTooltip(
  String figure,
  String unit,
  String span, {
  required bool many,
}) => many ? 'Average $figure $unit\n$span' : '$figure $unit\n$span';

/// [goal] as an error range on a bar reaching [toY], so fl_chart hands the
/// goal's height to [goalTicks]' painter; none without a goal.
FlErrorRange? goalRange(double toY, double? goal) => goal == null || goal <= 0
    ? null
    : FlErrorRange(
        lowerBy: math.max(0, toY - goal),
        upperBy: math.max(0, goal - toY),
      );

/// Each bar's own goal ([goalRange]) as a tick across it, in [color].
FlErrorIndicatorData<BarChartSpotErrorRangeCallbackInput> goalTicks(
  Color color,
) => FlErrorIndicatorData(
  painter: (input) => _GoalTick(color, input.rod.width + 6),
);

class _GoalTick extends FlSpotErrorRangePainter {
  final Color color;
  final double width;

  const _GoalTick(this.color, this.width);

  @override
  void draw(
    Canvas canvas,
    Offset offsetInCanvas,
    FlSpot origin,
    Rect errorRelativeRect,
    AxisChartData axisChartData,
  ) {
    // The range runs from the bar's top to the goal, up or down.
    final y =
        offsetInCanvas.dy +
        ((origin.yError?.upperBy ?? 0) > 0
            ? errorRelativeRect.top
            : errorRelativeRect.bottom);
    canvas.drawLine(
      Offset(offsetInCanvas.dx - width / 2, y),
      Offset(offsetInCanvas.dx + width / 2, y),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  List<Object?> get props => [color, width];
}

/// Bars a day of [values] (already in the unit shown) from zero, a week's
/// or a month's average a bar over a longer range ([barSpans]), with the
/// [goal] dashed across; given a [negativeColor], bars stand on a zero
/// line and negative ones hang below it.
class DailyBarChart extends StatelessWidget {
  final DaySeries values;
  final List<DateTime> dates;
  final Color color;
  final Color? negativeColor;
  final double? goal;
  final String unit;

  /// What the legend calls the [goal] line: "Limit" for a limit.
  final String goalLabel;

  /// A bar's figure as its tooltip shows it; whole numbers when null.
  final String Function(double value)? format;
  final String label;

  /// A tap on a day's bar; [selected] is the day picked, the others dimmed.
  /// A bar of several days is not a day: it takes no tap, and dims as one
  /// with the day picked in it.
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
    this.goalLabel = 'Goal',
    this.format,
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
    final spans = barSpans(dates);
    final many = spans.length < values.length;
    final bars = many ? spanMeans(values, spans) : values;
    // From zero, so a day's bar is as long as its figure: half the bar,
    // half the amount.
    final range = fittedRange([
      ...bars.nonNulls,
      if (goal != null && goal! > 0) goal!,
      0,
    ]);
    final shown = bars.whereType<double>();
    final axis = valueAxis(
      context,
      range.min,
      range.max,
      bothSides: shown.any((v) => v < 0) && shown.any((v) => v > 0),
    );
    final goals = goalLine(context, goal).horizontalLines;
    final dayLabel = dayLabels(context, dates);
    final spanLabel = spanLabels(context, dates);
    final palette = paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    String spoken(int i) => switch (values[i]) {
      null => '${dayLabel(i)}, nothing logged',
      final v => '${dayLabel(i)}, ${format?.call(v) ?? v.round()} $unit',
    };
    int target(int step) => stepDay(selected, step, values.length);
    void move(int step) {
      if (target(step) != selected) onTap!(target(step));
    }

    final picked = selected == null ? null : spoken(selected!);
    final pickedBar = selected == null
        ? null
        : spans.indexWhere((s) => s.start <= selected! && selected! < s.end);
    final chart = Semantics(
      container: true,
      label: label,
      value: picked,
      increasedValue: picked == null ? null : spoken(target(1)),
      decreasedValue: picked == null ? null : spoken(target(-1)),
      onIncrease: onTap == null ? null : () => move(1),
      onDecrease: onTap == null ? null : () => move(-1),
      hint: onTap == null ? null : 'Swipe up or down to change the day',
      // One node: the axis' weekdays are not read after its name.
      excludeSemantics: true,
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(
          builder: (context, box) => BarChart(
            // A new range is drawn afresh, not morphed from the old bars.
            key: ValueKey((dates.firstOrNull, dates.length)),
            duration: motionDuration(
              context,
              const Duration(milliseconds: 150),
            ),
            BarChartData(
              minY: axis.min,
              maxY: axis.max,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: weekdayTitles(
                context,
                [for (final s in spans) dates[s.start]],
                right: axis.titles,
                perBar: daysPerBar(dates.length),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (negativeColor != null)
                    HorizontalLine(
                      y: 0,
                      color: palette.textMuted,
                      strokeWidth: 1,
                    ),
                  ...goals,
                ],
              ),
              barTouchData: BarTouchData(
                touchCallback: onTap == null || many
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
                    barTooltip(
                      '${format?.call(rod.toY) ?? rod.toY.round()}',
                      unit,
                      spanLabel(spans[group.x]),
                      many: many,
                    ),
                    TextStyle(color: scheme.onInverseSurface),
                  ),
                ),
              ),
              barGroups: [
                for (final (i, v) in bars.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        fromY: 0,
                        toY: v ?? 0,
                        width: barWidth(box.maxWidth - axis.width, bars.length),
                        color: ((v ?? 0) < 0 ? negativeColor ?? color : color)
                            .withValues(
                              alpha: pickedBar == null || pickedBar == i
                                  ? 1
                                  : 0.35,
                            ),
                        borderRadius: BorderRadius.circular(
                          bars.length <= 31 ? 3 : 0,
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
    if (goals.isEmpty) return chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chart,
        const SizedBox(height: Dimens.spacing8),
        ChartLegend(
          entries: [(label: goalLabel, color: palette.textMuted, line: true)],
        ),
      ],
    );
  }
}

/// The day [step] days from [selected] of [count], picked without touch:
/// up from none is the first, down the last; at either end the day stays.
int stepDay(int? selected, int step, int count) =>
    ((selected ?? (step > 0 ? -1 : count)) + step).clamp(0, count - 1);

/// Whether [count] days across [width] leave each too narrow to tap.
bool narrowDaySlots(double width, int count) => width / count < 8;

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
