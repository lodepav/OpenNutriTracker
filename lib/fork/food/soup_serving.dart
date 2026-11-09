/// What a soup with no stated amount and no serving starts at: a bowl
/// (S98), the 300 g of the fork's own solyanka. 100 g, every other food's
/// start, is a third of a bowl: a photo's borscht and chłodnik logged 100 g.
const soupServingGrams = 300.0;

/// The same in ounces, for an imperial profile.
const soupServingOz = 10.5;

final _soup = RegExp(
  r'\b(soups?|borscht|borschtsch|borsch|broth|bouillon|chowder|bisque|'
  r'gazpacho|solyanka|minestrone|rassolnik|shchi|okroshka|chłodnik|'
  r'consomm[eé]|laksa|ramen|pho|lagman|kharcho|ukha)\b',
  caseSensitive: false,
);

/// What a soup's name holds when it is not a bowl of soup: something put
/// in one, or a cube or powder to make one.
final _notTheSoup = RegExp(
  r'\b(garnish|ingredient|added|cubes?|powder|instant|pearls|greens|dry|'
  r'dehydrated|condensed|mix|granules|concentrate|bouillon potatoes)\b',
  caseSensitive: false,
);

/// Whether [name] is a soup a bowl of is the usual amount.
bool isSoup(String? name) =>
    name != null && _soup.hasMatch(name) && !_notTheSoup.hasMatch(name);

/// What croutons with no stated amount and no serving start at: a soup's
/// handful, USDA's half-ounce serving. A photo's croutons on a solyanka
/// logged at the 100 g default, 408 to 492 kcal.
const croutonServingGrams = 15.0;

/// The same in ounces, for an imperial profile.
const croutonServingOz = 0.5;

final _croutons = RegExp(r'\bcro[uû]tons?\b', caseSensitive: false);

/// A food that comes with croutons is the food ("Cheese soup, with
/// croutons").
final _withCroutons = RegExp(r'\bwith\b[^,]*', caseSensitive: false);

/// Whether [name] is croutons, not a dish served with them.
bool isCroutons(String? name) =>
    name != null && _croutons.hasMatch(name.replaceAll(_withCroutons, ''));
