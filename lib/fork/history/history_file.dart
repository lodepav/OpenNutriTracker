import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

/// An entry an import wrote as a day's or a meal's totals, never a food to
/// offer again among the recents, nor a copy of one. A food an import
/// wrote food by food is a real food and is offered.
bool isImportedHistory(IntakeEntity intake) => switch (intake.meal.code) {
  final code? =>
    code.startsWith(historyCodePrefix) &&
        !code.startsWith('${historyCodePrefix}food') &&
        !code.startsWith('${historyCodePrefix}custom:') &&
        !code.startsWith('${historyCodePrefix}recipe:'),
  null => false,
};

/// Any entry an import wrote, totals or food: another app logged it, so it
/// is not written to the health store again. Told by the entry's id, which
/// an import makes and an edit or a move keeps; its food is the food's own,
/// as one logged here is.
bool wasImported(IntakeEntity intake) =>
    intake.id.startsWith(historyCodePrefix);

const historyCodePrefix = 'history-';
const historyFoodCodePrefix = 'history-food-';

/// One food of a food-by-food log (MacroFactor's): when it was eaten, what,
/// how much, and what it held.
class FoodRow {
  /// The file's date, and the minutes after its midnight (null with no
  /// time column, or an empty one). No date for a custom food.
  final DateTime? day;
  final int? minute;
  final String name;

  /// From a meal column; null where the file has none, and the time picks.
  final IntakeTypeEntity? meal;

  /// Grams eaten, null where the file does not say.
  final double? grams;
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;

  /// The amounts eaten of the other nutrients, by [nutrientColumns] key.
  final Map<String, double> nutrients;

  const FoodRow({
    this.day,
    this.minute,
    required this.name,
    this.meal,
    this.grams,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.nutrients = const {},
  });
}

/// The nutrients a food log's columns may hold beyond energy and macros,
/// by header start, in the units the app keeps them in (g, mg, µg as the
/// headers MacroFactor and Cronometer write say).
const nutrientColumns = <String, List<String>>{
  'fiber': ['fiber', 'fibre'],
  'sugars': ['sugars', 'sugar'],
  'saturatedFat': ['saturated fat', 'saturated'],
  'monounsaturatedFat': ['monounsaturated'],
  'polyunsaturatedFat': ['polyunsaturated'],
  'transFat': ['trans fat'],
  'cholesterol': ['cholesterol'],
  'sodium': ['sodium'],
  'potassium': ['potassium'],
  'magnesium': ['magnesium'],
  'calcium': ['calcium'],
  'iron': ['iron'],
  'zinc': ['zinc'],
  'phosphorus': ['phosphorus'],
  'vitaminA': ['vitamin a'],
  'vitaminC': ['vitamin c'],
  'vitaminD': ['vitamin d'],
  'vitaminB6': ['b6', 'vitamin b6'],
  'vitaminB12': ['b12', 'vitamin b12'],
  'niacin': ['b3', 'niacin', 'vitamin b3'],
};

/// What was eaten in a meal of a day, or the whole day where the file has
/// no meals.
class FoodTotals {
  double kcal = 0;
  double? protein;
  double? carbs;
  double? fat;

  void add(double kcal, double? protein, double? carbs, double? fat) {
    this.kcal += kcal;
    if (protein != null) this.protein = (this.protein ?? 0) + protein;
    if (carbs != null) this.carbs = (this.carbs ?? 0) + carbs;
    if (fat != null) this.fat = (this.fat ?? 0) + fat;
  }
}

/// A recipe of the user's (MacroFactor's "Recipes"): the whole of it as
/// one food, its grams the total weight (null where the file gives none).
class HistoryRecipe {
  final FoodRow food;
  final int? servings;

  /// The description, the ingredients and the steps, as the file has them.
  final String notes;

  const HistoryRecipe({required this.food, this.servings, this.notes = ''});
}

/// The history found in an export: food by day (and meal, where the file
/// has meals; null for a day's total) and one weigh-in a day.
class HistoryFile {
  final Map<DateTime, Map<IntakeTypeEntity?, FoodTotals>> food;
  final Map<DateTime, double> weightsKg;

