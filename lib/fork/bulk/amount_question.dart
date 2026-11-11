// The one amount a photo's review asks about: a photo read names foods well
// and sizes them badly, and the food with the most energy is the most-wrong
// one in most reads, so its amount confirmed fixes most of the error.
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/amounts/amount_units.dart';
import 'package:opennutritracker/fork/bulk/meal_scale.dart';
import 'package:opennutritracker/fork/bulk/review_totals.dart';
import 'package:opennutritracker/fork/bulk/review_units.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';

final _g = UnitDropdownItem.g.toString();
final _ml = UnitDropdownItem.ml.toString();
final _gml = UnitDropdownItem.gml.toString();
final _oz = UnitDropdownItem.oz.toString();
final _flOz = UnitDropdownItem.flOz.toString();
final _serving = UnitDropdownItem.serving.toString();

/// One answer chip: what it reads and says, and the amount it sets.
class AmountChoice {
  /// As the chip shows it: "150 g", "2 slices", "½ egg".
  final String label;

  /// As a screen reader says it: "150 grams", "2 slices", "half an egg".
  final String spoken;

  /// The unit and amount text the row takes when it is tapped.
  final String unit;
  final String text;

  /// The model's own amount, chosen from the start.
  final bool estimate;

  const AmountChoice({
    required this.label,
    required this.spoken,
    required this.unit,
    required this.text,
    this.estimate = false,
  });
}

/// The question on one row of a photo's review, held by the row's resolved
/// item as `MealScale` holds rows, so it follows the row when others move.
class AmountQuestion {
  final ResolvedMealItem item;

  /// The match it was asked about: another match is another food.
  final int selectedIndex;

  /// The food as the question names it, "chicken breast".
  final String food;

  /// Whether weights are offered in ounces where the Diary shows them so.
  final bool imperial;

  /// The chips as they were when the user answered, and the one tapped;
  /// null until they answer.
  List<AmountChoice>? _answeredChoices;
  int? _answered;

  AmountQuestion({
    required this.item,
    required this.selectedIndex,
    required this.food,
    required this.imperial,
  });

  bool isFor(BulkAddRow row) => identical(row.resolved, item);

  /// The chip the user tapped; null until they answer.
  int? get answered => _answered;

  /// The chips on [row], its row as it is now: until answered, built
  /// around the amount it shows (the photo's at the size chosen), so the
  /// one chosen is that amount; once answered, the chips it was answered
  /// with, so a mis-tap is corrected among the same.
  List<AmountChoice> choicesFor(BulkAddRow row) =>
      _answeredChoices ?? amountChoices(row, imperial: imperial) ?? const [];

  /// The chip of [choices] shown as chosen: the one tapped, or the amount
  /// the row shows; -1 for none.
  int selectedIn(List<AmountChoice> choices) =>
      _answered ?? choices.indexWhere((c) => c.estimate);

  /// Chip [choice] on [row] tapped: the chips stay as they are now. The
  /// chip, or null when there is no such chip.
  AmountChoice? answer(BulkAddRow row, int choice) {
    final choices = choicesFor(row);
    if (choice < 0 || choice >= choices.length) return null;
    _answeredChoices = choices;
    _answered = choice;
    return choices[choice];
  }

  /// Whether the question still stands among [rows]: its row is there with
  /// the same match. A breakdown or another match ends it for good.
  bool standsIn(List<BulkAddRow> rows) {
    for (final row in rows) {
      if (isFor(row)) return row.selectedIndex == selectedIndex;
    }
    return false;
  }
}

/// The question for a photo's [rows] as they first arrive: on the row with
/// the most energy among those the meal's Size may scale and the user has
/// not set ([pinned]); null when none qualifies or no chips can be built.
AmountQuestion? amountQuestionFor(
  List<BulkAddRow> rows, {
  String? note,
  required bool imperial,
  bool Function(BulkAddRow row)? pinned,
}) {
  BulkAddRow? best;
  var most = 0.0;
  for (final row in rows) {
    if (!isScalableRow(row, note: note)) continue;
    if (pinned?.call(row) ?? false) continue;
    final kcal = rowMacros(row)?.kcal ?? 0;
    if (kcal > most) {
      most = kcal;
      best = row;
    }
  }
  if (best == null) return null;
  if (amountChoices(best, imperial: imperial) == null) return null;
  return AmountQuestion(
    item: best.resolved,
    selectedIndex: best.selectedIndex,
    food: questionFood(best.meal?.name ?? best.resolved.parsed.query),
    imperial: imperial,
  );
}

