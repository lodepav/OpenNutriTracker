/// The typed prompt's rule for the language of a query: English, the
/// language of the fork's food table. Upstream asks for the user's own
/// language, which suits Open Food Facts' local products; against the
/// table it sent Latvian meals to whatever product shared a word: orange
/// juice to a 148 kcal/100 g "Rica Sula", coffee with milk to popcorn,
/// butter to peanut butter, an omelette to 2,295 kcal of "Egg Omletes".
/// A dish known by its name is one entry: "pelēkie zirņi ar speķi, 300 g"
/// came back as 300 g of grey peas and 300 g of bacon, 2,029 kcal.
const typedQueryLanguageRule = '''
This rule replaces the one about the language of "query": write "query" as
the nearest generic food in English, whatever language the meal is written
in ("burkāni" -> "carrots", "Hähnchenschenkel" -> "chicken thigh",
"tomātu sula" -> "tomato juice"). Keep a brand as written. A national dish
with no English name keeps its usual name ("pelmeni", "solyanka").
A dish known by its name is one entry at the amount stated, never a list
of what it is made with: "sautēti kāposti ar desu, 300 g" -> "braised
cabbage with sausage", 300 g; "350 g beef stroganoff" -> "beef
stroganoff", 350 g. Foods only served together are separate entries:
"toast with honey" -> "toast" and "honey".''';
