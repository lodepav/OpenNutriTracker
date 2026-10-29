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

  double? total;
  for (final m in amounts) {
    // "350g total", "total 350g", "in total: 350 g"
    final around = text.substring(
      (m.start - 12).clamp(0, text.length),
      (m.end + 12).clamp(0, text.length),
    );
    if (_totalWord.hasMatch(around)) total = _grams(m);
  }
  if (total == null && amounts.length == 1) {
    final m = amounts.single;
    final before = text.substring(0, m.start).trim();
    final after = text.substring(m.end).trim();
    final lead = after.isNotEmpty && _separators.contains(after[0]);
    final trail =
        before.isNotEmpty && _separators.contains(before[before.length - 1]);
    if (before.isEmpty && after.isEmpty) {
      total = _grams(m);
    } else if (before.isEmpty && lead) {
      // "350g: chicken, rice"
      total = _grams(m);
    } else if (after.isEmpty && trail) {
      // "chicken, rice, spinach - 350g", "plov - 350g": the whole of what
      // comes before, one food or several
      total = _grams(m);
    } else if (_onlySeparators(after) && _list.hasMatch(before)) {
      // "chicken, rice, spinach 350g:"
      total = _grams(m);
    }
  }

  final foods = <FoodWeight>[
    for (final item in parseMealText(text).items)
      if (item.quantity != null &&
          item.unit != null &&
          _toGrams(item.quantity!, item.unit!) != total)
        (name: _name(item.query), grams: _toGrams(item.quantity!, item.unit!)),
  ];
  return NoteWeights(
    totalGrams: total,
    foods: [
      for (final f in foods)
        if (f.name.isNotEmpty) f,
    ],
  );
}

bool _onlySeparators(String text) =>
    text.isNotEmpty && text.split('').every(_separators.contains);

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
String _name(String query) =>
    query.replaceAll(RegExp('[$_separators]+\$'), '').trim();
