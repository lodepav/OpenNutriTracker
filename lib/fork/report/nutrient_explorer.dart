import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// One nutrient the explorer follows.
class ExplorerNutrient {
  final String label;

  /// 'kcal' for energy, else 'g', 'mg' or 'µg'.
  final String unit;
  final double? Function(MealNutrimentsEntity n) per100;

  /// The day's own goal, when the tracked day keeps one.
  final double? Function(TrackedDayEntity d) dayGoal;

  /// Upstream's diary panel key for its DRI table, with that panel's
  /// default when the table has no row.
  final String? driKey;
  final double? fallbackGoal;

  /// A limit rather than a target: above it is the miss.
  final bool isLimit;

  /// Energy and the macros follow a plan that may be under or over on
  /// purpose, so their bars are not marked as missed.
  bool get marksMiss => fallbackGoal != null;

  const ExplorerNutrient(
    this.label,
    this.unit,
    this.per100,
    this.dayGoal, {
    this.driKey,
    this.fallbackGoal,
    this.isLimit = false,
  });

  /// Upstream's own sum (`NutrientPanelTotals`): amount times per 100 / 100.
  double? of(IntakeEntity intake) {
    final value = per100(intake.meal.nutriments);
    return value == null ? null : intake.amount * value / 100;
  }
}

/// Energy, the macros, and the nutrients of upstream's diary panel.
final explorerNutrients = [
  ExplorerNutrient(
    'Energy',
    'kcal',
    (n) => n.energyKcal100,
    (d) => d.calorieGoal,
  ),
  ExplorerNutrient('Protein', 'g', (n) => n.proteins100, (d) => d.proteinGoal),
  ExplorerNutrient('Carbs', 'g', (n) => n.carbohydrates100, (d) => d.carbsGoal),
  ExplorerNutrient('Fat', 'g', (n) => n.fat100, (d) => d.fatGoal),
  ExplorerNutrient(
    'Fibre',
    'g',
    (n) => n.fiber100,
    (d) => d.fibreGoal,
    driKey: NutrientPanelKeys.fiber,
    fallbackGoal: DailyNutrientPanel.defaultFibreRefG,
  ),
  ExplorerNutrient(
    'Sugar',
    'g',
    (n) => n.sugars100,
    (d) => d.sugarsGoal,
    fallbackGoal: DailyNutrientPanel.defaultSugarRefG,
    isLimit: true,
  ),
  ExplorerNutrient(
    'Saturated fat',
    'g',
    (n) => n.saturatedFat100,
    (d) => d.satFatGoal,
    fallbackGoal: DailyNutrientPanel.defaultSaturatedFatRefG,
    isLimit: true,
  ),
  ExplorerNutrient(
    'Sodium',
    'mg',
    (n) => n.sodium100,
    (d) => d.sodiumGoal,
    driKey: NutrientPanelKeys.sodium,
    fallbackGoal: DailyNutrientPanel.defaultSodiumRefMg,
    isLimit: true,
  ),
  ExplorerNutrient(
    'Potassium',
    'mg',
    (n) => n.potassium100,
    (d) => d.potassiumGoal,
    driKey: NutrientPanelKeys.potassium,
    fallbackGoal: DailyNutrientPanel.defaultPotassiumRefMg,
  ),
  ExplorerNutrient(
    'Calcium',
    'mg',
    (n) => n.calcium100,
    (d) => d.calciumGoal,
    driKey: NutrientPanelKeys.calcium,
    fallbackGoal: DailyNutrientPanel.defaultCalciumRefMg,
  ),
  ExplorerNutrient(
    'Iron',
    'mg',
    (n) => n.iron100,
    (d) => d.ironGoal,
    driKey: NutrientPanelKeys.iron,
    fallbackGoal: 14, // the panel's own figure between 8 and 18
  ),
  ExplorerNutrient(
    'Magnesium',
    'mg',
    (n) => n.magnesium100,
    (d) => d.magnesiumGoal,
    driKey: NutrientPanelKeys.magnesium,
    fallbackGoal: DailyNutrientPanel.defaultMagnesiumRefMg,
  ),
  ExplorerNutrient(
    'Vitamin D',
    'µg',
    (n) => n.vitaminD100,
    (d) => d.vitaminDGoal,
    driKey: NutrientPanelKeys.vitaminD,
    fallbackGoal: DailyNutrientPanel.defaultVitaminDRefUg,
  ),
  ExplorerNutrient(
    'Vitamin B12',
    'µg',
    (n) => n.vitaminB12100,
    (d) => d.vitaminB12Goal,
    driKey: NutrientPanelKeys.vitaminB12,
    fallbackGoal: DailyNutrientPanel.defaultVitaminB12RefUg,
  ),
];

/// A food's part of a nutrient over the range.
typedef FoodShare = ({String name, double amount});

/// A nutrient over a range of days.
class NutrientSummary {
  final ExplorerNutrient nutrient;

  /// The mean a logged day.
  final double perDay;

  /// The mean of the logged days' goals; null when there is none.
  final double? goal;

  /// Every food that supplied it, the most first.
  final List<FoodShare> foods;

  /// Foods logged in the range with no figure for it, so [perDay] is a
  /// floor (Open Food Facts often lacks the micronutrients).
  final int foodsWithout;

  const NutrientSummary({
    required this.nutrient,
    required this.perDay,
    required this.goal,
    required this.foods,
    required this.foodsWithout,
  });
}

String _foodKey(IntakeEntity i) => i.meal.code ?? i.meal.name ?? '';