  /// Food by food, where the food table names each food; empty where it
  /// holds only totals. [food] sums the same rows.
  final List<FoodRow> foods;

  /// The weigh-ins an earlier import misread from a food log's serving
  /// weights, by day: each a reading in kg and in lb taken for kg, so the
  /// ones still in the log can be found and removed.
  final Map<DateTime, Set<double>> misreadKg;

  /// A file of day totals: the day's other nutrients, by [nutrientColumns]
  /// key (MacroFactor's "Micronutrients" sheet).
  final Map<DateTime, Map<String, double>> dayNutrients;

  /// Body fat % and body measurements in cm, by day.
  final Map<DateTime, Map<BodyMetric, double>> measurements;

  /// The user's own foods, each as one serving (MacroFactor's "Custom
  /// Foods"), only those the file gives calories for.
  final List<FoodRow> customFoods;

  /// The names of all the user's own foods, lower case, with calories or
  /// not: a food of the log by one of these names is a custom meal.
  final Set<String> customFoodNames;

  /// The user's recipes, only those the file gives calories for.
  final List<HistoryRecipe> recipes;

  /// Days the user marked as logged in part (MacroFactor's "Partial
  /// Logging"), to leave out of the expenditure estimate.
  final Set<DateTime> partialDays;

  /// The goals over (MacroFactor's "Weight Goals"), oldest first; never
  /// the one in progress.
  final List<GoalRecord> goals;

  /// The tables food was read from, in order; none when none had it.
  final List<String> foodTables;

  /// The first of [foodTables]; null when none had food.
  String? get foodTable => foodTables.firstOrNull;

  /// The table weights were read from; null when none had them.
  final String? weightTable;

  /// The unit the weights were read in, and whether a header stated it.
  final BodyWeightUnit weightUnit;
  final bool weightUnitStated;

  const HistoryFile({
    required this.food,
    required this.weightsKg,
    this.foods = const [],
    this.misreadKg = const {},
    this.dayNutrients = const {},
    this.measurements = const {},
    this.customFoods = const [],
    this.customFoodNames = const {},
    this.recipes = const [],
    this.partialDays = const {},
    this.goals = const [],
    this.foodTables = const [],
    this.weightTable,
    required this.weightUnit,
    required this.weightUnitStated,
  });

  bool get isEmpty =>
      food.isEmpty &&
      weightsKg.isEmpty &&
      measurements.isEmpty &&
      customFoods.isEmpty &&
      recipes.isEmpty &&
      partialDays.isEmpty &&
      goals.isEmpty;
}

