import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';

/// An entry an import wrote: a day's or a meal's totals, never a food to
/// offer again among the recents.
bool isImportedHistory(IntakeEntity intake) =>
    intake.meal.code?.startsWith(historyCodePrefix) ?? false;

const historyCodePrefix = 'history-';

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

/// The history found in an export: food by day (and meal, where the file
/// has meals; null for a day's total) and one weigh-in a day.
class HistoryFile {
  final Map<DateTime, Map<IntakeTypeEntity?, FoodTotals>> food;
  final Map<DateTime, double> weightsKg;

  /// The table each was read from; null when none had it.
  final String? foodTable;
  final String? weightTable;

  /// The unit the weights were read in, and whether a header stated it.
  final BodyWeightUnit weightUnit;
  final bool weightUnitStated;

  const HistoryFile({
    required this.food,
    required this.weightsKg,
    this.foodTable,
    this.weightTable,
    required this.weightUnit,
    required this.weightUnitStated,
  });

  bool get isEmpty => food.isEmpty && weightsKg.isEmpty;
}

/// Reads food and weight history from an export's [tables] by their
/// headers, not by any one app's layout: a date column, then calories (or
/// energy, kcal or kJ), protein, carbs and fat, a meal, and a weight. A
/// target, goal, budget or expenditure column is never taken for what was
/// eaten, nor a trend weight for a weigh-in. Food comes from the first
/// table with calories, summed by day and meal, so a workbook holding both
/// a daily summary and a food log is not counted twice; weight from the
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
  final weights = <DateTime, double>{};
  String? foodTable;
  String? weightTable;
  var weightUnit = unit;
  var stated = false;

  for (final table in tables) {
    final layout = _Layout.find(table.rows);
    if (layout == null) continue;
    final rows = table.rows.sublist(layout.headerRow + 1);
    final dates = _DateColumn([for (final r in rows) _at(r, layout.date)]);

    if (foodTable == null && layout.kcal != null) {
      for (final row in rows) {
        final day = dates.parse(_at(row, layout.date));
        final kcal = _number(_at(row, layout.kcal));
        if (day == null || kcal == null || kcal <= 0) continue;
        final meal = layout.meal == null
            ? null
            : _mealOf(_at(row, layout.meal));
        food
            .putIfAbsent(day, () => {})
            .putIfAbsent(meal, FoodTotals.new)
            .add(
              kcal * layout.kcalFactor,
              _number(_at(row, layout.protein)),
              _number(_at(row, layout.carbs)),
              _number(_at(row, layout.fat)),
            );
      }
      if (food.isNotEmpty) foodTable = table.name;
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
    foodTable: foodTable,
    weightTable: weightTable,
    weightUnit: stated ? weightUnit : unit,
    weightUnitStated: stated,
  );
}

double _kg(double value, BodyWeightUnit unit) =>
    unit == BodyWeightUnit.kg ? value : UnitCalc.lbsToKg(value);

String _at(List<String> row, int? i) =>
    i == null || i >= row.length ? '' : row[i];

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

bool _isWeight(String header) =>
    (header.contains('weight') || header == 'body mass') &&
    !_any(header, [
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
