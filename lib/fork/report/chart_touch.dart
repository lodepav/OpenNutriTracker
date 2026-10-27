import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A touch on a Trends chart: a larger dot on the touched point rather than
/// fl_chart's line down to the axis, and a tooltip line a series that says
/// which series it is ([label]), its number rounded. [after] follows the
/// label in the same line, as its own span (a unit and a date after a bare
/// number, which upstream's tests read as the item's text). A touch
/// anywhere over the chart takes the nearest day: within fl_chart's 10 px
/// of a point, a tap between days far apart found nothing.
LineTouchData labelledTouch(
  BuildContext context,
  String Function(LineBarSpot spot) label, {
  String Function(LineBarSpot spot)? after,
}) {
  final scheme = Theme.of(context).colorScheme;
  final style = (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
      .copyWith(color: scheme.onInverseSurface);
  return LineTouchData(
    touchSpotThreshold: double.infinity,
    getTouchedSpotIndicator: (bar, indexes) => [
      for (final _ in indexes)
        TouchedSpotIndicatorData(
          const FlLine(color: Colors.transparent, strokeWidth: 0),
          FlDotData(
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 5,
              color: bar.color ?? scheme.primary,
              strokeWidth: 2,
              strokeColor: scheme.surface,
            ),
          ),
        ),
    ],
    touchTooltipData: LineTouchTooltipData(
      getTooltipColor: (_) => scheme.inverseSurface,
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      getTooltipItems: (spots) => [
        for (final s in spots)
          LineTooltipItem(
            label(s),
            style,
            children: [
              if (after != null) TextSpan(text: after(s), style: style),
            ],
          ),
      ],
    ),
  );
}