/// Reads food and weight history from an export's [tables] by their
/// headers, not by any one app's layout: a date column, then calories (or
/// energy, kcal or kJ), protein, carbs and fat, a meal, and a weight. A
/// target, goal, budget or expenditure column is never taken for what was
/// eaten, nor a trend weight for a weigh-in. Food comes from every food
/// log (a table naming each food), each day from the first log holding it,
/// so two exports of overlapping spans are not counted twice; with no food
/// log, from the first table with calories, summed by day and meal. A
/// daily summary beside a food log is never added to it. Weight from the
/// first with a weight, or with Cronometer's metric and amount columns.
/// A weight header that states no unit is read in [unit].
///
/// Checked against the headers MacroFactor, MyFitnessPal and Cronometer
/// are known to write, which none of them documents; the import's preview
/// shows what was found before anything is written.
HistoryFile readHistory(
  List<SheetTable> tables, {
  BodyWeightUnit unit = BodyWeightUnit.kg,
}) {
  final food = <DateTime, Map<IntakeTypeEntity?, FoodTotals>>{};
  final foods = <FoodRow>[];
  final misread = <DateTime, Set<double>>{};
  final dayNutrients = <DateTime, Map<String, double>>{};
  final measurements = <DateTime, Map<BodyMetric, double>>{};
  final customFoods = <FoodRow>[];
  final customFoodNames = <String>{};
  final recipes = <HistoryRecipe>[];
  final partialDays = <DateTime>{};
  final goals = <GoalRecord>[];
  final weights = <DateTime, double>{};
  final foodTables = <String>[];
  String? weightTable;
  var weightUnit = unit;
  var stated = false;
  final hasFoodLog = tables.any((t) {
    final layout = _Layout.find(t.rows);
    return layout?.kcal != null && layout?.name != null;
  });

  for (final table in tables) {
    if (customFoods.isEmpty) customFoods.addAll(_customFoods(table.rows));
    if (customFoodNames.isEmpty) {
      customFoodNames.addAll(_customFoodNames(table.rows));
    }
    if (recipes.isEmpty) recipes.addAll(_recipes(table.rows));
    if (goals.isEmpty) goals.addAll(_goals(table.rows, unit));
    final layout = _Layout.find(table.rows);
    if (layout == null) continue;
    final rows = table.rows.sublist(layout.headerRow + 1);
    final dates = _DateColumn([for (final r in rows) _at(r, layout.date)]);

    final partial = table.rows[layout.headerRow].indexWhere(
      (c) => c.toLowerCase().contains('partial'),
    );
    if (partial >= 0) {
      for (final row in rows) {
        final day = dates.parse(_at(row, layout.date));
        final yes = const ['yes', 'true', '1'];
        if (day != null &&
            yes.contains(_at(row, partial).trim().toLowerCase())) {
          partialDays.add(day);
        }
      }
    }

    final takesFood =
        layout.kcal != null &&
        (hasFoodLog ? layout.name != null : foodTables.isEmpty);
    if (takesFood) {
      // Days an earlier table already gave.
      final earlier = {...food.keys, for (final f in foods) f.day};
      var added = false;
      for (final row in rows) {
        final day = dates.parse(_at(row, layout.date));
        final kcal = _number(_at(row, layout.kcal));
        if (day == null || kcal == null || kcal < 0) continue;
        if (earlier.contains(day)) continue;
        added = true;
        // A food of no calories (water, black coffee) is still a food; a
        // day's total of none is no day.
        if (kcal == 0 && _at(row, layout.name).trim().isEmpty) continue;
        final meal = layout.meal == null
            ? null
            : _mealOf(_at(row, layout.meal));
        final protein = _number(_at(row, layout.protein));
        final carbs = _number(_at(row, layout.carbs));
        final fat = _number(_at(row, layout.fat));
        if (kcal > 0) {
          food
              .putIfAbsent(day, () => {})
              .putIfAbsent(meal, FoodTotals.new)
              .add(kcal * layout.kcalFactor, protein, carbs, fat);
        }
        final name = _at(row, layout.name).trim();
        if (layout.name == null || name.isEmpty) continue;
        final serving = _number(_at(row, layout.servingGrams));
        final count = layout.servings == null
            ? 1.0
            : _number(_at(row, layout.servings));
        foods.add(
          FoodRow(
            day: day,
            minute: _minuteOf(_at(row, layout.time)),
            name: name,
            meal: meal,
            grams: serving != null && serving > 0 && count != null && count > 0
                ? serving * count
                : null,
            kcal: kcal * layout.kcalFactor,
            protein: protein,
            carbs: carbs,
            fat: fat,
            nutrients: {
              for (final MapEntry(key: key, value: column)
                  in layout.nutrients.entries)
                if (_number(_at(row, column)) case final v? when v > 0) key: v,
            },
          ),
        );
        // What an earlier import read as the day's weigh-in: the serving
        // weight of the day's last food, taken for kg or lb.
        if (serving != null) {
          final candidates = {
            for (final unit in BodyWeightUnit.values) _kg(serving, unit),
          }.where((kg) => kg >= 20 && kg <= 400).toSet();
          if (candidates.isNotEmpty) misread[day] = candidates;
        }
      }
      if (added) foodTables.add(table.name);
    }

    // A sheet of the day's nutrients beside one of its calories.
    if (dayNutrients.isEmpty &&
        layout.kcal == null &&
        layout.nutrients.length >= 3) {
      for (final row in rows) {
        final day = dates.parse(_at(row, layout.date));
        if (day == null) continue;
        final values = {
          for (final MapEntry(key: key, value: column)
              in layout.nutrients.entries)
            if (_number(_at(row, column)) case final v? when v > 0) key: v,
        };
        if (values.isNotEmpty) dayNutrients[day] = values;
      }
    }

    for (final row in rows) {
      final day = dates.parse(_at(row, layout.date));
      if (day == null) continue;
      for (final MapEntry(key: metric, value: (column, factor))
          in layout.measures.entries) {
        final value = _number(_at(row, column));
        if (value == null || value <= 0) continue;
        if (metric == BodyMetric.bodyFat && value >= 70) continue;
        measurements.putIfAbsent(day, () => {})[metric] ??= value * factor;
      }
    }

    if (weightTable == null && layout.weight != null) {
      final headerUnit = layout.weightUnit;
      for (final row in rows) {
        final day = dates.parse(_at(row, layout.date));
        if (day == null) continue;
        if (layout.metric != null &&
            !_isWeight(_at(row, layout.metric).toLowerCase())) {
          continue;
        }
        final value = _number(_at(row, layout.weight));
        final rowUnit =
            _unitIn(_at(row, layout.unit).toLowerCase()) ?? headerUnit;
        if (value == null || value <= 0) continue;
        final kg = _kg(value, rowUnit ?? unit);
        // Outside what a person weighs: a misread column, not a weigh-in.
        if (kg < 20 || kg > 400) continue;
        weights[day] = kg;
        if (rowUnit != null) {
          weightUnit = rowUnit;
          stated = true;
        }
      }
      if (weights.isNotEmpty) weightTable = table.name;
    }
  }
  return HistoryFile(
    food: food,
    weightsKg: weights,
    foods: foods,
    misreadKg: misread,
    dayNutrients: dayNutrients,
    measurements: measurements,
    customFoods: customFoods,
    customFoodNames: customFoodNames,
    recipes: recipes,
    partialDays: partialDays,
    goals: goals,
    foodTables: foodTables,
    weightTable: weightTable,
    weightUnit: stated ? weightUnit : unit,
    weightUnitStated: stated,
  );
}

