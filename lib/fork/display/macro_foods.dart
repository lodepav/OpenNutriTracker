import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/home/domain/entity/nutrient_contribution_entity.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/history/food_icon.dart';
import 'package:opennutritracker/fork/off/off_kinds.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// What the foods page breaks down: the energy or one of the macros.
enum FoodsMetric {
  energy,
  carbs,
  fat,
  protein;

  static FoodsMetric of(MacroNutrient nutrient) => switch (nutrient) {
    MacroNutrient.carbs => carbs,
    MacroNutrient.fat => fat,
    MacroNutrient.protein => protein,
  };

  /// In kcal for the energy, grams for a macro.
  double valueIn(IntakeEntity intake) => switch (this) {
    energy => intake.totalKcal,
    carbs => intake.totalCarbsGram,
    fat => intake.totalFatsGram,
    protein => intake.totalProteinsGram,
  };
}

/// What was eaten of a metric against its goal (0: none set).
typedef FoodsTotal = ({double eaten, double goal});

/// One food's share of a metric over the day: every entry of the same food
/// summed, matched by its code, else its name, as upstream's
/// [NutrientContributionEntity.fromIntakes] has it.
class FoodShare {
  final String name;
  final double value;

  /// The food as first logged that day, for its details and its icon.
  final MealEntity meal;
  final IntakeEntity first;
  final List<IntakeTypeEntity> meals;

  const FoodShare({
    required this.name,
    required this.value,
    required this.meal,
    required this.first,
    required this.meals,
  });

  /// [intakes]' shares of [metric], highest first; foods with none of it
  /// are left out.
  static List<FoodShare> of(List<IntakeEntity> intakes, FoodsMetric metric) {
    final byFood = <String, FoodShare>{};
    for (final intake in intakes) {
      final value = metric.valueIn(intake);
      if (value <= 0) continue;
      final key = intake.meal.code ?? intake.meal.name ?? '';
      final previous = byFood[key];
      byFood[key] = FoodShare(
        name: intake.meal.name ?? '',
        value: (previous?.value ?? 0) + value,
        meal: previous?.meal ?? intake.meal,
        first: previous?.first ?? intake,
        meals: [
          ...?previous?.meals,
          if (!(previous?.meals.contains(intake.type) ?? false)) intake.type,
        ],
      );
    }
    return byFood.values.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}

/// Seam S124: the foods behind a total, as MacroFactor's (MacroA): a
/// switch between the energy and the macros, the total against its goal,
/// then each food with its kind, its meal and its share. A food opens its
/// details, as upstream's list did (#1266).
class MacroFoodsPage extends StatefulWidget {
  final FoodsMetric initial;
  final List<IntakeEntity> intakes;

  /// The dashboard's totals, so the two agree; a metric left out is
  /// summed from [intakes], with no goal.
  final Map<FoodsMetric, FoodsTotal> totals;

  final DateTime day;
  final bool usesImperialUnits;

  const MacroFoodsPage({
    super.key,
    required this.initial,
    required this.intakes,
    required this.totals,
    required this.day,
    this.usesImperialUnits = false,
  });

  @override
  State<MacroFoodsPage> createState() => _MacroFoodsPageState();
}

class _MacroFoodsPageState extends State<MacroFoodsPage> {
  late var _metric = widget.initial;

  String _label(BuildContext context, FoodsMetric m) => switch (m) {
    FoodsMetric.energy => energyUnit(context),
    FoodsMetric.carbs => S.of(context).carbsLabel,
    FoodsMetric.fat => S.of(context).fatLabel,
    FoodsMetric.protein => S.of(context).proteinLabel,
  };

  Color _color(AppPalette palette, ColorScheme scheme) => switch (_metric) {
    FoodsMetric.energy => scheme.primary,
    FoodsMetric.carbs => palette.carbs,
    FoodsMetric.fat => palette.fat,
    FoodsMetric.protein => palette.protein,
  };

