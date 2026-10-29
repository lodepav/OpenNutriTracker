import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

/// A stretch of days in a goal's colour behind [GoalWeightChart].
typedef GoalBand = ({DateTime start, DateTime end, PhaseKind kind});

DateTime _utc(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// The trend weight from [first] on, a point a day, over [bands] of goal
/// colour, with [targetKg] dashed; [label] says it for a screen reader.
class GoalWeightChart extends StatelessWidget {
  /// The trend, kg, one a day from [first].
  final List<double> trend;
  final DateTime first;
  final List<GoalBand> bands;
  final double? targetKg;
  final BodyWeightUnit unit;
  final String label;
  final double height;

  const GoalWeightChart({
    super.key,
    required this.trend,
    required this.first,
    required this.unit,
    required this.label,
    this.bands = const [],
    this.targetKg,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              trend: [for (final kg in trend) weightIn(unit, kg)],
              first: first,
              bands: [
                for (final b in bands)
                  (b, phaseColor(context, b.kind).withValues(alpha: 0.35)),
              ],
              target: targetKg == null ? null : weightIn(unit, targetKg!),
              line: scheme.onSurface,
              muted: scheme.onSurfaceVariant,
              text: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> trend;
  final DateTime first;
  final List<(GoalBand, Color)> bands;
  final double? target;
  final Color line;
  final Color muted;
  final TextStyle text;

  _ChartPainter({
    required this.trend,
    required this.first,
    required this.bands,
    required this.target,
    required this.line,
    required this.muted,
    required this.text,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trend.length < 2) return;
    const left = 32.0;
    final values = [...trend, ?target];
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    final pad = math.max(0.5, (hi - lo) * 0.1);
    lo -= pad;
    hi += pad;
    final width = size.width - left;
    final days = trend.length - 1;
    double x(int day) => left + width * day / days;
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));
    int dayOf(DateTime d) => _utc(d).difference(_utc(first)).inDays;

    for (final (b, color) in bands) {
      final from = dayOf(b.start).clamp(0, days);
      final to = dayOf(b.end).clamp(0, days);
      if (to <= from) continue;
      canvas.drawRect(
        Rect.fromLTRB(x(from), 0, x(to), size.height),
        Paint()..color = color,
      );
    }

    for (final v in [hi - pad, lo + pad]) {
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(0), style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }

    final t = target;
    if (t != null) {
      final paint = Paint()
        ..color = muted
        ..strokeWidth = 1.2;
      for (var dx = left; dx < size.width; dx += 8) {
        canvas.drawLine(
          Offset(dx, y(t)),
          Offset(math.min(dx + 4, size.width), y(t)),
          paint,
        );
      }
    }

    final path = Path()..moveTo(x(0), y(trend[0]));
    for (var i = 1; i < trend.length; i++) {
      path.lineTo(x(i), y(trend[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.trend != trend || old.bands != bands || old.target != target;
}
