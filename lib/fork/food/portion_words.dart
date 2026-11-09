/// A photo's food named with the shape it was served in (S200): "lemon
/// slice" found no row, though "Lemon, raw" has a "1 slice or wedge" of 8 g,
/// and neither did "pizza slice", "apple wedges" or "cucumber slices". The
/// search wants every word in the row's name; the shape is a portion, which
/// the row's own portions answer once the food is found.
final _shape = RegExp(
  r'\b(slices?|wedges?|pieces?|segments?|rings?|halves|half|chunks?|'
  r'strips?)\b',
  caseSensitive: false,
);

final _bracket = RegExp(r'\([^)]*\)');

final _of = RegExp(r'^\s*of\b|\bof\s*$', caseSensitive: false);
final _spaces = RegExp(r'\s+');

/// [query] without its shape words, or null when it has none or is
/// nothing else. A name the model gave another in brackets loses those too:
/// "fresh coriander (cilantro)" found no row where "fresh coriander" finds
/// the herb, and with nothing found the herb was broken down off the photo
/// into the whole plate, 1,848 kcal.
String? withoutShapeWords(String query) {
  if (!_shape.hasMatch(query) && !_bracket.hasMatch(query)) return null;
  final bare = query
      .replaceAll(_bracket, ' ')
      .replaceAll(_shape, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .replaceAll(_of, '')
      .trim();
  return bare.isEmpty ? null : bare;
}

/// A slice of a food whose portions name no slice is its piece (S202):
/// "2 slices of pepperoni pizza" matched no "slice" row, and the food's own
/// word then picked "1 personal size pizza", a whole pizza a slice. "piece"
/// when [portion] or [query] says slice or wedge, else null.
String? sliceAsPiece(String? portion, String query) =>
    _slice.hasMatch(portion ?? '') || _slice.hasMatch(query) ? 'piece' : null;

final _slice = RegExp(r'\b(slices?|wedges?)\b', caseSensitive: false);