  String _capitalized(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// [value] in the metric's unit: energy cut as everywhere (S114),
  /// grams rounded, a trace "<1".
  String _amount(BuildContext context, double value) {
    if (_metric == FoodsMetric.energy) {
      final shown = energyValue(context, value);
      return '${shown < 1 ? '<1' : shown} ${energyUnit(context)}';
    }
    return value < 0.5 ? '<1 g' : '${value.round()} g';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final color = _color(palette, scheme);
    final shares = FoodShare.of(widget.intakes, _metric);
    final total =
        widget.totals[_metric] ??
        (eaten: shares.fold(0.0, (s, f) => s + f.value), goal: 0.0);
    final top = shares.isEmpty ? 0.0 : shares.first.value;
    final label = _label(context, _metric);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's foods")),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Dimens.spacing12,
          0,
          Dimens.spacing12,
          Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Semantics(
            identifier: 'foods-metric',
            child: SegmentedButton<FoodsMetric>(
              key: const ValueKey('foods-metric'),
              showSelectedIcon: false,
              segments: [
                for (final m in [
                  FoodsMetric.energy,
                  ...inMacroOrder(
                    carbs: FoodsMetric.carbs,
                    fat: FoodsMetric.fat,
                    protein: FoodsMetric.protein,
                  ),
                ])
                  ButtonSegment(
                    value: m,
                    label: Text(_capitalized(_label(context, m))),
                  ),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.single),
            ),
          ),
          const SizedBox(height: Dimens.spacing12),
          _Summary(
            metric: _metric,
            total: total,
            label: label,
            color: color,
            amount: (v) => _amount(context, v),
          ),
          const SizedBox(height: Dimens.spacing12),
          if (shares.isEmpty)
            EmptyHint(
              icon: Icons.pie_chart_outline_rounded,
              title: S
                  .of(context)
                  .nutrientContributionsEmpty(
                    _metric == FoodsMetric.energy
                        ? 'energy'
                        : label.toLowerCase(),
                  ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
              child: Column(
                children: [
                  for (final (i, share) in shares.indexed) ...[
                    if (i > 0) Divider(height: 1, color: palette.surfaceMuted),
                    _FoodRow(
                      share: share,
                      amount: _amount(context, share.value),
                      percent: total.eaten > 0
                          ? '${(100 * share.value / total.eaten).round()}%'
                          : null,
                      fraction: top > 0 ? share.value / top : 0,
                      color: color,
                      palette: palette,
                      text: text,
                      onTap: () => Navigator.of(context).pushNamed(
                        NavigationOptions.mealDetailRoute,
                        arguments: MealDetailScreenArguments(
                          share.meal,
                          share.meals.first,
                          widget.day,
                          widget.usesImperialUnits,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final FoodsMetric metric;
  final FoodsTotal total;
  final String label;
  final Color color;
  final String Function(double) amount;

  const _Summary({
    required this.metric,
    required this.total,
    required this.label,
    required this.color,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = paletteOf(context);
    final energy = metric == FoodsMetric.energy;
    // Cut as the dashboard tile shows it, so the two agree.
    final eaten = energy
        ? '${energyValue(context, total.eaten)}'
        : '${total.eaten.toInt()}';
    final hasGoal = total.goal > 0;
    final goal = energy
        ? '${energyValue(context, total.goal)} $label'
        : '${total.goal.toInt()} g ${label.toLowerCase()}';
    final of = hasGoal
        ? 'of $goal'
        : (energy ? label : 'g ${label.toLowerCase()}');
    final left = total.goal - total.eaten;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  eaten,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: Dimens.spacing4),
                Expanded(
                  child: Text(
                    of,
                    style: text.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ),
                if (hasGoal)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: amount(left.abs()),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: left < 0 ? ' over' : ' left'),
                      ],
                    ),
                    style: text.bodyMedium?.copyWith(
                      color: left < 0 ? scheme.error : null,
                    ),
                  ),
              ],
            ),
            if (hasGoal) ...[
              const SizedBox(height: Dimens.spacing8),
              _Bar(
                fraction: total.eaten / total.goal,
                color: color,
                track: palette.surfaceMuted,
                height: 8,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  final FoodShare share;
  final String amount;
  final String? percent;
  final double fraction;
  final Color color;
  final AppPalette palette;
  final TextTheme text;
  final VoidCallback onTap;

  const _FoodRow({
    required this.share,
    required this.amount,
    required this.percent,
    required this.fraction,
    required this.color,
    required this.palette,
    required this.text,
    required this.onTap,
  });

  String _meal(BuildContext context, IntakeTypeEntity meal) => switch (meal) {
    IntakeTypeEntity.breakfast => S.of(context).breakfastLabel,
    IntakeTypeEntity.lunch => S.of(context).lunchLabel,
    IntakeTypeEntity.dinner => S.of(context).dinnerLabel,
    IntakeTypeEntity.snack => S.of(context).snackLabel,
  };

  @override
  Widget build(BuildContext context) {
    final brands = share.meal.brands;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing12,
              vertical: Dimens.spacing8,
            ),
            child: Row(
              children: [
                _KindIcon(intake: share.first, palette: palette),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(share.name, style: text.bodyLarge),
                      Text(
                        [
                          share.meals.map((m) => _meal(context, m)).join(', '),
                          if (brands?.isNotEmpty ?? false) brands!,
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing4),
                      _Bar(
                        fraction: fraction,
                        color: color,
                        track: palette.surfaceMuted,
                        height: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dimens.spacing12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (percent != null)
                      Text(
                        percent!,
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
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

/// The food's kind, as its diary row shows it when it has no photo (S117).
class _KindIcon extends StatelessWidget {
  final IntakeEntity intake;
  final AppPalette palette;

  const _KindIcon({required this.intake, required this.palette});

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(9),
    ),
    alignment: Alignment.center,
    child: ExcludeSemantics(
      child: switch (OffKinds.emojiFor(intake.meal)) {
        final emoji? when importedFoodIcon(intake) == null => Text(
          emoji,
          style: const TextStyle(fontSize: 18),
        ),
        _ => Icon(
          importedFoodIcon(intake) ?? Icons.restaurant_rounded,
          color: palette.textMuted,
          size: 18,
        ),
      },
    ),
  );
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color track;
  final double height;

  const _Bar({
    required this.fraction,
    required this.color,
    required this.track,
    required this.height,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: LinearProgressIndicator(
      value: fraction.clamp(0.0, 1.0),
      minHeight: height,
      backgroundColor: track,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );
}
