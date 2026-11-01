import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

/// A weight the user's note gives one food among others: "chicken 120g, rice",
/// "rice - 80 g, chicken", "spinach: 30g, rice".
typedef FoodWeight = ({String name, double grams});

/// The weights a photo's note states (S175): a total for the whole plate,
/// each food's own, or both.
class NoteWeights {
  /// The whole plate in grams: "350g total", "350g chicken, rice", "chicken,
  /// rice 350g", "plov - 350g", or a note that is only "350g".
  final double? totalGrams;

  final List<FoodWeight> foods;

  /// The note names one thing ("300g plov"), so a dish the model splits it
  /// into weighs what the note says. "chicken 150g, rice" names two.
  final bool namesOneThing;

  const NoteWeights({
    this.totalGrams,
    this.foods = const [],
    this.namesOneThing = false,
  });
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

/// More than one food named: "chicken, rice", "fries with pork", and the
/// Latvian a note may be typed in.
final _list = RegExp(r',|;|\+|&|\n|\b(and|with|un|ar)\b', caseSensitive: false);

/// A weight in the middle of a name: "panini with 200g beef". The parser reads
/// weights only at an item's ends, so the word before it becomes a comma.
final _withWeight = RegExp(
  r'\b(with|ar)\s+(?=\d+(?:[.,]\d+)?\s*(?:kg|grams?|gr|g|ml|l|oz|lb)\b)',
  caseSensitive: false,
);

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
    final after = text.substring(m.end).trim();
    // Last, it weighs all the note names: "chicken, rice 350g", "plov - 350g",
    // "whole plate 350g". First, all of several: "350g chicken, rice", "350g:
    // chicken". Else it is a food's: "200g rice", "chicken 150g, rice".
    if (_onlySeparators(after) ||
        text.substring(0, m.start).trim().isEmpty &&
            (_separators.contains(after[0]) || _list.hasMatch(after))) {
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
    namesOneThing: !_list.hasMatch(text),
    foods: [
      for (final item in parseMealText(
        // "spinach 30g." and "spinach 30g -" read as no weight at all
        rest
            .replaceAll(_withWeight, ', ')
            .replaceAllMapped(_markAfterWeight, (m) => m[1]!),
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
