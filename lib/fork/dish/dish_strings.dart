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
  static const yourAmounts = 'Your amounts';
  static const yourUsual = 'Your usual';

  /// [own] while the user's earlier amounts are used, [usual] while their
  /// usual sizes are: the sizes scale those.
  static String sizeChip(
    double factor, {
    bool own = false,
    bool usual = false,
  }) => factor == 1
      ? (own
            ? yourAmounts
            : usual
            ? yourUsual
            : asShown)
      : '×$factor';
  static String sizeChipSpoken(
    double factor, {
    bool own = false,
    bool usual = false,
  }) => factor == 1
      ? sizeChip(factor, own: own, usual: usual)
      : "$factor times ${own
            ? 'your'
            : usual
            ? 'your usual'
            : "the photo's"} amounts";
  static const sizeScalesUnset = "Scales the amounts you haven't set";
  static const sizeAllSet = 'Every amount is set by you';
  static const setByYou = 'Set by you';
  static String mealNow(String energy) => 'Meal now $energy';

  // a photo's meal like one the user corrected before
  /// [day] is "today", "yesterday" or a date, which takes "on".
  static String historyLike(String slot, String day, {bool date = true}) =>
      'Like your $slot ${date ? 'on ' : ''}$day';
  // the meal as the tap would leave it, not the earlier meal's energy
  static String historyAmounts(String energy) =>
      'This meal with your amounts: $energy';
  static const historyUse = 'Use your amounts';
  static String historyUsing(String day) => 'Using your amounts from $day';
  static const historyUndo = 'Undo';
  static const today = 'today';
  static const yesterday = 'yesterday';

  // the photo's amounts sized the way the user usually corrects them (D46)
  static String _factor(double factor) {
    final rounded = double.parse(factor.toStringAsFixed(2));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  static String usualSized(
    List<({String name, double factor})> foods, {
    int more = 0,
  }) =>
      'Sized the way you usually correct: ${[for (final food in foods) '${food.name} ×${_factor(food.factor)}', if (more > 0) 'and $more more'].join(' · ')}';
  static String usualSizedSpoken(
    List<({String name, double factor})> foods, {
    int more = 0,
  }) =>
      'Sized the way you usually correct: ${[for (final food in foods) '${food.name} ${_factor(food.factor)} times', if (more > 0) 'and $more more'].join(', ')}';
  static const usePhotoAmounts = "Use the photo's amounts";
  static const usingPhotoAmounts = "Using the photo's amounts";
  static const useUsualSizes = 'Use your usual sizes';

  /// The Size's hint while the usual sizes are in force: the sizes change
  /// those.
  static const sizesChangeUsual = 'Sizes change your usual amounts';

  // the one amount a photo's review asks about, on its row
  static String amountQuestion(String food) => 'How much $food was it?';
  static const amountAnswered = 'Thanks. Tap another to change it.';
  static String amountSaid(String amount, String energy) =>
      '$amount. ${mealNow(energy)}';

  // the fat a meal was cooked or dressed with (D48)
  static const cookedWithFat = 'Cooked with oil or butter?';
  static const dressedWithFat = 'Any dressing or oil?';
  // a little fat on the read already, under 10 g
  static const moreCookedFat = 'Any more oil or butter?';
  static const moreDressing = 'Any more dressing or oil?';
  static const fatNone = 'None';
  static const fatLittle = 'A little (5 g)';
  static const fatSome = 'Some (10 g)';
  static const fatLot = 'A lot (20 g)';
  static const fatLittleSpoken = 'A little, 5 grams';
  static const fatSomeSpoken = 'Some, 10 grams';
  static const fatLotSpoken = 'A lot, 20 grams';
  static const fatNotFound = 'No oil found in the food table';

  // words for a photo's note, one tap each (D49)
  static const noteChipsLabel = 'Add to the note';
}