double _kg(double value, BodyWeightUnit unit) =>
    unit == BodyWeightUnit.kg ? value : UnitCalc.lbsToKg(value);

String _at(List<String> row, int? i) =>
    i == null || i >= row.length ? '' : row[i];

/// "08:00", "8:05 PM" or "20:05:00" as minutes after midnight.
int? _minuteOf(String raw) {
  final m = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]\.?m\.?)?$',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final half = m.group(3)?.toLowerCase();
  if (half != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (half.startsWith('p') ? 12 : 0);
  }
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Where a table keeps what the import reads: its header row and columns.
class _Layout {
  final int headerRow;
  final int date;
  final int? kcal;
  final double kcalFactor;
  final int? protein;
  final int? carbs;
  final int? fat;
  final int? meal;
  final int? weight;
  final BodyWeightUnit? weightUnit;

  /// A food log's: the food's name, the time it was eaten, the grams of a
  /// serving and the servings eaten, and the other nutrients by
  /// [nutrientColumns] key.
  final int? name;
  final int? time;
  final int? servingGrams;
  final int? servings;
  final Map<String, int> nutrients;

  /// Body fat % and body measurements: the column, and the factor to cm.
  final Map<BodyMetric, (int, double)> measures;

  /// Cronometer's biometrics: one row per reading, its metric and unit in
  /// columns of their own.
  final int? metric;
  final int? unit;

  const _Layout({
    required this.headerRow,
    required this.date,
    this.kcal,
    this.kcalFactor = 1,
    this.protein,
    this.carbs,
    this.fat,
    this.meal,
    this.weight,
    this.weightUnit,
    this.name,
    this.time,
    this.servingGrams,
    this.servings,
    this.nutrients = const {},
    this.measures = const {},
    this.metric,
    this.unit,
  });

