import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

/// A weight the user's note gives one food: "chicken 120g", "rice - 80 g",
/// "spinach: 30g".
typedef FoodWeight = ({String name, double grams});

/// The weights a photo's note states (S175): a total for the whole plate,
/// each food's own, or both.
class NoteWeights {
  /// The whole plate in grams: "350g total", "chicken, rice - 350g",
  /// "350g: chicken, rice", or a note that is only "350g".
  final double? totalGrams;

  final List<FoodWeight> foods;

  const NoteWeights({this.totalGrams, this.foods = const []});
}

final _amount = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(kg|grams?|gr|g|ml|l|oz|lb)\b',
  caseSensitive: false,
);

/// Words that make an amount the plate's: English, and the Latvian and
/// Russian a note may be typed in.
final _totalWord = RegExp(
  r'\b(total|in total|altogether|overall|all together)\b|kopā|всего|итого',
  caseSensitive: false,
);

/// A food list: more than one food in the rest of the note.
final _list = RegExp(r',|;|\+|&|\band\b|\bwith\b', caseSensitive: false);

const _separators = '-–—:=';

/// What [note] states in grams, or null when it states no weight or also
/// states a count: those, and a note naming foods alone, are the photo
/// read's, not this.
NoteWeights? noteWeights(String? note) {
  final text = note?.trim() ?? '';
  final amounts = _amount.allMatches(text).toList();
  if (amounts.isEmpty) return null;
  // "200g rice, 2 eggs": a count stays the photo read's to keep (S170)
  if (parseMealText(
    text.replaceAll(_amount, ''),
  ).items.any((i) => i.quantity != null)) {
    return null;
  }

  RegExpMatch? total;
  for (final m in amounts) {
    // "350g total", "total 350g", "in total: 350 g"
    final around = text.substring(
      (m.start - 12).clamp(0, text.length),
      (m.end + 12).clamp(0, text.length),
    );
    if (_totalWord.hasMatch(around)) total = m;
  }
  if (total == null && amounts.length == 1) {
    final m = amounts.single;
    final rawBefore = text.substring(0, m.start);
    final before = rawBefore.trim();
    final after = text.substring(m.end).trim();
    if (before.isEmpty &&
        (after.isEmpty || _separators.contains(after[0]) || after[0] == ',')) {
      // "350g", "350g: chicken, rice"
      total = m;
    } else if (_onlySeparators(after) &&
        (_trailSeparator.hasMatch(rawBefore) || _plate.hasMatch(before))) {
      // "chicken, rice - 350g", "plov - 350g", "chicken, rice (350g)",
      // "chicken, rice" and the weight on a line of its own, "whole plate
      // 350g": the whole of what comes before, one food or several
      total = m;
    } else if (_onlySeparators(after) &&
        after.isNotEmpty &&
        _list.hasMatch(before)) {
      // "chicken, rice, spinach 350g:"
      total = m;
    }
  }

  // The foods' own weights, read with the total and its word taken out
  // ("spinach 30g - 250g total" is spinach's 30 g).
  final rest = total == null
      ? text
      : text
            .replaceRange(total.start, total.end, '')
            .replaceAll(_totalWord, '');
  return NoteWeights(
    totalGrams: total == null ? null : _grams(total),
    foods: [
      for (final item in parseMealText(
        // "spinach 30g." and "spinach 30g -" read as no weight at all
        rest.replaceAllMapped(_markAfterWeight, (m) => m[1]!),
      ).items)
        if (item.quantity != null && item.unit != null)
          if (_name(item.query) case final name when name.isNotEmpty)
            (name: name, grams: _toGrams(item.quantity!, item.unit!)),
    ],
  );
}

final _markAfterWeight = RegExp(
  r'(\d\s*(?:kg|grams?|gr|g|ml|l|oz|lb))\b[ \t]*[-–—:=.)]+',
  caseSensitive: false,
);

/// What may stand between a list and the weight of all of it: a separator,
/// a comma, a full stop, an opening bracket, or a new line.
final _trailSeparator = RegExp(r'([-–—:=,.(]|\n)\s*$');

/// A note that names the plate rather than a food: "whole plate 350g",
/// "weighed 350g", "bowl - 350g".
final _plate = RegExp(
  r'^(the |my )?(whole |entire )?(plate|bowl|portion|meal|everything|all|'
  r'weighed|weight)\b[\s\-–—:=,(]*$',
  caseSensitive: false,
);

/// Nothing but closing marks: "", ":", ")", ".".
bool _onlySeparators(String text) =>
    text.split('').every((c) => '$_separators).'.contains(c));

double _grams(RegExpMatch m) => _toGrams(
  double.parse(m.group(1)!.replaceAll(',', '.')),
  m.group(2)!.toLowerCase(),
);

/// A plate's foods are weighed: a millilitre of soup counts as a gram.
double _toGrams(double quantity, String unit) => switch (unit) {
  'kg' => quantity * 1000,
  'l' => quantity * 1000,
  'lb' => quantity * 453.6,
  'oz' => quantity * 28.35,
  _ => quantity,
};

/// The food's name without the separator the parser left on it ("rice -").
String _name(String query) => query
    .replaceAll(RegExp('[$_separators]+\$'), '')
    // a bullet: "- chicken 120g"
    .replaceAll(RegExp(r'^[-–—•*\s]+'), '')
    .trim();
