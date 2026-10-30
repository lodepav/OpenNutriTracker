import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/health/weight_import_ui.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';
import 'package:opennutritracker/fork/display/settings_tile.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// What an import writes, and what it keeps of the app's own.
class HistoryPlan {
  /// The new entries by logical day: food by food where the file names its
  /// foods, else one per meal of a day, or one for the day's total.
  final Map<DateTime, List<IntakeEntity>> intakes;
  final List<WeightLogEntity> weights;

  /// What an earlier import wrote on the days [intakes] fills again, to be
  /// deleted first, so importing a food log over its earlier totals
  /// replaces them.
  final Map<DateTime, List<IntakeEntity>> replaced;

  /// Weigh-ins an earlier import misread from serving weights, to delete.
  final List<WeightLogEntity> misread;

  /// Body fat and measurements on days without that one here.
  final Map<DateTime, Map<BodyMetric, double>> measurements;

  /// The file's custom foods whose names are not among the custom meals:
  /// those it gives calories for, and those it names only, as the food log
  /// last had them.
  final List<MealEntity> customFoods;

  /// The file's recipes whose names are not among the recipes here.
  final List<RecipeEntity> recipes;

  /// Days logged in part, to leave out of the expenditure estimate.
  final Set<DateTime> partialDays;

  /// Goals over that overlap none of the goals here.
  final List<GoalRecord> goals;

  /// Days of the file already logged here, and weigh-ins already here:
  /// the app's own are never replaced or added to.
  final int keptDays;
  final int keptWeighIns;

  /// What an earlier import already wrote: days of food (the same file
  /// again, or totals over its foods), days whose measurements are all
  /// here, and custom foods by name. Said, so "nothing new" says why.
  final int keptImportedDays;
  final int keptMeasurementDays;
  final int keptCustomFoods;
  final int keptRecipes;
  final int keptPartialDays;
  final int keptGoals;

  const HistoryPlan({
    required this.intakes,
    required this.weights,
    this.replaced = const {},
    this.misread = const [],
    this.measurements = const {},
    this.customFoods = const [],
    this.recipes = const [],
    this.partialDays = const {},
    this.goals = const [],
    required this.keptDays,
    required this.keptWeighIns,
    this.keptImportedDays = 0,
    this.keptMeasurementDays = 0,
    this.keptCustomFoods = 0,
    this.keptRecipes = 0,
    this.keptPartialDays = 0,
    this.keptGoals = 0,
  });

  /// What is already here, for the dialog: "489 days already imported, …".
  List<String> get kept {
    return [
      if (keptDays > 0) '${_count(keptDays, 'day')} already logged',
      if (keptImportedDays > 0)
        '${_count(keptImportedDays, 'day')} already imported',
      if (keptWeighIns > 0)
        '${_count(keptWeighIns, 'weigh-in')} already entered',
      if (keptMeasurementDays > 0)
        'body measurements on ${_count(keptMeasurementDays, 'day')}',
      if (keptCustomFoods > 0) _count(keptCustomFoods, 'custom food'),
      if (keptRecipes > 0) _count(keptRecipes, 'recipe'),
      if (keptPartialDays > 0)
        '${_count(keptPartialDays, 'day')} already left out of the '
            'expenditure estimate',
      if (keptGoals > 0) _count(keptGoals, 'past goal'),
    ];
  }

  bool get isEmpty =>
      intakes.isEmpty &&
      weights.isEmpty &&
      misread.isEmpty &&
      measurements.isEmpty &&
      customFoods.isEmpty &&
      recipes.isEmpty &&
      partialDays.isEmpty &&
      goals.isEmpty;
}

/// "1 day", "2 days".
String _count(int count, String one) =>
    '$count ${count == 1 ? one : '${one}s'}';

/// A custom meal as entries name it: by its code, or by its name, spelt
/// as here, where it has none.
typedef CustomMealHere = ({String? code, String name});

/// What is here already, as an import sees it.
class HistoryExisting {
  /// Days with an entry or calories of the app's own.
  final Set<DateTime> loggedDays;

  /// Days holding only what an earlier import wrote, with those entries.
  final Map<DateTime, List<IntakeEntity>> importedDays;
  final List<WeightLogEntity> weighIns;
  final List<Measurement> measurements;