  /// The first of the top rows that names a date column.
  static _Layout? find(List<List<String>> rows) {
    for (var r = 0; r < rows.length && r < 10; r++) {
      final h = [for (final c in rows[r]) c.toLowerCase().trim()];
      final date = h.indexWhere(
        (c) => c == 'date' || c == 'day' || c.startsWith('date '),
      );
      if (date < 0) continue;
      int? first(bool Function(String) test) {
        final i = h.indexWhere(test);
        return i < 0 ? null : i;
      }

      final kcal = first(
        (c) =>
            _any(c, ['calorie', 'energy', 'kcal', 'kj']) && !_any(c, _notEaten),
      );
      final metric = first((c) => c == 'metric');
      final amount = first((c) => c == 'amount');
      final weight = metric != null && amount != null
          ? amount
          : first((c) => _isWeight(c));
      return _Layout(
        headerRow: r,
        date: date,
        kcal: kcal,
        kcalFactor:
            kcal != null && h[kcal].contains('kj') && !h[kcal].contains('kcal')
            ? 1 / 4.184
            : 1,
        protein: first((c) => c.contains('protein') && !_any(c, _notEaten)),
        carbs:
            first(
              (c) =>
                  c.contains('carb') &&
                  !c.contains('net') &&
                  !_any(c, _notEaten),
            ) ??
            first((c) => c.contains('carb') && !_any(c, _notEaten)),
        fat: first(
          (c) =>
              (c == 'fat' ||
                  c.startsWith('fat ') ||
                  c.startsWith('fat(') ||
                  c.contains('total fat')) &&
              !_any(c, ['saturated', 'trans', 'mono', 'poly', ..._notEaten]),
        ),
        meal: first((c) => c == 'meal' || c == 'meal type' || c == 'group'),
        name: first(
          (c) =>
              c == 'food name' ||
              c == 'food' ||
              c == 'name' ||
              c == 'food item' ||
              c == 'description',
        ),
        time: first((c) => c == 'time'),
        servingGrams: first(
          (c) =>
              c.contains('serving weight') ||
              c == 'weight (g)' ||
              c == 'grams' ||
              c == 'amount (g)',
        ),
        servings: first(
          (c) => c == 'serving qty' || c == 'servings' || c == 'quantity',
        ),
        nutrients: {
          for (final MapEntry(key: key, value: starts)
              in nutrientColumns.entries)
            key: ?first(
              (c) => starts.any((s) => _names(c, s)) && !c.contains('added'),
            ),
        },
        measures: _measures(h),
        weight: weight,
        weightUnit: weight == null || metric != null
            ? null
            : _unitIn(h[weight]),
        metric: metric != null && amount != null ? metric : null,
        unit: metric != null && amount != null
            ? first((c) => c == 'unit')
            : null,
      );
    }
    return null;
  }
}

/// Body fat % and the body measurements among [headers] (MacroFactor's
/// "Scale Weight" fat percent and "Body Metrics"), each with its factor to
/// cm; an arm or thigh with no side is taken as the right one.
Map<BodyMetric, (int, double)> _measures(List<String> headers) {
  final found = <BodyMetric, (int, double)>{};
  void take(BodyMetric metric, bool Function(String) test) {
    if (found.containsKey(metric)) return;
    final i = headers.indexWhere(test);
    if (i < 0) return;
    final h = headers[i];
    final factor = metric == BodyMetric.bodyFat
        ? 1.0
        : RegExp(r'\b(in|inch|inches)\b').hasMatch(h)
        ? 2.54
        : 1.0;
    found[metric] = (i, factor);
  }

  take(
    BodyMetric.bodyFat,
    (c) =>
        c == 'fat percent' ||
        c.startsWith('body fat') ||
        c == 'fat %' ||
        c == 'fat mass (%)',
  );
  for (final (metric, word) in [
    (BodyMetric.waist, 'waist'),
    (BodyMetric.hips, 'hips'),
    (BodyMetric.chest, 'chest'),
    (BodyMetric.neck, 'neck'),
  ]) {
    take(metric, (c) => _names(c, word));
  }
  for (final (metric, words) in [
    (BodyMetric.leftArm, ['left bicep', 'left arm']),
    (BodyMetric.rightArm, ['right bicep', 'right arm', 'bicep', 'arm']),
    (BodyMetric.leftThigh, ['left thigh']),
    (BodyMetric.rightThigh, ['right thigh', 'thigh']),
  ]) {
    for (final word in words) {
      take(metric, (c) => _names(c, word));
    }
  }
  return found;
}