/// [title] as a question names it: lower case except acronyms and names
/// with capitals inside ("BBQ sauce", "McDonald's"), and a long database
/// name cut at its first comma ("Chicken, broilers or fryers, …" is
/// "chicken").
String questionFood(String title) {
  var name = title.trim();
  final comma = name.indexOf(',');
  if (comma > 0 && name.length > 30) name = name.substring(0, comma).trim();
  return [
    for (final word in name.split(' '))
      word.length > 1 && word.substring(1) != word.substring(1).toLowerCase()
          ? word
          : word.toLowerCase(),
  ].join(' ');
}

/// The unit an imperial profile edits [row]'s weight in, the one its amount
/// is shown in ("oz" for grams); null when the row is shown in its own unit.
String? shownEditUnit(BulkAddRow row, bool imperial) {
  final meal = row.meal;
  if (!imperial || meal == null || !isWeightUnit(row.effectiveUnit)) {
    return null;
  }
  return _imperialWeight(meal, row.allowedUnits, row.effectiveUnit);
}

/// Ounces or fluid ounces where the Diary shows [meal] in them and [unit]
/// is not already that; null otherwise.
String? _imperialWeight(MealEntity meal, List<String> allowed, String unit) {
  final shown = diaryUnit(meal, true).unit;
  if (shown == unit || !allowed.contains(shown)) return null;
  return shown == _oz || shown == _flOz ? shown : null;
}

/// [value] to a number a person would say: to 0.5 in ounces, else to 5
/// below 100, to 10 up to 300, to 25 above.
double friendlyAmount(double value, String unit) {
  if (unit == _oz || unit == _flOz) return (value * 2).roundToDouble() / 2;
  final step = value < 100 ? 5.0 : (value <= 300 ? 10.0 : 25.0);
  return (value / step).roundToDouble() * step;
}

/// Four counts around the model's [n], always holding it: ½, 1, 2, 3 for
/// one; 1-4 for two; n-1 to n+2 above.
List<double> countChoices(double n) {
  final whole = n == n.roundToDouble();
  List<double> counts;
  if (n <= 2) {
    counts = n <= 1 ? [0.5, 1, 2, 3] : [1, 2, 3, 4];
    if (!counts.contains(n)) {
      // the farthest goes, the largest of two as far
      final far = counts.reduce(
        (a, b) => (b - n).abs() >= (a - n).abs() ? b : a,
      );
      counts = [...counts..remove(far), n]..sort();
    }
  } else if (whole) {
    counts = [n - 1, n, n + 1, n + 2];
  } else {
    final f = n.floorToDouble();
    counts = [f, n, f + 1, f + 2];
  }
  return counts;
}

// A serving or portion that weighs out food rather than counting it, and
// one that holds many of a thing or is none; as in count_piece.dart (S198).
final _measure = RegExp(
  r'\b(cups?|tbsps?|tablespoons?|tsps?|teaspoons?|oz|ounces?|fl|lbs?|'
  r'pounds?|g|grams?|kg|ml|l|liters?|litres?|cubic|inch|inches|chopped|'
  r'diced|sliced|shredded|grated|mashed|pureed|cubed|cubes?)\b',
  caseSensitive: false,
);
final _notOne = RegExp(
  r'\b(packages?|packets?|containers?|bags?|bottles?|jars?|cans?|box(es)?|'
  r'cartons?|recipe|yield|servings?|portions?|meals?|NFS|crust|loaf|pie|'
  r'cake|pizza|nlea)\b',
  caseSensitive: false,
);
final _leadingOne = RegExp(r'^\s*1\s+');
final _parenthetical = RegExp(r'\([^)]*\)');
const _sizeWords = {
  'small',
  'medium',
  'large',
  'extra',
  'jumbo',
  'regular',
  'whole',
};

