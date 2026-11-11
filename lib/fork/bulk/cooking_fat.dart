// The fat a meal was cooked or dressed with, asked about on a photo's
// review (D48): a photo cannot show the oil in a pan or on leaves, and a
// tablespoon of it is 120 kcal the read leaves out.
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// Which question the meal card asks.
enum CookingFatAsk {
  /// "Cooked with oil or butter?": something fried, roasted, sautéed or
  /// stir-fried.
  cooked,

  /// "Any dressing or oil?": a salad, nothing cooked in fat.
  salad,

  /// "Any more oil or butter?": cooked in fat, with a little fat on the
  /// read already ([cookingFatEnough]).
  cookedMore,

  /// "Any more dressing or oil?": a salad with a little fat on it.
  saladMore,
}

/// At this many grams of fat rows on the read, together, the fat is taken
/// as counted and nothing is asked; under it, the model's few grams are
/// more often a dab than the meal's fat.
const cookingFatEnough = 10.0;

/// The chips' grams after None: a little, some, a lot.
const cookingFatGrams = [5.0, 10.0, 20.0];

/// The food a chip adds, from the food table.
const cookingFatQuery = 'sunflower oil';

// Names are matched as the model and the table write them, in English,
// with the words of the five languages a dish name may be typed in.

/// Cooked in fat: fried, roasted, sautéed, seared in a pan, stir-fried.
/// Not grilled alone (a grill needs none), dry-roasted (nuts), nor fries:
/// the table's fries already hold their frying fat.
final _cooked = RegExp(
  r'\b(fried|fry|frying|seared|griddled|roast|roasted|roasting)\b|'
  r'\bstir[- ]?fr|\bpan[- ](fried|seared|grilled)|\bsaut[eé]|'
  // de, lv, lt, pl, ru
  r'\b(gebraten|angebraten|frittiert|geröstet|cept[sauio]|kept(as|a|i|os|ų)|'
  r'smażon|pieczon)|жарен|обжарен|жарк',
  caseSensitive: false,
  unicode: true,
);

final _dryRoasted = RegExp(r'\bdry[- ]roasted\b', caseSensitive: false);

/// A salad or slaw.
final _salad = RegExp(
  r'\b(salads?|slaw|coleslaw|salat|salate)\b|'
  // lv, pl, lt, ru
  r'\bsalāt|\bsałatk|\bsurówk|\bsalot|салат',
  caseSensitive: false,
  unicode: true,
);

/// Fat already on the plate: oil, butter, a dressing, mayonnaise, a sauce
/// made of fat (hollandaise, pesto, a cream, cheese or garlic sauce), or a
/// row the table says has fat added. Not a sauce or gravy by itself: a
/// tomato sauce or a gravy holds little and leaves the pan's oil unsaid.
/// Not a nut butter, nor butternut, buttermilk or butter beans.
final _fat = RegExp(
  r'\b(oils?|ghee|lard|margarine|dressings?|vinaigrette|mayonnaise|mayo|'
  r'aioli|fat added|with fat|cooking fat|hollandaise|b[eé]arnaise|alfredo|'
  r'pesto)\b|'
  r'\b(tartare?|cream|creamy|cheese|garlic)\s+sauces?\b|'
  r'\bsauces?,\s*(tartare?|cream|cheese|garlic)\b|'
  r'(?<!peanut |nut |almond |apple |cocoa |shea )butter'
  r'(?!nut|milk|scotch|cup|head| beans?| lettuce)|'
  // de (compounds end in it: "Sonnenblumenöl"), pl, lv, lt, ru; not
  // маслины, olives
  r'öl\b|\bolej|\bmasł|majonēz|majonez|eļļ|\bsviest|\baliej|'
  r'масл(о|а|е|ом)(?![а-яё])|майонез|заправк',
  caseSensitive: false,
  unicode: true,
);

/// A fat named only as absent: "without dressing", "no added fat", "fat
/// not added", and German, Latvian, Polish and Russian "without …". The
/// table's plain salad is "Salad, green, without dressing".
final _noFat = RegExp(
  r'\b(without|no|ohne|bez)\s+(added\s+)?[\p{L}-]+(\s+added)?|'
  r'\bfat not added|без\s+\p{L}+',
  caseSensitive: false,
  unicode: true,
);