/// What one row of a sheet of foods with headers [h] holds, as a food of
/// [name] and [grams]: its calories, macros and nutrients. Null when the
/// headers name no calories, or a row gives none.
FoodRow? Function(List<String> row, String name, double? grams)? _foodColumns(
  List<String> h,
) {
  final kcal = _col(
    h,
    (c) => _names(c, 'calories') || c == 'kcal' || c.startsWith('energy'),
  );
  if (kcal == null) return null;
  final protein = _col(h, (c) => _names(c, 'protein'));
  final carbs = _col(
    h,
    (c) => _names(c, 'carbs') || _names(c, 'carbohydrates'),
  );
  final fat = _col(h, (c) => _names(c, 'fat'));
  final nutrients = {
    for (final MapEntry(key: key, value: starts) in nutrientColumns.entries)
      key: ?_col(
        h,
        (c) => starts.any((s) => _names(c, s)) && !c.contains('added'),
      ),
  };
  return (row, name, grams) => switch (_number(_at(row, kcal))) {
    final k? when k >= 0 => FoodRow(
      name: name,
      grams: grams,
      kcal: k,
      protein: _number(_at(row, protein)),
      carbs: _number(_at(row, carbs)),
      fat: _number(_at(row, fat)),
      nutrients: {
        for (final MapEntry(key: key, value: column) in nutrients.entries)
          if (_number(_at(row, column)) case final v? when v > 0) key: v,
      },
    ),
    _ => null,
  };
}

/// The index of the first of headers [h] to pass [test]; null for none.
int? _col(List<String> h, bool Function(String) test) {
  final i = h.indexWhere(test);
  return i < 0 ? null : i;
}

/// The headers of a sheet with no date column, lower case; null for one
/// with a date column, which is a log.
List<String>? _undatedHeaders(List<List<String>> rows) {
  if (rows.isEmpty) return null;
  final h = [for (final c in rows.first) c.toLowerCase().trim()];
  return h.any((c) => c == 'date' || c == 'day' || c.startsWith('date '))
      ? null
      : h;
}

/// The custom foods of a sheet that names foods and their calories but no
/// date: one serving each, with its grams where the sheet gives them.
List<FoodRow> _customFoods(List<List<String>> rows) {
  final h = _undatedHeaders(rows);
  if (h == null) return const [];
  final name = h.indexWhere((c) => c == 'food name' || c == 'food');
  final food = _foodColumns(h);
  if (name < 0 || food == null) return const [];
  final grams = _col(h, (c) => c.contains('serving weight'));
  final servings = _col(h, (c) => c == 'serving qty');
  return [
    for (final row in rows.skip(1))
      if (_at(row, name).trim() case final n when n.isNotEmpty)
        ?food(row, n, switch ((
          _number(_at(row, grams)),
          servings == null ? 1.0 : _number(_at(row, servings)),
        )) {
          (final g?, final q?) when g > 0 && q > 0 => g * q,
          _ => null,
        }),
  ];
}

/// The names of a sheet of custom foods, lower case, calories or not.
Set<String> _customFoodNames(List<List<String>> rows) {
  final h = _undatedHeaders(rows);
  if (h == null) return const {};
  final name = h.indexWhere((c) => c == 'food name' || c == 'food');
  if (name < 0 || _foodColumns(h) == null) return const {};
  return {
    for (final row in rows.skip(1))
      if (_at(row, name).trim() case final n when n.isNotEmpty) n.toLowerCase(),
  };
}

