import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Diary's day at a glance (seam S118, MacroFactor's diary header):
/// how many meals and foods, then the energy and each macro against its
/// goal, side by side, each with a bar that turns red past the goal.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final meals = {for (final i in intakes) i.type}.length;
    final kcal = _sum((i) => i.totalKcal).clamp(0.0, double.infinity);
    final unit = energyUnit(context);
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Total(
                  value: energyValue(context, kcal),
                  goal: energyValue(context, trackedDay.calorieGoal),
                  label: unit,
                  color: palette.accent,
                ),
                _Total(
                  value: _sum((i) => i.totalCarbsGram).round(),
                  goal: (trackedDay.carbsGoal ?? 0).round(),
                  label: 'carbs g',
                  color: palette.carbsColor,
                ),
                _Total(
                  value: _sum((i) => i.totalFatsGram).round(),
                  goal: (trackedDay.fatGoal ?? 0).round(),
                  label: 'fat g',
                  color: palette.fatColor,
                ),
                _Total(
                  value: _sum((i) => i.totalProteinsGram).round(),
                  goal: (trackedDay.proteinGoal ?? 0).round(),
                  label: 'protein g',
                  color: palette.proteinColor,
                ),
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
  final String label;
  final Color color;

  const _Total({
    required this.value,
    required this.goal,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final over = goal > 0 && value > goal;
    final error = Theme.of(context).colorScheme.error;
    return Expanded(
      child: Semantics(
        label: '$value of $goal $label${over ? ', over' : ''}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$value',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: over ? error : palette.textStrong,
                      ),
                    ),
                    if (goal > 0) TextSpan(text: ' / $goal'),
                  ],
                ),
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Dimens.spacing4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0,
                  minHeight: 5,
                  color: over ? error : color,
                  backgroundColor: palette.surfaceMuted,
                ),
              ),
              const SizedBox(height: Dimens.spacing4),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
