/// What a soup with no stated amount and no serving starts at: a bowl
/// (S98), the 300 g of the fork's own solyanka. 100 g, every other food's
/// start, is a third of a bowl: a photo's borscht and chłodnik logged 100 g.
const soupServingGrams = 300.0;

/// The same in ounces, for an imperial profile.
const soupServingOz = 10.5;

final _soup = RegExp(
  r'\b(soups?|borscht|borschtsch|borsch|broth|bouillon|chowder|bisque|'
  r'gazpacho|solyanka|minestrone|rassolnik|shchi|okroshka|chłodnik|'
  r'consomm[eé])\b',
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