  /// The custom meals by name, lower case: a food of the log by one of
  /// these names is logged as that meal, as it would be here.
  final Map<String, CustomMealHere> customMeals;

  /// The recipes' names, lower case, and their ids: an earlier import's
  /// recipe renamed here since is kept.
  final Set<String> recipeNames;
  final Set<String> recipeIds;

  /// Days left out of the expenditure estimate.
  final Set<DateTime> partialDays;

  /// The goals over.
  final List<GoalRecord> goals;

  /// The day start, in minutes after midnight: a food eaten before it
  /// belongs to the day before, as one logged here does.
  final int dayStartMinutes;

  /// The meal shares: a food's time picks a meal the user has on.
  final Map<String, int>? mealSharesPct;

  const HistoryExisting({
    this.loggedDays = const {},
    this.importedDays = const {},
    this.weighIns = const [],
    this.measurements = const [],
    this.customMeals = const {},
    this.recipeNames = const {},
    this.recipeIds = const {},
    this.partialDays = const {},
    this.goals = const [],
    this.dayStartMinutes = 0,
    this.mealSharesPct,
  });
}

/// The plan for [file]: its days not logged here and its weigh-ins on days
/// with none, up to [today]. A food log comes in food by food at its times,
/// each into its meal (or the one its time suggests); a file of totals
/// comes in quick-add style (the totals as per 100 g of a 100 g entry),
/// date-only so any day start keeps them on their day. Ids are made from
/// the day and the row, so a second import of the same file adds nothing,
/// and a day only an import wrote is written again from the newer file.
HistoryPlan planImport(
  HistoryFile file, {
  required HistoryExisting existing,
  required DateTime today,
  required String source,
}) {
  // The custom foods first: the log's foods by their names are logged as
  // them.
  final meals = {...existing.customMeals};
  final here = {for (final m in existing.customMeals.values) m.code};
  final customFoods = <MealEntity>[];
  final kept = <String>{};
  void custom(FoodRow food) {
    final name = food.name.toLowerCase();
    if (meals.containsKey(name)) {
      if (existing.customMeals.containsKey(name)) kept.add(name);
      return;
    }
    final code = '${historyCodePrefix}custom:$name';
    meals[name] = (code: code, name: food.name);
    // An earlier import's, renamed here since: kept as it is.
    if (here.contains(code)) {
      kept.add(name);
      return;
    }
    customFoods.add(_meal(code, food, MealSourceEntity.custom));
  }

  file.customFoods.forEach(custom);
  // Named only: as the log last had it.
  final latest = <String, FoodRow>{};
  for (final f in file.foods) {
    final name = f.name.toLowerCase();
    final was = latest[name];
    if (was == null || _at(f).compareTo(_at(was)) >= 0) latest[name] = f;
  }
  for (final name in file.customFoodNames) {
    if (latest[name] case final food?) custom(food);
  }

  final byDay = file.foods.isNotEmpty
      ? _foodIntakes(file.foods, existing, meals)
      : {
          for (final MapEntry(key: day, value: meals) in file.food.entries)
            day: [
              for (final MapEntry(key: type, value: totals) in meals.entries)
                _intake(
                  day,
                  type,
                  totals,
                  source,
                  // The day's nutrients go on its one entry, not on meals.
                  meals.length == 1 ? file.dayNutrients[day] : null,
                ),
            ],
        };
  final intakes = <DateTime, List<IntakeEntity>>{};
  final replaced = <DateTime, List<IntakeEntity>>{};
  var keptDays = 0;
  var keptImportedDays = 0;
  for (final MapEntry(key: day, value: entries) in byDay.entries) {
    if (day.isAfter(today)) continue;
    if (existing.loggedDays.contains(day)) {
      keptDays++;
      continue;
    }
    final earlier = existing.importedDays[day];
    if (earlier != null) {
      final ids = {for (final i in entries) i.id};
      // Totals never replace foods: a day imported food by food stays.
      if (!earlier.every(isImportedHistory) &&
          entries.every(isImportedHistory)) {
        keptImportedDays++;
        continue;
      }
      // The same file again: nothing to do. An earlier import's foods,
      // each a food of its own, are written again as one food each.
      final foodOf = {for (final i in entries) i.id: i.meal.code};
      if (earlier.length == entries.length &&
          earlier.every(
            (i) => ids.contains(i.id) && foodOf[i.id] == i.meal.code,
          )) {
        keptImportedDays++;
        continue;
      }
      replaced[day] = earlier;
    }
    intakes[day] = entries;
  }

  bool misreadOn(WeightLogEntity w) =>
      file.misreadKg[_date(w.date)]?.any(
        (kg) => (kg - w.weightKg).abs() < 1e-6,
      ) ??
      false;
  final misread = [
    for (final w in existing.weighIns)
      if (misreadOn(w)) w,
  ];
  final weighed = {
    for (final w in existing.weighIns)
      if (!misreadOn(w)) _date(w.date),
  };
  var keptWeighIns = 0;
  final weights = <WeightLogEntity>[];
  for (final MapEntry(key: day, value: kg) in file.weightsKg.entries) {
    if (day.isAfter(today)) continue;
    if (weighed.contains(day)) {
      keptWeighIns++;
      continue;
    }
    weights.add(WeightLogEntity(date: day, weightKg: kg));
  }
  final measured = {
    for (final m in existing.measurements) (_date(m.date), m.metric),
  };
  final measurements = <DateTime, Map<BodyMetric, double>>{};
  var keptMeasurementDays = 0;
  for (final MapEntry(key: day, value: values) in file.measurements.entries) {
    if (day.isAfter(today)) continue;
    final fresh = {
      for (final MapEntry(key: metric, value: value) in values.entries)
        if (!measured.contains((day, metric))) metric: value,
    };
    if (fresh.isNotEmpty) {
      measurements[day] = fresh;
    } else if (values.isNotEmpty) {
      keptMeasurementDays++;
    }
  }
  final recipeNames = {...existing.recipeNames};
  final recipes = [
    for (final recipe in file.recipes)
      if (recipeNames.add(recipe.food.name.toLowerCase()))
        _recipe(recipe, today),
  ]..removeWhere((r) => existing.recipeIds.contains(r.id));
  final partialDays = {
    for (final day in file.partialDays)
      if (!day.isAfter(today) && !existing.partialDays.contains(day)) day,
  };
  final goals = [
    for (final goal in file.goals)
      if (!goal.end.isAfter(today) &&
          !existing.goals.any(
            (g) =>
                g.start == goal.start && g.end == goal.end ||
                g.start.isBefore(goal.end) && goal.start.isBefore(g.end),
          ))
        goal,
  ];
  return HistoryPlan(
    intakes: intakes,
    weights: weights,
    replaced: replaced,
    misread: misread,
    measurements: measurements,
    customFoods: customFoods,
    recipes: recipes,
    partialDays: partialDays,
    goals: goals,
    keptDays: keptDays,
    keptWeighIns: keptWeighIns,
    keptImportedDays: keptImportedDays,
    keptMeasurementDays: keptMeasurementDays,
    keptCustomFoods: kept.length,
    keptRecipes: file.recipes.length - recipes.length,
    keptPartialDays:
        file.partialDays.where((d) => !d.isAfter(today)).length -
        partialDays.length,
    keptGoals:
        file.goals.where((g) => !g.end.isAfter(today)).length - goals.length,
  );
}

DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

/// When [food] was eaten, for ordering: its day, then its minute.
DateTime _at(FoodRow food) =>
    food.day!.add(Duration(minutes: food.minute ?? 0));

/// [foods] as entries by the logical day each was eaten on. A food is one
/// food however often it was logged, as one logged here is: the custom
/// meal by its name in [customMeals], else one code for its name, so the
/// recents, their order and the amounts remembered see it once.
Map<DateTime, List<IntakeEntity>> _foodIntakes(
  List<FoodRow> foods,
  HistoryExisting existing,
  Map<String, CustomMealHere> customMeals,
) {
  final byDay = <DateTime, List<IntakeEntity>>{};
  final rowOfDay = <DateTime, int>{};
  for (final food in foods) {
    final date = food.day!;
    final minute = food.minute;
    // A food with no time stays date-only: its day under any day start.
    final at = minute == null ? date : date.add(Duration(minutes: minute));
    final day = DayBoundaryCalc.dayLabelOf(at, existing.dayStartMinutes);
    final row = rowOfDay[date] = (rowOfDay[date] ?? 0) + 1;
    final id =
        '$historyFoodCodePrefix${DateFormat('yyyy-MM-dd').format(date)}'
        '-$row';
    final name = food.name.toLowerCase();
    final meal =
        food.meal ??
        (minute == null
            ? IntakeTypeEntity.snack
            : MealTypeSuggester.suggestFromTime(
                at,
                mealSharesPct: existing.mealSharesPct,
              ));
    byDay
        .putIfAbsent(day, () => [])
        .add(
          IntakeEntity(
            id: id,
            unit: 'g',
            amount: food.grams ?? 100,
            type: meal,
            meal: switch (customMeals[name]) {
              final here? => _meal(
                here.code,
                food,
                MealSourceEntity.custom,
                name: here.name,
              ),
              null => _meal(
                '${historyCodePrefix}food:$name',
                food,
                MealSourceEntity.unknown,
              ),
            },
            dateTime: at,
          ),
        );
  }
  return byDay;
}

