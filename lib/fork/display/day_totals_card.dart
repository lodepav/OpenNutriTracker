import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show keepUnits;
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Diary's day at a glance (seam S118, MacroFactor's diary header):
/// how many meals and foods, then the energy and each macro against its
/// goal, side by side (one a line at a large font), each with a bar.
class DayTotalsCard extends StatelessWidget {
  final List<IntakeEntity> intakes;
  final TrackedDayEntity trackedDay;

  const DayTotalsCard({
    super.key,
    required this.intakes,
    required this.trackedDay,
  });

  double _sum(double Function(IntakeEntity) of) =>
      intakes.fold(0.0, (sum, i) => sum + of(i));

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    final meals = {for (final i in intakes) i.type}.length;
    final kcal = _sum((i) => i.totalKcal).clamp(0.0, double.infinity);
    final totals = [
      _Total(
        value: energyValue(context, kcal),
        goal: energyValue(context, trackedDay.calorieGoal),
        name: 'Energy',
        unit: energyUnit(context),
        color: palette.accent,
      ),
      ...inMacroOrder(
        carbs: _Total(
          value: _sum((i) => i.totalCarbsGram).round(),
          goal: (trackedDay.carbsGoal ?? 0).round(),
          name: 'Carbs',
          unit: 'g',
          color: palette.carbsColor,
        ),
        fat: _Total(
          value: _sum((i) => i.totalFatsGram).round(),
          goal: (trackedDay.fatGoal ?? 0).round(),
          name: 'Fat',
          unit: 'g',
          color: palette.fatColor,
        ),
        protein: _Total(
          value: _sum((i) => i.totalProteinsGram).round(),
          goal: (trackedDay.proteinGoal ?? 0).round(),
          name: 'Protein',
          unit: 'g',
          color: palette.proteinColor,
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing12,
          Dimens.spacing12,
          Dimens.spacing12,
          Dimens.spacing12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$meals ${meals == 1 ? 'meal' : 'meals'} · '
              '${intakes.length} ${intakes.length == 1 ? 'food' : 'foods'}',
              style: textTheme.labelMedium?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Dimens.spacing8),
            // Above 1.5x text, as on Home and Trends, one figure a line.
            if (MediaQuery.textScalerOf(context).scale(10) > 15)
              for (final (i, total) in totals.indexed) ...[
                if (i > 0) const SizedBox(height: Dimens.spacing8),
                total,
              ]
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Energy carries the longest figure; a wider column keeps
                  // it at the macros' size on a 360-412 dp phone.
                  for (final (i, total) in totals.indexed)
                    Expanded(flex: i == 0 ? 5 : 4, child: total),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final int value;
  final int goal;
  final String name;
  final String unit;
  final Color color;

  const _Total({
    required this.value,
    required this.goal,
    required this.name,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: dayTotalLabel(name: name, value: value, goal: goal, unit: unit),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One line, smaller if it must: "12124 / 12960" in kJ broke
            // in two and pushed its bar below the others (JC8).
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                maxLines: 1,
                TextSpan(
                  children: [
                    // A target, not a limit: passing it is not coloured,
                    // as on Home and Trends.
                    TextSpan(
                      text: '$value',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: palette.textStrong,
                      ),
                    ),
                    TextSpan(
                      text: keepUnits(goal > 0 ? ' / $goal $unit' : ' $unit'),
                    ),
                  ],
                ),
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
            const SizedBox(height: Dimens.spacing4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0,
                minHeight: 5,
                color: color,
                backgroundColor: palette.surfaceMuted,
              ),
            ),
            const SizedBox(height: Dimens.spacing4),
            Text(
              name,
              style: textTheme.labelSmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A day's total in words, "Fat 96 of 86 g, 10 g over", or with no goal
/// "Fat 96 g".
String dayTotalLabel({
  required String name,
  required int value,
  required int goal,
  required String unit,
}) {
  if (goal <= 0) return '$name $value $unit';
  final over = value > goal ? ', ${value - goal} $unit over' : '';
  return '$name $value of $goal $unit$over';
}
