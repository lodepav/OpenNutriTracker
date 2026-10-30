import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/timeline/timeline.dart';

/// One meal of the Diary's timeline (seam S118): its kind, its foods and
/// its section as the Diary builds it.
typedef TimelineMeal = ({
  IntakeTypeEntity type,
  List<IntakeEntity> intakes,
  Widget section,
});

/// When a meal of [day] sits on the timeline: its first food with a time,
/// or, with none, the hour the meal is usually eaten.
DateTime mealTime(
  DateTime day,
  IntakeTypeEntity type,
  List<IntakeEntity> intakes,
) {
  final timed = [
    for (final i in intakes)
      if (!hasNoTime(i)) i.dateTime,
  ];
  if (timed.isNotEmpty) return timed.reduce((a, b) => a.isBefore(b) ? a : b);
  return usualMealTime(day, type);
}

/// The last hour a meal of [day] takes up on the timeline.
DateTime _mealEnd(DateTime day, TimelineMeal meal) {
  final timed = [
    for (final i in meal.intakes)
      if (!hasNoTime(i)) i.dateTime,
  ];
  return timed.isEmpty
      ? mealTime(day, meal.type, meal.intakes)
      : timed.reduce((a, b) => a.isAfter(b) ? a : b);
}

/// MacroFactor's day as a timeline: the [meals] in the order they were
/// eaten, and between two meals more than an hour apart, the hours with
/// nothing logged.
List<Widget> diaryTimeline(DateTime day, List<TimelineMeal> meals) {
  final timed = [
    for (final (index, meal) in meals.indexed)
      (at: mealTime(day, meal.type, meal.intakes), index: index, meal: meal),
  ];
  // Meals at the same time keep the usual order.
  timed.sort(
    (a, b) => switch (a.at.compareTo(b.at)) {
      0 => a.index.compareTo(b.index),
      final order => order,
    },
  );
  final widgets = <Widget>[];
  DateTime? previousEnd;
  for (final (:at, index: _, :meal) in timed) {
    if (previousEnd != null) {
      final from = DateTime(
        previousEnd.year,
        previousEnd.month,
        previousEnd.day,
        previousEnd.hour + 1,
      );
      final to = DateTime(at.year, at.month, at.day, at.hour - 1);
      if (!to.isBefore(from)) widgets.add(TimelineGap(from: from, to: to));
    }
    widgets.add(meal.section);
    final end = _mealEnd(day, meal);
    if (previousEnd == null || end.isAfter(previousEnd)) previousEnd = end;
  }
  return widgets;
}

/// The hours between two meals with nothing logged in them.
class TimelineGap extends StatelessWidget {
  final DateTime from;
  final DateTime to;

  const TimelineGap({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    // [to] is the last empty hour's start: the range ends an hour later.
    final hours =
        '${clockText(context, from)} – '
        '${clockText(context, to.add(const Duration(hours: 1)))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        0,
      ),
      // The text takes what it needs and wraps at the row's width; the rule
      // takes what is left. A Flexible would split the row with the rule and
      // wrap a text that fits.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth - Dimens.spacing8,
              ),
              child: Text(
                '$hours · nothing logged',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Expanded(child: Divider(color: palette.border, height: 1)),
          ],
        ),
      ),
    );
  }
}