/// [food] as a meal of its grams (or 100 g where the file gives none),
/// the nutrients as per 100 g of it. Only the user's own foods are custom,
/// as here: Settings' custom meals would list every food else. Their merge
/// and edit rewrite the entries logged as them, as they would here.
MealEntity _meal(
  String? code,
  FoodRow food,
  MealSourceEntity source, {
  String? name,
}) {
  final grams = food.grams ?? 100;
  double? per100(double? eaten) => eaten == null ? null : eaten / grams * 100;
  double? n(String key) => per100(food.nutrients[key]);
  return MealEntity(
    code: code,
    name: name ?? food.name,
    url: null,
    mealQuantity: _amount(grams),
    mealUnit: 'g',
    servingQuantity: food.grams,
    servingUnit: 'g',
    servingSize: food.grams == null ? '' : '${_amount(grams)} g',
    nutriments: MealNutrimentsEntity(
      energyKcal100: per100(food.kcal),
      carbohydrates100: per100(food.carbs),
      fat100: per100(food.fat),
      proteins100: per100(food.protein),
      sugars100: n('sugars'),
      saturatedFat100: n('saturatedFat'),
      fiber100: n('fiber'),
      monounsaturatedFat100: n('monounsaturatedFat'),
      polyunsaturatedFat100: n('polyunsaturatedFat'),
      transFat100: n('transFat'),
      cholesterol100: n('cholesterol'),
      sodium100: n('sodium'),
      potassium100: n('potassium'),
      magnesium100: n('magnesium'),
      calcium100: n('calcium'),
      iron100: n('iron'),
      zinc100: n('zinc'),
      phosphorus100: n('phosphorus'),
      vitaminA100: n('vitaminA'),
      vitaminC100: n('vitaminC'),
      vitaminD100: n('vitaminD'),
      vitaminB6100: n('vitaminB6'),
      vitaminB12100: n('vitaminB12'),
      niacin100: n('niacin'),
    ),
    source: source,
  );
}

/// [recipe] as one here: the whole of it one ingredient, the file's
/// totals as they are, at 100 g a serving where it gives no weight.
RecipeEntity _recipe(HistoryRecipe recipe, DateTime today) {
  final f = recipe.food;
  final grams = f.grams ?? 100.0 * (recipe.servings ?? 1);
  final whole = FoodRow(
    name: f.name,
    grams: grams,
    kcal: f.kcal,
    protein: f.protein,
    carbs: f.carbs,
    fat: f.fat,
    nutrients: f.nutrients,
  );
  final name = f.name.toLowerCase();
  final meal = _meal(
    '${historyCodePrefix}recipe:$name',
    whole,
    MealSourceEntity.unknown,
  );
  return RecipeEntity(
    id: '${historyCodePrefix}recipe:$name',
    name: f.name,
    description: [
      recipe.notes,
      if (f.grams == null)
        'The export gave no total weight: taken as 100 g a serving.',
    ].where((t) => t.isNotEmpty).join('\n\n'),
    ingredients: [
      RecipeIngredientEntity(
        snapshotMeal: meal,
        amount: grams,
        unit: 'g',
        convertedAmountG: grams,
      ),
    ],
    totalWeightG: grams,
    aggregatedNutrimentsPer100: meal.nutriments,
    createdAt: today,
    updatedAt: today,
    servingsCount: recipe.servings,
  );
}

