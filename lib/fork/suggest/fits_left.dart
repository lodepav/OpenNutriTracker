import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_item_card.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// What is left of a day's budget: energy and each macro, in kcal and
/// grams; below zero once over.
typedef DayLeft = ({double kcal, double protein, double carbs, double fat});

/// How far over what's left a food may go and still fit: a rounding's
/// worth, as no one weighs to the calorie.
const fitsSlackKcal = 25.0;

/// How many suggestions are shown.
const fitsLimit = 20;

/// [recents] (upstream's, each a food's latest entry) that fit [left] at
/// the amount last logged, the best fit first: a food scores how much of
/// each macro still left it fills, less how far it goes over any. So with
/// protein left and fat spent, the lean foods lead. None once the energy
/// is spent.
List<IntakeEntity> fitsLeft(List<IntakeEntity> recents, DayLeft left) {
  if (left.kcal <= 0) return const [];
  double score(IntakeEntity food) {
    var score = 0.0;
    for (final (has, wanted) in [
      (food.totalProteinsGram, left.protein),
      (food.totalCarbsGram, left.carbs),
      (food.totalFatsGram, left.fat),
    ]) {
      if (wanted > 0) score += (has < wanted ? has : wanted) / wanted;
      final over = has - (wanted > 0 ? wanted : 0);
      if (has > 0 && over > 0) score -= over / has;
    }
    return score;
  }

  final fits = [
    for (final food in recents)
      if (food.totalKcal > 0 && food.totalKcal <= left.kcal + fitsSlackKcal)
        (food, score(food)),
  ];
  // Stable: equal scores keep the recents' order.
  final ranked = [...fits.indexed]
    ..sort((a, b) {
      final byScore = b.$2.$2.compareTo(a.$2.$2);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [for (final (_, (food, _)) in ranked.take(fitsLimit)) food];
}

/// What is left of [day]: its tracked goals less what is logged, or the
/// profile's goals on a day with nothing logged yet.
Future<DayLeft> dayLeft(DateTime day) async {
  final tracked = await locator<GetTrackedDayUsecase>().getTrackedDay(day);
  final kcalGoal =
      tracked?.calorieGoal ?? await locator<GetKcalGoalUsecase>().getKcalGoal();
  final macros = locator<GetMacroGoalUsecase>();
  return (
    kcal: kcalGoal - (tracked?.caloriesTracked ?? 0),
    protein:
        (tracked?.proteinGoal ?? await macros.getProteinsGoal(kcalGoal)) -
        (tracked?.proteinTracked ?? 0),
    carbs:
        (tracked?.carbsGoal ?? await macros.getCarbsGoal(kcalGoal)) -
        (tracked?.carbsTracked ?? 0),
    fat:
        (tracked?.fatGoal ?? await macros.getFatsGoal(kcalGoal)) -
        (tracked?.fatTracked ?? 0),
  );
}

/// What is left, the recents, and whether foods show in imperial units.
typedef FitsLeftData = ({
  DayLeft left,
  List<IntakeEntity> recents,
  bool imperial,
});

Future<FitsLeftData> _load(DateTime day) async => (
  left: await dayLeft(day),
  recents: await locator<GetIntakeUsecase>().getRecentIntake(),
  imperial:
      (await locator<GetConfigUsecase>().getConfig()).usesImperialFoodUnits,
);

/// Seam S85: "Fits what's left" over the add-meal screen's recents
/// (MacroFactor's suggestions): a chip that swaps [recents] for the foods
/// logged before that fit what is left of [day], each at the amount last
/// logged, which is the amount its page opens at.
class FitsLeftSwitch extends StatefulWidget {
  final DateTime day;
  final AddMealType addMealType;
  final Widget recents;
  final Future<FitsLeftData> Function(DateTime day) load;

  const FitsLeftSwitch({
    super.key,
    required this.day,
    required this.addMealType,
    required this.recents,
    this.load = _load,
  });

  @override
  State<FitsLeftSwitch> createState() => _FitsLeftSwitchState();
}

class _FitsLeftSwitchState extends State<FitsLeftSwitch> {
  /// Kept while the app runs, so a search, or the next meal added, comes
  /// back to it.
  static bool _on = false;
  Future<FitsLeftData>? _data;

  Future<FitsLeftData> get _loaded => _data ??= widget.load(widget.day);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FilterChip(
        key: const ValueKey('add-meal-fits-left'),
        label: const Text("Fits what's left"),
        selected: _on,
        onSelected: (on) => setState(() => _on = on),
      ),
      Expanded(child: _on ? _fits(context) : widget.recents),
    ],
  );

  Widget _fits(BuildContext context) => FutureBuilder<FitsLeftData>(
    future: _loaded,
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      if (snapshot.hasError) {
        return const Center(child: Text("Couldn't read today's totals."));
      }
      final data = snapshot.data;
      if (data == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final left = data.left;
      final foods = fitsLeft(data.recents, left);
      String grams(double g) => '${g < 0 ? 0 : g.round()} g';
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              left.kcal <= 0
                  ? 'Nothing is left of the day\'s energy.'
                  : '${energyText(context, left.kcal)} left: '
                        '${grams(left.protein)} protein, '
                        '${grams(left.carbs)} carbs, ${grams(left.fat)} fat. '
                        'Best fit first, at the amount you logged last.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (left.kcal > 0 && foods.isEmpty)
            const Text('Nothing you logged before fits in that.'),
          for (final food in foods) ...[
            MealItemCard(
              day: widget.day,
              mealEntity: food.meal,
              addMealType: widget.addMealType,
              usesImperialUnits: data.imperial,
            ),
            Text(
              '${_amount(food)}: ${energyText(context, food.totalKcal)}, '
              '${food.totalProteinsGram.round()} g protein',
              key: ValueKey('fits-${food.id}'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      );
    },
  );

  static String _amount(IntakeEntity food) {
    final n = food.amount;
    final text = n == n.roundToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(1);
    return '$text ${food.unit}';
  }
}
