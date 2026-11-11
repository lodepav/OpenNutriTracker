/// Upstream's rule for "query" in the typed prompt, which asks for the
/// user's own language: that suits Open Food Facts' local products, but
/// against the fork's English table it sent Latvian meals to whatever
/// product shared a word: orange juice to a 148 kcal/100 g "Rica Sula",
/// coffee with milk to popcorn, butter to peanut butter, an omelette to
/// 2,295 kcal of "Egg Omletes".
const upstreamQueryRule = '''
- "query" is the food name alone, with no amount in it, in the same language
  the user wrote. Keep a brand if one is given.
''';

/// Upstream's portion example, whose query is German.
const upstreamPortionExample = '-> query "Brot"';

/// The fork's rules in the place of [upstreamQueryRule]: "query" in English,
/// the language of the fork's food table. A dish known by its name is one
/// entry: "pelēkie zirņi ar speķi, 300 g" came back as 300 g of grey peas
/// and 300 g of bacon, 2,029 kcal.
const typedQueryLanguageRule = '''
- "query" is the nearest generic food in English, with no amount in it,
  whatever language the meal is written in ("burkāni" -> "carrots",
  "Hähnchenschenkel" -> "chicken thigh", "tomātu sula" -> "tomato juice").
  Keep a brand as written. A national dish with no English name keeps its
  usual name ("pelmeni", "solyanka").
- A dish known by its name is one entry at the amount stated, never a list
  of what it is made with: "sautēti kāposti ar desu, 300 g" -> "braised
  cabbage with sausage", 300 g; "350 g beef stroganoff" -> "beef
  stroganoff", 350 g.
- Foods only served together are separate entries: "toast with honey" ->
  "toast" and "honey".
''';

/// Upstream's typed prompt [system] with [typedQueryLanguageRule] in place
/// of [upstreamQueryRule] and the portion example's query in English, so
/// the model reads one rule for "query" rather than a rule and its
/// retraction. Throws when upstream has reworded either, so a test fails
/// rather than the old rule going out unseen.
String typedQueryPrompt(String system) {
  for (final part in [upstreamQueryRule, upstreamPortionExample]) {
    if (!system.contains(part)) {
      throw StateError('The typed prompt no longer holds: $part');
    }
  }
  return system
      .replaceFirst(upstreamQueryRule, typedQueryLanguageRule)
      .replaceFirst(upstreamPortionExample, '-> query "bread"');
}