String _amount(double grams) =>
    grams == grams.roundToDouble() ? '${grams.round()}' : '$grams';

IntakeEntity _intake(
  DateTime day,
  IntakeTypeEntity? type,
  FoodTotals totals,
  String source, [
  Map<String, double>? nutrients,
]) {
  double? n(String key) => nutrients?[key];
  final key = '${DateFormat('yyyy-MM-dd').format(day)}-${type?.name ?? 'day'}';
  return IntakeEntity(
    id: '$historyCodePrefix$key',
    unit: 'g',
    amount: 100,
    type: type ?? IntakeTypeEntity.snack,
    meal: MealEntity(
      code: '$historyCodePrefix$key',
      name: type == null ? 'Day logged in $source' : 'Logged in $source',
      url: null,
      mealQuantity: '100',
      mealUnit: 'gml',
      servingQuantity: null,
      servingUnit: 'gml',
      servingSize: '',
      nutriments: MealNutrimentsEntity(
        energyKcal100: totals.kcal,
        carbohydrates100: totals.carbs,
        fat100: totals.fat,
        proteins100: totals.protein,
        sugars100: n('sugars'),
        saturatedFat100: n('saturatedFat'),
        fiber100: n('fiber'),
        monounsaturatedFat100: n('monounsaturatedFat'),
        polyunsaturatedFat100: n('polyunsaturatedFat'),
        transFat100: n('transFat'),
        cholesterol100: n('cholesterol'),
        sodium100: n('sodium'),
        potassium100: n('potassium'),
        magnesium100: n('magnesium'),
        calcium100: n('calcium'),
        iron100: n('iron'),
        zinc100: n('zinc'),
        phosphorus100: n('phosphorus'),
        vitaminA100: n('vitaminA'),
        vitaminC100: n('vitaminC'),
        vitaminD100: n('vitaminD'),
        vitaminB6100: n('vitaminB6'),
        vitaminB12100: n('vitaminB12'),
        niacin100: n('niacin'),
      ),
      // Not custom: Settings' custom meals would list every day, and their
      // merge and edit would rewrite the history.
      source: MealSourceEntity.unknown,
    ),
    // Date-only, as an import's entry is: its day under any day start.
    dateTime: DateTime(day.year, day.month, day.day),
  );
}

/// What is here already in the active profile: days with entries or
/// calories of its own, days holding only an import's entries, and the
/// weigh-ins.
Future<HistoryExisting> _existing() async {
  final config = await locator<GetConfigUsecase>().getConfig();
  final offset = config.dayStartOffsetTotalMinutes;
  final recipes = locator<RecipeRepository>().getAllRecipes();
  final own = <DateTime>{};
  final imported = <DateTime, List<IntakeEntity>>{};
  for (final dbo in await locator<IntakeRepository>().getAllIntakesDBO()) {
    final intake = IntakeEntity.fromIntakeDBO(dbo);
    final day = _date(DayBoundaryCalc.dayLabelOf(intake.dateTime, offset));
    if (wasImported(intake)) {
      imported.putIfAbsent(day, () => []).add(intake);
    } else {
      own.add(day);
    }
  }
  imported.removeWhere((day, _) => own.contains(day));
  for (final t
      in await locator<TrackedDayRepository>().getAllTrackedDaysDBO()) {
    final day = _date(t.day);
    if (t.caloriesTracked > 0 && !imported.containsKey(day)) own.add(day);
  }
  return HistoryExisting(
    loggedDays: own,
    importedDays: imported,
    weighIns: await locator<WeightLogRepository>().getAllEntries(),
    measurements: await MeasurementStore().all(),
    customMeals: {
      for (final m in locator<CustomMealDataSource>().getAllCustomMeals())
        if (m.name case final name?)
          name.toLowerCase(): (code: m.code, name: name),
    },
    recipeNames: {for (final r in recipes) r.name.toLowerCase()},
    recipeIds: {for (final r in recipes) r.id},
    partialDays: await AdaptiveStore().skippedDays(),
    goals: [
      ...await PhaseStore().history(),
      // The goal running here: no past goal is laid over its weeks.
      if (await PhaseStore().plan() case final plan?)
        GoalRecord(
          kind: plan.kind,
          start: plan.start,
          end: plan.end,
          startKg: null,
          endKg: null,
        ),
    ],
    dayStartMinutes: offset,
    mealSharesPct: config.mealKcalSharesPct,
  );
}