/// The recipes of a sheet that names recipes and their calories: the whole
/// recipe as one food, its servings, and its text.
List<HistoryRecipe> _recipes(List<List<String>> rows) {
  final h = _undatedHeaders(rows);
  if (h == null) return const [];
  final name = h.indexWhere((c) => c == 'recipe name' || c == 'recipe');
  final food = _foodColumns(h);
  if (name < 0 || food == null) return const [];
  final grams = _col(h, (c) => c.startsWith('total weight'));
  final servings = _col(h, (c) => c == 'serving qty' || c == 'servings');
  final description = _col(h, (c) => c == 'description');
  final ingredients = _col(h, (c) => c == 'ingredients');
  final steps = [
    for (var i = 0; i < h.length; i++)
      if (RegExp(r'^step \d+$').hasMatch(h[i])) i,
  ];
  return [
    for (final row in rows.skip(1))
      if (_at(row, name).trim() case final n when n.isNotEmpty)
        if (food(row, n, switch (_number(_at(row, grams))) {
              final g? when g > 0 => g,
              _ => null,
            })
            case final f?)
          HistoryRecipe(
            food: f,
            servings: switch (_number(_at(row, servings))) {
              final q? when q >= 1 => q.round(),
              _ => null,
            },
            notes: [
              _at(row, description).trim(),
              if (_at(row, ingredients).trim() case final i when i.isNotEmpty)
                'Ingredients:\n$i',
              for (final (k, i) in steps.indexed)
                if (_at(row, i).trim() case final step when step.isNotEmpty)
                  '${k + 1}. $step',
            ].where((t) => t.isNotEmpty).join('\n\n'),
          ),
  ];
}

/// The goals over in a sheet of goals (MacroFactor's "Weight Goals"): its
/// kind, start and end dates, and the scale weights at either end and the
/// goal weight. A weight header that states no unit is read in [unit].
List<GoalRecord> _goals(List<List<String>> rows, BodyWeightUnit unit) {
  final h = _undatedHeaders(rows);
  if (h == null) return const [];
  final goal = _col(h, (c) => c == 'goal' || c == 'goal type');
  final start = _col(h, (c) => c == 'start date');
  final end = _col(h, (c) => c == 'end date');
  if (goal == null || start == null || end == null) return const [];
  final status = _col(h, (c) => c == 'status');
  final startKg = _col(h, (c) => c.startsWith('start') && _isWeight(c));
  final endKg = _col(h, (c) => c.startsWith('end') && _isWeight(c));
  final targetKg = _col(
    h,
    (c) => c.startsWith('goal weight') || c.startsWith('target weight'),
  );
  double? kg(List<String> row, int? column) {
    final value = _number(_at(row, column));
    if (column == null || value == null || value <= 0) return null;
    return _kg(value, _unitIn(h[column]) ?? unit);
  }

  final body = rows.skip(1).toList();
  final dates = _DateColumn([
    for (final r in body) ...[_at(r, start), _at(r, end)],
  ]);
  final goals = [
    for (final row in body)
      if ((
            _kindOf(_at(row, goal)),
            dates.parse(_at(row, start)),
            dates.parse(_at(row, end)),
          )
          case (final kind?, final from?, final to?)
          when !to.isBefore(from) &&
              !_at(row, status).toLowerCase().contains('progress'))
        GoalRecord(
          kind: kind,
          start: from,
          end: to,
          startKg: kg(row, startKg),
          endKg: kg(row, endKg),
          targetKg: kind == PhaseKind.maintain ? null : kg(row, targetKg),
        ),
  ];
  return goals..sort((a, b) => a.start.compareTo(b.start));
}

PhaseKind? _kindOf(String goal) {
  final g = goal.toLowerCase();
  if (_any(g, ['loss', 'lose', 'cut'])) return PhaseKind.cut;
  if (_any(g, ['gain', 'bulk'])) return PhaseKind.bulk;
  if (g.contains('maint')) return PhaseKind.maintain;
  return null;
}

const _notEaten = [
  'target',
  'goal',
  'budget',
  'remaining',
  'burn',
  'expend',
  'exercise',
  'tdee',
  'net calories',
];

bool _any(String text, List<String> words) => words.any(text.contains);

