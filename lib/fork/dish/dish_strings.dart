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
  static const saveAsRecipe = 'Save recipe';
  static const recipeDescription =
      'One serving, from an AI breakdown. The grams are estimates: check them.';
  static const logSeparately = 'Log separately';
  static const logAsOneDish = 'Log as one dish';
  static const portion = 'Portion';
  static const showFoods = 'Show the foods';
  static const hideFoods = 'Hide the foods';

  /// [foods] is the review's count of the dish's rows (`foodCountText`).
  static String dishSummary(String foods, String energy) => '$foods · $energy';
  static const nothingToSave = 'No ingredient row is ready to save.';
  static const saveAllAsRecipe = 'Save all as a recipe';
  static const typedRecipeDescription =
      'From typed ingredients. Check each match and amount.';
  static String linkedRecipeDescription(String site) =>
      'From $site. Check each match and amount.';
  static const readingLink = 'Reading the recipe page…';
  static const linkHasNoRecipe =
      'That page has no recipe data. Paste its ingredient lines instead.';
  static const linkFailed = 'The page could not be loaded.';

  // the meal's Size on a photo's review
  static const mealSize = 'Size';
  static const asShown = 'As shown';
  static String sizeChip(double factor) => factor == 1 ? asShown : '×$factor';
  static String sizeChipSpoken(double factor) =>
      factor == 1 ? asShown : "$factor times the photo's amounts";
  static const sizeScalesUnset = "Scales the amounts you haven't set";
  static const sizeAllSet = 'Every amount is set by you';
  static const setByYou = 'Set by you';
  static String mealNow(String energy) => 'Meal now $energy';

  // a photo's meal like one the user corrected before
  /// [day] is "today", "yesterday" or a date, which takes "on".
  static String historyLike(String slot, String day, {bool date = true}) =>
      'Like your $slot ${date ? 'on ' : ''}$day';
  static String historyAmounts(String energy) => 'Your amounts then: $energy';
  static const historyUse = 'Use your amounts';
  static String historyUsing(String day) => 'Using your amounts from $day';
  static const historyUndo = 'Undo';
  static const today = 'today';
  static const yesterday = 'yesterday';

  // the one amount a photo's review asks about, on its row
  static String amountQuestion(String food) => 'How much $food was it?';
  static const amountAnswered = 'Thanks. Tap another to change it.';
  static String amountSaid(String amount, String energy) =>
      '$amount. ${mealNow(energy)}';
}