/// Writes [plan] under the tracked-day lock: each day's entries and their
/// totals as a logged entry adds them, then the weigh-ins. Only into the
/// profile [startedOn] names, which [plan] was made against: false, and
/// nothing written, after a profile switch.
Future<bool> writeHistory(HistoryPlan plan, ProfileStamp startedOn) async {
  final written = await withTrackedDayLockOnProfile(
    startedOn: startedOn,
    () async {
      final writer = CopyEntries.fromLocator();
      final entries = locator<IntakeRepository>();
      final days = locator<TrackedDayRepository>();
      for (final MapEntry(key: day, value: intakes) in plan.intakes.entries) {
        final earlier = plan.replaced[day];
        if (earlier != null) {
          for (final intake in earlier) {
            await entries.deleteIntake(intake);
          }
          // The day held only those: it starts again from nothing.
          await days.reconcileDayTracked(day, 0, 0, 0, 0);
        }
        await writer.restoreIntakes(intakes, day);
      }
      final weights = locator<WeightLogRepository>();
      for (final weight in plan.misread) {
        await weights.deleteEntry(weight.filedDay ?? weight.date);
      }
      for (final weight in plan.weights) {
        await weights.addEntry(weight);
      }
      final store = MeasurementStore();
      for (final MapEntry(key: day, value: values)
          in plan.measurements.entries) {
        await store.addDay(day, values);
      }
      final custom = locator<CustomMealDataSource>();
      for (final meal in plan.customFoods) {
        await custom.saveCustomMeal(MealDBO.fromMealEntity(meal));
      }
      for (final recipe in plan.recipes) {
        await locator<RecipeRepository>().saveRecipe(recipe);
      }
      if (plan.partialDays.isNotEmpty) {
        await AdaptiveStore().mergeSkippedDays(plan.partialDays);
      }
      if (plan.goals.isNotEmpty) await PhaseStore().addToHistory(plan.goals);
      return true;
    },
  );
  if (written == null) return false;
  refreshAfterLogging();
  if (plan.recipes.isNotEmpty && locator.isRegistered<RecipesBloc>()) {
    locator<RecipesBloc>().add(const LoadRecipesEvent());
  }
  if (plan.weights.isNotEmpty || plan.misread.isNotEmpty) {
    refreshAfterWeightImport();
  }
  return true;
}

/// "Import history" in Settings' data section (seam S51): food totals and
/// weigh-ins from another app's export, so the trend and the expenditure
/// estimate start from months of history.
class HistoryImportTile extends StatelessWidget {
  const HistoryImportTile({super.key});

  @override
  Widget build(BuildContext context) => ForkSettingsTile(
    key: const ValueKey('fork-history-import'),
    icon: Icons.history_rounded,
    title: 'Import history',
    subtitle: const Text(
      'From MacroFactor, MyFitnessPal, Cronometer or a spreadsheet; '
      'several files at once',
    ),
    onTap: () => _run(context),
  );

  static int _csvFirst(String name) =>
      name.toLowerCase().endsWith('.csv') ? 0 : 1;

