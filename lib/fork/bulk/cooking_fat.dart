// The fat a meal was cooked or dressed with, asked about on a photo's
// review (D48): a photo cannot show the oil in a pan or on leaves, and a
// tablespoon of it is 120 kcal the read leaves out.
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

/// Which question the meal card asks.
enum CookingFatAsk {
  /// "Cooked with oil or butter?": something fried, roasted, sautéed or
  /// stir-fried.
  cooked,

  /// "Any dressing or oil?": a salad, nothing cooked in fat.
  salad,
}

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

/// Fat already on the plate: oil, butter, a dressing, mayonnaise or a
/// sauce, or a row the table says has fat added. Not a nut butter, nor
/// butternut, buttermilk or butter beans.
final _fat = RegExp(
  r'\b(oils?|ghee|lard|margarine|dressings?|vinaigrette|mayonnaise|mayo|'
  r'aioli|sauces?|gravy|fat added|with fat|cooking fat|sos)\b|'
  r'(?<!peanut |nut |almond |apple |cocoa |shea )butter'
  r'(?!nut|milk|scotch|cup|head| beans?| lettuce)|'
  // de (compounds end in it: "Sonnenblumenöl"), pl, lv, lt, ru; not
  // маслины, olives
  r'öl\b|soße|\bolej|\bmasł|majonēz|majonez|eļļ|\bsviest|mērc|\baliej|'
  r'\bpadaž|масл(о|а|е|ом)(?![а-яё])|майонез|соус|заправк',
  caseSensitive: false,
  unicode: true,
);

/// The words a row is known by: the model's own text, the food matched,
/// and the dish it belongs to.
String _words(BulkAddRow row) => [
  row.resolved.parsed.query,
  row.meal?.name ?? '',
  row.dishIngredient?.dish ?? '',
].join(' · ');

bool _isCooked(String words) =>
    _cooked.hasMatch(words.replaceAll(_dryRoasted, ''));

/// The question for a photo's [rows] as they first arrive, [note] being
/// what the photo was sent with: [CookingFatAsk.cooked] when a food was
/// fried, roasted, sautéed or stir-fried, else [CookingFatAsk.salad] for a
/// salad; null when the read already holds a fat, oil, butter, dressing,
/// mayonnaise or sauce, or when the note states weights (a weighed plate
/// lists its fat, D24). Rows left out count for neither.
CookingFatAsk? cookingFatAskFor(List<BulkAddRow> rows, {String? note}) {
  if (noteWeights(note) != null) return null;
  final named = [
    for (final row in rows)
      if (!row.skipped) _words(row),
  ];
  if (named.isEmpty || named.any(_fat.hasMatch)) return null;
  if (named.any(_isCooked)) return CookingFatAsk.cooked;
  if (named.any(_salad.hasMatch)) return CookingFatAsk.salad;
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
