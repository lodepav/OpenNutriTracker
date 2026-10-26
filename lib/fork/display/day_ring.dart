import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';

/// A day of the Diary's calendar (seam S118, MacroFactor's week strip):
/// its date inside a ring that fills with the energy eaten against the
/// day's goal, in the day's rating colour (upstream's marker dot).
class DayRing extends StatelessWidget {
  final DateTime day;
  final TrackedDayEntity? trackedDay;
  final bool selected;
  final bool today;
  final bool outside;

  const DayRing({
    super.key,
    required this.day,
    required this.trackedDay,
    this.selected = false,
    this.today = false,
    this.outside = false,
  });

  /// How full the ring is: none for a day with nothing tracked.
  static double fill(TrackedDayEntity? trackedDay) {
    if (trackedDay == null || trackedDay.calorieGoal <= 0) return 0;
    return (trackedDay.caloriesTracked / trackedDay.calorieGoal).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: selected || today ? FontWeight.w700 : null,
      color: selected
          ? scheme.onPrimary
          : today
          ? scheme.primary
          : outside
          ? palette.textMuted
          : palette.textStrong,
    );
    return Center(
      child: SizedBox.square(
        dimension: 38,
        child: CustomPaint(
          painter: _RingPainter(
            fill: fill(trackedDay),
            track: palette.surfaceMuted,
            color:
                trackedDay?.getCalendarDayRatingColor(context) ??
                scheme.primary,
            filled: selected ? scheme.primary : null,
          ),
          child: Center(child: Text('${day.day}', style: style)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fill;
  final Color track;
  final Color color;
  final Color? filled;

  _RingPainter({
    required this.fill,
    required this.track,
    required this.color,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    if (filled case final inside?) {
      canvas.drawCircle(
        rect.center,
        ring.width / 2 - stroke,
        Paint()..color = inside,
      );
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(ring, paint..color = track);
    if (fill > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * fill,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill ||
      old.track != track ||
      old.color != color ||
      old.filled != filled;
}