  /// Which files to export and pick, before the picker opens; true to
  /// choose them.
  static Future<bool> confirmPick(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import history'),
          content: const Text(
            'From MacroFactor, export both the food log (CSV, with each '
            "food's time) and the workbook (weigh-ins and measurements), "
            'then pick them together: long-press the first file to choose '
            'several.\n\n'
            'From MyFitnessPal or Cronometer, pick their exported CSV files. '
            'Days already logged here are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('history-import-choose'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose files'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(BuildContext context) async {
    if (!await confirmPick(context) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    // Several files at once: MacroFactor's food log CSV holds each food's
    // time, its workbook the weigh-ins and measurements but only daily
    // totals. CSVs go first, so a food log is read before a summary.
    final picked = [
      for (final f in await FilePicker.pickFiles(type: FileType.any))
        if (f.path != null) f,
    ]..sort((a, b) => _csvFirst(a.name).compareTo(_csvFirst(b.name)));
    if (picked.isEmpty) return;
    final names = picked.map((f) => f.name).join(', ');
    final tables = <SheetTable>[];
    for (final f in picked) {
      try {
        tables.addAll(readTables(f.name, await File(f.path!).readAsBytes()));
      } catch (_) {
        say('Could not read ${f.name}');
        return;
      }
    }
    // What is already here is read from this profile: the plan is written
    // only into it.
    final startedOn = ProfileStamp.now();
    final config = await locator<GetConfigUsecase>().getConfig();
    final existing = await _existing();
    final now = DateTime.now();
    final source = picked.first.name.replaceFirst(RegExp(r'\.[^.]*$'), '');
    HistoryPlan plan(HistoryFile file) => planImport(
      file,
      existing: existing,
      today: DateTime(now.year, now.month, now.day),
      source: source,
    );
    final unit = config.bodyWeightUnit == BodyWeightUnit.kg
        ? BodyWeightUnit.kg
        : BodyWeightUnit.lb;
    final first = readHistory(tables, unit: unit);
    if (first.isEmpty) {
      say('No days with calories or weight found in $names');
      return;
    }
    if (!context.mounted) return;
    final chosen = await showDialog<HistoryPlan>(
      context: context,
      builder: (_) => HistoryImportDialog(
        file: first,
        reread: (unit) => readHistory(tables, unit: unit),
        plan: plan,
      ),
    );
    if (chosen == null) return;
    say('Importing…');
    try {
      if (!await writeHistory(chosen, startedOn)) {
        say('Nothing was imported: the profile changed.');
        return;
      }
      // Zero counts are left out, and each count agrees with its noun.
      String n(int count, String one, String many) =>
          '$count ${count == 1 ? one : many}';
      final parts = [
        if (chosen.intakes.isNotEmpty)
          n(chosen.intakes.length, 'day of food', 'days of food'),
        if (chosen.weights.isNotEmpty)
          n(chosen.weights.length, 'weigh-in', 'weigh-ins'),
        if (chosen.measurements.isNotEmpty)
          n(
            chosen.measurements.length,
            'day of body measurements',
            'days of body measurements',
          ),
        if (chosen.customFoods.isNotEmpty)
          n(chosen.customFoods.length, 'custom food', 'custom foods'),
        if (chosen.recipes.isNotEmpty)
          n(chosen.recipes.length, 'recipe', 'recipes'),
        if (chosen.goals.isNotEmpty)
          n(chosen.goals.length, 'past goal', 'past goals'),
        if (chosen.partialDays.isNotEmpty)
          n(
            chosen.partialDays.length,
            'day left out of expenditure',
            'days left out of expenditure',
          ),
      ];
      say(
        '${parts.isEmpty ? 'Imported nothing new' : 'Imported ${parts.join(', ')}'}'
        '${chosen.misread.isEmpty ? '' : '; removed ${n(chosen.misread.length, 'misread weigh-in', 'misread weigh-ins')}'}.',
      );
    } catch (_) {
      say('The import stopped partway; what was written stays.');
    }
  }
}

/// The preview: what was found where, what is kept, and the weight unit
/// when the file does not say it.
class HistoryImportDialog extends StatefulWidget {
  final HistoryFile file;
  final HistoryFile Function(BodyWeightUnit unit) reread;
  final HistoryPlan Function(HistoryFile file) plan;

  const HistoryImportDialog({
    super.key,
    required this.file,
    required this.reread,
    required this.plan,
  });

  @override
  State<HistoryImportDialog> createState() => _HistoryImportDialogState();
}

class _HistoryImportDialogState extends State<HistoryImportDialog> {
  late var _file = widget.file;
  late var _plan = widget.plan(_file);

  static final _date = DateFormat.yMMMd();

  String _span(Iterable<DateTime> days) {
    final sorted = days.toList()..sort();
    return '${_date.format(sorted.first)} – ${_date.format(sorted.last)}';
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final plan = _plan;
    return AlertDialog(
      title: const Text('Import history'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plan.isEmpty) ...[
              Text(
                plan.keptDays > 0 && plan.keptImportedDays == 0
                    ? 'Nothing to import: the file\'s days are already '
                          'logged here.'
                    : 'Nothing new to import: it is all already here.',
                key: const ValueKey('history-nothing-new'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
            ],
            if (file.food.isEmpty && file.foods.isEmpty)
              const Text('No food found.')
            else
              Text(
                'Food from ${file.foodTables.map((t) => '"$t"').join(' and ')}: '
                '${plan.intakes.isEmpty ? 'no new days' : '${_count(plan.intakes.length, 'day')} to add, ${_span(plan.intakes.keys)}'}.',
                key: const ValueKey('history-food'),
              ),
            const SizedBox(height: 8),
            if (file.weightsKg.isEmpty)
              const Text('No weigh-ins found.')
            else
              Text(
                'Weigh-ins: '
                '${plan.weights.isEmpty ? 'none new' : '${plan.weights.length} to add, ${_span(plan.weights.map((w) => w.date))}'}.',
                key: const ValueKey('history-weights'),
              ),
            if (file.weightsKg.isNotEmpty && !file.weightUnitStated) ...[
              const SizedBox(height: 8),
              const Text('The file does not say the weight unit:'),
              const SizedBox(height: 4),
              SegmentedButton<BodyWeightUnit>(
                key: const ValueKey('history-unit'),
                segments: const [
                  ButtonSegment(value: BodyWeightUnit.kg, label: Text('kg')),
                  ButtonSegment(value: BodyWeightUnit.lb, label: Text('lb')),
                ],
                selected: {file.weightUnit},
                onSelectionChanged: (s) {
                  final file = widget.reread(s.single);
                  setState(() {
                    _file = file;
                    _plan = widget.plan(file);
                  });
                },
              ),
            ],
            if (plan.measurements.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Body measurements: '
                '${_count(plan.measurements.length, 'day')} to add.',
                key: const ValueKey('history-measurements'),
              ),
            ],
            if (plan.customFoods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.customFoods.length, 'custom food')} to add.',
                key: const ValueKey('history-custom-foods'),
              ),
            ],
            if (plan.recipes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.recipes.length, 'recipe')} to add, the '
                'ingredients listed in each.',
                key: const ValueKey('history-recipes'),
              ),
            ],
            if (plan.goals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.goals.length, 'past goal')} to add, '
                '${_span([plan.goals.first.start, plan.goals.last.end])}.',
                key: const ValueKey('history-goals'),
              ),
            ],
            if (plan.partialDays.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.partialDays.length, 'day')} logged in part, '
                'to leave out of the expenditure estimate.',
                key: const ValueKey('history-partial'),
              ),
            ],
            if (plan.replaced.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.replaced.length, 'day')} an earlier import wrote '
                '${plan.replaced.length == 1 ? 'is' : 'are'} written again '
                'from this file.',
                key: const ValueKey('history-replaced'),
              ),
            ],
            if (plan.misread.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.misread.length, 'weigh-in')} an earlier import '
                'read from serving weights ${plan.misread.length == 1 ? 'is' : 'are'} '
                'removed.',
                key: const ValueKey('history-misread'),
              ),
            ],
            if (plan.kept.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Kept as they are here: ${plan.kept.join(', ')}.',
                key: const ValueKey('history-kept'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              file.foods.isNotEmpty
                  ? 'Each food comes in at the time it was eaten, in the '
                        'meal that time suggests.'
                  : 'Each day comes in as its totals (one entry a meal, or '
                        'one for the day), not food by food.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('history-import'),
          onPressed: plan.isEmpty
              ? null
              : () => Navigator.of(context).pop(plan),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
