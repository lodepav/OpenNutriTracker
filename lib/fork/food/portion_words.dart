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

final _of = RegExp(r'^\s*of\b|\bof\s*$', caseSensitive: false);
final _spaces = RegExp(r'\s+');

/// [query] without its shape words, or null when it has none or is
/// nothing else.
String? withoutShapeWords(String query) {
  if (!_shape.hasMatch(query)) return null;
  final bare = query
      .replaceAll(_shape, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .replaceAll(_of, '')
      .trim();
  return bare.isEmpty ? null : bare;
}
