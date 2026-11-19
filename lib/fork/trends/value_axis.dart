import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';

/// A round step near [raw]: 1, 2 or 5 times a power of ten.
double niceStep(double raw) {
  if (raw <= 0) return 100;
  final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 5, 10]) {
    if (m * p >= raw) return m * p;
  }
  return 10 * p;
}

/// A value axis for a chart from [min] to [max]: round values at a step
/// of about a third of the range, finer when that labels under 3 but not
/// past 5, so they do not crowd at a large font. With values on [bothSides]
/// of 0, the range is widened to a step on a side that has none, so 0 has
/// a value either side; a side that is only padding is left as it is.
({double min, double max, double step, List<double> ticks}) axisTicks(
  double min,
  double max, {
  bool bothSides = false,
}) {
  if (!(max > min)) {
    return (min: min, max: max, step: niceStep(0), ticks: [min]);
  }
  // A hair of slack, so an end on the step is not lost to rounding.
  List<double> at(double s) => [
    for (var k = (min / s - 1e-9).ceil(); k <= max / s + 1e-9; k++) k * s,
  ];
  var step = niceStep((max - min) / 3);
  var ticks = at(step);
  if (ticks.length < 3) {
    // Down a round step: 5, 2, 1.
    final p = math.pow(10, (math.log(step) / math.ln10).floor()).toDouble();
    final finer = switch ((step / p).round()) {
      1 => p / 2,
      2 => p,
      _ => 2 * p,
    };
    if (at(finer).length <= 5) {
      step = finer;
      ticks = at(step);
    }
  }
  if (bothSides && min < 0 && max > 0) {
    if (ticks.first >= 0) min = -step;
    if (ticks.last <= 0) max = step;
    ticks = at(step);
  }
  return (min: min, max: max, step: step, ticks: ticks);
}

/// [y], a tick of [step], as the axis shows it: as many decimals as the
/// step has, a minus sign as the app's signed figures have, and no "-0".
String axisLabel(double y, double step) {
  final decimals = step >= 1
      ? 0
      : -(math.log(step) / math.ln10).floor().clamp(-20, 0);
  final v = (y / step).round() * step;
  if (v == 0) return '0';
  final text = v.abs().toStringAsFixed(decimals);
  return v < 0 ? '\u2212$text' : text;
}

/// A value axis on the right of a chart from [min] to [max], as
/// Expenditure's: its round values in the muted small style, as wide as
/// its widest number at the user's font. The chart spans the returned
/// [min] to [max], which values on [bothSides] of 0 may widen.
({AxisTitles titles, double width, double min, double max}) valueAxis(
  BuildContext context,
  double min,
  double max, {
  bool bothSides = false,
}) {
  final (:step, :ticks, min: lo, max: hi) = axisTicks(
    min,
    max,
    bothSides: bothSides,
  );
  final small = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: paletteOf(context).textMuted);
  var width = 0.0;
  for (final y in [?ticks.firstOrNull, ?ticks.lastOrNull]) {
    final painter = TextPainter(
      text: TextSpan(text: axisLabel(y, step), style: small),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    width = math.max(width, painter.width);
    painter.dispose();
  }
  bool onStep(double v) => (v / step - (v / step).round()).abs() < 1e-9;
  return (
    titles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: step,
        // fl_chart labels the ends too; only when they are round.
        minIncluded: onStep(lo),
        maxIncluded: onStep(hi),
        reservedSize: width + 8,
        getTitlesWidget: (y, meta) => SideTitleWidget(
          meta: meta,
          child: Text(axisLabel(y, step), style: small),
        ),
      ),
    ),
    width: width + 8,
    min: lo,
    max: hi,
  );
}
