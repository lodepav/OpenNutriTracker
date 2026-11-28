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
    final finer = _finerStep(step);
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

/// A round step down from [step]: 5, 2, 1.
double _finerStep(double step) {
  // The slack keeps log10(1000) from flooring to 2.
  final p = math
      .pow(10, (math.log(step) / math.ln10 + 1e-9).floor())
      .toDouble();
  return switch ((step / p).round()) {
    1 => p / 2,
    2 => p,
    _ => 2 * p,
  };
}

/// [step], or a round step under it, so the axis from [min] to [max] has
/// at least two ticks inside it: a flat week gave a single "87.0".
double atLeastTwoTicks(double min, double max, double step) {
  if (!(max > min) || !(step > 0)) return step;
  // Inside the ends: a chart that leaves its ends unlabelled.
  int count(double s) => (max / s - 1e-9).ceil() - (min / s + 1e-9).floor() - 1;
  while (count(step) < 2) {
    step = _finerStep(step);
  }
  return step;
}

/// The whole-day interval of a date axis from day 0 to day [last], at
/// [dayWidth] a day, whose labels, [room] wide each, neither crowd nor run
/// into the label of [last], which a chart adds at its end: [last] falls
/// on the interval or a full label away from it.
int dateInterval(int last, double dayWidth, double room) {
  if (last <= 0 || !(dayWidth > 0)) return 1;
  final least = math.max(1, (room / dayWidth).ceil());
  for (var step = least; step < last; step++) {
    final rest = last % step;
    if (rest == 0 || rest >= least) return step;
  }
  return last;
}

/// The room a date label needs on an axis: the widest of [labels] at the
/// user's font in [style], and a gap.
double dateLabelRoom(
  BuildContext context,
  TextStyle? style,
  Iterable<String> labels,
) {
  var width = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    width = math.max(width, painter.width);
    painter.dispose();
  }
  return width + 12;
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
