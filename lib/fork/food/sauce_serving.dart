/// The most a sauce's row starts at when no amount was stated (fix of
/// 2026-11-02): a photo's gravy came in as USDA's "Gravy, beef, canned" at
/// its serving, the whole 233 g can, and an Open Food Facts gravy with no
/// serving at the 100 g default; a plate's gravy is a ladle, 30-60 ml.
/// About a quarter cup, the serving USDA gives most sauces.
const sauceServingGrams = 60.0;

final _sauce = RegExp(
  r'\b(gravy|gravies|sauces?|dressings?|dips?|jus|ketchup|mayonnaise|aioli|'
  r'salsa|pesto|vinaigrette|coulis)\b',
  caseSensitive: false,
);

/// A food that comes with a sauce is the food ("Ham or pork with gravy").
final _comesWith = RegExp(
  r'\b(with|in|without|no|from)\b[^,]*',
  caseSensitive: false,
);

/// Whether [name] is a sauce, gravy or dressing, not a food served in one.
bool isSauce(String? name) =>
    name != null && _sauce.hasMatch(name.replaceAll(_comesWith, ''));

/// [serving], at most [sauceServingGrams] for a sauce: the amount a row of
/// [name] starts at when none was stated.
double sauceDefault(String? name, double serving) =>
    isSauce(name) && serving > sauceServingGrams ? sauceServingGrams : serving;