/// Whether [header] starts with the word or words [name]: "iron (mg)" and
/// "b6, pyridoxine (mg)" name iron and b6, "isoleucine (g)" not iron.
bool _names(String header, String name) =>
    header.startsWith(name) &&
    (header.length == name.length ||
        !RegExp('[a-z0-9]').hasMatch(header[name.length]));

bool _isWeight(String header) =>
    (header.contains('weight') || header == 'body mass') &&
    !_any(header, [
      // A food log's serving weight (MacroFactor's "Serving Weight (g)"),
      // which an earlier reading took for a weigh-in.
      'serving',
      'portion',
      'food',
      '(g)',
      'trend',
      'target',
      'goal',
      'lean',
      'change',
      'average',
      'avg',
      'smooth',
    ]);

/// lb or kg where [text] names one; null where it names none.
BodyWeightUnit? _unitIn(String text) {
  if (RegExp(r'\b(lbs?|pounds?)\b').hasMatch(text)) return BodyWeightUnit.lb;
  if (RegExp(r'\b(kg|kilograms?)\b').hasMatch(text)) return BodyWeightUnit.kg;
  return null;
}

IntakeTypeEntity _mealOf(String name) {
  final n = name.toLowerCase();
  if (n.contains('breakfast')) return IntakeTypeEntity.breakfast;
  if (n.contains('lunch')) return IntakeTypeEntity.lunch;
  if (n.contains('dinner') || n.contains('supper')) {
    return IntakeTypeEntity.dinner;
  }
  return IntakeTypeEntity.snack;
}

/// A number as spreadsheets write it: "1,234.5", "1.234,5", "1 234,5",
/// "2,5" or "1,234" (a thousand, not a decimal). Null for anything else.
double? _number(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s ]'), '');
  if (s.isEmpty) return null;
  final comma = s.lastIndexOf(',');
  final dot = s.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    s = comma > dot
        ? s.replaceAll('.', '').replaceAll(',', '.')
        : s.replaceAll(',', '');
  } else if (comma >= 0) {
    s = RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(s)
        ? s.replaceAll(',', '')
        : s.replaceAll(',', '.');
  }
  final value = double.tryParse(s);
  return value != null && value.isFinite ? value : null;
}

final _iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})');
final _short = RegExp(r'^(\d{1,2})([-/.])(\d{1,2})\2(\d{2,4})\b');
final _serial = RegExp(r'^\d{5}(\.\d+)?$');

/// A column of dates: whether its "05/04/2024" is day first is decided once
/// for the whole column, by a day over 12 on either side; a dot or no such
/// day reads them the European way only with dots (MyFitnessPal is US).
class _DateColumn {
  final bool dayFirst;

  _DateColumn(List<String> values) : dayFirst = _dayFirst(values);

  static bool _dayFirst(List<String> values) {
    var dots = false;
    for (final v in values) {
      final m = _short.firstMatch(v.trim());
      if (m == null) continue;
      if (int.parse(m.group(1)!) > 12) return true;
      if (int.parse(m.group(3)!) > 12) return false;
      dots = dots || m.group(2) == '.';
    }
    return dots;
  }

  DateTime? parse(String raw) {
    final s = raw.trim();
    if (_serial.hasMatch(s)) {
      // An Excel day number: days since 30 December 1899.
      final days = double.parse(s).floor();
      if (days < 20000 || days > 80000) return null;
      final d = DateTime.utc(1899, 12, 30).add(Duration(days: days));
      return DateTime(d.year, d.month, d.day);
    }
    if (_iso.firstMatch(s) case final m?) {
      return _date(m.group(1)!, m.group(2)!, m.group(3)!);
    }
    if (_short.firstMatch(s) case final m?) {
      final year = int.parse(m.group(4)!);
      final y = '${year < 100 ? 2000 + year : year}';
      return dayFirst
          ? _date(y, m.group(3)!, m.group(1)!)
          : _date(y, m.group(1)!, m.group(3)!);
    }
    return null;
  }

  static DateTime? _date(String y, String m, String d) {
    final (year, month, day) = (int.parse(y), int.parse(m), int.parse(d));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.month == month ? date : null;
  }
}