/// Each of [explorerNutrients] over [intakes]: a mean over the days with
/// something logged (an empty day is not a day of eating nothing), against
/// those days' goals in [days], or the DRI for [user] where a day keeps
/// none.
List<NutrientSummary> summarizeNutrients(
  List<IntakeEntity> intakes,
  List<TrackedDayEntity> days,
  UserEntity? user,
) {
  int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  final logged = {for (final i in intakes) dayKey(i.dateTime)};
  final goalDays = [
    for (final d in days)
      if (logged.contains(dayKey(d.day))) d,
  ];

  NutrientSummary summarize(ExplorerNutrient nutrient) {
    final byFood = <String, ({String name, double amount})>{};
    final without = <String>{};
    for (final intake in intakes) {
      final key = _foodKey(intake);
      final amount = nutrient.of(intake);
      if (amount == null) {
        without.add(key);
        continue;
      }
      final before = byFood[key]?.amount ?? 0;
      byFood[key] = (name: intake.meal.name ?? '?', amount: before + amount);
    }
    without.removeAll(byFood.keys);
    final total = byFood.values.fold<double>(0, (s, f) => s + f.amount);

    double? fallback() => nutrient.fallbackGoal == null
        ? null
        : nutrient.driKey == null
        ? nutrient.fallbackGoal
        : DailyNutrientPanel.defaultReferenceFor(
            nutrient.driKey!,
            user,
            nutrient.fallbackGoal!,
          );
    final goals = [
      for (final d in goalDays) nutrient.dayGoal(d) ?? fallback(),
    ].whereType<double>().toList();
    final goal = goals.isNotEmpty
        ? goals.reduce((a, b) => a + b) / goals.length
        : fallback();

    return NutrientSummary(
      nutrient: nutrient,
      perDay: logged.isEmpty ? 0 : total / logged.length,
      goal: goal,
      foods: byFood.values.toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
      foodsWithout: without.length,
    );
  }

  return [for (final n in explorerNutrients) summarize(n)];
}

/// The intakes from [first] to [last], both whole days.
typedef IntakeLoader =
    Future<List<IntakeEntity>> Function(DateTime first, DateTime last);

Future<List<IntakeEntity>> _intakesBetween(
  DateTime first,
  DateTime last,
) async {
  final from = DateTime(first.year, first.month, first.day);
  final to = DateTime(last.year, last.month, last.day + 1);
  return [
    for (final dbo in await locator<IntakeDataSource>().getAllIntakes())
      if (!dbo.dateTime.isBefore(from) && dbo.dateTime.isBefore(to))
        IntakeEntity.fromIntakeDBO(dbo),
  ];
}

Future<UserEntity?> _user() async {
  try {
    return await locator<GetUserUsecase>().getUserData();
  } catch (_) {
    return null;
  }
}

/// MacroFactor's nutrient explorer, from the weekly report: each nutrient's
/// mean a logged day over the Trends range against its goal; a nutrient
/// opens the foods it came from.
class NutrientExplorerScreen extends StatelessWidget {
  final List<TrackedDayEntity> days;
  final DateTime first;
  final DateTime last;
  final IntakeLoader? load;
  final Future<UserEntity?> Function() user;

  const NutrientExplorerScreen({
    super.key,
    required this.days,
    required this.first,
    required this.last,
    this.load,
    this.user = _user,
  });

  Future<List<NutrientSummary>> _summaries() async => summarizeNutrients(
    await (load ?? _intakesBetween)(first, last),
    days,
    await user(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nutrients')),
    body: FutureBuilder<List<NutrientSummary>>(
      future: _summaries(),
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (all.first.foods.isEmpty) {
          return const Center(child: Text('Nothing logged in this range.'));
        }
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'A day\'s mean over the days logged, against their goals.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final s in all) _NutrientTile(s),
          ],
        );
      },
    ),
  );
}

String _amount(BuildContext context, ExplorerNutrient n, double value) =>
    n.unit == 'kcal'
    ? energyText(context, value)
    : '${value < 10 ? value.toStringAsFixed(1) : value.round()} ${n.unit}';

class _NutrientTile extends StatelessWidget {
  final NutrientSummary summary;

  const _NutrientTile(this.summary);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final n = s.nutrient;
    final goal = s.goal;
    final share = goal == null || goal == 0 ? null : s.perDay / goal;
    final scheme = Theme.of(context).colorScheme;
    final missed =
        n.marksMiss && share != null && (n.isLimit ? share > 1 : share < 0.9);
    return ListTile(
      key: ValueKey('nutrient-${n.label}'),
      title: Text(n.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              '${_amount(context, n, s.perDay)} a day',
              if (goal != null)
                '${n.isLimit ? 'limit' : 'goal'} ${_amount(context, n, goal)}',
            ].join(' · '),
          ),
          if (share != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                color: missed ? scheme.error : scheme.primary,
              ),
            ),
          if (s.foodsWithout > 0)
            Text(
              '${s.foodsWithout} food${s.foodsWithout == 1 ? '' : 's'} '
              'without a figure',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: share == null ? null : Text('${(share * 100).round()}%'),
      onTap: s.foods.isEmpty
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => _FoodsScreen(s)),
            ),
    );
  }
}

class _FoodsScreen extends StatelessWidget {
  final NutrientSummary summary;

  const _FoodsScreen(this.summary);

  @override
  Widget build(BuildContext context) {
    final n = summary.nutrient;
    final total = summary.foods.fold<double>(0, (s, f) => s + f.amount);
    return Scaffold(
      appBar: AppBar(title: Text('${n.label} by food')),
      body: ListView(
        children: [
          for (final f in summary.foods)
            ListTile(
              title: Text(f.name),
              subtitle: Text('${_amount(context, n, f.amount)} in the range'),
              trailing: Text(
                total == 0 ? '' : '${(f.amount / total * 100).round()}%',
              ),
            ),
        ],
      ),
    );
  }
}