/// What one of a portion labelled [label] is called when it is one counted
/// thing: "slice" of "1 slice (32 g)", "large egg" of "1 large egg"; null
/// for a measure ("1 cup, chopped") or many ("1 package").
String? pieceWord(String label) {
  if (!_leadingOne.hasMatch(label)) return null;
  final rest = label
      .replaceFirst(_leadingOne, '')
      .replaceAll(_parenthetical, '')
      .split(',')
      .first
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (rest.isEmpty || _measure.hasMatch(rest) || _notOne.hasMatch(rest)) {
    return null;
  }
  if (!RegExp(r'^[\p{L} ]+$', unicode: true).hasMatch(rest)) return null;
  return rest.toLowerCase();
}

/// [word] for more than one: "slices", "patties", "large eggs"; a size
/// alone ("medium") stays.
String _plural(String word) {
  final words = word.split(' ');
  final last = words.last;
  if (_sizeWords.contains(last)) return word;
  final String many;
  if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(last)) {
    many = '${last}es';
  } else if (RegExp(r'[^aeiou]y$').hasMatch(last)) {
    many = '${last.substring(0, last.length - 1)}ies';
  } else {
    many = '${last}s';
  }
  return [...words.take(words.length - 1), many].join(' ');
}

AmountChoice _countChoice(
  double count,
  String word,
  String unit, {
  bool estimate = false,
  String? text,
}) {
  final half = count == 0.5;
  final number = half ? '½' : amountText(count);
  final noun = count <= 1 ? word : _plural(word);
  final article = RegExp('^[aeiou]').hasMatch(word) ? 'an' : 'a';
  return AmountChoice(
    label: '$number $noun',
    spoken: half ? 'half $article $word' : '${amountText(count)} $noun',
    unit: unit,
    text: text ?? amountText(count),
    estimate: estimate,
  );
}

String _weightLabel(String unit) =>
    unit == _ml ? 'ml' : (unit == _oz ? 'oz' : (unit == _flOz ? 'fl oz' : 'g'));

String _weightSpoken(String unit, double value) {
  final one = value == 1;
  if (unit == _ml) return one ? 'millilitre' : 'millilitres';
  if (unit == _oz) return one ? 'ounce' : 'ounces';
  if (unit == _flOz) return one ? 'fluid ounce' : 'fluid ounces';
  return one ? 'gram' : 'grams';
}

AmountChoice _weightChoice(
  double value,
  String unit, {
  bool estimate = false,
  String? sendUnit,
  String? text,
}) => AmountChoice(
  label: '${amountText(value)} ${_weightLabel(unit)}',
  spoken: '${amountText(value)} ${_weightSpoken(unit, value)}',
  unit: sendUnit ?? unit,
  text: text ?? amountText(value),
  estimate: estimate,
);

/// A portion of [meal] that is one counted thing: its index's unit, its
/// name and weight; a medium one when there are sizes. The food's serving
/// when it has no portion list.
({String unit, String word, double grams})? _piece(
  MealEntity meal,
  List<String> allowed,
) {
  ({String unit, String word, double grams})? first;
  for (final (i, p) in meal.portions.indexed) {
    final word = pieceWord(p.englishLabel ?? p.label);
    final unit = portionUnit(i);
    if (word == null || !allowed.contains(unit)) continue;
    final piece = (unit: unit, word: word, grams: p.gramWeight);
    if (word.split(' ').contains('medium')) return piece;
    first ??= piece;
  }
  if (first != null || meal.portions.isNotEmpty) return first;
  final serving = meal.scalableServingQuantity;
  final word = pieceWord(meal.servingSize ?? '');
  if (serving == null || word == null || !allowed.contains(_serving)) {
    return null;
  }
  return (unit: _serving, word: word, grams: serving);
}

/// The word one of [unit] of [meal] is, when it counts a thing.
String? _pieceWordOf(MealEntity meal, String unit) {
  if (meal.portions.isNotEmpty) {
    final index = effectivePortionIndex(unit);
    if (index >= meal.portions.length) return null;
    final p = meal.portions[index];
    return pieceWord(p.englishLabel ?? p.label);
  }
  if (meal.scalableServingQuantity == null) return null;
  return pieceWord(meal.servingSize ?? '');
}