/// A table food whose numbers hold the fat it was cooked in: fried, fries,
/// roasted, sautéed, stir-fried, or fat or oil added.
final _holdsFat = RegExp(
  r'\bfries\b|\b(fat added|with oil|in oil|with butter|in butter)\b',
  caseSensitive: false,
);

String _plain(String words) =>
    words.replaceAll(_noFat, ' ').replaceAll(_dryRoasted, ' ');

/// Whether the food [row] matched holds its own fat: then the row neither
/// asks (the fat is counted) nor is a fat of its own beside the others.
bool _tableHoldsFat(BulkAddRow row) {
  final name = _plain(row.meal?.name ?? '');
  return _cooked.hasMatch(name) || _holdsFat.hasMatch(name);
}

/// The words a row is known by: the model's own text, the food matched,
/// and the dish it belongs to; without a fat named as absent.
String _words(BulkAddRow row) => _plain(
  [
    row.resolved.parsed.query,
    row.meal?.name ?? '',
    row.dishIngredient?.dish ?? '',
  ].join(' · '),
);

/// Cooked in fat by the model's or the user's words, the dish's too.
bool _saidCooked(BulkAddRow row) => _cooked.hasMatch(
  _plain('${row.resolved.parsed.query} · ${row.dishIngredient?.dish ?? ''}'),
);

/// [row]'s grams or millilitres; null when it has none to say.
double? _grams(BulkAddRow row) {
  final meal = row.meal;
  final amount = double.tryParse(row.amountText.trim().replaceAll(',', '.'));
  if (meal == null || amount == null) return null;
  return convertQuantityToBaseUnit(amount, row.effectiveUnit, meal);
}

/// The question for a photo's [rows] as they first arrive, [note] being
/// what the photo was sent with: [CookingFatAsk.cooked] when the model or
/// the user says a food was fried, roasted, sautéed or stir-fried and the
/// food matched is a plain one ("fried potatoes" as "Potato, boiled"),
/// else [CookingFatAsk.salad] for a salad. A fat, oil, butter, dressing,
/// mayonnaise or fatty sauce on the read makes it "Any more …?"
/// ([CookingFatAsk.cookedMore], [CookingFatAsk.saladMore]) while those rows
/// come to under [cookingFatEnough] together, and asks nothing at it or
/// over it, or with one whose amount cannot be weighed. Null too when the
/// note states weights (a weighed plate lists its fat, D24). A row matched
/// to a table food that holds its fat ("Potatoes, home fries", "fat
/// added") asks nothing and is no fat beside the others. Rows left out
/// count for neither.
CookingFatAsk? cookingFatAskFor(List<BulkAddRow> rows, {String? note}) {
  if (noteWeights(note) != null) return null;
  final kept = [
    for (final row in rows)
      if (!row.skipped) row,
  ];
  if (kept.isEmpty) return null;
  final own = [for (final row in kept) _tableHoldsFat(row)];
  var fat = 0.0;
  var anyFat = false;
  for (final (i, row) in kept.indexed) {
    if (own[i] || !_fat.hasMatch(_words(row))) continue;
    final grams = _grams(row);
    if (grams == null) return null;
    anyFat = true;
    fat += grams;
  }
  if (fat >= cookingFatEnough) return null;
  for (final (i, row) in kept.indexed) {
    if (!own[i] && _saidCooked(row)) {
      return anyFat ? CookingFatAsk.cookedMore : CookingFatAsk.cooked;
    }
  }
  if (kept.any((row) => _salad.hasMatch(_words(row)))) {
    return anyFat ? CookingFatAsk.saladMore : CookingFatAsk.salad;
  }
  return null;
}

/// The chip of [cookingFatGrams] a fat row at [amountText] grams is at;
/// null for another amount.
int? cookingFatChipOf(String amountText) {
  final grams = double.tryParse(amountText.trim().replaceAll(',', '.'));
  final at = cookingFatGrams.indexOf(grams ?? -1);
  return at < 0 ? null : at;
}

/// [grams] as the amount field holds them: "5", "10".
String cookingFatText(double grams) => grams == grams.roundToDouble()
    ? grams.toInt().toString()
    : grams.toString();
