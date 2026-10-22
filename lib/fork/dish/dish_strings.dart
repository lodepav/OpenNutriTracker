/// The fork's UI text, English only. Upstream's strings live in
/// `lib/l10n/intl_en.arb` and reach other languages through Weblate; a
/// fork string there would collide with every upstream merge of that file.
abstract final class DishStrings {
  static const breakDownAction = 'Ingredients';
  static const breakingDown = 'Breaking into ingredients…';
  static String ingredientOf(String dish) =>
      'Ingredient of $dish · AI estimate, check the grams';
  static const breakDownEmpty = 'The model found no ingredients for this.';
  static const breakDownNoModel = 'Set up an AI model to break a dish down.';
  static const breakDownFailed = 'The breakdown did not work. Try again later.';
}