/// A chip of [count] [word]s in [unit], read and said as the question's
/// are; for the usual serving's offer (`usual_serving.dart`).
AmountChoice countChoiceOf(double count, String word, String unit) =>
    _countChoice(count, word, unit);

/// A chip of [value] in the weight [unit], read and said as the
/// question's are.
AmountChoice weightChoiceOf(double value, String unit) =>
    _weightChoice(value, unit);

/// The word one of [unit] of [meal] is, when it counts a thing.
String? pieceWordIn(MealEntity meal, String unit) => _pieceWordOf(meal, unit);

/// Ounces or fluid ounces where the Diary shows [meal] in them and [unit]
/// is not already that; null otherwise.
String? imperialWeightOf(MealEntity meal, List<String> allowed, String unit) =>
    _imperialWeight(meal, allowed, unit);

/// The chips that answer the question on [row], at the amount it has now
/// (the photo's at the size chosen): counts when it counts a thing, or when its weight is
/// within 15% of a whole or half piece; else weights at about ½, ¾, 1 and
/// 1½ of it, in the unit the row is shown in. The model's amount is one of
/// them, and sets the row's amount unchanged. Null without a usable amount.
List<AmountChoice>? amountChoices(BulkAddRow row, {required bool imperial}) {
  final meal = row.meal;
  final unit = row.effectiveUnit;
  final base = double.tryParse(row.amountText.trim().replaceAll(',', '.'));
  if (meal == null || base == null || base <= 0) return null;
  final allowed = row.allowedUnits;

  if (isPortionUnit(unit)) {
    final word = _pieceWordOf(meal, unit);
    if (word != null) {
      return [
        for (final n in countChoices(base))
          _countChoice(
            n,
            word,
            unit,
            estimate: n == base,
            text: n == base ? row.amountText : null,
          ),
      ];
    }
  } else {
    final grams = convertQuantityToBaseUnit(base, unit, meal);
    final piece = _piece(meal, allowed);
    if (piece != null && grams > 0) {
      final count = grams / piece.grams;
      final nearest = count < 0.5 ? 0.5 : (count * 2).roundToDouble() / 2;
      if (nearest <= 20 && (count - nearest).abs() / nearest <= 0.15) {
        return [
          for (final n in countChoices(nearest))
            // the estimate keeps the row as it is: confirming never
            // changes the amount or its unit
            n == nearest
                ? _countChoice(
                    n,
                    piece.word,
                    unit,
                    estimate: true,
                    text: row.amountText,
                  )
                : _countChoice(n, piece.word, piece.unit),
        ];
      }
    }
  }

  // weights, in the unit the row is shown in
  final String weight;
  if (isWeightUnit(unit)) {
    weight = unit;
  } else {
    final grams = convertQuantityToBaseUnit(1, unit, meal);
    // a portion with no weight to say it in
    if (grams == 1 && meal.portions.isEmpty) return null;
    weight = meal.isLiquid && allowed.contains(_ml)
        ? _ml
        : meal.isSolid && allowed.contains(_g)
        ? _g
        : _gml;
  }
  final shown = imperial
      ? _imperialWeight(meal, allowed, weight) ?? weight
      : weight;
  final estimate = shown == unit
      ? base
      : double.tryParse(amountInUnit(row.amountText, unit, shown, meal) ?? '');
  if (estimate == null || estimate <= 0) return null;
  final values = <double>[estimate];
  for (final share in [1.5, 0.75, 0.5]) {
    final value = friendlyAmount(estimate * share, shown);
    if (value <= 0) continue;
    if (values.any((v) => amountText(v) == amountText(value))) continue;
    values.add(value);
  }
  values.sort();
  return [
    for (final value in values)
      value == estimate
          ? _weightChoice(
              value,
              shown,
              estimate: true,
              sendUnit: unit,
              text: row.amountText,
            )
          : _weightChoice(value, shown),
  ];
}
